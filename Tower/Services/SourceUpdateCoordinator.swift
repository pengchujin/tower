import Foundation

/// A source's newest request owns the right to commit. Array positions never
/// cross a suspension point; replacing a snapshot invalidates every ticket.
struct SourceUpdateCoordinator {
    private var tickets: [UUID: UUID] = [:]

    mutating func begin(_ sourceID: UUID) -> UUID {
        let ticket = UUID()
        tickets[sourceID] = ticket
        return ticket
    }

    func accepts(_ ticket: UUID, for sourceID: UUID) -> Bool {
        tickets[sourceID] == ticket
    }

    mutating func finish(_ ticket: UUID, for sourceID: UUID) {
        guard accepts(ticket, for: sourceID) else { return }
        tickets[sourceID] = nil
    }

    mutating func invalidate(_ sourceID: UUID) { tickets[sourceID] = nil }
    mutating func invalidateAll() { tickets.removeAll() }
}
