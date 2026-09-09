import Foundation
import Testing
@testable import Tower

@MainActor
struct AuditScaleTests {
    @Test
    func warmRequestsReusePreparationAcrossTabsButNeverReuseChangedInputs() throws {
        let model = AppModel(arguments: ["--demo"])
        let original = model.configurationRequest(target: .clash)
        let count = model.configurationRequestPreparationCount
        for _ in 0..<10 {
            model.selectedTab = .rules
            model.selectedTab = .export
            #expect(model.configurationRequest(target: .clash) == original)
            _ = model.enabledNodes
            _ = model.coveredCountryCount
        }
        #expect(model.configurationRequestPreparationCount == count)
        // Same UUID and count, changed credentials must invalidate the snapshot.
        model.nodes[0].password = "changed-fixture"
        let changed = model.configurationRequest(target: .clash)
        #expect(changed != original)
        #expect(model.configurationRequestPreparationCount == count + 1)
        #expect(changed.generate().content != original.generate().content)
        model.configurationName = "New fixture name"
        #expect(model.configurationRequest(target: .clash).name == "New fixture name")
        model.excludedKinds[.clash] = [.shadowsocks]
        #expect(model.configurationRequest(target: .clash) != changed)
    }

    @Test
    func preparationSeparatesClientModeAndSupportedKinds() {
        let model = AppModel(arguments: ["--demo"])
        let full = model.configurationRequest(target: .surge)
        let nodes = model.configurationRequest(target: .surge, contentMode: .nodesOnly)
        let other = model.configurationRequest(target: .clash)
        let count = model.configurationRequestPreparationCount
        #expect(model.configurationRequest(target: .surge) == full)
        #expect(model.configurationRequest(target: .surge, contentMode: .nodesOnly) == nodes)
        #expect(model.configurationRequest(target: .clash) == other)
        #expect(model.configurationRequestPreparationCount == count)
        #expect(model.configurationRequest(target: .surge, supportedKindsOverride: [.trojan]) != full)
    }

    @Test
    func cachedNodeSelectionTracksSourceExclusionsMetadataAndRename() throws {
        let model = AppModel(arguments: ["--demo"])
        let source = try #require(model.subscriptions.first)
        let node = ProxyNode(sourceID: source.id, kind: .trojan, name: "Japan", server: "node.test", port: 443, rawURI: "")
        model.nodes = [node]
        #expect(model.enabledNodes == [node])
        #expect(model.nodeCount(for: source) == 1)
        #expect(model.coveredCountryCount == 1)
        model.excludedNodeIDs.insert(node.id)
        #expect(model.availableNodes == [node])
        #expect(model.enabledNodes.isEmpty)
        #expect(model.coveredCountryCount == 0)
        model.excludedNodeIDs.remove(node.id)
        model.subscriptions[0].isEnabled = false
        #expect(model.availableNodes.isEmpty)
        #expect(model.nodeCount(for: source) == 1)
        model.subscriptions[0].isEnabled = true
        model.nodes[0].isSubscriptionMetadata = true
        model.filterSubscriptionInfoNodes = true
        #expect(model.nodeCount(for: source) == 0)
        #expect(model.availableNodes.isEmpty)
        model.filterSubscriptionInfoNodes = false
        model.nodes[0].name = "unknown"
        #expect(model.coveredCountryCount == 0)
        model.nodeIPCountryCodes[node.id] = "JP"
        #expect(model.coveredCountryCount == 1)
    }

    @Test
    func previewGenerationRunsOffMainThreadAndReusesCache() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tower-preview-\(UUID()).json")
        let model = AppModel(persistence: PersistenceStore(fileURL: file), arguments: ["--demo"])
        let snapshot = model.configurationRequest(target: .clash)
        let request = ConfigurationRequest(key: snapshot.key, name: snapshot.name) {
            #expect(!Thread.isMainThread)
            return snapshot.generate()
        }
        let generated = await model.configuration(for: request)
        let count = model.configurationGenerationCount
        #expect(model.configuration(target: .clash).content == generated.content)
        #expect(model.configurationGenerationCount == count)
    }

    @Test
    func previewRequestKeepsItsInputsWhenSelectionChanges() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tower-preview-\(UUID()).json")
        let model = AppModel(persistence: PersistenceStore(fileURL: file), arguments: ["--demo"])
        let request = model.configurationRequest(target: .clash)
        let expected = request.generate()
        model.nodes = []
        model.selectedTarget = .surgeMac
        let newRequest = model.configurationRequest()
        #expect(request != newRequest)
        let result = await model.configuration(for: request)
        #expect(result.target == .clash)
        #expect(result.content == expected.content)
        #expect(result.supportedNodeCount == expected.supportedNodeCount)
    }

    @Test(arguments: [1_000, 5_000])
    func mapAndWarmClientSwitchesAtRepresentativeSizes(count: Int) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tower-scale-\(UUID()).json")
        let model = AppModel(persistence: PersistenceStore(fileURL: file), arguments: ["--demo"])
        let source = try #require(model.subscriptions.first)
        model.nodes = (0..<count).map { index in
            ProxyNode(sourceID: source.id, kind: .shadowsocks, name: "Japan \(index)",
                      server: "node.example.test", port: 443, password: "fixture", rawURI: "")
        }
        let mapStart = ContinuousClock.now
        let presentation = NodeMapPresentation(nodes: model.nodes, countryCodes: [:])
        let mapDuration = mapStart.duration(to: .now)
        #expect(presentation.clusters.reduce(0) { $0 + $1.nodes.count } == count)
        model.embedRemoteSubscriptionLinks = true
        _ = model.configuration(target: .clash)
        _ = model.configuration(target: .shadowrocket)
        let generations = model.configurationGenerationCount
        let warmStart = ContinuousClock.now
        for _ in 0..<5 {
            _ = model.configuration(target: .clash)
            _ = model.configuration(target: .shadowrocket)
        }
        let warmDuration = warmStart.duration(to: .now)
        #expect(model.configurationGenerationCount == generations)
        // Synthetic simulator measurements, not device frame-rate claims.
        print("AuditScale nodes=\(count) map=\(mapDuration) tenWarmSwitches=\(warmDuration)")
    }
}
