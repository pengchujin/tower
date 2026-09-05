import Foundation
import Testing
@testable import Tower

@MainActor
struct ClientFilterTests {
    @Test
    func freshInstallShowsEverySupportedClient() {
        let model = makeModel()

        #expect(model.visibleClientOrder == ClientTargetOrder.defaultOrder)
        #expect(model.hiddenClientOrder.isEmpty)
        #expect(model.exportDestinationOrder.compactMap(\.clientTarget) == ClientTargetOrder.defaultOrder)
        #expect(model.exportDestinationOrder.contains(.lanSharing))
        #expect(model.hiddenExportDestinationOrder.isEmpty)
    }

    @Test
    func hidingSelectedClientChoosesVisibleFallbackAndPersists() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.selectTarget(.surge)
        model.setClient(.surge, isVisible: false)

        #expect(!model.visibleClientTargets.contains(.surge))
        #expect(model.selectedTarget == .shadowrocket)
        #expect(!model.exportDestinationOrder.contains(.client(.surge)))

        let reloaded = AppModel(persistence: store, arguments: [])
        #expect(reloaded.visibleClientTargets == model.visibleClientTargets)
        #expect(reloaded.selectedTarget == .shadowrocket)
    }

    @Test
    func addingHiddenClientReturnsItToExportPicker() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.setClient(.karing, isVisible: false)
        #expect(model.hiddenClientOrder.contains(.karing))

        model.setClient(.karing, isVisible: true)

        #expect(model.visibleClientTargets.contains(.karing))
        #expect(model.exportDestinationOrder.contains(.client(.karing)))
        #expect(try store.load()?.visibleClientTargets == nil)
    }

    @Test
    func lanSharingCanBeHiddenRestoredAndPersists() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.setExportDestination(.lanSharing, isVisible: false)

        #expect(!model.isLANSharingVisible)
        #expect(!model.exportDestinationOrder.contains(.lanSharing))
        #expect(model.hiddenExportDestinationOrder.contains(.lanSharing))
        #expect(try store.load()?.isLANSharingVisible == false)

        let reloaded = AppModel(persistence: store, arguments: [])
        #expect(!reloaded.isLANSharingVisible)

        reloaded.setExportDestination(.lanSharing, isVisible: true)

        #expect(reloaded.isLANSharingVisible)
        #expect(reloaded.exportDestinationOrder.contains(.lanSharing))
        #expect(try store.load()?.isLANSharingVisible == nil)
    }

    @Test
    func atLeastOneClientMustRemainVisible() {
        let model = makeModel()

        for target in model.visibleClientOrder.dropFirst() {
            model.setClient(target, isVisible: false)
        }
        let lastClient = model.visibleClientOrder[0]
        model.setClient(lastClient, isVisible: false)

        #expect(model.visibleClientOrder == [lastClient])
        #expect(model.hiddenClientOrder.count == ClientTarget.allCases.count - 1)
    }

    @Test
    func visibleClientsCanMoveWhileHiddenClientsKeepTheirStoredSlot() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])
        model.setClient(.clash, isVisible: false)

        model.moveVisibleClients(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        #expect(Array(model.visibleClientOrder.prefix(2)) == [.surge, .shadowrocket])
        #expect(Array(model.clientOrder.prefix(3)) == [.surge, .clash, .shadowrocket])
        let reloaded = AppModel(persistence: store, arguments: [])
        #expect(reloaded.visibleClientOrder == model.visibleClientOrder)
        #expect(reloaded.hiddenClientOrder == [.clash])
    }

    @Test
    func legacySnapshotWithoutVisibilityKeepsAllClientsVisible() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge,
            clientOrder: ClientTargetOrder.defaultOrder.map(\.rawValue)
        ))

        let model = AppModel(persistence: store, arguments: [])

        #expect(model.visibleClientTargets == Set(ClientTarget.allCases))
        #expect(model.isLANSharingVisible)
    }

    @Test
    func visibleClientsCanReorderWhileLANSharingIsHidden() {
        let model = makeModel()
        model.setExportDestination(.lanSharing, isVisible: false)

        model.moveExportDestination(.client(.surge), across: .client(.shadowrocket))

        #expect(Array(model.visibleClientOrder.prefix(2)) == [.surge, .shadowrocket])
        #expect(!model.exportDestinationOrder.contains(.lanSharing))
    }

    @Test
    func hidingClientBeforeLANKeepsCanonicalPositionAndRestoresExactOrder() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])

        model.setClient(.clash, isVisible: false)

        #expect(Array(model.exportDestinationOrder.prefix(3)) == [
            .client(.shadowrocket),
            .lanSharing,
            .client(.surge),
        ])
        #expect(model.lanSharingOrderIndex == 2)
        let loadedSnapshot = try store.load()
        let saved = try #require(loadedSnapshot)
        #expect(saved.lanSharingFullOrderIndex == 2)
        #expect(saved.lanSharingOrderIndex == 1)

        let reloaded = AppModel(persistence: store, arguments: [])
        #expect(Array(reloaded.exportDestinationOrder.prefix(3)) == [
            .client(.shadowrocket),
            .lanSharing,
            .client(.surge),
        ])

        reloaded.setClient(.clash, isVisible: true)
        #expect(Array(reloaded.exportDestinationOrder.prefix(4)) == [
            .client(.shadowrocket),
            .client(.clash),
            .lanSharing,
            .client(.surge),
        ])
    }

    @Test
    func legacyVisibleLANIndexMigratesWithoutChangingVisibleOrder() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge,
            clientOrder: ClientTargetOrder.defaultOrder.map(\.rawValue),
            clientOrderMigrationVersion: ClientTargetOrder.currentMigrationVersion,
            lanSharingOrderIndex: 1,
            visibleClientTargets: ClientTargetOrder.defaultOrder
                .filter { $0 != .clash }
                .map(\.rawValue)
        ))

        let model = AppModel(persistence: store, arguments: [])

        #expect(model.lanSharingOrderIndex == 2)
        #expect(Array(model.exportDestinationOrder.prefix(3)) == [
            .client(.shadowrocket),
            .lanSharing,
            .client(.surge),
        ])

        model.setClient(.clash, isVisible: true)
        #expect(Array(model.exportDestinationOrder.prefix(4)) == [
            .client(.shadowrocket),
            .client(.clash),
            .lanSharing,
            .client(.surge),
        ])
    }

    @Test
    func canonicalLANIndexWinsOverLegacyProjection() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge,
            clientOrder: ClientTargetOrder.defaultOrder.map(\.rawValue),
            clientOrderMigrationVersion: ClientTargetOrder.currentMigrationVersion,
            lanSharingOrderIndex: 0,
            lanSharingFullOrderIndex: 2
        ))

        let model = AppModel(persistence: store, arguments: [])

        #expect(model.exportDestinationOrder[2] == .lanSharing)
    }

    @Test
    func visibleDestinationReorderOnlyReplacesVisibleFullOrderSlots() throws {
        let model = makeModel()
        model.setClient(.clash, isVisible: false)
        model.setClient(.loon, isVisible: false)
        var reordered = model.exportDestinationOrder
        let surge = try #require(reordered.firstIndex(of: .client(.surge)))
        reordered.remove(at: surge)
        reordered.insert(.client(.surge), at: 0)

        model.setExportDestinationOrder(reordered)
        model.setClient(.clash, isVisible: true)
        model.setClient(.loon, isVisible: true)

        #expect(Array(model.exportDestinationOrder.prefix(5)) == [
            .client(.surge),
            .client(.clash),
            .client(.shadowrocket),
            .lanSharing,
            .client(.loon),
        ])
    }

    @Test
    func snapshotCannotRestoreAHiddenSelectedClient() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge,
            visibleClientTargets: [ClientTarget.karing.rawValue]
        ))

        let model = AppModel(persistence: store, arguments: [])

        #expect(model.visibleClientOrder == [.karing])
        #expect(model.selectedTarget == .karing)
    }

    private func makeModel() -> AppModel {
        AppModel(
            persistence: PersistenceStore(fileURL: temporaryFileURL()),
            arguments: []
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-client-filter-\(UUID().uuidString).json")
    }
}
