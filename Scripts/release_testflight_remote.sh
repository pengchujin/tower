#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=release_testflight_common.sh
source "$SCRIPT_DIR/release_testflight_common.sh"

tower_load_local_config "$REPO_ROOT"

version=""
build=""
expected_commit=""
aqua_mode=false
release_dir=""
# The signing machine owns this value. It is never checked in, because the
# repository is public.
team="${TOWER_DEVELOPMENT_TEAM:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            version="$2"
            shift 2
            ;;
        --build)
            build="$2"
            shift 2
            ;;
        --commit)
            expected_commit="$2"
            shift 2
            ;;
        --aqua)
            aqua_mode=true
            shift
            ;;
        --release-dir)
            release_dir="$2"
            shift 2
            ;;
        --team)
            team="$2"
            shift 2
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

tower_validate_version "$version"
tower_validate_build "$build"
tower_validate_commit "$expected_commit"
# Checked in both modes so a missing team ID fails before the keychain prompt,
# not twenty minutes later at the end of the archive.
[[ -n "$team" ]] || { tower_missing_setting TOWER_DEVELOPMENT_TEAM --team || exit 2; }
tower_validate_team "$team" || exit 2

project_file="$REPO_ROOT/Tower.xcodeproj/project.pbxproj"
actual_version="$(tower_project_version "$project_file")"
actual_build="$(tower_project_build "$project_file")"
actual_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"

[[ "$actual_version" == "$version" ]] || {
    printf 'Remote project version %s does not match requested version %s.\n' "$actual_version" "$version" >&2
    exit 1
}
[[ "$actual_build" == "$build" ]] || {
    printf 'Remote project build %s does not match requested build %s.\n' "$actual_build" "$build" >&2
    exit 1
}
[[ "$actual_commit" == "$expected_commit" ]] || {
    printf 'Remote commit %s does not match requested commit %s.\n' "$actual_commit" "$expected_commit" >&2
    exit 1
}
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || {
    printf 'Remote worktree is not clean. Release stopped.\n' >&2
    exit 1
}

if [[ "$aqua_mode" == false ]]; then
    keychain="$HOME/Library/Keychains/login.keychain-db"
    printf '\nSigning access\n'
    printf '  Keychain: %s\n' "$keychain"
    printf '  Enter the Mac mini login/keychain password if prompted. Input is handled by macOS security and is not saved.\n\n'

    if ! security show-keychain-info "$keychain" >/dev/null 2>&1; then
        security unlock-keychain "$keychain" </dev/tty
    fi

    if ! security find-identity -v -p codesigning "$keychain" | grep -q 'Apple Development\|Apple Distribution'; then
        printf 'No usable Apple code-signing identity is visible after unlocking the keychain.\n' >&2
        exit 1
    fi

    timestamp="$(date '+%Y%m%d-%H%M%S')"
    release_dir="$HOME/Builds/Tower-TestFlight-${version}-${build}-${timestamp}"
    runner_path="$release_dir/run-in-aqua.command"
    session_log="$release_dir/session.log"
    status_file="$release_dir/status"
    aqua_command="$(tower_aqua_command "$REPO_ROOT" "$version" "$build" "$expected_commit" "$release_dir")"
    mkdir -p "$release_dir"
    : > "$session_log"

    {
        printf '#!/bin/bash\n'
        printf 'set -o pipefail\n'
        printf 'status_file=%q\n' "$status_file"
        printf 'session_log=%q\n' "$session_log"
        printf 'finish() { code=$?; trap - EXIT; printf "%%s\\n" "$code" > "$status_file"; exit "$code"; }\n'
        printf 'trap finish EXIT\n'
        printf 'exec > >(/usr/bin/tee -a "$session_log") 2>&1\n'
        printf '%s\n' "$aqua_command"
    } > "$runner_path"
    chmod 700 "$runner_path"

    printf 'Starting the archive in the Mac mini Aqua session so codesign can access the private key…\n'
    /usr/bin/open -a Terminal "$runner_path"

    /usr/bin/tail -n +1 -F "$session_log" &
    tail_pid=$!
    while [[ ! -f "$status_file" ]]; do
        sleep 2
    done
    kill "$tail_pid" >/dev/null 2>&1 || true
    wait "$tail_pid" 2>/dev/null || true

    aqua_status="$(tr -d '[:space:]' < "$status_file")"
    if [[ "$aqua_status" != "0" ]]; then
        printf 'Aqua release failed with exit code %s. Logs: %s\n' "$aqua_status" "$release_dir" >&2
        exit "${aqua_status:-1}"
    fi
    printf 'Aqua release completed successfully. Logs: %s\n' "$release_dir"
    exit 0
fi

[[ "$release_dir" == /* && "$release_dir" != *$'\n'* ]] || {
    printf 'Aqua mode requires an absolute --release-dir.\n' >&2
    exit 2
}

archive_path="$release_dir/Tower-${version}-${build}.xcarchive"
export_path="$release_dir/export"
mkdir -p "$export_path"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# The checked-in plist carries no teamID, so the complete one is rendered here,
# into the release directory rather than the working tree. That keeps the team
# ID out of the repository even while a release is running.
export_options="$release_dir/ExportOptions.plist"
cp "$REPO_ROOT/Config/ExportOptions-TestFlight.plist" "$export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $team" "$export_options" >/dev/null

printf '\nArchiving Tower %s (%s)…\n' "$version" "$build"
cd "$REPO_ROOT"
xcodebuild \
    -project Tower.xcodeproj \
    -scheme Tower \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team" \
    CODE_SIGN_STYLE=Automatic \
    archive 2>&1 | tee "$release_dir/archive.log"

printf '\nUploading to App Store Connect…\n'
xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates 2>&1 | tee "$release_dir/upload.log"

printf '\nUpload command completed successfully.\n'
printf 'Archive: %s\n' "$archive_path"
printf 'Logs:    %s\n' "$release_dir"
printf 'Next: verify that build %s appears in App Store Connect; upload completion is not the same as TestFlight availability.\n' "$build"
