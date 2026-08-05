#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT_DIR/scripts/ci-changed-areas.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

ALL_TRUE=$'backend=true\nfrontend=true\ndocker=true\nscripts=true'

# Assert the four output lines for <base-sha>, described by <label>.
assert_areas() {
  local label=$1 base=$2 expected=$3 actual
  actual=$("$SCRIPT" "$base")
  [[ "$actual" == "$expected" ]] \
    || fail "$label expected:"$'\n'"$expected"$'\n'"got:"$'\n'"${actual:-<empty>}"
}

# Sourcing as a library must define the function without dispatching.
(
  export RENTIVO_CI_AREAS_LIB_ONLY=1
  # shellcheck source=../ci-changed-areas.sh
  source "$SCRIPT"
  declare -F changed_areas >/dev/null || fail 'library mode did not define changed_areas'
) || exit 1

REPO="$WORK_DIR/repo"
git init -q "$REPO"
cd "$REPO"
git config user.email tests@example.test
git config user.name 'Rentivo Tests'
mkdir -p ios backend/rentivo/api frontend/src scripts .github/workflows
printf 'a\n' > ios/Foo.swift
printf 'a\n' > backend/rentivo/api/app.py
printf 'a\n' > backend/Dockerfile.api
printf 'a\n' > frontend/src/main.tsx
printf 'a\n' > docker-compose.yml
printf 'a\n' > uv.lock
printf 'a\n' > scripts/ios-ci.sh
printf 'a\n' > scripts/asc_builds.py
printf 'a\n' > .github/workflows/test-pr.yaml
git add -A
git commit -qm 'base'
ROOT_COMMIT=$(git rev-parse HEAD)

# An unusable base fails open so no check silently vanishes.
assert_areas 'empty base' '' "$ALL_TRUE"
assert_areas 'all-zero base' 0000000000000000000000000000000000000000 "$ALL_TRUE"
assert_areas 'unknown base' deadbeefdeadbeefdeadbeefdeadbeefdeadbeef "$ALL_TRUE"

# Commit <file> on top of the base commit and report the resulting areas.
# Each case starts from the same root so the diffs stay independent.
areas_for_change() {
  local path=$1
  git checkout -q -B case "$ROOT_COMMIT"
  mkdir -p "$(dirname "$path")"
  printf 'changed\n' > "$path"
  git add -A
  git commit -qm "change $path"
}

areas_for_change ios/Foo.swift
assert_areas 'ios-only change' "$ROOT_COMMIT" \
  $'backend=false\nfrontend=false\ndocker=false\nscripts=false'

areas_for_change backend/rentivo/api/app.py
assert_areas 'backend source change' "$ROOT_COMMIT" \
  $'backend=true\nfrontend=false\ndocker=false\nscripts=false'

areas_for_change frontend/src/main.tsx
assert_areas 'frontend source change' "$ROOT_COMMIT" \
  $'backend=false\nfrontend=true\ndocker=false\nscripts=false'

areas_for_change docker-compose.yml
assert_areas 'compose change' "$ROOT_COMMIT" \
  $'backend=false\nfrontend=false\ndocker=true\nscripts=false'

# The API image lives under backend/, so it is both a Docker and a backend input.
areas_for_change backend/Dockerfile.api
assert_areas 'backend Dockerfile change' "$ROOT_COMMIT" \
  $'backend=true\nfrontend=false\ndocker=true\nscripts=false'

areas_for_change scripts/ios-ci.sh
assert_areas 'shell script change' "$ROOT_COMMIT" \
  $'backend=false\nfrontend=false\ndocker=false\nscripts=true'

# Ruff lints repository Python, so a script module is a backend input too.
areas_for_change scripts/asc_builds.py
assert_areas 'python script change' "$ROOT_COMMIT" \
  $'backend=true\nfrontend=false\ndocker=false\nscripts=true'

areas_for_change uv.lock
assert_areas 'lockfile change' "$ROOT_COMMIT" \
  $'backend=true\nfrontend=false\ndocker=false\nscripts=false'

# Workflow edits can change any job's behavior, so every area runs.
areas_for_change .github/workflows/test-pr.yaml
assert_areas 'workflow change' "$ROOT_COMMIT" "$ALL_TRUE"

cd "$ROOT_DIR"
printf 'changed-area helper shell tests passed\n'
