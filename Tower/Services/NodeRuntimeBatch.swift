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

/// Latency results publish incrementally with burst coalescing. Cancellation
/// clears the spinner without fabricating a failed measurement.
struct NodeLatencyResultBatch: Sendable {
    let completedIDs: Set<UUID>
    let measurements: [UUID: NodeLatencyMeasurement]

    static func resolve(
        nodes: [ProxyNode],
        concurrency: Int = 32,
        onProgress: @escaping @MainActor @Sendable (Self) -> Void = { _ in },
        operation: @escaping @Sendable (ProxyNode) async -> NodeLatencyMeasurement?
    ) async -> Self {
        await withTaskGroup(of: (UUID, NodeLatencyMeasurement?).self) { group in
            var remaining = nodes.makeIterator()
            for _ in 0..<min(max(1, concurrency), nodes.count) {
                guard !Task.isCancelled, let node = remaining.next() else { break }
                group.addTask { (node.id, await operation(node)) }
            }

            var completedIDs: Set<UUID> = []
            var measurements: [UUID: NodeLatencyMeasurement] = [:]
            completedIDs.reserveCapacity(nodes.count)
            measurements.reserveCapacity(nodes.count)

            var pendingIDs: Set<UUID> = []
            var pendingMeasurements: [UUID: NodeLatencyMeasurement] = [:]
            var lastPublished: ContinuousClock.Instant?
            for await (id, measurement) in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let node = remaining.next() {
                    group.addTask { (node.id, await operation(node)) }
                }
                completedIDs.insert(id)
                pendingIDs.insert(id)
                if let measurement {
                    measurements[id] = measurement
                    pendingMeasurements[id] = measurement
                }
                let now = ContinuousClock.now
                // Publish the first result immediately; coalesce bursts to
                // avoid redrawing the map once per node in large subscriptions.
                if lastPublished == nil || now - lastPublished! >= .milliseconds(100) {
                    await onProgress(Self(completedIDs: pendingIDs, measurements: pendingMeasurements))
                    pendingIDs.removeAll(keepingCapacity: true)
                    pendingMeasurements.removeAll(keepingCapacity: true)
                    lastPublished = now
                }
            }

            if !pendingIDs.isEmpty {
                await onProgress(Self(completedIDs: pendingIDs, measurements: pendingMeasurements))
            }
            return Self(completedIDs: completedIDs, measurements: measurements)
        }
    }
}
