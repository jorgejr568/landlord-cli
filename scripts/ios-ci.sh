#!/usr/bin/env bash
# Shared iOS CI helpers for .github/workflows/test-pr.yaml and ios-release.yml.
# Source with RENTIVO_IOS_CI_LIB_ONLY=1 to load the functions without dispatching.
set -euo pipefail

# Paths whose changes require the macOS iOS jobs to run. This must cover every
# input to those jobs, including the composite action that holds their steps
# and the OpenAPI sync script the release workflow verifies with.
IOS_PATH_PATTERN='^(ios/|\.github/actions/ios-unit-tests/|scripts/(ios-ci|sync-ios-openapi)\.sh$|scripts/tests/ios-ci-test\.sh$|\.github/workflows/(ios-release\.yml|test-pr\.yaml)$)'

# Print the single MARKETING_VERSION declared by an Xcode project file.
# Debug and Release both declare it; disagreement is a project bug, not a
# version to guess at, so it fails loudly.
marketing_version() {
  local pbxproj=${1:?pbxproj path required}
  local values
  values=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);$/\1/p' "$pbxproj" \
    | sed 's/^"\(.*\)"$/\1/' \
    | sort -u)
  if [[ -z "$values" ]]; then
    printf 'No MARKETING_VERSION found in %s\n' "$pbxproj" >&2
    return 1
  fi
  if [[ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" -ne 1 ]]; then
    printf 'Conflicting MARKETING_VERSION values in %s:\n%s\n' "$pbxproj" "$values" >&2
    return 1
  fi
  printf '%s\n' "$values"
}

# Print true when HEAD differs from <base-sha> in an iOS-relevant path.
# An unusable base (first push, tag push, force push) reports true so the
# checks run rather than silently vanish.
paths_changed() {
  local base=${1:-}
  if [[ -z "$base" || "$base" =~ ^0+$ ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    printf 'true\n'
    return 0
  fi
  local merge_base
  merge_base=$(git merge-base "$base" HEAD 2>/dev/null || printf '%s' "$base")
  # The file list is materialised before matching: piping `git diff` into
  # `grep -q` lets grep exit on its first match, killing `git diff` with
  # SIGPIPE, which `pipefail` would report as "no iOS changes".
  local changed
  changed=$(git diff --name-only "$merge_base" HEAD)
  if grep -qE "$IOS_PATH_PATTERN" <<<"$changed"; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

if [[ -n "${RENTIVO_IOS_CI_LIB_ONLY:-}" ]]; then
  return 0
fi

case "${1:-}" in
  marketing-version)
    marketing_version "${2:-ios/Rentivo.xcodeproj/project.pbxproj}"
    ;;
  paths-changed)
    paths_changed "${2:-}"
    ;;
  *)
    printf 'usage: %s [marketing-version <pbxproj>|paths-changed <base-sha>]\n' "$0" >&2
    exit 64
    ;;
esac
