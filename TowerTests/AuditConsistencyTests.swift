import Foundation
import Testing
@testable import Tower

private actor PausedCloud: CloudSnapshotSyncing {
    nonisolated let isAccountAvailable = true
    private var continuation: CheckedContinuation<AppSnapshot?, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var uploads: [AppSnapshot] = []

    func download() async throws -> AppSnapshot? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiter?.resume()
            waiter = nil
        }
    }
    func waitForDownload() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish(_ snapshot: AppSnapshot?) { continuation?.resume(returning: snapshot); continuation = nil }
    func upload(_ snapshot: AppSnapshot) { uploads.append(snapshot) }
    func removeRemoteSnapshot() {}
}

private actor PausedSourceFetcher: SubscriptionFetching {
    private var pending: [String: CheckedContinuation<ImportResult, Never>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        await withCheckedContinuation { continuation in
            pending[source.urlString] = continuation
            waiters.removeValue(forKey: source.urlString)?.resume()
        }
    }
    func waitForRequest(_ url: String) async {
        if pending[url] != nil { return }
        await withCheckedContinuation { waiters[url] = $0 }
    }
    func finish(_ url: String, sourceID: UUID, name: String) {
        let node = ProxyNode(sourceID: sourceID, kind: .shadowsocks, name: name,
                             server: "node.example.test", port: 443, password: "fixture", rawURI: "")
        pending.removeValue(forKey: url)?.resume(returning: ImportResult(nodes: [node], rejectedLineCount: 0, usage: nil))
    }
}

@MainActor
@Suite(.serialized)
struct AuditConsistencyTests {
    private func temporaryStore() -> PersistenceStore {
        PersistenceStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("tower-audit-\(UUID()).json"))
    }

    @Test(arguments: [false, true])
    func localEditsDuringCloudDownloadWinInMemoryDiskAndUpload(coalesced: Bool) async throws {
        let previous = CloudSyncPreference.isEnabled()
        CloudSyncPreference.setEnabled(false)
        defer { CloudSyncPreference.setEnabled(previous) }
        let store = temporaryStore()
        try store.save(AppSnapshot(subscriptions: [], nodes: [], selectedPresetID: "acl4ssr-default", selectedTarget: .surge, updatedAt: Date.now.addingTimeInterval(-100)))
        let cloud = PausedCloud()
        let model = AppModel(persistence: store, cloudSync: cloud,
                             persistencePolicy: coalesced ? .coalesced(.seconds(60)) : .immediate,
                             arguments: [])
        let sync = Task { await model.setICloudSyncEnabled(true) }
        await cloud.waitForDownload()
        model.setConfigurationName("new local edit")
        let remote = AppSnapshot(subscriptions: [], nodes: [], selectedPresetID: "acl4ssr-default", selectedTarget: .clash, updatedAt: Date.now.addingTimeInterval(-50))
        await cloud.finish(remote)
        await sync.value
        #expect(model.configurationName == "new local edit")
        model.flushPendingWrite()
        #expect(try store.load()?.configurationName == "new local edit")
        #expect(await cloud.uploads.last?.configurationName == "new local edit")
        await model.setICloudSyncEnabled(false)
    }

    @Test func disablingSyncDuringDownloadPreventsApplyAndUpload() async {
        let previous = CloudSyncPreference.isEnabled()
        CloudSyncPreference.setEnabled(false)
        defer { CloudSyncPreference.setEnabled(previous) }
        let cloud = PausedCloud()
        let model = AppModel(persistence: temporaryStore(), cloudSync: cloud, arguments: [])
        let sync = Task { await model.setICloudSyncEnabled(true) }
        await cloud.waitForDownload()
        await model.setICloudSyncEnabled(false)
        await cloud.finish(AppSnapshot(subscriptions: [], nodes: [], selectedPresetID: "acl4ssr-default", selectedTarget: .clash, updatedAt: .distantFuture))
        await sync.value
        #expect(model.selectedTarget == .surge)
        #expect(await cloud.uploads.isEmpty)
    }

    @Test(arguments: [false, true])
    func editingSourceWhileItIsDeletedOrReorderedDoesNotUseOldIndex(delete: Bool) async throws {
        let fetcher = PausedSourceFetcher()
        let model = AppModel(persistence: temporaryStore(), subscriptionService: fetcher, arguments: ["--demo"])
        let source = try #require(model.subscriptions.first)
        let other = SubscriptionSource(name: "other", urlString: "https://other.example.test/sub")
        model.subscriptions.append(other)
        let url = "https://new.example.test/sub"
        let edit = Task { try await model.updateSubscriptionDetails(source, name: "edited", urlString: url, userAgent: nil, dnsOverHTTPSURL: nil) }
        await fetcher.waitForRequest(url)
        if delete { model.deleteSubscription(source) } else { model.subscriptions.reverse() }
        await fetcher.finish(url, sourceID: source.id, name: "new node")
        try await edit.value
        #expect(model.subscriptions.first(where: { $0.id == other.id }) == other)
        if delete {
            #expect(!model.nodes.contains { $0.sourceID == source.id })
        } else {
            #expect(model.subscriptions.first(where: { $0.id == source.id })?.name == "edited")
            #expect(model.nodes.contains { $0.sourceID == source.id && $0.name == "new node" })
        }
    }

    @Test func newestEditWinsEvenWhenOldFetchIgnoresCancellation() async throws {
        let fetcher = PausedSourceFetcher()
        let model = AppModel(persistence: temporaryStore(), subscriptionService: fetcher, arguments: ["--demo"])
        let source = try #require(model.subscriptions.first)
        let oldURL = "https://old.example.test/sub"
        let newURL = "https://new.example.test/sub"
        let old = Task { try await model.updateSubscriptionDetails(source, name: "old", urlString: oldURL, userAgent: nil, dnsOverHTTPSURL: nil) }
        await fetcher.waitForRequest(oldURL)
        let new = Task { try await model.updateSubscriptionDetails(source, name: "new", urlString: newURL, userAgent: nil, dnsOverHTTPSURL: nil) }
        await fetcher.waitForRequest(newURL)
        await fetcher.finish(newURL, sourceID: source.id, name: "new node")
        try await new.value
        await fetcher.finish(oldURL, sourceID: source.id, name: "old node")
        try await old.value
        #expect(model.subscriptions.first(where: { $0.id == source.id })?.urlString == newURL)
        #expect(model.nodes.filter { $0.sourceID == source.id }.map(\.name) == ["new node"])
    }

    @Test func oldRefreshCannotOverwriteNewEditedURL() async throws {
        let fetcher = PausedSourceFetcher()
        let model = AppModel(persistence: temporaryStore(), subscriptionService: fetcher, arguments: ["--demo"])
        let source = try #require(model.subscriptions.first)
        let refresh = Task { await model.updateSubscription(id: source.id) }
        await fetcher.waitForRequest(source.urlString)
        let url = "https://new.example.test/sub"
        let edit = Task { try await model.updateSubscriptionDetails(source, name: "new", urlString: url, userAgent: nil, dnsOverHTTPSURL: nil) }
        await fetcher.waitForRequest(url)
        await fetcher.finish(url, sourceID: source.id, name: "new node")
        try await edit.value
        await fetcher.finish(source.urlString, sourceID: source.id, name: "stale node")
        #expect(await refresh.value == false)
        #expect(model.subscriptions.first?.urlString == url)
        #expect(model.nodes.filter { $0.sourceID == source.id }.map(\.name) == ["new node"])
        #expect(model.refreshingSourceIDs.isEmpty)
    }

    @Test func cloudReplacementInvalidatesPendingSourceEdit() async throws {
        let previous = CloudSyncPreference.isEnabled()
        CloudSyncPreference.setEnabled(false)
        defer { CloudSyncPreference.setEnabled(previous) }
        let store = temporaryStore()
        let source = SubscriptionSource(name: "old", urlString: "https://old.example.test/sub")
        try store.save(AppSnapshot(subscriptions: [source], nodes: [], selectedPresetID: "acl4ssr-default", selectedTarget: .surge, updatedAt: .distantPast))
        let fetcher = PausedSourceFetcher()
        let cloud = PausedCloud()
        let model = AppModel(persistence: store, cloudSync: cloud, subscriptionService: fetcher, arguments: [])
        let url = "https://new.example.test/sub"
        let edit = Task { try await model.updateSubscriptionDetails(source, name: "edited", urlString: url, userAgent: nil, dnsOverHTTPSURL: nil) }
        await fetcher.waitForRequest(url)
        let sync = Task { await model.setICloudSyncEnabled(true) }
        await cloud.waitForDownload()
        await cloud.finish(AppSnapshot(subscriptions: [], nodes: [], selectedPresetID: "acl4ssr-default", selectedTarget: .clash, updatedAt: .now))
        await sync.value
        await fetcher.finish(url, sourceID: source.id, name: "stale")
        try await edit.value
        #expect(model.subscriptions.isEmpty)
        #expect(model.nodes.isEmpty)
        #expect(try store.load()?.nodes.isEmpty == true)
        await model.setICloudSyncEnabled(false)
    }

    @Test func remoteOnlyExportIsUsableAndClientSwitchesReuseCache() throws {
        let model = AppModel(persistence: temporaryStore(), arguments: ["--demo"])
        model.embedRemoteSubscriptionLinks = true
        model.excludedNodeIDs = Set(model.nodes.map(\.id))
        let remote = model.configuration(target: .clash)
        #expect(remote.remoteSourceCount > 0)
        #expect(remote.supportedNodeCount == 0)
        #expect(remote.skippedNodeCount == 0)
        #expect(remote.hasExportableProxies)
        #expect(model.hasExportableSources)
        _ = model.configuration(target: .shadowrocket)
        let count = model.configurationGenerationCount
        let again = model.configuration(target: .clash)
        #expect(model.configurationGenerationCount == count)
        #expect(again.content == remote.content)
        #expect(model.filterableKinds(for: .clash).isEmpty)
    }

    @Test func mapRevisionIncludesCredentialNameAndProtocolChanges() throws {
        var node = ProxyNode(kind: .shadowsocks, name: "Japan", server: "node.example.test", port: 443, password: "old", rawURI: "")
        let original = NodeMapPresentation.revision(nodes: [node], countryCodes: [:])
        node.password = "new"
        #expect(NodeMapPresentation.revision(nodes: [node], countryCodes: [:]) != original)
        node.name = "Singapore"
        let presentation = NodeMapPresentation(nodes: [node], countryCodes: [:])
        #expect(presentation.clusters.first?.nodes.first?.password == "new")
        #expect(presentation.clusters.first?.region.code == "SG")
    }
}
