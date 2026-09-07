import Foundation
import Testing
@testable import Tower

struct NodeGeographyTests {
    private func node(_ name: String = "Premium") -> ProxyNode {
        ProxyNode(kind: .trojan, name: name, server: "edge.example.uk", port: 443, rawURI: "")
    }

    @Test func manualCountryWinsAndSurvivesCoding() throws {
        var n = node("🇯🇵 Tokyo")
        n.countryOverride = "SG"
        let restored = try JSONDecoder().decode(ProxyNode.self, from: JSONEncoder().encode(n))
        #expect(NodeRegionResolver.countryCode(for: restored) == "SG")
        #expect(NodeRegionResolver.clusters(for: [restored], countryCodes: [n.id: "US"]).first?.region.code == "SG")
    }

    @Test func countryOverrideSurvivesUniqueRenameButNotAmbiguousRefresh() {
        var old = node("old")
        old.countryOverride = "SG"
        let refreshed = node("renamed")
        #expect(AppModel.carryingOverCountryOverrides(previous: [old], refreshed: [refreshed]).first?.countryOverride == "SG")
        #expect(AppModel.carryingOverCountryOverrides(previous: [old, node("other")], refreshed: [refreshed]).first?.countryOverride == nil)
    }

    @Test(arguments: ClientTarget.allCases) func manualRegionIsUsedByEveryExport(target: ClientTarget) {
        var n = node("Tokyo")
        n.password = "synthetic-test-only"
        n.countryOverride = "SG"
        let result = ConfigurationGenerator().generate(nodes: [n], preset: RulePreset.builtIns[0], target: target, countryCodes: [n.id: "US"])
        #expect(result.supportedNodeCount == 1)
        #expect(!result.hasInvalidPolicyReferences)
        // Region groups are only emitted when this preset/client uses them.
        if result.content.contains("新加坡") {
            #expect(!result.content.contains("🇯🇵 日本"))
        }
    }

    @Test func asnRangeBoundariesIPv6AndInvalidNameOffset() {
        func word(_ n: UInt32) -> [UInt8] { [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)] }
        let meta = word(64512) + word(0) + [0, 7]
        let v4 = Data([1,1,1,0,1,1,1,255] + meta)
        let start: [UInt8] = [0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 0, count: 12)
        let end: [UInt8] = [0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 255, count: 12)
        let db = IPASNDatabase(ipv4: v4, ipv6: Data(start + end + meta), names: Data("Example".utf8))
        #expect(db.organization(forIPAddress: "1.1.1.0")?.asn == 64512)
        #expect(db.organization(forIPAddress: "1.1.1.255")?.name == "Example")
        #expect(db.organization(forIPAddress: "1.1.2.0") == nil)
        #expect(db.organization(forIPAddress: "2001:db8::42")?.name == "Example")
        #expect(IPASNDatabase(ipv4: v4, ipv6: Data(), names: Data()).organization(forIPAddress: "1.1.1.1") == nil)
    }

    @Test func bundledASNIsPresent() {
        #expect(IPASNDatabase().organization(forIPAddress: "1.1.1.1") != nil)
    }

    @Test @MainActor func manualOverrideIsPersistedAndRestored() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PersistenceStore(fileURL: url)
        let model = AppModel(persistence: store, arguments: [])
        let n = node("🇯🇵 Tokyo")
        model.nodes = [n]
        model.setCountryOverride("SG", for: n)
        #expect(model.countryCode(for: model.nodes[0]) == "SG")
        let restored = AppModel(persistence: store, arguments: [])
        #expect(restored.nodes.first?.countryOverride == "SG")
        restored.setCountryOverride(nil, for: restored.nodes[0])
        #expect(restored.countryCode(for: restored.nodes[0]) == "JP")
    }

    @Test @MainActor func newServerCanResolveWhileOldServerIsStillPending() async {
        let data = Data([1,1,1,0,1,1,1,255] + Array("SG".utf8) + [8,8,8,0,8,8,8,255] + Array("US".utf8))
        let gate = DNSGate()
        let service = IPCountryLookupService(database: IPCountryDatabase(ipv4Data: data, ipv6Data: Data()), resolver: { host in
            if host == "edge.example.uk" { await gate.wait(); return ["1.1.1.1"] }
            return ["8.8.8.8"]
        })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = AppModel(persistence: PersistenceStore(fileURL: url), ipCountryLookupService: service, arguments: [])
        let old = node()
        model.nodes = [old]
        let request = Task { await model.resolveIPCountries(for: [old]) }
        while !(await gate.started) { await Task.yield() }
        var changed = old
        changed.server = "new.example"
        model.nodes = [changed]
        await model.resolveIPCountries(for: [changed])
        #expect(model.ipCountryCode(for: changed) == "US")
        await gate.release()
        await request.value
        #expect(model.ipCountryCode(for: changed) == "US")
    }

    @Test func mixedCountriesRemainUnknownAndDNSIsCoalesced() async {
        let data = Data([1,1,1,0,1,1,1,255] + Array("SG".utf8) + [8,8,8,0,8,8,8,255] + Array("US".utf8))
        let counter = LookupCounter()
        let service = IPCountryLookupService(database: IPCountryDatabase(ipv4Data: data, ipv6Data: Data()), resolver: { _ in
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(10))
            return ["1.1.1.1", "8.8.8.8"]
        })
        async let first = service.countryCode(forHost: "edge.example.uk")
        async let second = service.countryCode(forHost: "edge.example.uk")
        let results = await [first, second]
        #expect(results == [nil, nil])
        #expect(await counter.count == 1)
        #expect(await service.info(forHost: "edge.example.uk").hasCountryConflict)
    }

    @Test func failedDNSCanRetryAfterExpiration() async {
        let data = Data([1,1,1,0,1,1,1,255] + Array("SG".utf8))
        let counter = LookupCounter()
        let service = IPCountryLookupService(database: IPCountryDatabase(ipv4Data: data, ipv6Data: Data()), failureTTL: 0, resolver: { _ in
            await counter.increment()
            return await counter.count == 1 ? [] : ["1.1.1.1"]
        })
        #expect(await service.countryCode(forHost: "retry.example") == nil)
        #expect(await service.countryCode(forHost: "retry.example") == "SG")
    }

    @Test func positiveDNSExpiresAndUsesNewAddress() async {
        let data = Data([1,1,1,0,1,1,1,255] + Array("SG".utf8) + [8,8,8,0,8,8,8,255] + Array("US".utf8))
        let counter = LookupCounter()
        let service = IPCountryLookupService(database: IPCountryDatabase(ipv4Data: data, ipv6Data: Data()), successTTL: 0, resolver: { _ in
            await counter.increment()
            return await counter.count == 1 ? ["1.1.1.1"] : ["8.8.8.8"]
        })
        #expect(await service.countryCode(forHost: "moving.example") == "SG")
        #expect(await service.countryCode(forHost: "moving.example") == "US")
    }
}

private actor LookupCounter {
    var count = 0
    func increment() { count += 1 }
}

private actor DNSGate {
    var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
