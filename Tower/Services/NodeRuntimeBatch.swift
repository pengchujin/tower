import Foundation

/// Collects a bounded group of asynchronous country lookups without exposing
/// each individual completion to the observable app model. The caller can
/// publish both collections once after the whole batch has settled.
struct NodeCountryResolutionBatch: Sendable {
    let completedIDs: Set<UUID>
    let countryCodes: [UUID: String]

    static func resolve(
        nodes: [ProxyNode],
        lookup: @escaping @Sendable (ProxyNode) async -> String?
    ) async -> Self {
        await withTaskGroup(of: (UUID, String?).self) { group in
            for node in nodes {
                group.addTask {
                    (node.id, await lookup(node))
                }
            }

            var completedIDs: Set<UUID> = []
            var countryCodes: [UUID: String] = [:]
            completedIDs.reserveCapacity(nodes.count)
            countryCodes.reserveCapacity(nodes.count)

            for await (id, countryCode) in group {
                completedIDs.insert(id)
                if let countryCode {
                    countryCodes[id] = countryCode
                }
            }

            return Self(completedIDs: completedIDs, countryCodes: countryCodes)
        }
    }
}

/// Latency counterpart to `NodeCountryResolutionBatch`. Failed probes are
/// intentionally represented by a completed id with no measurement so the UI
/// can clear its spinner without publishing one observable mutation per node.
struct NodeLatencyResultBatch: Sendable {
    let completedIDs: Set<UUID>
    let measurements: [UUID: NodeLatencyMeasurement]

    static func resolve(
        nodes: [ProxyNode],
        operation: @escaping @Sendable (ProxyNode) async -> NodeLatencyMeasurement?
    ) async -> Self {
        await withTaskGroup(of: (UUID, NodeLatencyMeasurement?).self) { group in
            for node in nodes {
                group.addTask {
                    (node.id, await operation(node))
                }
            }

            var completedIDs: Set<UUID> = []
            var measurements: [UUID: NodeLatencyMeasurement] = [:]
            completedIDs.reserveCapacity(nodes.count)
            measurements.reserveCapacity(nodes.count)

            for await (id, measurement) in group {
                completedIDs.insert(id)
                if let measurement {
                    measurements[id] = measurement
                }
            }

            return Self(completedIDs: completedIDs, measurements: measurements)
        }
    }
}
