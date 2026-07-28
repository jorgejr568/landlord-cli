#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

export RENTIVO_IOS_CI_LIB_ONLY=1
# shellcheck source=../ios-ci.sh
source "$ROOT_DIR/scripts/ios-ci.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

# A pbxproj repeats MARKETING_VERSION once per build configuration.
cat > "$WORK_DIR/ok.pbxproj" <<'PBX'
		A1 /* Debug */ = {
			buildSettings = {
				MARKETING_VERSION = 1.0.1;
			};
		};
		A2 /* Release */ = {
			buildSettings = {
				MARKETING_VERSION = 1.0.1;
			};
		};
PBX
actual=$(marketing_version "$WORK_DIR/ok.pbxproj")
[[ "$actual" == "1.0.1" ]] || fail "expected 1.0.1, got ${actual:-<empty>}"

printf '\t\t\t\tMARKETING_VERSION = "2.3.4";\n' > "$WORK_DIR/quoted.pbxproj"
actual=$(marketing_version "$WORK_DIR/quoted.pbxproj")
[[ "$actual" == "2.3.4" ]] || fail "expected 2.3.4, got ${actual:-<empty>}"

printf '\t\t\t\tMARKETING_VERSION = 1.0.1;\n\t\t\t\tMARKETING_VERSION = 1.0.2;\n' \
  > "$WORK_DIR/conflict.pbxproj"
if marketing_version "$WORK_DIR/conflict.pbxproj" >/dev/null 2>&1; then
  fail 'conflicting MARKETING_VERSION values must fail'
fi

: > "$WORK_DIR/empty.pbxproj"
if marketing_version "$WORK_DIR/empty.pbxproj" >/dev/null 2>&1; then
  fail 'a missing MARKETING_VERSION must fail'
fi

# The committed project file must always parse to exactly one dotted version.
actual=$(marketing_version "$ROOT_DIR/ios/Rentivo.xcodeproj/project.pbxproj")
[[ "$actual" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "unexpected project version: $actual"

REPO="$WORK_DIR/repo"
git init -q "$REPO"
cd "$REPO"
git config user.email tests@example.test
git config user.name 'Rentivo Tests'
mkdir -p ios backend
printf 'a\n' > backend/app.py
printf 'a\n' > ios/App.swift
git add -A
git commit -qm 'base'
BASE=$(git rev-parse HEAD)

printf 'b\n' > backend/app.py
git add -A
git commit -qm 'backend only'
actual=$(paths_changed "$BASE")
[[ "$actual" == "false" ]] || fail "backend-only change reported $actual"

printf 'b\n' > ios/App.swift
git add -A
git commit -qm 'ios change'
actual=$(paths_changed "$BASE")
[[ "$actual" == "true" ]] || fail "ios change reported $actual"

actual=$(paths_changed "")
[[ "$actual" == "true" ]] || fail "empty base reported $actual"

actual=$(paths_changed 0000000000000000000000000000000000000000)
[[ "$actual" == "true" ]] || fail "zero base reported $actual"

actual=$(paths_changed deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)
[[ "$actual" == "true" ]] || fail "unknown base reported $actual"

cd "$ROOT_DIR"
printf 'iOS CI helper shell tests passed\n'
