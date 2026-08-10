import XCTest
@testable import Tower

/// The privacy manifest is not something the app reads, so nothing breaks when
/// it goes stale — it fails much later, as an ITMS-91053 email after an upload.
/// These tests are the only thing standing between a new `UserDefaults` call
/// and a rejected build.
final class PrivacyManifestTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func manifest() throws -> [String: Any] {
        let url = repositoryRoot
            .appendingPathComponent("Tower")
            .appendingPathComponent("PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    /// The manifest has to ship inside the app bundle, not merely exist in the
    /// repository. A file that is in the folder but not in the target is worth
    /// exactly nothing to App Review.
    func testManifestIsInsideTheAppBundle() throws {
        let bundled = try XCTUnwrap(
            Bundle(for: AppModel.self).url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy 没有打进 App bundle"
        )

        XCTAssertNotNil(try? Data(contentsOf: bundled))
    }

    func testTowerDeclaresNoTrackingAndNoCollection() throws {
        let manifest = try manifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty, true)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    }

    /// Every required-reason API the source actually calls, and a reason for it.
    func testDeclaredAPIsMatchWhatTheSourceCalls() throws {
        let declared = try declaredReasons()

        XCTAssertEqual(declared["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        // The export folder's own files, read to purge stale temporary exports.
        XCTAssertEqual(declared["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
        // `systemUptime` differences, used to time a latency probe.
        XCTAssertEqual(declared["NSPrivacyAccessedAPICategorySystemBootTime"], ["35F9.1"])
    }

    /// Catches the case this file exists for: a new call to a required-reason
    /// API landing in the source without anyone touching the manifest.
    func testNoUndeclaredRequiredReasonAPIAppearsInTheSource() throws {
        let declared = Set(try declaredReasons().keys)
        // Only the symbols Tower plausibly reaches for. Each maps to the
        // category Apple files it under.
        let symbols: [String: String] = [
            "UserDefaults": "NSPrivacyAccessedAPICategoryUserDefaults",
            "@AppStorage": "NSPrivacyAccessedAPICategoryUserDefaults",
            "contentModificationDate": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "creationDate": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "attributesOfItem": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "systemUptime": "NSPrivacyAccessedAPICategorySystemBootTime",
            "mach_absolute_time": "NSPrivacyAccessedAPICategorySystemBootTime",
            "volumeAvailableCapacity": "NSPrivacyAccessedAPICategoryDiskSpace",
            "systemFreeSize": "NSPrivacyAccessedAPICategoryDiskSpace",
            "activeInputModes": "NSPrivacyAccessedAPICategoryActiveKeyboards"
        ]

        let sources = repositoryRoot.appendingPathComponent("Tower")
        var used: Set<String> = []
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (symbol, category) in symbols where text.contains(symbol) {
                used.insert(category)
            }
        }

        XCTAssertFalse(used.isEmpty, "扫描没有命中任何符号，说明这个测试自己坏了")
        XCTAssertTrue(
            used.subtracting(declared).isEmpty,
            "代码用了未声明的必需理由 API：\(used.subtracting(declared).sorted())"
        )
    }

    private func declaredReasons() throws -> [String: [String]] {
        let types = try XCTUnwrap(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: try types.map { entry in
            (
                try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String),
                try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            )
        })
    }
}
