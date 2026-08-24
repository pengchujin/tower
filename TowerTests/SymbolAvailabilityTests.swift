import XCTest
import SwiftUI
import UIKit
@testable import Tower

/// `Image(systemName:)` draws nothing for a name SF Symbols does not have, and
/// says nothing about it — no crash, no log, just a blank where the icon was.
/// Snell shipped with an invented `shell.fill` and went unnoticed until the
/// export screen showed a gap, so every symbol the app names is checked here.
final class SymbolAvailabilityTests: XCTestCase {
    func testEveryProtocolSymbolExists() {
        for kind in ProxyKind.allCases {
            guard case .system(let symbol) = kind.iconDescriptor else { continue }
            XCTAssertNotNil(
                UIImage(systemName: symbol),
                "\(kind.rawValue) 用了不存在的 SF Symbol：\(symbol)"
            )
        }
    }

    func testProtocolSymbolsReflectTheirProtocolMeaning() {
        let expected: [ProxyKind: ProxyIconDescriptor] = [
            .shadowsocks: .system("paperplane.fill"),
            .shadowsocksR: .system("paperplane.circle.fill"),
            .vmess: .system("point.3.filled.connected.trianglepath.dotted"),
            .vless: .system("v.circle.fill"),
            .trojan: .trojanHorse,
            .hysteria: .system("hare.fill"),
            .hysteria2: .system("hare.fill"),
            .tuic: .system("bolt.circle.fill"),
            .wireguard: .system("shield.checkered"),
            .anytls: .system("lock.shield.fill"),
            .snell: .system("s.square.fill"),
            .socks5: .system("5.circle.fill"),
            .http: .system("globe"),
            .unknown: .system("questionmark.circle.fill"),
        ]

        XCTAssertEqual(expected.count, ProxyKind.allCases.count)
        for kind in ProxyKind.allCases {
            XCTAssertEqual(kind.iconDescriptor, expected[kind], "\(kind.title) 的图标没有表达协议含义")
        }
    }

    func testTrojanHorseShapeIsReadableAtACompactIconSize() {
        let bounds = TrojanHorseShape()
            .path(in: CGRect(x: 0, y: 0, width: 38, height: 38))
            .boundingRect

        XCTAssertGreaterThan(bounds.width, 30)
        XCTAssertGreaterThan(bounds.height, 30)
        XCTAssertLessThanOrEqual(bounds.maxX, 38)
        XCTAssertLessThanOrEqual(bounds.maxY, 38)
    }

    func testTrojanHorseUsesTwoSeparatedWheels() {
        let centers = TrojanHorseShape.wheelCenters(
            in: CGRect(x: 0, y: 0, width: 38, height: 38)
        )

        XCTAssertEqual(centers.count, 2)
        XCTAssertGreaterThan(centers[1].x - centers[0].x, 16)
        XCTAssertEqual(centers[0].y, centers[1].y, accuracy: 0.01)
    }

    func testTrojanHorseHasACentralLadder() {
        let ladder = TrojanHorseShape.ladderPath(
            in: CGRect(x: 0, y: 0, width: 38, height: 38)
        )
        let bounds = ladder.boundingRect

        XCTAssertEqual(bounds.midX, 19, accuracy: 1)
        XCTAssertGreaterThan(bounds.height, 10)
        XCTAssertLessThan(bounds.width, 9)
    }

    func testEveryTabSymbolExists() {
        for tab in AppTab.allCases {
            XCTAssertNotNil(
                UIImage(systemName: tab.symbol),
                "\(tab) 用了不存在的 SF Symbol：\(tab.symbol)"
            )
        }
    }

    func testEveryWelcomeSymbolExists() {
        for symbol in WelcomeView.promises.map(\.symbol) + ["lock.iphone", "arrow.right"] {
            XCTAssertNotNil(UIImage(systemName: symbol), "引导页用了不存在的 SF Symbol：\(symbol)")
        }
    }

    func testProtocolSymbolsAreDistinctEnoughToTellApart() {
        // Trojan, AnyTLS and Snell all mean "encrypted", and three shields in a
        // row would make the filter list unreadable.
        XCTAssertNotEqual(ProxyKind.snell.iconDescriptor, ProxyKind.anytls.iconDescriptor)
        XCTAssertNotEqual(ProxyKind.snell.iconDescriptor, ProxyKind.trojan.iconDescriptor)
    }
}
