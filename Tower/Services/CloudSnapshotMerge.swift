import CryptoKit
import Foundation

/// Three-way merge against the last shared snapshot. Absence only means deletion
/// when the item was present in that baseline; a fresh device cannot delete it.
enum CloudSnapshotMerge {
    static func data(_ snapshot: AppSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// A digest of what the user decided, and nothing that changes by itself.
    ///
    /// Refreshing regenerates every fetched node's id and rewrites a
    /// subscription's traffic, expiry, error and time; resolving countries
    /// fills a host cache. Counting those as edits synced to iCloud minutes
    /// apart and filled the ten-version history with copies nobody made.
    /// Left out: fetched nodes, subscription status, host caches, the edit
    /// time and the client merely being looked at. Kept, as stable keys that
    /// survive a refresh: which fetched nodes are excluded and their manual
    /// regions. Local nodes are user-authored and count in full.
    static func signature(_ snapshot: AppSnapshot) -> Data? {
        var content = snapshot
        content.updatedAt = nil
        content.resolvedHostCountryCodes = nil
        content.resolvedHostCountryCodeUpdatedAt = nil
        content.resolvedHostCountryDatabaseVersion = nil
        content.selectedTarget = .surge
        content.macClientPreferences?.selectedTarget = .surge
        // Refreshing a scheme re-downloads rule lists kept on this device only;
        // the stamp it leaves behind is not a decision another device needs.
        content.importedSchemes = content.importedSchemes?.map { scheme in
            var scheme = scheme
            scheme.updatedAt = nil
            return scheme
        }
        content.subscriptions = content.subscriptions.map { source in
            var source = source
            source.lastUpdatedAt = nil
            source.lastError = nil
            source.usage = nil
            return source
        }
        let excluded = Set(content.excludedNodeIDs ?? [])
        let decisions = content.nodes.compactMap { node -> String? in
            guard let sourceID = node.sourceID else { return nil }
            let isExcluded = excluded.contains(node.id)
            guard isExcluded || node.countryOverride != nil else { return nil }
            return [sourceID.uuidString, AppModel.nodeStableIdentity(node),
                    isExcluded ? "excluded" : "", node.countryOverride ?? ""].joined(separator: "|")
        }.sorted()
        content.nodes = content.nodes.filter { $0.sourceID == nil }
        let localIDs = Set(content.nodes.map(\.id))
        content.excludedNodeIDs = content.excludedNodeIDs?.filter(localIDs.contains)
        guard var data = try? self.data(content) else { return nil }
        data.append(Data(decisions.joined(separator: "\n").utf8))
        return Data(SHA256.hash(data: data))
    }

    /// Same user-decided content: see `signature`.
    static func sameContent(_ lhs: AppSnapshot?, _ rhs: AppSnapshot?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        guard let left = signature(lhs), let right = signature(rhs) else { return equal(lhs, rhs) }
        return left == right
    }

    static func equal(_ lhs: AppSnapshot?, _ rhs: AppSnapshot?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return (try? object(lhs))?.isEqual(to: (try? object(rhs)) as? [AnyHashable: Any] ?? [:]) == true
    }

    private static func object(_ snapshot: AppSnapshot) throws -> NSDictionary {
        var value = try JSONSerialization.jsonObject(with: data(snapshot)) as! [String: Any]
        value.removeValue(forKey: "updatedAt")
        return value as NSDictionary
    }

    /// The pure part of adopting a committed cloud snapshot, done off the main
    /// actor: every step round-trips whole snapshots through JSON.
    struct Adoption {
        let adopted: AppSnapshot
        let adoptedData: Data
        let baselineData: Data
        let needsAnotherSync: Bool
        /// `signature(adopted)`: what this device now has in common with iCloud.
        let signature: Data?
    }

    /// `latest` is the local state after the commit; `local` what was merged
    /// before it; `cloudContent` what iCloud now holds and so the next
    /// baseline. Backs up a local version the adoption would replace.
    static func adoption(latest: AppSnapshot, local: AppSnapshot, merged: AppSnapshot,
                         cloudContent: AppSnapshot, persistence: PersistenceStore) throws -> Adoption {
        let adopted = try equal(latest, local) ? merged : merge(local: latest, remote: merged, base: local)
        if !sameContent(latest, adopted), !sameContent(latest, local) { try persistence.backup(latest) }
        return Adoption(
            adopted: adopted,
            adoptedData: try PersistenceStore.encoded(adopted),
            baselineData: try PersistenceStore.encoded(cloudContent),
            needsAnotherSync: !sameContent(adopted, cloudContent),
            signature: signature(adopted)
        )
    }

    static func merge(local: AppSnapshot, remote: AppSnapshot, base: AppSnapshot?) throws -> AppSnapshot {
        var l = try object(local) as! [String: Any]
        var r = try object(remote) as! [String: Any]
        // On first contact, defaults are not user deletions. Merge all owned items.
        var b = try base.map { try object($0) as! [String: Any] }
        normalize(&l, &r, &b, snapshots: [base, local, remote].compactMap { $0 })
        var merged = try dictionary(l, r, b, bootstrap: base == nil)
        merged["updatedAt"] = ISO8601DateFormatter().string(from: max(local.updatedAt ?? .distantPast, remote.updatedAt ?? .distantPast))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppSnapshot.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    /// Refresh generates UUIDs and metadata locally. Give identical subscription
    /// nodes one identity before merging, including their selection references.
    private static func normalize(_ l: inout [String: Any], _ r: inout [String: Any], _ b: inout [String: Any]?, snapshots: [AppSnapshot]) {
        var identities: [String: String] = [:]
        var remap: [String: String] = [:]
        // A remark change is still a refresh of the same connection, but a
        // shared endpoint can represent multiple named routes. Only use this
        // fallback when it is unambiguous in every participating snapshot.
        func connectionKey(_ node: ProxyNode) -> String {
            var connection = node
            connection.name = ""
            return node.sourceID!.uuidString + "|" + connection.canonicalKey
        }
        let connectionGroups = snapshots.map {
            Dictionary(grouping: $0.nodes.filter { $0.sourceID != nil }, by: connectionKey)
        }
        let ambiguousKeys = Set(connectionGroups.flatMap { groups in
            groups.compactMap { $0.value.count > 1 ? $0.key : nil }
        })
        var connectionIdentities: [String: String] = [:]
        for snapshot in snapshots {
            for node in snapshot.nodes where node.sourceID != nil {
                let key = node.sourceID!.uuidString + "|" + node.canonicalKey
                let connection = connectionKey(node)
                let unique = !ambiguousKeys.contains(connection)
                let id = identities[key] ?? (unique ? connectionIdentities[connection] : nil) ?? node.id.uuidString
                identities[key] = id
                if unique { connectionIdentities[connection] = id }
                remap[node.id.uuidString] = id
            }
        }
        // Caches and provider usage are observations, not user edits. Pick one
        // coherent observation per source and keep them out of conflict detection.
        var observations: [String: [String: Any]] = [:]
        for snapshot in snapshots {
            for source in snapshot.subscriptions {
                guard let object = try? JSONSerialization.jsonObject(with: data(AppSnapshot(subscriptions: [source], nodes: [], selectedPresetID: "", selectedTarget: .surge))) as? [String: Any],
                      let item = (object["subscriptions"] as? [[String: Any]])?.first else { continue }
                let previous = observations[source.id.uuidString]
                if previous == nil || (item["lastUpdatedAt"] as? String ?? "") > (previous?["lastUpdatedAt"] as? String ?? "") {
                    observations[source.id.uuidString] = item
                }
            }
        }
        let cache = snapshots.max { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }.flatMap { try? object($0) as? [String: Any] } ?? [:]
        func normalized(_ input: [String: Any]) -> [String: Any] {
            var value = input
            if let nodes = value["nodes"] as? [[String: Any]] {
                value["nodes"] = nodes.map { node in
                    var node = node
                    if let id = node["id"] as? String, let mapped = remap[id] { node["id"] = mapped }
                    return node
                }
            }
            if let ids = value["excludedNodeIDs"] as? [String] {
                value["excludedNodeIDs"] = Array(Set(ids.map { remap[$0] ?? $0 })).sorted()
            }
            if let sources = value["subscriptions"] as? [[String: Any]] {
                value["subscriptions"] = sources.map { source in
                    var source = source
                    if let id = source["id"] as? String, let observation = observations[id] {
                        for key in ["lastUpdatedAt", "lastError", "usage"] { source[key] = observation[key] }
                    }
                    return source
                }
            }
            for key in ["resolvedHostCountryCodes", "resolvedHostCountryCodeUpdatedAt", "resolvedHostCountryDatabaseVersion"] { value[key] = cache[key] }
            return value
        }
        l = normalized(l); r = normalized(r); b = b.map(normalized)
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return (a as AnyObject).isEqual?(b) ?? false
    }

    private static func dictionary(_ l: [String: Any], _ r: [String: Any], _ b: [String: Any]?, bootstrap: Bool) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for key in Set(l.keys).union(r.keys).union(b?.keys.map { $0 } ?? []) {
            result[key] = try value(l[key], r[key], b?[key], bootstrap: bootstrap, key: key)
        }
        return result
    }

    private static func value(_ l: Any?, _ r: Any?, _ b: Any?, bootstrap: Bool, key: String) throws -> Any? {
        if key == "excludedNodeIDs" {
            let ls = Set(l as? [String] ?? []), rs = Set(r as? [String] ?? []), bs = Set(b as? [String] ?? [])
            if bootstrap { return ls.union(rs).sorted() }
            return ls.intersection(rs).union(ls.subtracting(bs)).union(rs.subtracting(bs)).sorted()
        }
        // A set of deleted policy groups: two devices deleting different groups
        // both win, and a group restored on one side stays restored.
        if key == "removedGroupNames", l is [String] || r is [String] {
            let ls = Set(l as? [String] ?? []), rs = Set(r as? [String] ?? []), bs = Set(b as? [String] ?? [])
            if bootstrap { return ls.union(rs).sorted() }
            return ls.intersection(rs).union(ls.subtracting(bs)).union(rs.subtracting(bs)).sorted()
        }
        if same(l, r) { return l }
        if !bootstrap {
            if same(l, b) { return r }
            if same(r, b) { return l }
        }
        if let la = l as? [Any], let ra = r as? [Any] {
            let ba = b as? [Any] ?? []
            let all = la + ra + ba
            if !all.isEmpty, all.allSatisfy({ ($0 as? [String: Any])?["id"] as? String != nil }) {
                func keyed(_ items: [Any]) -> [String: Any] {
                    var values: [String: Any] = [:]
                    for item in items { let d = item as! [String: Any]; values[d["id"] as! String] = d }
                    return values
                }
                let values = try dictionary(keyed(la), keyed(ra), bootstrap ? nil : keyed(ba), bootstrap: bootstrap)
                var seen = Set<String>()
                return (ra + la).compactMap { item -> Any? in
                    let id = (item as! [String: Any])["id"] as! String
                    return seen.insert(id).inserted ? values[id] : nil
                }
            }
            if bootstrap && la.isEmpty { return ra }
            if bootstrap && ra.isEmpty { return la }
        }
        if let ld = l as? [String: Any], let rd = r as? [String: Any] {
            return try dictionary(ld, rd, b as? [String: Any], bootstrap: bootstrap)
        }
        if bootstrap {
            if l == nil { return r }
            if r == nil { return l }
            // First sync adopts remote preferences; owned records with differing
            // contents are conflicts, not candidates for timestamp replacement.
            let preferences: Set<String> = ["selectedPresetID", "selectedTarget", "configurationName", "clientOrder", "visibleClientTargets", "lanSharingOrderIndex", "lanSharingFullOrderIndex", "clientOrderMigrationVersion", "macClientPreferences", "renewalRemindersEnabled", "isLANSharingVisible", "appendSubscriptionNameToNodes", "filterSubscriptionInfoNodes", "nodeExportNameFilter", "autoRefreshOnOpen", "preferRuleSets", "preferRuleSetsWasExplicitlySet", "embedRemoteSubscriptionLinks"]
            if preferences.contains(key) { return r }
        }
        throw CloudSyncError.conflict
    }
}
