import Foundation

struct GenerationCacheKey: Hashable {
    let target: ClientTarget
    let presetID: String
    let nodesHash: Int
    let countryCodesHash: Int
    let rulesHash: Int
    let excludedHash: Int
    let preferRuleSets: Bool
    let remoteSubscriptionsHash: Int
    /// A node subscription and a complete profile are different documents built
    /// from the same nodes, so they need separate entries rather than one
    /// overwriting the other.
    let contentMode: ExportContentMode

    init(
        target: ClientTarget,
        presetID: String,
        nodesHash: Int,
        countryCodesHash: Int,
        rulesHash: Int = 0,
        excludedHash: Int = 0,
        preferRuleSets: Bool = true,
        remoteSubscriptionsHash: Int = 0,
        contentMode: ExportContentMode = .fullConfiguration
    ) {
        self.target = target
        self.presetID = presetID
        self.nodesHash = nodesHash
        self.countryCodesHash = countryCodesHash
        self.rulesHash = rulesHash
        self.excludedHash = excludedHash
        self.preferRuleSets = preferRuleSets
        self.remoteSubscriptionsHash = remoteSubscriptionsHash
        self.contentMode = contentMode
    }

    /// What makes a previously generated profile obsolete.
    fileprivate var signature: GenerationCacheSignature {
        GenerationCacheSignature(
            presetID: presetID,
            nodesHash: nodesHash,
            countryCodesHash: countryCodesHash,
            rulesHash: rulesHash
        )
    }

    /// The same, for node subscriptions. They contain no rules, so nothing
    /// about the selected scheme belongs here.
    fileprivate var nodeSubscriptionSignature: NodeSubscriptionSignature {
        NodeSubscriptionSignature(
            nodesHash: nodesHash,
            countryCodesHash: countryCodesHash
        )
    }
}

private struct GenerationCacheSignature: Hashable {
    let presetID: String
    let nodesHash: Int
    let countryCodesHash: Int
    let rulesHash: Int
}

private struct NodeSubscriptionSignature: Hashable {
    let nodesHash: Int
    let countryCodesHash: Int
}

struct ConfigurationCache {
    /// Complete client profiles. One of these can be several hundred kilobytes,
    /// so a superseded generation is dropped as soon as the nodes or the rules
    /// change rather than accumulating one copy per client.
    private var profiles: [GenerationCacheKey: GeneratedConfiguration] = [:]
    private var profileSignature: GenerationCacheSignature?

    /// Node subscriptions, held apart from the profiles.
    ///
    /// They are built from the nodes alone and name no scheme, so sharing one
    /// signature with the profiles made the two evict each other every time the
    /// user switched between 完整配置 and 仅节点 — which is exactly the switch
    /// this cache exists to make cheap.
    private var nodeSubscriptions: [GenerationCacheKey: GeneratedConfiguration] = [:]
    private var nodeSubscriptionSignature: NodeSubscriptionSignature?

    var count: Int { profiles.count + nodeSubscriptions.count }

    subscript(key: GenerationCacheKey) -> GeneratedConfiguration? {
        get {
            key.contentMode == .nodesOnly ? nodeSubscriptions[key] : profiles[key]
        }
        set {
            if key.contentMode == .nodesOnly {
                guard let newValue else {
                    nodeSubscriptions[key] = nil
                    return
                }
                if nodeSubscriptionSignature != key.nodeSubscriptionSignature {
                    nodeSubscriptions.removeAll(keepingCapacity: true)
                    nodeSubscriptionSignature = key.nodeSubscriptionSignature
                }
                nodeSubscriptions = nodeSubscriptions.filter { $0.key.target != key.target }
                nodeSubscriptions[key] = newValue
                return
            }

            guard let newValue else {
                profiles[key] = nil
                return
            }
            if profileSignature != key.signature {
                profiles.removeAll(keepingCapacity: true)
                profileSignature = key.signature
            }
            profiles = profiles.filter { $0.key.target != key.target }
            profiles[key] = newValue
        }
    }
}
