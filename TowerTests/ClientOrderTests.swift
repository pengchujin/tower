import XCTest
@testable import Tower

@MainActor
final class ClientOrderTests: XCTestCase {
    func testFreshExportOrderMatchesProductDefault() {
        let model = AppModel(
            persistence: PersistenceStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tower-export-order-default-\(UUID().uuidString).json")
            ),
            arguments: []
        )

        XCTAssertEqual(model.exportDestinationOrder, [
            .client(.shadowrocket),
            .client(.clash),
            .lanSharing,
            .client(.surge),
            .client(.loon),
            .client(.quanx),
            .client(.clashApple),
            .client(.v2box),
            .client(.singBox),
            .client(.hiddify),
            .client(.egern),
        ])
    }

    func testEveryExportDestinationIdentifierRoundTrips() {
        let destinations = ClientTarget.allCases.map(ExportDestination.client) + [.lanSharing]

        for destination in destinations {
            XCTAssertEqual(ExportDestination(identifier: destination.id), destination)
        }
        XCTAssertNil(ExportDestination(identifier: "client:not-a-client"))
        XCTAssertNil(ExportDestination(identifier: "unknown"))
    }

    func testNormalizationRemovesUnknownsAndDuplicatesThenAppendsNewClients() {
        let order = ClientTargetOrder.normalized(
            rawValues: ["quanx", "surge", "unknown", "quanx"]
        )

        XCTAssertEqual(Array(order.prefix(2)), [.quanx, .surge])
        XCTAssertEqual(Set(order), Set(ClientTarget.allCases))
        XCTAssertEqual(order.count, ClientTarget.allCases.count)
    }

    func testPreviousDefaultOrderMigratesToCurrentDefault() {
        let existingOrder = [
            "surge", "clash", "clash-apple", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box"
        ]

        let order = ClientTargetOrder.normalized(rawValues: existingOrder)

        XCTAssertEqual(order, ClientTargetOrder.defaultOrder)
        XCTAssertEqual(order[7], .singBox)
    }

    func testFreshAndPreClashOrdersUseCurrentDefault() {
        let preClashOrder = [
            "surge", "clash", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box"
        ]

        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: nil), ClientTargetOrder.defaultOrder)
        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: preClashOrder), ClientTargetOrder.defaultOrder)
        XCTAssertEqual(ClientTargetOrder.defaultOrder[7], .singBox)
    }

    func testMissingSingBoxIsInsertedAtCurrentDefaultSlotWithoutReorderingExistingClients() {
        let customOrder = [
            "egern", "surge", "quanx", "loon", "shadowrocket", "clash", "hiddify", "v2box", "clash-apple"
        ]

        let order = ClientTargetOrder.normalized(rawValues: customOrder)

        XCTAssertEqual(order[7], .singBox)
        XCTAssertEqual(order.filter { $0 != .singBox }.map(\.rawValue), customOrder)
    }

    func testCurrentExplicitSingBoxPositionIsPreserved() {
        let customOrder = [
            "sing-box", "surge", "clash", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box", "clash-apple"
        ]

        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: customOrder).first, .singBox)
    }

    func testCurrentExplicitClashPositionAfterStashIsPreserved() {
        let customOrder = [
            "shadowrocket", "clash", "clash-apple", "surge", "loon",
            "quanx", "v2box", "sing-box", "hiddify", "egern",
        ]

        XCTAssertEqual(
            ClientTargetOrder.normalized(rawValues: customOrder).map(\.rawValue),
            customOrder
        )
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

        XCTAssertEqual(Array(model.clientOrder.prefix(4)), [
            .shadowrocket,
            .clash,
            .egern,
            .surge,
        ])

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

    func testLegacySnapshotAddsLANSharingThirdWithoutChangingCustomClientOrder() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-export-order-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let customOrder = [
            "egern", "surge", "quanx", "loon", "shadowrocket",
            "clash", "hiddify", "v2box", "clash-apple", "sing-box"
        ]
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: "acl4ssr-online-full",
            selectedTarget: .surge,
            clientOrder: customOrder,
            clientOrderMigrationVersion: ClientTargetOrder.currentMigrationVersion
        ))

        let model = AppModel(persistence: store, arguments: [])

        XCTAssertEqual(model.exportDestinationOrder[2], .lanSharing)
        XCTAssertEqual(model.clientOrder.map(\.rawValue), customOrder)
    }

    func testPreviousOfficialExportOrderMigratesAsOneSequence() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-export-order-official-migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: "acl4ssr-online-full",
            selectedTarget: .surge,
            clientOrder: [
                "surge", "clash", "shadowrocket", "loon", "sing-box",
                "quanx", "hiddify", "egern", "v2box", "clash-apple",
            ],
            clientOrderMigrationVersion: ClientTargetOrder.currentMigrationVersion,
            lanSharingOrderIndex: ExportDestinationOrder.previousDefaultLANSharingIndex
        ))

        let model = AppModel(persistence: store, arguments: [])

        XCTAssertEqual(model.exportDestinationOrder, [
            .client(.shadowrocket),
            .client(.clash),
            .lanSharing,
            .client(.surge),
            .client(.loon),
            .client(.quanx),
            .client(.clashApple),
            .client(.v2box),
            .client(.singBox),
            .client(.hiddify),
            .client(.egern),
        ])
    }

    func testMovingLANSharingToFrontPersistsAcrossReload() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-export-order-persist-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.moveExportDestination(.lanSharing, before: .client(.shadowrocket))

        XCTAssertEqual(model.exportDestinationOrder.first, .lanSharing)
        XCTAssertEqual(try XCTUnwrap(store.load()).lanSharingOrderIndex, 0)
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.exportDestinationOrder.first, .lanSharing)
    }

    func testClientAndLANSharingCanMoveAcrossEachOtherAndPersist() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-export-order-cross-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.moveExportDestination(.client(.loon), before: .lanSharing)
        XCTAssertEqual(Array(model.exportDestinationOrder[2...4]), [
            .client(.loon),
            .lanSharing,
            .client(.surge),
        ])

        model.moveExportDestination(.lanSharing, by: -2)
        XCTAssertEqual(model.exportDestinationOrder[1], .lanSharing)

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.exportDestinationOrder, model.exportDestinationOrder)
    }

    func testDragAcrossMovesRightwardAndCanReachLastPlace() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-export-order-across-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.moveExportDestination(.client(.shadowrocket), across: .client(.clash))
        XCTAssertEqual(Array(model.exportDestinationOrder.prefix(2)), [
            .client(.clash),
            .client(.shadowrocket),
        ])

        model.moveExportDestination(.lanSharing, across: .client(.egern))
        XCTAssertEqual(model.exportDestinationOrder.last, .lanSharing)
        XCTAssertEqual(
            AppModel(persistence: store, arguments: []).exportDestinationOrder.last,
            .lanSharing
        )
    }

    func testLANSharingIndexIsClampedWhenLoadingDamagedSnapshot() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-export-order-clamp-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: "acl4ssr-online-full",
            selectedTarget: .surge,
            lanSharingOrderIndex: Int.max
        ))

        let model = AppModel(persistence: store, arguments: [])

        XCTAssertEqual(model.lanSharingOrderIndex, model.clientOrder.count)
        XCTAssertEqual(model.exportDestinationOrder.last, .lanSharing)
        XCTAssertEqual(
            ExportDestinationOrder.normalizedLANSharingIndex(Int.min, clientCount: model.clientOrder.count),
            0
        )
    }

    func testMovingLANSharingInFrontOfItselfDoesNothing() {
        let model = AppModel(
            persistence: PersistenceStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tower-export-order-noop-\(UUID().uuidString).json")
            ),
            arguments: []
        )
        let original = model.exportDestinationOrder

        model.moveExportDestination(.lanSharing, before: .lanSharing)

        XCTAssertEqual(model.exportDestinationOrder, original)
    }
}
