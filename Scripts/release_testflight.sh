#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=release_testflight_common.sh
source "$SCRIPT_DIR/release_testflight_common.sh"

tower_load_local_config "$REPO_ROOT"

# Deliberately empty defaults: the release host is a private address and this
# repository is public. The value comes from Config/release.local.sh, the
# environment, or --host.
host="${TOWER_RELEASE_HOST:-}"
remote_repo="${TOWER_RELEASE_REPO:-}"
requested_version=""
requested_build=""
inside_ghostty=false
no_ghostty=false
dry_run=false

usage() {
    cat <<'USAGE'
Usage: Scripts/release_testflight.sh [options]

Open an interactive Ghostty window, connect to the release Mac, unlock its
login keychain without storing the password, then archive and upload Tower.

Options:
  --version VERSION       Require this marketing version (default: project value)
  --build BUILD           Require this build number (default: project value)
  --host USER@HOST        SSH destination (default: $TOWER_RELEASE_HOST)
  --remote-repo PATH      Repository on the release Mac (default: $TOWER_RELEASE_REPO)
  --no-ghostty            Run SSH in the current interactive terminal
  --dry-run               Validate and print the release plan without opening SSH
  -h, --help              Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || { printf 'Missing value for --version\n' >&2; exit 2; }
            requested_version="$2"
            shift 2
            ;;
        --build)
            [[ $# -ge 2 ]] || { printf 'Missing value for --build\n' >&2; exit 2; }
            requested_build="$2"
            shift 2
            ;;
        --host)
            [[ $# -ge 2 ]] || { printf 'Missing value for --host\n' >&2; exit 2; }
            host="$2"
            shift 2
            ;;
        --remote-repo)
            [[ $# -ge 2 ]] || { printf 'Missing value for --remote-repo\n' >&2; exit 2; }
            remote_repo="$2"
            shift 2
            ;;
        --inside-ghostty)
            inside_ghostty=true
            shift
            ;;
        --no-ghostty)
            no_ghostty=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ -n "$host" ]] || { tower_missing_setting TOWER_RELEASE_HOST --host || exit 2; }
[[ -n "$remote_repo" ]] || { tower_missing_setting TOWER_RELEASE_REPO --remote-repo || exit 2; }
tower_validate_ssh_destination "$host" || exit 2

project_file="$REPO_ROOT/Tower.xcodeproj/project.pbxproj"
project_version="$(tower_project_version "$project_file")"
project_build="$(tower_project_build "$project_file")"
tower_validate_version "$project_version"
tower_validate_build "$project_build"

if [[ -n "$requested_version" && "$requested_version" != "$project_version" ]]; then
    printf 'Requested version %s does not match project version %s.\n' "$requested_version" "$project_version" >&2
    exit 1
fi
if [[ -n "$requested_build" && "$requested_build" != "$project_build" ]]; then
    printf 'Requested build %s does not match project build %s.\n' "$requested_build" "$project_build" >&2
    exit 1
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    printf 'The local worktree is not clean. Commit or stash changes before releasing.\n' >&2
    exit 1
fi

printf 'Checking bundled ACL4SSR rules…\n'
tower_check_bundled_rules_current "$REPO_ROOT"

printf 'Checking origin/main…\n'
git -C "$REPO_ROOT" fetch --quiet origin main
local_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
remote_commit="$(git -C "$REPO_ROOT" rev-parse origin/main)"
if [[ "$local_commit" != "$remote_commit" ]]; then
    printf 'Local HEAD (%s) is not exactly origin/main (%s). Push or pull first.\n' "$local_commit" "$remote_commit" >&2
    exit 1
fi

remote_command="$(tower_remote_command "$remote_repo" "$project_version" "$project_build" "$local_commit")"

printf '\nTower TestFlight release\n'
printf '  Version: %s (%s)\n' "$project_version" "$project_build"
printf '  Commit:  %s\n' "$local_commit"
printf '  Host:    %s\n' "$host"
printf '  Repo:    %s\n\n' "$remote_repo"

if [[ "$dry_run" == true ]]; then
    printf 'Dry run complete. The SSH command contains no password.\n'
    exit 0
fi

if [[ "$inside_ghostty" == false && "$no_ghostty" == false ]]; then
    ghostty_app="/Applications/Ghostty.app"
    [[ -d "$ghostty_app" ]] || {
        printf 'Ghostty is not installed at %s. Use --no-ghostty in another interactive terminal.\n' "$ghostty_app" >&2
        exit 1
    }

    open -na "$ghostty_app" --args \
        --title="Tower TestFlight ${project_version} (${project_build})" \
        -e "$SCRIPT_PATH" \
        --inside-ghostty \
        --version "$project_version" \
        --build "$project_build" \
        --host "$host" \
        --remote-repo "$remote_repo"
    printf 'Ghostty opened. Complete the keychain prompt in that window.\n'
    exit 0
fi

printf 'Connecting to the Mac mini. If SSH or the login keychain needs a password, enter it at the prompt; input is not saved.\n\n'
exec ssh -t "$host" "$remote_command"
