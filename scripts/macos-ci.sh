#!/usr/bin/env bash
# Shared macOS app CI helpers for .github/workflows/test-pr.yaml.
# Source with RENTIVO_MACOS_CI_LIB_ONLY=1 to load the functions without
# dispatching.
set -euo pipefail

# Paths whose changes require the macOS app job to run. Besides macos/ itself,
# the job compiles the RentivoCore package that lives under ios/, so the
# package manifest and its Domain/Data sources are job inputs too; ios/
# RentivoTests/ is included because it is compiled by the same package and a
# change there can break the shared target. The rest of ios/ (the iOS app
# sources) cannot affect the macOS build and is deliberately excluded so an
# iOS-only UI change does not spend a macOS runner. The macos-* scripts are
# included because they build, package, and generate assets the app ships.
MACOS_PATH_PATTERN='^(macos/|\.github/actions/macos-app-tests/|ios/(Package\.swift$|Rentivo/(Domain|Data)/|RentivoTests/)|scripts/macos-[a-z-]+\.(sh|swift)$|scripts/tests/macos-ci-test\.sh$|\.github/workflows/test-pr\.yaml$)'

# Print true when HEAD differs from <base-sha> in a macOS-relevant path.
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
  # SIGPIPE, which `pipefail` would report as "no macOS changes".
  # core.quotePath=false keeps non-ASCII paths (PT-BR copy) literal; the
  # default renders them as "\303\241"-style escapes that match no pattern.
  local changed
  changed=$(git -c core.quotePath=false diff --name-only "$merge_base" HEAD)
  if grep -qE "$MACOS_PATH_PATTERN" <<<"$changed"; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

if [[ -n "${RENTIVO_MACOS_CI_LIB_ONLY:-}" ]]; then
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
