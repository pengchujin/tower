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
