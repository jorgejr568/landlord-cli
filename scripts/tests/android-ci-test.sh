#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

export RENTIVO_ANDROID_CI_LIB_ONLY=1
# shellcheck source=../android-ci.sh
source "$ROOT_DIR/scripts/android-ci.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

REPO="$WORK_DIR/repo"
git init -q "$REPO"
cd "$REPO"
git config user.email tests@example.test
git config user.name 'Rentivo Tests'
mkdir -p android/app backend
printf 'a\n' > backend/app.py
printf 'a\n' > android/app/Main.kt
git add -A
git commit -qm 'base'
BASE=$(git rev-parse HEAD)

printf 'b\n' > backend/app.py
git add -A
git commit -qm 'backend only'
actual=$(paths_changed "$BASE")
[[ "$actual" == "false" ]] || fail "backend-only change reported $actual"

printf 'b\n' > android/app/Main.kt
git add -A
git commit -qm 'android change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "android change reported $actual"

# The job's steps live in a composite action, and the job runs the OpenAPI sync
# script against frontend/openapi.json; all three must trigger the Android job.
BASE=$(git rev-parse HEAD)
mkdir -p .github/actions/android-unit-tests
printf 'name: Android unit tests\n' > .github/actions/android-unit-tests/action.yml
git add -A
git commit -qm 'composite action change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "composite action change reported $actual"

BASE=$(git rev-parse HEAD)
mkdir -p scripts
printf 'check\n' > scripts/sync-android-openapi.sh
git add -A
git commit -qm 'openapi sync change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "sync-android-openapi.sh change reported $actual"

BASE=$(git rev-parse HEAD)
mkdir -p frontend
printf '{}\n' > frontend/openapi.json
git add -A
git commit -qm 'contract source change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "frontend/openapi.json change reported $actual"

# `scripts/` is not matched wholesale; only the named Android entries are.
BASE=$(git rev-parse HEAD)
printf 'unrelated\n' > scripts/unrelated.sh
git add -A
git commit -qm 'unrelated script change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "false" ]] || fail "unrelated script change reported $actual"

# `frontend/` is not matched wholesale either; only the contract source is.
BASE=$(git rev-parse HEAD)
printf 'unrelated\n' > frontend/main.tsx
git add -A
git commit -qm 'unrelated frontend change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "false" ]] || fail "unrelated frontend change reported $actual"

# Non-ASCII paths arrive escaped unless core.quotePath is disabled.
BASE=$(git rev-parse HEAD)
printf 'a\n' > 'android/app/Configuração.kt'
git add -A
git commit -qm 'accented android path change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "accented Android path change reported $actual"

actual=$(paths_changed "")
[[ "$actual" == "true" ]] || fail "empty base reported $actual"

actual=$(paths_changed 0000000000000000000000000000000000000000)
[[ "$actual" == "true" ]] || fail "zero base reported $actual"

actual=$(paths_changed deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)
[[ "$actual" == "true" ]] || fail "unknown base reported $actual"

cd "$ROOT_DIR"
printf 'Android CI helper shell tests passed\n'
