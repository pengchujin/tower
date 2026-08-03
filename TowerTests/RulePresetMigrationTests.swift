import XCTest
@testable import Tower

final class RulePresetMigrationTests: XCTestCase {
    func testSelfConfigurationReplacesEveryLegacyPreset() {
        XCTAssertEqual(RulePreset.builtIns.map(\.id), ["self-configuration"])
        XCTAssertEqual(RulePreset.builtIns.first?.name, "Self-Configuration")
        XCTAssertEqual(
            RuleRepository.sourceURL,
            URL(string: "https://github.com/ClashConnectRules/Self-Configuration")
        )
    }

    func testSelfConfigurationKeepsCorePolicyGroups() throws {
        let preset = try XCTUnwrap(RulePreset.builtIns.first)
        let policyNames = Set(preset.policies.map(\.configurationName))

        XCTAssertTrue(policyNames.contains("AI服务"))
        XCTAssertTrue(policyNames.contains("YouTube"))
        XCTAssertTrue(policyNames.contains("国际流量"))
        XCTAssertTrue(policyNames.contains("国内流量"))
        XCTAssertTrue(policyNames.contains("国外广告"))
    }
}
