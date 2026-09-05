import CoreGraphics

/// Pure geometry and collection operations shared by reorderable views.
///
/// The caller freezes item midpoints when a drag begins, then feeds the
/// gesture's translation into ``insertionIndex``. Keeping those measurements
/// frozen prevents animated neighbours from moving the target underneath the
/// user's finger.
enum ReorderPlanner {
    /// Rebuild vertical slots from actual row heights, including separators.
    /// Reusing the old slot's midpoint is wrong when Dynamic Type wraps rows.
    static func landingOrigin<ID: Hashable>(sourceID: ID, originalIDs: [ID], reorderedIDs: [ID], frames: [ID: CGRect], horizontal: Bool = false) -> CGFloat? {
        guard let first = originalIDs.first, let firstFrame = frames[first],
              let index = reorderedIDs.firstIndex(of: sourceID),
              originalIDs.count == reorderedIDs.count,
              Set(originalIDs) == Set(reorderedIDs),
              originalIDs.allSatisfy({ frames[$0] != nil }) else { return nil }
        let gaps = zip(originalIDs, originalIDs.dropFirst()).compactMap { lhs, rhs -> CGFloat? in
            guard let a = frames[lhs], let b = frames[rhs] else { return nil }
            return max(0, horizontal ? b.minX - a.maxX : b.minY - a.maxY)
        }
        let gap = gaps.first ?? 0
        return reorderedIDs.prefix(index).reduce(horizontal ? firstFrame.minX : firstFrame.minY) { origin, id in
            origin + (horizontal ? frames[id]!.width : frames[id]!.height) + gap
        }
    }
    /// Returns the insertion slot for `sourceID` after temporarily removing it
    /// from `orderedIDs`.
    ///
    /// The returned slot is in `0 ... orderedIDs.count - 1`, which is the full
    /// set of valid insertion positions after one element has been removed.
    /// A dragged midpoint exactly on another item's midpoint remains before
    /// that item; it moves past the item only after crossing its midpoint.
    static func insertionIndex<ID: Hashable>(
        sourceID: ID,
        orderedIDs: [ID],
        frozenMidpoints: [ID: CGFloat],
        translation: CGFloat,
        activationThreshold: CGFloat
    ) -> Int? {
        guard orderedIDs.count > 1,
              orderedIDs.contains(sourceID),
              Set(orderedIDs).count == orderedIDs.count,
              translation.isFinite,
              abs(translation) >= max(0, activationThreshold),
              let sourceMidpoint = frozenMidpoints[sourceID],
              sourceMidpoint.isFinite
        else {
            return nil
        }

        let remainingIDs = orderedIDs.filter { $0 != sourceID }

        let remainingMidpoints = remainingIDs.compactMap { frozenMidpoints[$0] }
        guard remainingMidpoints.count == remainingIDs.count,
              remainingMidpoints.allSatisfy(\.isFinite)
        else {
            return nil
        }

        let draggedMidpoint = sourceMidpoint + translation
        guard draggedMidpoint.isFinite else { return nil }

        return remainingMidpoints.reduce(into: 0) { insertionIndex, midpoint in
            if midpoint < draggedMidpoint {
                insertionIndex += 1
            }
        }
    }

    /// Moves exactly one matching element into a clamped insertion slot.
    ///
    /// `insertionIndex` uses the coordinate system of the array *after* the
    /// source has been removed. If no element has `sourceID`, the original
    /// array is returned unchanged.
    static func moving<Element, ID: Hashable>(
        _ elements: [Element],
        identifiedBy id: KeyPath<Element, ID>,
        sourceID: ID,
        toInsertionIndex insertionIndex: Int
    ) -> [Element] {
        guard let sourceIndex = elements.firstIndex(where: { $0[keyPath: id] == sourceID }) else {
            return elements
        }

        var result = elements
        let source = result.remove(at: sourceIndex)
        result.insert(source, at: min(max(0, insertionIndex), result.count))
        return result
    }
}
