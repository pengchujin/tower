import Foundation
import Testing
@testable import Tower

@MainActor
struct AuditScaleTests {
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
