import CoreGraphics
import Testing
@testable import Tower

struct ReorderPlannerTests {
    @Test func landingUsesActualMixedRowHeightsAndHorizontalWidths() {
        let rows = ["a": CGRect(x: 0, y: 10, width: 80, height: 68),
                    "b": CGRect(x: 0, y: 79, width: 80, height: 140),
                    "c": CGRect(x: 0, y: 220, width: 80, height: 90)]
        #expect(ReorderPlanner.landingOrigin(sourceID: "a", originalIDs: ["a", "b", "c"],
            reorderedIDs: ["b", "c", "a"], frames: rows) == 242)
        #expect(ReorderPlanner.landingOrigin(sourceID: "b", originalIDs: ["a", "b", "c"],
            reorderedIDs: ["b", "a", "c"], frames: rows) == 10)
        let cards = rows.mapValues { CGRect(x: $0.minY, y: 0, width: $0.height, height: $0.width) }
        #expect(ReorderPlanner.landingOrigin(sourceID: "a", originalIDs: ["a", "b", "c"],
            reorderedIDs: ["b", "c", "a"], frames: cards, horizontal: true) == 242)
        #expect(ReorderPlanner.landingOrigin(sourceID: "a", originalIDs: ["a", "b", "c"],
            reorderedIDs: ["b", "a"], frames: rows) == nil)
    }
    private let order = ["a", "b", "c", "d"]
    private let midpoints: [String: CGFloat] = [
        "a": 0,
        "b": 100,
        "c": 200,
        "d": 300,
    ]

    @Test(arguments: [
        (-101.0, 0), // Before a.
        (-100.0, 0), // Exactly on a stays before a.
        (-99.0, 1),  // Between a and c.
        (100.0, 1),  // Exactly on c stays before c.
        (101.0, 2),  // Between c and d.
        (200.0, 2),  // Exactly on d stays before d.
        (201.0, 3),  // After d.
    ])
    func everyInsertionGapIsReachableFromFrozenMidpoints(
        translation: CGFloat,
        expectedIndex: Int
    ) {
        let index = ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: translation,
            activationThreshold: 0
        )

        #expect(index == expectedIndex)
    }

    @Test
    func activationThresholdIsInclusiveInBothDirections() {
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: 11.99,
            activationThreshold: 12
        ) == nil)
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: -11.99,
            activationThreshold: 12
        ) == nil)
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: 12,
            activationThreshold: 12
        ) == 1)
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: -12,
            activationThreshold: 12
        ) == 1)
    }

    @Test
    func draggingFromEitherDirectionCanReachTheMiddleInsertionSlot() {
        let fromLeft = ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: 150,
            activationThreshold: 0
        )
        let fromRight = ReorderPlanner.insertionIndex(
            sourceID: "d",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: -150,
            activationThreshold: 0
        )

        #expect(fromLeft == 2)
        #expect(fromRight == 2)
    }

    @Test
    func movingOnePlaceRightDoesNotJumpToTheFront() {
        let index = ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: 101,
            activationThreshold: 0
        )
        let reordered = ReorderPlanner.moving(
            order,
            identifiedBy: \.self,
            sourceID: "b",
            toInsertionIndex: index ?? 0
        )

        #expect(index == 2)
        #expect(reordered == ["a", "c", "b", "d"])
    }

    @Test
    func reorderClampsAtBothEndsWithoutLosingOrDuplicatingElements() {
        let movedToStart = ReorderPlanner.moving(
            order,
            identifiedBy: \.self,
            sourceID: "c",
            toInsertionIndex: -100
        )
        let movedToEnd = ReorderPlanner.moving(
            order,
            identifiedBy: \.self,
            sourceID: "b",
            toInsertionIndex: 100
        )

        #expect(movedToStart == ["c", "a", "b", "d"])
        #expect(movedToEnd == ["a", "c", "d", "b"])
        #expect(movedToStart.count == order.count)
        #expect(movedToEnd.count == order.count)
        #expect(Set(movedToStart) == Set(order))
        #expect(Set(movedToEnd) == Set(order))
    }

    @Test
    func reorderUsesStableIdentityAndPreservesTheExactElement() {
        struct Item: Equatable {
            let id: Int
            let payload: String
        }

        let items = [
            Item(id: 7, payload: "first"),
            Item(id: 11, payload: "source"),
            Item(id: 19, payload: "last"),
        ]

        let reordered = ReorderPlanner.moving(
            items,
            identifiedBy: \.id,
            sourceID: 11,
            toInsertionIndex: 2
        )
        let missingSource = ReorderPlanner.moving(
            items,
            identifiedBy: \.id,
            sourceID: 99,
            toInsertionIndex: 0
        )

        #expect(reordered == [items[0], items[2], items[1]])
        #expect(missingSource == items)
    }

    @Test
    func incompleteOrDuplicateGeometryDoesNotProduceATarget() {
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "missing",
            orderedIDs: order,
            frozenMidpoints: midpoints,
            translation: 20,
            activationThreshold: 10
        ) == nil)
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: ["a", "b", "b", "c"],
            frozenMidpoints: midpoints,
            translation: 20,
            activationThreshold: 10
        ) == nil)
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: ["a", "a", "b", "c"],
            frozenMidpoints: midpoints,
            translation: 20,
            activationThreshold: 10
        ) == nil)
        #expect(ReorderPlanner.insertionIndex(
            sourceID: "b",
            orderedIDs: order,
            frozenMidpoints: ["a": 0, "b": 100, "c": 200],
            translation: 20,
            activationThreshold: 10
        ) == nil)
    }
}
