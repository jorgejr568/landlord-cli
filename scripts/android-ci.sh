#!/usr/bin/env bash
# Shared Android CI helpers for .github/workflows/test-pr.yaml.
# Source with RENTIVO_ANDROID_CI_LIB_ONLY=1 to load the functions without
# dispatching.
set -euo pipefail

# Paths whose changes require the Android job to run. This must cover every
# input to that job, including the composite action that holds its steps, the
# OpenAPI sync script it verifies with, and frontend/openapi.json itself,
# which is the source the Android contract copy must match.
ANDROID_PATH_PATTERN='^(android/|\.github/actions/android-unit-tests/|scripts/(android-ci|sync-android-openapi)\.sh$|scripts/tests/android-ci-test\.sh$|frontend/openapi\.json$|\.github/workflows/test-pr\.yaml$)'

# Print true when HEAD differs from <base-sha> in an Android-relevant path.
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
  # SIGPIPE, which `pipefail` would report as "no Android changes".
  # core.quotePath=false keeps non-ASCII paths (PT-BR copy) literal; the
  # default renders them as "\303\241"-style escapes that match no pattern.
  local changed
  changed=$(git -c core.quotePath=false diff --name-only "$merge_base" HEAD)
  if grep -qE "$ANDROID_PATH_PATTERN" <<<"$changed"; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

if [[ -n "${RENTIVO_ANDROID_CI_LIB_ONLY:-}" ]]; then
  return 0
fi

case "${1:-}" in
  paths-changed)
    paths_changed "${2:-}"
    ;;
  *)
    printf 'usage: %s [paths-changed <base-sha>]\n' "$0" >&2
    exit 64
    ;;
esac
