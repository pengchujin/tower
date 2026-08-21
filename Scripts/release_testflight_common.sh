#!/usr/bin/env bash

# Shared, side-effect-free helpers for the TestFlight release scripts.

# Machine-specific release settings, loaded from outside Git.
#
# This repository is public, so the release host, its repository path and the
# Apple team ID are never checked in — see the identifiers rule in CLAUDE.md.
# Each machine that takes part in a release keeps its own
# `Config/release.local.sh`, which Git ignores and which only ever assigns the
# TOWER_RELEASE_* variables. Writing them with `${VAR:-…}` lets an environment
# variable win, so a one-off release needs no edit at all.
tower_load_local_config() {
    local repo_root="$1"
    local config="$repo_root/Config/release.local.sh"

    [[ -f "$config" ]] || return 0
    # shellcheck disable=SC1090
    source "$config"
}

tower_missing_setting() {
    local name="$1"
    local flag="$2"

    cat >&2 <<MISSING
${name} is not set.

This repository is public, so the release host and Apple team ID are not stored
in it. Set the value in one of these places, on the machine that needs it:

  1. Config/release.local.sh (ignored by Git):
         ${name}="\${${name}:-<value>}"
  2. The environment: export ${name}=<value>
MISSING
    [[ -z "$flag" ]] || printf '  3. The command line: %s <value>\n' "$flag" >&2
    return 1
}

# Apple team IDs are ten upper-case alphanumerics. Validated so a typo fails
# before xcodebuild runs, and so the value can never carry shell syntax.
tower_validate_team() {
    [[ "$1" =~ ^[A-Z0-9]{10}$ ]] || {
        printf 'Invalid Apple team ID: %s\n' "$1" >&2
        return 1
    }
}

# Reads `security find-identity -v -p codesigning` output from stdin and emits
# only the identity names. Unlike `find-certificate`, this list contains valid
# code-signing identities backed by an accessible private key.
tower_codesigning_identity_names() {
    sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-Fa-f]{40}[[:space:]]+"([^"]+)"[[:space:]]*$/\1/p'
}

tower_validate_ssh_destination() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$ ]] || {
        printf 'Invalid SSH destination: %s\n' "$1" >&2
        return 1
    }
}

tower_unique_project_setting() {
    local project_file="$1"
    local setting="$2"
    local values
    local count

    [[ -f "$project_file" ]] || {
        printf 'Project file not found: %s\n' "$project_file" >&2
        return 1
    }

    values="$(sed -nE "s/^[[:space:]]*${setting} = ([^;]+);/\\1/p" "$project_file" | sort -u)"
    count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l | tr -d ' ')"
    [[ "$count" == "1" ]] || {
        printf 'Expected one consistent %s value, found: %s\n' "$setting" "${values:-<none>}" >&2
        return 1
    }

    printf '%s\n' "$values"
}

tower_project_build() {
    tower_unique_project_setting "$1" "CURRENT_PROJECT_VERSION"
}

tower_project_version() {
    tower_unique_project_setting "$1" "MARKETING_VERSION"
}

tower_validate_version() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)*$ ]] || {
        printf 'Invalid marketing version: %s\n' "$1" >&2
        return 1
    }
}

tower_validate_build() {
    [[ "$1" =~ ^[0-9]+$ ]] || {
        printf 'Invalid build number: %s\n' "$1" >&2
        return 1
    }
}

tower_check_bundled_rules_current() {
    local repo_root="$1"
    local updater="$repo_root/Scripts/update_acl4ssr_rules.py"

    [[ -f "$updater" ]] || {
        printf 'Bundled rule updater not found: %s\n' "$updater" >&2
        return 1
    }
    python3 "$updater" --check-latest
}

tower_validate_commit() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]] || {
        printf 'Invalid Git commit: %s\n' "$1" >&2
        return 1
    }
}

tower_remote_command() {
    local remote_repo="$1"
    local version="$2"
    local build="$3"
    local commit="$4"
    local quoted_repo

    tower_validate_version "$version" || return 1
    tower_validate_build "$build" || return 1
    tower_validate_commit "$commit" || return 1
    [[ "$remote_repo" == /* && "$remote_repo" != *$'\n'* ]] || {
        printf 'Remote repository must be an absolute path without newlines: %s\n' "$remote_repo" >&2
        return 1
    }

    printf -v quoted_repo '%q' "$remote_repo"
    printf 'cd %s && test -z "$(git status --porcelain)" && git fetch origin main && git checkout main && git merge --ff-only origin/main && test "$(git rev-parse HEAD)" = %s && exec ./Scripts/release_testflight_remote.sh --version %s --build %s --commit %s' \
        "$quoted_repo" "$commit" "$version" "$build" "$commit"
}

tower_aqua_command() {
    local remote_repo="$1"
    local version="$2"
    local build="$3"
    local commit="$4"
    local release_dir="$5"
    local quoted_repo
    local quoted_release_dir

    tower_validate_version "$version" || return 1
    tower_validate_build "$build" || return 1
    tower_validate_commit "$commit" || return 1
    [[ "$remote_repo" == /* && "$remote_repo" != *$'\n'* ]] || return 1
    [[ "$release_dir" == /* && "$release_dir" != *$'\n'* ]] || return 1

    printf -v quoted_repo '%q' "$remote_repo"
    printf -v quoted_release_dir '%q' "$release_dir"
    printf 'cd %s && ./Scripts/release_testflight_remote.sh --aqua --version %s --build %s --commit %s --release-dir %s' \
        "$quoted_repo" "$version" "$build" "$commit" "$quoted_release_dir"
}
