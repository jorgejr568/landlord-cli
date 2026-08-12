#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

export RENTIVO_MACOS_CI_LIB_ONLY=1
# shellcheck source=../macos-ci.sh
source "$ROOT_DIR/scripts/macos-ci.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

REPO="$WORK_DIR/repo"
git init -q "$REPO"
cd "$REPO"
git config user.email tests@example.test
git config user.name 'Rentivo Tests'
mkdir -p macos backend ios/Rentivo/Domain ios/Rentivo/Data ios/Rentivo/Features ios/RentivoTests scripts
printf 'a\n' > backend/app.py
printf 'a\n' > macos/App.swift
printf 'a\n' > ios/Package.swift
printf 'a\n' > ios/Rentivo/Domain/Bill.swift
printf 'a\n' > ios/Rentivo/Data/Client.swift
printf 'a\n' > ios/Rentivo/Features/HomeView.swift
printf 'a\n' > ios/RentivoTests/BillTests.swift
git add -A
git commit -qm 'base'
BASE=$(git rev-parse HEAD)

printf 'b\n' > backend/app.py
git add -A
git commit -qm 'backend only'
actual=$(paths_changed "$BASE")
[[ "$actual" == "false" ]] || fail "backend-only change reported $actual"

printf 'b\n' > macos/App.swift
git add -A
git commit -qm 'macos change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "macos change reported $actual"

# The macOS app compiles RentivoCore out of ios/, so the package manifest and
# its Domain/Data sources are job inputs.
for input in ios/Package.swift ios/Rentivo/Domain/Bill.swift \
  ios/Rentivo/Data/Client.swift ios/RentivoTests/BillTests.swift; do
  BASE=$(git rev-parse HEAD)
  printf 'changed\n' > "$input"
  git add -A
  git commit -qm "change $input"
  actual=$(paths_changed "$BASE")
  [[ "$actual" == "true" ]] || fail "$input change reported $actual"
done

# The iOS app's own feature sources are not compiled into the macOS app.
BASE=$(git rev-parse HEAD)
printf 'changed\n' > ios/Rentivo/Features/HomeView.swift
git add -A
git commit -qm 'ios feature change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "false" ]] || fail "iOS-only feature change reported $actual"

# The job's steps live in a composite action, and the DMG/icon scripts package
# and generate what the app ships; all of them must trigger the job.
BASE=$(git rev-parse HEAD)
mkdir -p .github/actions/macos-app-tests
printf 'name: macOS app tests\n' > .github/actions/macos-app-tests/action.yml
git add -A
git commit -qm 'composite action change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "composite action change reported $actual"

for script in scripts/macos-ci.sh scripts/macos-dmg.sh scripts/macos-app-icon.swift \
  scripts/tests/macos-ci-test.sh; do
  BASE=$(git rev-parse HEAD)
  mkdir -p "$(dirname "$script")"
  printf 'changed\n' > "$script"
  git add -A
  git commit -qm "change $script"
  actual=$(paths_changed "$BASE")
  [[ "$actual" == "true" ]] || fail "$script change reported $actual"
done

# `scripts/` is not matched wholesale; only the named macOS entries are.
BASE=$(git rev-parse HEAD)
printf 'unrelated\n' > scripts/unrelated.sh
git add -A
git commit -qm 'unrelated script change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "false" ]] || fail "unrelated script change reported $actual"

# Non-ASCII paths arrive escaped unless core.quotePath is disabled.
BASE=$(git rev-parse HEAD)
printf 'a\n' > 'macos/Configuração.swift'
git add -A
git commit -qm 'accented macos path change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "accented macOS path change reported $actual"

actual=$(paths_changed "")
[[ "$actual" == "true" ]] || fail "empty base reported $actual"

actual=$(paths_changed 0000000000000000000000000000000000000000)
[[ "$actual" == "true" ]] || fail "zero base reported $actual"

actual=$(paths_changed deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)
[[ "$actual" == "true" ]] || fail "unknown base reported $actual"

cd "$ROOT_DIR"
printf 'macOS CI helper shell tests passed\n'
