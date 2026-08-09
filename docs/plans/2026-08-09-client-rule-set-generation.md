# Client Rule Set Generation Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add a persistent Settings switch that lets every generated client configuration prefer native remote rule sets when the source is compatible, while preserving a safe inline fallback.

**Architecture:** Keep `RuleScheme` as the common rule graph and add one capability planner beside `ConfigurationGenerator`. The planner examines the source URL and cached rule syntax, then selects either a target-native remote reference or the existing mapped inline path. `AppModel` owns the user preference, includes it in the generation cache key, and persists it in `AppSnapshot`.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, native Surge/Shadowrocket/Loon/Quantumult X/Mihomo/sing-box/Egern configuration formats.

---

### Task 1: Lock down the compatibility matrix

**Files:**
- Create: `TowerTests/RuleSetGenerationTests.swift`
- Modify: `TowerTests/RuleSchemeTests.swift`

**Steps:**
1. Add failing tests proving Clash emits `rule-providers` plus `RULE-SET` for compatible classical lists.
2. Add failing tests proving Surge and Shadowrocket emit URL-based `RULE-SET`, and Loon emits `[Remote Rule]`.
3. Add failing tests proving Quantumult X uses `[filter_remote]` only for native filter syntax and otherwise keeps mapped `[filter_local]` rules.
4. Add failing tests proving sing-box and Egern reference only their native rule-set formats and safely inline ACL/Surge lists.
5. Add tests proving disabling the preference restores the current fully inline output.

### Task 2: Add the shared rule-set planner and generators

**Files:**
- Create: `Tower/Services/RuleSetEmissionPlanner.swift`
- Modify: `Tower/Services/ConfigurationGenerator.swift`

**Steps:**
1. Model a stable rule-set identifier, URL, policy, source dialect, and fallback lines.
2. Detect target compatibility from the cached source content instead of file extension alone.
3. Refactor imported-scheme generation so Clash, Surge, Shadowrocket, Loon, QuanX, Hiddify/sing-box, and Egern consume the same plan.
4. Keep inline custom rules and the final catch-all local and ordered after remote resources.
5. Preserve current rule counts and unsupported-rule filtering.

### Task 3: Persist and expose the preference

**Files:**
- Modify: `Tower/Models/DomainModels.swift`
- Modify: `Tower/AppModel.swift`
- Modify: `Tower/Features/Settings/SettingsView.swift`
- Modify: `Tower/Localizable.xcstrings`
- Modify: `TowerTests/RuleCustomizationTests.swift`

**Steps:**
1. Add optional snapshot field `preferRuleSets` so old snapshots decode safely.
2. Default the preference to off, migrate the previous implicit-on snapshot value, add a model setter, persist explicit changes, and include it in generation caching.
3. Add a Settings toggle explaining that incompatible sources automatically remain local.
4. Add persistence and backward-compatibility tests.

### Task 4: Verify real output and device delivery

**Files:**
- Modify: `docs/HANDOFF.md`

**Steps:**
1. Run the focused rule-set tests and inspect representative generated files for all seven targets.
2. Run the complete Tower test suite.
3. Build a signed Debug app for the connected iPhone.
4. Install and launch `com.jzb.tower` on the physical device.
5. Record the capability matrix and fallback behavior for the next maintainer.
