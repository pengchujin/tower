import XCTest
import UIKit
@testable import Tower

/// A client can support a protocol the user's licence does not cover — Surge
/// needs a paid tier for AnyTLS — so protocols can be excluded per client.
@MainActor
final class ProtocolFilterTests: XCTestCase {
    private func nodes() -> [ProxyNode] {
        [
            ProxyNode(kind: .shadowsocks, name: "SS 01", server: "a.example.com", port: 8388, cipher: "aes-128-gcm", password: "pw", rawURI: "ss://a"),
            ProxyNode(kind: .shadowsocks, name: "SS 02", server: "b.example.com", port: 8388, cipher: "aes-128-gcm", password: "pw", rawURI: "ss://b"),
            ProxyNode(kind: .anytls, name: "AnyTLS 01", server: "c.example.com", port: 40500, password: "pw", tls: true, rawURI: "anytls://c")
        ]
    }

    private func makeModel() throws -> AppModel {
        let store = PersistenceStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("tower-filter-\(UUID().uuidString).json")
        )
        let model = AppModel(persistence: store, arguments: [])
        model.nodes = nodes()
        return model
    }

    // MARK: - Generator

    func testExcludedKindIsCountedAsSkippedRatherThanDisappearing() {
        let result = ConfigurationGenerator().generate(
            nodes: nodes(),
            preset: RulePreset.builtIns[0],
            target: .surge,
            excludedKinds: [.anytls]
        )

        XCTAssertEqual(result.supportedNodeCount, 2)
        XCTAssertEqual(result.skippedNodeCount, 1)
        XCTAssertFalse(result.content.contains("c.example.com"))
    }

    func testExcludingNothingKeepsEveryNode() {
        let result = ConfigurationGenerator().generate(
            nodes: nodes(),
            preset: RulePreset.builtIns[0],
            target: .surge
        )

        XCTAssertEqual(result.supportedNodeCount, 3)
        XCTAssertEqual(result.skippedNodeCount, 0)
    }

    // MARK: - Per client

    func testExclusionAppliesOnlyToTheChosenClient() throws {
        let model = try makeModel()
        model.setExcluded(true, kind: .anytls, for: .surge)

        XCTAssertEqual(model.configuration(target: .surge).supportedNodeCount, 2)
        XCTAssertEqual(model.configuration(target: .clash).supportedNodeCount, 3)
    }

    func testTogglingBackRestoresTheNodes() throws {
        let model = try makeModel()
        model.setExcluded(true, kind: .anytls, for: .surge)
        XCTAssertEqual(model.configuration(target: .surge).supportedNodeCount, 2)

        // The cache is keyed on the exclusion set; without that the old
        // configuration would be served again.
        model.setExcluded(false, kind: .anytls, for: .surge)
        XCTAssertEqual(model.configuration(target: .surge).supportedNodeCount, 3)
    }

    // MARK: - Offered choices

    func testOnlyProtocolsPresentAndSupportedAreOffered() throws {
        let model = try makeModel()

        let surge = model.filterableKinds(for: .surge)
        XCTAssertEqual(surge.map(\.kind), [.shadowsocks, .anytls])
        XCTAssertEqual(surge.first?.count, 2)
    }

    func testSingleCompatibleProtocolStillShowsTheFilter() {
        XCTAssertTrue(ProtocolFilterPolicy.isVisible(compatibleKindCount: 1))
        XCTAssertFalse(ProtocolFilterPolicy.isVisible(compatibleKindCount: 0))
    }

    /// Menus are UIKit menus underneath, and a menu item icon has to reduce to
    /// a plain `Image`. Reading the source only proves the call is spelled
    /// right, so the contract is asserted where it can actually fail: the two
    /// menu call sites use `ProtocolMenuIcon`, and that view has a drawable
    /// image for every protocol including the one with no SF Symbol.
    func testMenuCallSitesUseAnIconAMenuCanRender() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let nodeFilter = try String(
            contentsOf: projectRoot.appendingPathComponent("Tower/Features/Subscriptions/NodeFilterView.swift"),
            encoding: .utf8
        )
        let addSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Tower/Features/Subscriptions/AddSourceSheet.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            nodeFilter.contains("ProtocolMenuIcon(kind: option)"),
            "协议筛选菜单里的图标必须是菜单能渲染的 Image"
        )
        XCTAssertTrue(
            addSource.contains("ProtocolMenuIcon(kind: kind)"),
            "手动添加节点的协议选择器同样是菜单"
        )
    }

    @MainActor
    func testEveryProtocolHasAnIconAMenuCanDraw() {
        for kind in ProxyKind.allCases {
            switch kind.iconDescriptor {
            case .system(let name):
                XCTAssertNotNil(UIImage(systemName: name), "\(kind.title) 的 SF Symbol 不存在")
            case .trojanHorse:
                let image = TrojanHorseImage.shared
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
                XCTAssertEqual(
                    image.renderingMode, .alwaysTemplate,
                    "菜单图标要跟随菜单的着色"
                )
            }
        }
    }

    func testProtocolIconsAvoidTheEquestrianAthlete() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for path in [
            "Tower/Features/Subscriptions/NodeFilterView.swift",
            "Tower/Features/Subscriptions/AddSourceSheet.swift",
            "Tower/Features/Export/ExportView.swift",
            "Tower/Features/Subscriptions/NodeMapOverview.swift",
            "Tower/Features/Subscriptions/SharePayloadSheet.swift",
        ] {
            let source = try String(
                contentsOf: projectRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains("figure.equestrian.sports"),
                "Trojan 不应再显示骑马人物：\(path)"
            )
        }
    }

    func testProtocolTheClientCannotWriteIsNotOffered() throws {
        let model = try makeModel()
        model.nodes.append(
            ProxyNode(kind: .vless, name: "VLESS", server: "d.example.com", port: 443, uuid: "u", rawURI: "vless://d")
        )

        // Surge cannot express VLESS at all, so it is not a choice there.
        XCTAssertFalse(model.filterableKinds(for: .surge).contains { $0.kind == .vless })
        XCTAssertTrue(model.filterableKinds(for: .clash).contains { $0.kind == .vless })
    }

    // MARK: - Persistence

    func testExclusionSurvivesReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-filter-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PersistenceStore(fileURL: url)

        let model = AppModel(persistence: store, arguments: [])
        model.nodes = nodes()
        model.setExcluded(true, kind: .anytls, for: .surge)

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertTrue(reloaded.isExcluded(.anytls, for: .surge))
        XCTAssertFalse(reloaded.isExcluded(.anytls, for: .clash))
        XCTAssertFalse(reloaded.isExcluded(.shadowsocks, for: .surge))
    }

    func testSnapshotWrittenBeforeThisFeatureStillDecodes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let legacy = """
        {
          "nodes": [],
          "selectedPresetID": "self-configuration",
          "selectedTarget": "surge",
          "subscriptions": []
        }
        """
        try Data(legacy.utf8).write(to: url)

        let model = AppModel(persistence: PersistenceStore(fileURL: url), arguments: [])
        XCTAssertTrue(model.excludedKinds.isEmpty)
        XCTAssertEqual(model.selectedPresetID, "acl4ssr-default")
    }
}
