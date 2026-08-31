import XCTest
@testable import Tower

@MainActor
final class ClientOrderTests: XCTestCase {
    func testNormalizationRemovesUnknownsAndDuplicatesThenAppendsNewClients() {
        let order = ClientTargetOrder.normalized(
            rawValues: ["quanx", "surge", "unknown", "quanx"]
        )

        XCTAssertEqual(Array(order.prefix(2)), [.quanx, .surge])
        XCTAssertEqual(Set(order), Set(ClientTarget.allCases))
        XCTAssertEqual(order.count, ClientTarget.allCases.count)
    }

    func testPreviousDefaultOrderMigratesSingBoxToFifthPlace() {
        let existingOrder = [
            "surge", "clash", "clash-apple", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box"
        ]

        let order = ClientTargetOrder.normalized(rawValues: existingOrder)

        XCTAssertEqual(order, ClientTargetOrder.defaultOrder)
        XCTAssertEqual(order[4], .singBox)
    }

    func testSingBoxIsFifthForFreshAndPreClashOrders() {
        let preClashOrder = [
            "surge", "clash", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box"
        ]

        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: nil), ClientTargetOrder.defaultOrder)
        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: preClashOrder), ClientTargetOrder.defaultOrder)
        XCTAssertEqual(ClientTargetOrder.defaultOrder[4], .singBox)
    }

    func testMissingSingBoxIsInsertedFifthWithoutReorderingExistingClients() {
        let customOrder = [
            "egern", "surge", "quanx", "loon", "shadowrocket", "clash", "hiddify", "v2box", "clash-apple"
        ]

        let order = ClientTargetOrder.normalized(rawValues: customOrder)

        XCTAssertEqual(order[4], .singBox)
        XCTAssertEqual(order.filter { $0 != .singBox }.map(\.rawValue), customOrder)
    }

    func testCurrentExplicitSingBoxPositionIsPreserved() {
        let customOrder = [
            "sing-box", "surge", "clash", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box", "clash-apple"
        ]

        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: customOrder).first, .singBox)
    }

    func testLegacyExplicitSingBoxPositionMigratesToFifthOnce() {
        let customOrder = [
            "sing-box", "egern", "surge", "quanx", "loon", "shadowrocket", "clash", "hiddify", "v2box", "clash-apple"
        ]

        let migrated = ClientTargetOrder.normalized(
            rawValues: customOrder,
            savedMigrationVersion: nil
        )

        XCTAssertEqual(migrated[4], .singBox)
        XCTAssertEqual(
            migrated.filter { $0 != .singBox }.map(\.rawValue),
            customOrder.filter { $0 != "sing-box" }
        )
    }

    func testPersistedMigrationVersionKeepsLaterSingBoxDrag() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-client-order-version-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: "acl4ssr-online-full",
            selectedTarget: .surge,
            clientOrder: [
                "sing-box", "surge", "clash", "shadowrocket", "loon",
                "quanx", "hiddify", "egern", "v2box", "clash-apple"
            ]
        ))

        let migrated = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(migrated.clientOrder[4], .singBox)

        migrated.moveClient(.singBox, before: .surge)
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.clientOrder.first, .singBox)
    }

    func testDraggingClientBeforeAnotherPersistsOrder() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-client-order-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.moveClient(.egern, before: .surge)

        XCTAssertEqual(model.clientOrder.first, .egern)
        XCTAssertEqual(model.clientOrder.dropFirst().first, .surge)

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.clientOrder, model.clientOrder)
    }

    func testMovingClientInFrontOfItselfDoesNothing() {
        let model = AppModel(
            persistence: PersistenceStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tower-client-noop-\(UUID().uuidString).json")
            ),
            arguments: []
        )
        let original = model.clientOrder

        model.moveClient(.surge, before: .surge)

        XCTAssertEqual(model.clientOrder, original)
    }
}
