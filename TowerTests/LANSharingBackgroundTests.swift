import UIKit
import XCTest
@testable import Tower

@MainActor
final class LANSharingBackgroundTests: XCTestCase {
    @MainActor private final class Assertions {
        var expirations: [@MainActor @Sendable () -> Void] = []
        var ended: [UIBackgroundTaskIdentifier] = []
        var granted = true
        lazy var lease = LANSharingBackgroundLease(begin: { expiration in
            self.expirations.append(expiration)
            return self.granted ? UIBackgroundTaskIdentifier(rawValue: self.expirations.count) : .invalid
        }, end: { self.ended.append($0) })
    }

    func testBackgroundKeepsHTTPAvailableAndForegroundKeepsURL() async throws {
        let assertions = Assertions()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = AppModel(persistence: PersistenceStore(fileURL: file), clientPlatform: .phone,
                             lanBackgroundLease: assertions.lease)
        model.nodes = [ProxyNode(kind: .shadowsocks, name: "Test", server: "example.com", port: 443,
                                cipher: "aes-128-gcm", password: "test", rawURI: "ss://test")]
        await model.startLANSharing(listenerEnvironment: .loopback)
        defer { model.stopLANSharing() }
        let url = try XCTUnwrap(model.lanSubscriptionURL(target: .surge))
        model.lanSharingWillLeaveForeground()
        model.lanSharingWillLeaveForeground()
        XCTAssertEqual(assertions.expirations.count, 1)
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        model.lanSharingDidBecomeActive()
        XCTAssertEqual(model.lanSubscriptionURL(target: .surge), url)
        XCTAssertEqual(assertions.ended.count, 1)
        assertions.expirations[0]()
        await Task.yield()
        XCTAssertTrue(model.isLANSharingActive, "A stale expiry must not stop a foreground server")
        model.lanSharingWillLeaveForeground()
        assertions.expirations[1]()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(model.isLANSharingActive)
        XCTAssertEqual(assertions.ended.count, 2)
    }

    func testOldExpirationCannotCloseNewLeaseAndFinishIsIdempotent() async {
        let assertions = Assertions()
        var expired = 0
        assertions.lease.retainUntilExpiration { expired += 1 }
        assertions.lease.finish()
        assertions.lease.retainUntilExpiration { expired += 1 }
        assertions.expirations[0]()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(expired, 0)
        assertions.expirations[1]()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(expired, 1)
        assertions.lease.finish()
        XCTAssertEqual(assertions.ended.count, 2)
    }

    func testDeniedAssertionExpiresImmediately() {
        let assertions = Assertions()
        assertions.granted = false
        var expired = false
        assertions.lease.retainUntilExpiration { expired = true }
        XCTAssertTrue(expired)
        XCTAssertTrue(assertions.ended.isEmpty)
    }

    func testMacDoesNotRequestBackgroundTime() {
        let assertions = Assertions()
        let model = AppModel(clientPlatform: .mac, lanBackgroundLease: assertions.lease)
        model.isLANSharingStarting = true
        model.lanSharingWillLeaveForeground()
        XCTAssertTrue(assertions.expirations.isEmpty)
        XCTAssertTrue(model.isLANSharingStarting)
    }
}
