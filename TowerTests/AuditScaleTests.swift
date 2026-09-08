import Foundation
import Testing
@testable import Tower

@MainActor
struct AuditScaleTests {
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
