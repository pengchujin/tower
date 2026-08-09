import XCTest
@testable import Tower

@MainActor
final class RulePresetMigrationTests: XCTestCase {
    func testSelfConfigurationManualDownloadUsesTheOfficialClashDocument() {
        XCTAssertNotEqual(AppModel.defaultRuleSchemeID, "self-configuration")
        XCTAssertEqual(
            SelfConfigurationSource.projectURL,
            URL(string: "https://github.com/ClashConnectRules/Self-Configuration")
        )
        XCTAssertEqual(
            SelfConfigurationSource.downloadURL,
            URL(string: "https://raw.githubusercontent.com/ClashConnectRules/Self-Configuration/main/Clash.yaml")
        )
    }

    func testLegacyPresetMetadataKeepsCorePolicyGroupsForOldSnapshots() throws {
        let preset = try XCTUnwrap(RulePreset.builtIns.first)
        let policyNames = Set(preset.policies.map(\.configurationName))

        XCTAssertTrue(policyNames.contains("AI服务"))
        XCTAssertTrue(policyNames.contains("YouTube"))
        XCTAssertTrue(policyNames.contains("国际流量"))
        XCTAssertTrue(policyNames.contains("国内流量"))
        XCTAssertTrue(policyNames.contains("国外广告"))
    }
}
