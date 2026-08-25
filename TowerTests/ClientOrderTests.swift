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

    func testClashAppMovesToTheEndWhenMigratingThePreviousDefaultOrder() throws {
        let clashApp = try XCTUnwrap(ClientTarget(rawValue: "clash-apple"))
        let existingOrder = [
            "surge", "clash", "clash-apple", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box"
        ]

        let order = ClientTargetOrder.normalized(rawValues: existingOrder)

        XCTAssertEqual(order.last, clashApp)
    }

    func testClashAppIsLastForFreshAndPreClashOrders() throws {
        let clashApp = try XCTUnwrap(ClientTarget(rawValue: "clash-apple"))
        let preClashOrder = [
            "surge", "clash", "shadowrocket", "loon", "quanx", "hiddify", "egern", "v2box"
        ]

        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: nil).last, clashApp)
        XCTAssertEqual(ClientTargetOrder.normalized(rawValues: preClashOrder).last, clashApp)
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
