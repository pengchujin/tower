import XCTest
@testable import Tower

final class MotionDesignTests: XCTestCase {
    func testPressFeedbackIsImmediateAndRemovesScaleForReducedMotion() {
        XCTAssertEqual(
            TowerMotion.pressScale(isPressed: true, reduceMotion: false),
            0.97,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TowerMotion.pressScale(isPressed: false, reduceMotion: false),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TowerMotion.pressScale(isPressed: true, reduceMotion: true),
            1,
            accuracy: 0.0001
        )
        XCTAssertLessThanOrEqual(TowerMotion.pressInDuration, 0.16)
        XCTAssertLessThan(TowerMotion.pressInDuration, TowerMotion.pressReleaseDuration)
    }

    func testSelectionFeedbackIsSubtleAndRemovesScaleForReducedMotion() {
        XCTAssertEqual(
            TowerMotion.selectionSymbolScale(isSelected: false, reduceMotion: false),
            0.92,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TowerMotion.selectionSymbolScale(isSelected: true, reduceMotion: false),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TowerMotion.selectionSymbolScale(isSelected: false, reduceMotion: true),
            1,
            accuracy: 0.0001
        )
        XCTAssertLessThanOrEqual(TowerMotion.selectionDuration, 0.20)
    }

    func testDisclosureMotionIsSharedAndShort() {
        XCTAssertLessThanOrEqual(TowerMotion.disclosureResponse, 0.30)
        XCTAssertLessThanOrEqual(TowerMotion.reducedMotionDuration, 0.16)
    }

    func testCardBackgroundAndContentsShareGeometryDuringAncestorCollapse() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Tower/Design/TowerTheme.swift"),
            encoding: .utf8
        )
        let modifierStart = try XCTUnwrap(source.range(of: "struct TowerCardModifier: ViewModifier"))
        let extensionStart = try XCTUnwrap(source.range(of: "extension View"))
        let modifierSource = String(source[modifierStart.lowerBound..<extensionStart.lowerBound])

        XCTAssertTrue(
            modifierSource.contains(".geometryGroup()"),
            "卡片受祖先展开收起影响时，背景与内部文字必须作为同一几何单元移动"
        )
    }

    func testDisclosureHeadersAnimateOnlyTheirChevrons() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let subscriptions = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift"),
            encoding: .utf8
        )
        let subscriptionStart = try XCTUnwrap(subscriptions.range(of: "private struct SubscriptionCard"))
        let subscriptionToggle = try XCTUnwrap(
            subscriptions.range(of: "Toggle(", range: subscriptionStart.upperBound..<subscriptions.endIndex)
        )
        let subscriptionHeader = String(subscriptions[subscriptionStart.lowerBound..<subscriptionToggle.lowerBound])

        let nodes = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/NodeMapOverview.swift"),
            encoding: .utf8
        )
        let nodeStart = try XCTUnwrap(nodes.range(of: "struct ExpandableNodeRow"))
        let nodeShare = try XCTUnwrap(
            nodes.range(of: "sharePayload = SharePayloadFactory.node", range: nodeStart.upperBound..<nodes.endIndex)
        )
        let nodeHeader = String(nodes[nodeStart.lowerBound..<nodeShare.lowerBound])

        let settings = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        let reminderStart = try XCTUnwrap(settings.range(of: "private struct RenewalReminderSection"))
        let reminderList = try XCTUnwrap(
            settings.range(of: "if isExpanded {", range: reminderStart.upperBound..<settings.endIndex)
        )
        let reminderHeader = String(settings[reminderStart.lowerBound..<reminderList.lowerBound])

        for header in [subscriptionHeader, nodeHeader, reminderHeader] {
            XCTAssertTrue(header.contains(".rotationEffect(.degrees(isExpanded ? 180 : 0))"))
            XCTAssertTrue(header.contains(".buttonStyle(.plain)"))
            XCTAssertFalse(
                header.contains(".buttonStyle(ResponsivePressButtonStyle())"),
                "展开按钮不能让名称、图标和整行跟着缩放或改变透明度"
            )
        }
    }
}
