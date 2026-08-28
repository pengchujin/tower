#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../release_testflight_common.sh
source "$REPO_ROOT/Scripts/release_testflight_common.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$message (missing '$needle')"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "$haystack" != *"$needle"* ]] || fail "$message (unexpected '$needle')"
}

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

unicode_repo="$fixture_dir/塔台"
mkdir -p "$unicode_repo"
cat > "$unicode_repo/capture.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@"
SH
chmod +x "$unicode_repo/capture.sh"

ghostty_launcher="$(tower_create_ghostty_launcher "$unicode_repo/capture.sh")"
[[ "$ghostty_launcher" == /tmp/* || "$ghostty_launcher" == /var/folders/* ]] \
    || fail "Ghostty launcher must use an ASCII temporary path"
[[ "$ghostty_launcher" != *"塔台"* ]] \
    || fail "Ghostty launcher path must not contain the Unicode repository name"
assert_equal \
    $'argument with spaces\n中文参数' \
    "$("$ghostty_launcher" "argument with spaces" "中文参数")" \
    "Ghostty launcher preserves a Unicode script path and its arguments"
[[ ! -e "$ghostty_launcher" ]] || fail "Ghostty launcher removes itself after starting"

cat > "$fixture_dir/project.pbxproj" <<'PBX'
				CURRENT_PROJECT_VERSION = 28;
				MARKETING_VERSION = 1.0.2;
				CURRENT_PROJECT_VERSION = 28;
				MARKETING_VERSION = 1.0.2;
PBX

assert_equal "28" "$(tower_project_build "$fixture_dir/project.pbxproj")" "reads one consistent build number"
assert_equal "1.0.2" "$(tower_project_version "$fixture_dir/project.pbxproj")" "reads one consistent marketing version"

cat >> "$fixture_dir/project.pbxproj" <<'PBX'
				CURRENT_PROJECT_VERSION = 29;
PBX

if tower_project_build "$fixture_dir/project.pbxproj" >/dev/null 2>&1; then
    fail "rejects inconsistent build numbers"
fi

if tower_validate_version "1.0.2 beta" >/dev/null 2>&1; then
    fail "rejects unsafe marketing versions"
fi

if tower_validate_build "28; touch /tmp/nope" >/dev/null 2>&1; then
    fail "rejects unsafe build numbers"
fi

example_repo="/Users/example/tower-release"
example_commit="2016b51d5f759c9806d94f7c9afe7e4b83b992a4"

remote_command="$(tower_remote_command "$example_repo" "1.0.2" "28" "$example_commit")"
assert_contains "$remote_command" "release_testflight_remote.sh" "remote command invokes the checked-in helper"
assert_contains "$remote_command" "$example_commit" "remote command pins the expected commit"
# The password is never an argument, so it cannot reach the process list, the
# shell history or a log. Asserted by verb rather than by any literal value:
# writing a real password into this file to prove it is absent would be the
# leak the assertion exists to prevent.
assert_not_contains "$remote_command" "unlock-keychain" "remote command carries no keychain password operation"
assert_not_contains "$remote_command" "security " "remote command never invokes security(1) with arguments"

aqua_command="$(tower_aqua_command "$example_repo" "1.0.2" "28" "$example_commit" "/Users/example/Builds/Tower 28")"
assert_contains "$aqua_command" "--aqua" "Aqua runner explicitly changes to the GUI signing session"
assert_contains "$aqua_command" "Tower\\ 28" "Aqua runner safely quotes paths with spaces"
assert_not_contains "$aqua_command" "unlock-keychain" "generated Aqua command does not contain a keychain password operation"

# Team IDs are validated, so a typo or an injected fragment fails before
# xcodebuild ever runs.
tower_validate_team "ABCDE12345" || fail "accepts a well-formed Apple team ID"
for bad in "abcde12345" "ABCDE1234" "ABCDE12345 " "ABC; rm -rf /"; do
    if tower_validate_team "$bad" >/dev/null 2>&1; then
        fail "rejects malformed Apple team ID: $bad"
    fi
done

identity_output='  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Example (<DEVELOPER_ID>)"'
assert_equal \
    'Apple Development: Example (<DEVELOPER_ID>)' \
    "$(printf '%s\n' "$identity_output" | tower_codesigning_identity_names)" \
    "extracts only valid code-signing identities with private keys"

invalid_identity_output='  0 valid identities found'
assert_equal "" \
    "$(printf '%s\n' "$invalid_identity_output" | tower_codesigning_identity_names)" \
    "does not mistake a certificate without a private key for a signing identity"

fake_repo="$fixture_dir/fake-repo"
mkdir -p "$fake_repo/Scripts"
cat > "$fake_repo/Scripts/update_acl4ssr_rules.py" <<'PY'
import sys

if sys.argv[1:] != ["--check-latest"]:
    raise SystemExit(2)
print("bundled rules current")
PY
assert_equal \
    "bundled rules current" \
    "$(tower_check_bundled_rules_current "$fake_repo")" \
    "release preflight checks the bundled ACL4SSR snapshot"

local_release_source="$(<"$REPO_ROOT/Scripts/release_testflight.sh")"
remote_release_source="$(<"$REPO_ROOT/Scripts/release_testflight_remote.sh")"
assert_contains "$local_release_source" 'tower_check_bundled_rules_current "$REPO_ROOT"' \
    "local release checks bundled rules before connecting"
assert_contains "$local_release_source" 'ghostty_launcher="$(tower_create_ghostty_launcher "$SCRIPT_PATH")"' \
    "local release launches Ghostty through the Unicode-safe helper"
assert_contains "$local_release_source" '-e "$ghostty_launcher"' \
    "Ghostty receives only the ASCII launcher path"
assert_contains "$remote_release_source" 'tower_check_bundled_rules_current "$REPO_ROOT"' \
    "remote archive checks bundled rules before signing"

releasing_document="$(<"$REPO_ROOT/docs/RELEASING.md")"
assert_contains "$releasing_document" 'python3 Scripts/update_acl4ssr_rules.py --latest' \
    "release documentation explains how to fetch the latest bundled rules"
assert_contains "$releasing_document" 'python3 Scripts/update_acl4ssr_rules.py --check-latest' \
    "release documentation includes the non-mutating freshness check"

if tower_validate_ssh_destination "user@host; touch /tmp/nope" >/dev/null 2>&1; then
    fail "rejects unsafe SSH destinations"
fi

for script in \
    "$REPO_ROOT/Scripts/release_testflight.sh" \
    "$REPO_ROOT/Scripts/release_testflight_remote.sh"; do
    [[ -x "$script" ]] || fail "$script must be executable"
    bash -n "$script"
done

# The checked-in export options must not name a team. The release script adds
# the key outside the working tree; a teamID here means it came back.
if grep -q '<key>teamID</key>' "$REPO_ROOT/Config/ExportOptions-TestFlight.plist"; then
    fail "Config/ExportOptions-TestFlight.plist must not carry a teamID in a public repository"
fi

# Constraint 17 in CLAUDE.md — no device UDIDs, team IDs, build-host addresses
# or personal paths in tracked files — used to rely on someone remembering to
# look before committing. Twice it was not looked at. These checks read the
# forbidden values out of this machine's own untracked release config, so the
# rule is enforced without any secret being written down here to enforce it.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # Tracked files *and* untracked ones Git would not ignore — everything a
    # `git add -A` would publish. Scanning only tracked files is how the release
    # scripts reached this repository carrying a team ID and a build host: they
    # were new, so they were invisible to the check meant to stop them.
    tracked_files="$(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard)"

    scan_tracked() {
        local pattern="$1"
        local message="$2"
        local hits
        hits="$(printf '%s\n' "$tracked_files" \
            | xargs -I{} grep -lIE "$pattern" "$REPO_ROOT/{}" 2>/dev/null || true)"
        [[ -z "$hits" ]] || fail "$message: $(printf '%s' "$hits" | tr '\n' ' ')"
    }

    # SSH destinations pointing at a private address: a build host, by shape.
    scan_tracked '[A-Za-z0-9._-]+@(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)[0-9]+\.[0-9]+' \
        "A build-host SSH destination is committed"

    # Certificate examples are especially easy to paste from `security` or
    # OpenSSL output. Their common-name suffix and OU expose personal/team
    # identifiers even when no explicit teamID assignment exists.
    scan_tracked 'Apple (Development|Distribution):[^\"]*\([A-Z0-9]{10}\)|OU[=/][A-Z0-9]{10}' \
        "An Apple certificate subject containing a real identifier is committed"

    remote_source="$(<"$REPO_ROOT/Scripts/release_testflight_remote.sh")"
    assert_contains "$remote_source" 'find-identity -v -p codesigning' \
        "release preflight checks usable code-signing identities"
    assert_not_contains "$remote_source" 'find-certificate -a -p' \
        "release preflight must not accept certificate-only keychain entries"

    local_config="$REPO_ROOT/Config/release.local.sh"
    if [[ -f "$local_config" ]]; then
        while IFS= read -r secret; do
            # Short values collide with ordinary text; the identifiers this
            # guards are all comfortably longer.
            [[ ${#secret} -ge 6 ]] || continue
            scan_tracked "$(printf '%s' "$secret" | sed 's/[][\.*^$(){}?+|/]/\\&/g')" \
                "A value from Config/release.local.sh is committed"
        done < <(sed -nE 's/^[[:space:]]*TOWER_[A-Z_]+="?\$\{TOWER_[A-Z_]+:-([^}"]+)\}"?[[:space:]]*$/\1/p; s/^[[:space:]]*TOWER_[A-Z_]+="([^"]+)"[[:space:]]*$/\1/p' "$local_config")
    fi
fi

printf 'release_testflight_test: PASS\n'
