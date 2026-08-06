import XCTest
import UIKit
@testable import Tower

/// `Image(systemName:)` draws nothing for a name SF Symbols does not have, and
/// says nothing about it — no crash, no log, just a blank where the icon was.
/// Snell shipped with an invented `shell.fill` and went unnoticed until the
/// export screen showed a gap, so every symbol the app names is checked here.
final class SymbolAvailabilityTests: XCTestCase {
    func testEveryProtocolSymbolExists() {
        for kind in ProxyKind.allCases {
            XCTAssertNotNil(
                UIImage(systemName: kind.symbol),
                "\(kind.rawValue) 用了不存在的 SF Symbol：\(kind.symbol)"
            )
        }
    }

    func testEveryTabSymbolExists() {
        for tab in AppTab.allCases {
            XCTAssertNotNil(
                UIImage(systemName: tab.symbol),
                "\(tab) 用了不存在的 SF Symbol：\(tab.symbol)"
            )
        }
    }

    func testProtocolSymbolsAreDistinctEnoughToTellApart() {
        // Trojan, AnyTLS and Snell all mean "encrypted", and three shields in a
        // row would make the filter list unreadable.
        XCTAssertNotEqual(ProxyKind.snell.symbol, ProxyKind.anytls.symbol)
        XCTAssertNotEqual(ProxyKind.snell.symbol, ProxyKind.trojan.symbol)
    }
}
