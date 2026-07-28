# iOS App Store Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the iOS app to App Store Connect automatically whenever `MARKETING_VERSION` changes on `main`, and run the existing iOS PR checks only when `ios/` (and its CI helpers) actually change.

**Architecture:** A new `.github/workflows/ios-release.yml` detects a `MARKETING_VERSION` change by diffing `ios/Rentivo.xcodeproj/project.pbxproj` against the previous commit, re-runs the iOS test suites for that exact SHA, preflights App Store Connect for a free build number, then archives **unsigned**, exports **signed** (Xcode cloud-managed distribution signing driven by an App Store Connect API key), verifies the signature and embedded version numbers, validates, uploads, and polls until the build reaches `state=VALID`. Two small, unit-tested helpers back the workflows: `scripts/ios-ci.sh` (pbxproj version parsing + changed-path detection) and `scripts/asc_builds.py` (App Store Connect build queries). `test-pr.yaml` gains a `changes` job so its macOS `ios` job is skipped on non-iOS PRs, and a `scripts` job that runs both helpers' tests unconditionally.

**Tech Stack:** GitHub Actions (`ubuntu-latest`, `macos-15`), `xcodebuild`, `xcrun altool`, App Store Connect API (ES256 JWT via `pyjwt`), Bash, Python 3 run through `uv`.

## Global Constraints

- Code, comments, and identifiers are English; customer-facing copy — including the iOS app's UI — is PT-BR.
- Python runs through `uv`, never bare `python`/`pip`/`pytest`. Backend code uses `uv run --project backend ...`. **Documented exception:** `scripts/asc_builds.py` is CI tooling, not app code, and runs as `uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py ...` so `pyjwt` never enters the application's locked dependency set. Its unit tests run under the backend env (`uv run --project backend --no-sync pytest scripts/tests/test_asc_builds.py -q`), which is why the module must import `jwt` lazily.
- `uv.lock` and `frontend/package-lock.json` must not change in this work.
- The repository `jorgejr568/rentivo` is **PUBLIC**. Never publish the `.p8` contents, the Key ID, or the Issuer ID in workflow files, logs, or build artifacts. Never upload the signed `.ipa` as a workflow artifact.
- The `.p8` private key is only ever moved by shell redirection from a GitHub secret to a file. Never `cat`, `echo`, or otherwise print its contents.
- Apple account values (already registered, verified against the live API on 2026-07-28):
  - Team ID `Q87D3V95YZ`
  - Bundle ID `br.com.rentivo.ios`
  - App Store Connect app ID `6795485414`
  - Current `MARKETING_VERSION` `1.0.1`, current `CURRENT_PROJECT_VERSION` `1`
- `xcodebuild` invocations against `ios/Rentivo.xcodeproj` must pass `-skipPackagePluginValidation` (and `-skipMacroValidation` for `archive`) or they die at `Validate plug-in "OpenAPIGenerator"`.
- Archiving must be **unsigned**; all signing happens at `-exportArchive`. Archiving with automatic signing requests an *iOS App Development* profile, which requires registered devices — this team has none.
- The build number source of truth is `${{ github.run_number }}`, injected at archive time. `CURRENT_PROJECT_VERSION` in `project.pbxproj` stays `1` and is never edited for a release.
- External GitHub Actions are referenced by major version tag (`actions/checkout@v7`, `astral-sh/setup-uv@v8`, `actions/cache@v4`, `actions/upload-artifact@v7`), matching every existing workflow. `backend/tests/test_preview_infrastructure.py` enforces an allowlist of permitted actions, so introducing an action not already used in the repo means adding it there too.
- `backend/tests/test_preview_infrastructure.py` asserts on workflow and composite-action structure. Any change to `.github/` must be checked against it — notably `test_image_builds_are_consolidated_under_the_complete_release_gate`, which asserts exact set equality on `release-gate.needs`.
- The repo's pre-commit hook runs `ruff check`, `ruff format`, and the full backend suite. Task 0 must land before any other commit can succeed. Do not bypass the hook with `--no-verify`.
- Conventional Commit messages. Automated contributors open PRs but never merge them or push to `main`.

## Known risks, stated up front

1. **Fully automatic upload (user's explicit choice).** A `MARKETING_VERSION` bump merged to `main` uploads to App Store Connect with no human approval step. Uploads are irreversible: the build number is burned permanently and an uploaded build can only be expired, never deleted. The `workflow_dispatch` `skip_upload` input exists so dry runs are possible, but the `push` path has no gate.
2. **Cloud-managed distribution signing is assumed, not yet proven on CI.** The Apple account has **no** distribution certificate and **no** provisioning profiles (verified against `/v1/certificates` and `/v1/profiles`), and the local Mac keychain holds only an `Apple Development` identity — yet local exports produce an `Apple Distribution: … (Q87D3V95YZ)` signature. That is Xcode cloud-managed signing, which needs only the API key and therefore should reproduce on a fresh `macos-15` runner. Task 7 proves this with a `skip_upload` dry run **before** any real upload. If it fails, the fallback is exporting a distribution certificate to a `.p12` and importing it into a temporary keychain on the runner — out of scope for this plan.
3. **Re-running a failed release run reuses `github.run_number`.** If a run fails *after* upload and is re-run, the preflight in Task 2/5 fails fast with a clear message rather than burning a second number silently. The fix is to re-dispatch (fresh run number), not to re-run.

## File Structure

| File | Responsibility |
|---|---|
| `scripts/ios-ci.sh` (create) | Two pure Bash helpers used by both workflows: extract the single `MARKETING_VERSION` from a `project.pbxproj`, and decide whether a commit range touched iOS-relevant paths. |
| `scripts/tests/ios-ci-test.sh` (create) | Unit tests for the above, following the existing `scripts/tests/smoke-production-stack-test.sh` sourcing convention. |
| `scripts/asc_builds.py` (create) | App Store Connect build queries: `list`, `check` (is this version+build free?), `wait` (poll for `VALID`). Pure parsing helpers separated from HTTP so they are unit-testable. |
| `scripts/tests/conftest.py` (create) | Puts `scripts/` on `sys.path` for the Python script tests. |
| `scripts/tests/test_asc_builds.py` (create) | Unit tests for `asc_builds.py`'s pure helpers. |
| `.github/actions/ios-unit-tests/action.yml` (create) | Composite action holding the macOS iOS test steps (Xcode selection, SPM cache, `swift test`, simulator resolution, `RentivoTests`). Both `test-pr.yaml` and `ios-release.yml` need the identical sequence; the repo already uses this pattern for `.github/actions/docker-build`. |
| `.github/workflows/test-pr.yaml` (modify) | Add a `changes` job and a `scripts` job; gate the macOS `ios` job on `changes` and reduce it to the composite action; teach `release-gate` that a skipped `ios` job is acceptable. |
| `.github/workflows/ios-release.yml` (create) | The release pipeline: `detect` → (`verify`, `preflight`) → `release`. |
| `docs/runbooks/ios-release.md` (rewrite) | The runbook is factually wrong today (claims placeholder bundle IDs, `MARKETING_VERSION = 0.1`, and no App Store Connect integration). Replace with the real procedure. |
| `CLAUDE.md` (modify) | One line pointing at the iOS release workflow alongside the existing Compose/release notes. |

---

### Task 0: Make the workflow contract tests pass again

**Files:**
- Modify: `backend/tests/test_preview_infrastructure.py:29-38` (constants), `:433-486` (assertions), `:213-236` (`required_jobs`)

**Interfaces:**
- Consumes: nothing.
- Produces: a green backend suite, which every later task depends on — the repo's pre-commit hook runs the full suite, so **no commit in any later task can land until this passes**.

`main` is red. Six tests in `backend/tests/test_preview_infrastructure.py` fail at `7ae492c` for two independent reasons:

1. Dependabot has replaced every pinned action SHA with a mutable version tag (`actions/checkout@v7`, `astral-sh/setup-uv@v8`, …) across all workflows, while the tests still demand 40-hex SHAs. Jorge's decision: accept version tags. The allowlist of *which* external actions may be used stays — only the ref format relaxes — so an unreviewed new action is still a failure.
2. Commit `c0426b4` added the `ios` job to `release-gate.needs` without adding it to this test's `required_jobs` set.

- [ ] **Step 1: Run the suite to see the six failures**

Run: `uv run --project backend --no-sync pytest backend/tests/test_preview_infrastructure.py -c backend/pyproject.toml -q`
Expected: `6 failed`, naming `test_docker_build_action_supports_exact_immutable_publication`, `test_every_external_action_is_pinned_to_an_expected_commit`, `test_complete_gate_runs_dependency_repository_and_image_security_scans`, `test_deploy_runs_one_protected_atomic_webhook_for_the_tested_sha`, `test_image_builds_are_consolidated_under_the_complete_release_gate`, and `test_release_requires_the_exact_commit_gate_and_published_images`.

- [ ] **Step 2: Replace the SHA constants with the reviewed version refs**

Replace lines 29-38 of `backend/tests/test_preview_infrastructure.py`:

```python
CHECKOUT_SHA = "9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
LOGIN_SHA = "c94ce9fb468520275223c153574b00df6fe4bcc9"
SETUP_BUILDX_SHA = "8d2750c68a42422c14e847fe6c8ac0403b4cbd6f"
BUILD_PUSH_SHA = "10e90e3645eae34f1e60eeb005ba3a3d33f178e8"
ATTEST_SHA = "977bb373ede98d70efdf65b84cb5f73e068dcc2a"
TRIVY_SHA = "ed142fd0673e97e23eac54620cfb913e5ce36c25"
SETUP_UV_SHA = "08807647e7069bb48b6ef5acd8ec9567f424441b"
SETUP_NODE_SHA = "249970729cb0ef3589644e2896645e5dc5ba9c38"
UPLOAD_ARTIFACT_SHA = "b7c566a772e6b6bfb58ed0dc250532a479d7789f"
CODECOV_SHA = "a99c28d3f0da835de33ff2feb2e15691c7b9641f"
```

with:

```python
# Dependabot maintains these as major-version tags rather than pinned commits.
# The allowlist below still gates which external actions may appear at all; the
# ref only has to match the reviewed major version.
CACHE_REF = "v4"
CHECKOUT_REF = "v7"
LOGIN_REF = "v4"
SETUP_BUILDX_REF = "v3"
BUILD_PUSH_REF = "v7"
ATTEST_REF = "v3"
TRIVY_REF = "v0"
SETUP_UV_REF = "v8"
SETUP_NODE_REF = "v7"
UPLOAD_ARTIFACT_REF = "v7"
CODECOV_REF = "v7"
```

Then rename every usage. The f-string call sites keep their shape — only the constant name changes. Exact lines to update: `408` (`SETUP_BUILDX_SHA`), `409` (`BUILD_PUSH_SHA`), `433` (`CHECKOUT_SHA`), `435` (`SETUP_UV_SHA`), `447` and `461` (`TRIVY_SHA`), `477-486` (the `expected` dict), `566` (`TRIVY_SHA`), `571` (`ATTEST_SHA`), `586` (`CHECKOUT_SHA`), `589` (`LOGIN_SHA`), `843` (`LOGIN_SHA`), `844` (`SETUP_BUILDX_SHA`), `848` (`CHECKOUT_SHA`).

- [ ] **Step 3: Add `actions/cache` to the allowlist and relax the ref format**

In `test_every_external_action_is_pinned_to_an_expected_commit`, the `expected` dict becomes:

```python
    expected = {
        "actions/cache": CACHE_REF,
        "actions/checkout": CHECKOUT_REF,
        "actions/setup-node": SETUP_NODE_REF,
        "actions/upload-artifact": UPLOAD_ARTIFACT_REF,
        "astral-sh/setup-uv": SETUP_UV_REF,
        "codecov/codecov-action": CODECOV_REF,
        "docker/login-action": LOGIN_REF,
        "docker/build-push-action": BUILD_PUSH_REF,
        "docker/setup-buildx-action": SETUP_BUILDX_REF,
        "actions/attest-build-provenance": ATTEST_REF,
        "aquasecurity/trivy-action": TRIVY_REF,
    }
```

`actions/cache` is new to the dict: `test-pr.yaml`'s `ios` job already uses it, and the test's closing `assert found == set(expected)` means every listed action must actually appear somewhere.

Replace the mutable-ref assertion:

```python
            assert re.fullmatch(r"[0-9a-f]{40}", ref), f"{path}: {action}@{ref} is mutable"
```

with:

```python
            assert re.fullmatch(r"v\d+(\.\d+)*", ref), f"{path}: {action}@{ref} is not a version tag"
```

Rename the test to match what it now checks:

```python
def test_every_external_action_is_an_allowlisted_reviewed_version():
```

- [ ] **Step 4: Add the `ios` job to `required_jobs`**

In `test_image_builds_are_consolidated_under_the_complete_release_gate`, add `"ios"` to the `required_jobs` set so it reads:

```python
    required_jobs = {
        "backend",
        "e2e",
        "frontend",
        "ios",
        "migrations",
        "compose-config",
        "functional-stack",
        "production-startup",
        "security-scan",
    }
```

Task 3 adds `changes` and `scripts` to this same set when it adds those jobs. Do not add them here.

- [ ] **Step 5: Run the file's tests to verify they pass**

Run: `uv run --project backend --no-sync pytest backend/tests/test_preview_infrastructure.py -c backend/pyproject.toml -q`
Expected: PASS, `0 failed`

- [ ] **Step 6: Run the full suite to confirm the pre-commit hook will pass**

Run: `uv run --project backend --no-sync pytest -c backend/pyproject.toml -n auto -q`
Expected: PASS with 100% coverage (`fail_under = 100`), no failures.

- [ ] **Step 7: Verify no stale constant names remain**

Run:

```bash
grep -n "_SHA" backend/tests/test_preview_infrastructure.py
```

Expected: no output.

- [ ] **Step 8: Fix the unrelated formatting failure that also blocks the hook**

`scripts/seed_parity_fixtures.py` fails `ruff format --check` at `main`, which blocks the same pre-commit hook. It is unrelated to this plan but has to be fixed for any commit to land.

Run: `uv run --project backend --no-sync ruff format scripts/seed_parity_fixtures.py`
Then run: `uv run --project backend --no-sync ruff format --check . && uv run --project backend --no-sync ruff check .`
Expected: both PASS.

Do not make any other edit to that file — reformatting only.

- [ ] **Step 9: Commit**

```bash
git add backend/tests/test_preview_infrastructure.py scripts/seed_parity_fixtures.py
git commit -m "test(ci): accept Dependabot version tags and the iOS release gate job"
```

The commit must succeed with the pre-commit hook running. If the hook fails, the task is not done — do not use `--no-verify`.

---

### Task 1: iOS CI shell helpers

**Files:**
- Create: `scripts/ios-ci.sh`
- Test: `scripts/tests/ios-ci-test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `scripts/ios-ci.sh marketing-version [pbxproj-path]` → prints the version (e.g. `1.0.1`) on stdout, exit `0`; exits non-zero with a stderr message when the setting is missing or has conflicting values. Default path: `ios/Rentivo.xcodeproj/project.pbxproj`.
  - `scripts/ios-ci.sh paths-changed <base-sha>` → prints exactly `true` or `false`. Prints `true` when `<base-sha>` is empty, all-zeros, or not a reachable commit.
  - Sourcing with `RENTIVO_IOS_CI_LIB_ONLY=1` exposes the shell functions `marketing_version` and `paths_changed` without running the CLI dispatcher.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/ios-ci-test.sh`:

```bash
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
```

Make it executable:

```bash
chmod +x scripts/tests/ios-ci-test.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./scripts/tests/ios-ci-test.sh`
Expected: FAIL with `scripts/ios-ci.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `scripts/ios-ci.sh`:

```bash
#!/usr/bin/env bash
# Shared iOS CI helpers for .github/workflows/test-pr.yaml and ios-release.yml.
# Source with RENTIVO_IOS_CI_LIB_ONLY=1 to load the functions without dispatching.
set -euo pipefail

# Paths whose changes require the macOS iOS jobs to run.
IOS_PATH_PATTERN='^(ios/|scripts/ios-ci\.sh$|scripts/tests/ios-ci-test\.sh$|\.github/workflows/(ios-release\.yml|test-pr\.yaml)$)'

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
  if git diff --name-only "$merge_base" HEAD | grep -qE "$IOS_PATH_PATTERN"; then
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
```

Make it executable:

```bash
chmod +x scripts/ios-ci.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./scripts/tests/ios-ci-test.sh`
Expected: PASS, final line `iOS CI helper shell tests passed`

- [ ] **Step 5: Check the CLI dispatcher by hand**

Run:

```bash
./scripts/ios-ci.sh marketing-version
```

Expected: `1.0.1`

Run:

```bash
./scripts/ios-ci.sh paths-changed "$(git rev-parse HEAD)"
```

Expected: `false`

- [ ] **Step 6: Commit**

```bash
git add scripts/ios-ci.sh scripts/tests/ios-ci-test.sh
git commit -m "feat(ci): add iOS version and changed-path shell helpers"
```

---

### Task 2: App Store Connect build query script

**Files:**
- Create: `scripts/asc_builds.py`
- Create: `scripts/tests/conftest.py`
- Test: `scripts/tests/test_asc_builds.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `python scripts/asc_builds.py list --bundle-id <id>` → prints every uploaded build as `<marketing version> (<build>) state=<state> uploaded=<date>`.
  - `python scripts/asc_builds.py check --bundle-id <id> --version <marketing> --build <n>` → exit `0` when the pair is free, exit `1` when already consumed.
  - `python scripts/asc_builds.py wait --bundle-id <id> --version <marketing> --build <n> [--timeout 1800] [--interval 30]` → polls until `processingState == VALID` (exit `0`); exits `1` on `FAILED`/`INVALID` or timeout.
  - Pure helpers importable as `asc_builds.normalize_builds(payload) -> list[dict]`, `asc_builds.find_build(builds, version, build_number) -> dict | None`, `asc_builds.classify(state) -> str`.
  - Credentials read from `ASC_KEY_ID` and `ASC_ISSUER_ID`; the key file is read from `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/conftest.py`:

```python
"""Make the repository's standalone CI scripts importable by their tests."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

Create `scripts/tests/test_asc_builds.py`:

```python
import asc_builds

PAYLOAD = {
    "data": [
        {
            "id": "build-a",
            "attributes": {
                "version": "42",
                "processingState": "VALID",
                "uploadedDate": "2026-07-28T10:00:00-07:00",
            },
            "relationships": {
                "preReleaseVersion": {"data": {"id": "train-1", "type": "preReleaseVersions"}}
            },
        },
        {
            "id": "build-b",
            "attributes": {
                "version": "43",
                "processingState": "PROCESSING",
                "uploadedDate": "2026-07-28T11:00:00-07:00",
            },
            "relationships": {
                "preReleaseVersion": {"data": {"id": "train-2", "type": "preReleaseVersions"}}
            },
        },
        {
            "id": "build-orphan",
            "attributes": {"version": "44", "processingState": "VALID"},
        },
    ],
    "included": [
        {"id": "train-1", "type": "preReleaseVersions", "attributes": {"version": "1.0.1"}},
        {"id": "train-2", "type": "preReleaseVersions", "attributes": {"version": "1.0.2"}},
        {"id": "app-1", "type": "apps", "attributes": {"name": "Rentivo"}},
    ],
}


def test_normalize_builds_joins_the_marketing_version_train():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert builds[0] == {
        "id": "build-a",
        "build": "42",
        "version": "1.0.1",
        "state": "VALID",
        "uploaded": "2026-07-28T10:00:00-07:00",
    }
    assert builds[1]["version"] == "1.0.2"
    assert builds[1]["state"] == "PROCESSING"


def test_normalize_builds_tolerates_a_missing_train_relationship():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert builds[2] == {
        "id": "build-orphan",
        "build": "44",
        "version": None,
        "state": "VALID",
        "uploaded": None,
    }


def test_normalize_builds_handles_an_empty_payload():
    assert asc_builds.normalize_builds({}) == []


def test_find_build_matches_on_marketing_version_and_build_number():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert asc_builds.find_build(builds, "1.0.1", 42)["id"] == "build-a"
    assert asc_builds.find_build(builds, "1.0.1", "42")["id"] == "build-a"


def test_find_build_returns_none_when_either_half_differs():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert asc_builds.find_build(builds, "1.0.2", 42) is None
    assert asc_builds.find_build(builds, "1.0.1", 43) is None
    assert asc_builds.find_build(builds, "9.9.9", 1) is None


def test_classify_maps_processing_states_to_outcomes():
    assert asc_builds.classify("VALID") == "valid"
    assert asc_builds.classify("FAILED") == "failed"
    assert asc_builds.classify("INVALID") == "failed"
    assert asc_builds.classify("PROCESSING") == "pending"
    assert asc_builds.classify(None) == "pending"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run --project backend --no-sync pytest scripts/tests/test_asc_builds.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'asc_builds'`

- [ ] **Step 3: Write the implementation**

Create `scripts/asc_builds.py`:

```python
"""App Store Connect build queries for the iOS release workflow.

Usage:
    uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
        list --bundle-id br.com.rentivo.ios
    uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
        check --bundle-id br.com.rentivo.ios --version 1.0.2 --build 42
    uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
        wait --bundle-id br.com.rentivo.ios --version 1.0.2 --build 42

The account is configured with ASC_KEY_ID and ASC_ISSUER_ID; the private key is
read from ~/.appstoreconnect/private_keys/AuthKey_<key id>.p8 and is never
printed. `jwt` is imported lazily so the pure helpers stay importable under the
backend test environment, which does not carry pyjwt.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API_ROOT = "https://api.appstoreconnect.apple.com"
FAILED_STATES = frozenset({"FAILED", "INVALID"})


def normalize_builds(payload):
    """Flatten an ASC /v1/builds response into marketing-version-aware rows.

    ASC calls CFBundleVersion `version` on a build and keeps the marketing
    version on the related preReleaseVersion, so the two have to be joined.
    """
    trains = {
        item["id"]: item.get("attributes", {}).get("version")
        for item in payload.get("included", [])
        if item.get("type") == "preReleaseVersions"
    }
    builds = []
    for item in payload.get("data", []):
        attributes = item.get("attributes", {})
        related = item.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
        builds.append(
            {
                "id": item.get("id"),
                "build": attributes.get("version"),
                "version": trains.get(related.get("id")),
                "state": attributes.get("processingState"),
                "uploaded": attributes.get("uploadedDate"),
            }
        )
    return builds


def find_build(builds, version, build_number):
    """Return the row for a marketing version and build number, or None."""
    wanted = str(build_number)
    for build in builds:
        if build["version"] == version and build["build"] == wanted:
            return build
    return None


def classify(state):
    """Reduce a processingState to valid / failed / pending."""
    if state == "VALID":
        return "valid"
    if state in FAILED_STATES:
        return "failed"
    return "pending"


def _token():
    import jwt

    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        sys.exit("ASC_KEY_ID and ASC_ISSUER_ID must be set.")
    key_path = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    if not key_path.exists():
        sys.exit(f"No App Store Connect API key at {key_path}.")
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def _get(path, bearer):
    request = urllib.request.Request(
        f"{API_ROOT}{path}", headers={"Authorization": f"Bearer {bearer}"}
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"App Store Connect API error {error.code}: {error.read().decode()[:400]}")


def _app_id(bundle_id, bearer):
    apps = _get(f"/v1/apps?filter[bundleId]={bundle_id}", bearer)
    if not apps["data"]:
        sys.exit(f"No App Store Connect app record exists for {bundle_id}.")
    return apps["data"][0]["id"]


def _builds(bundle_id, bearer):
    app_id = _app_id(bundle_id, bearer)
    payload = _get(f"/v1/builds?filter[app]={app_id}&include=preReleaseVersion&limit=200", bearer)
    return normalize_builds(payload)


def _describe(build):
    return (
        f"{build['version']} ({build['build']}) "
        f"state={build['state']} uploaded={build['uploaded']}"
    )


def command_list(arguments, bearer):
    builds = _builds(arguments.bundle_id, bearer)
    if not builds:
        print("No builds uploaded yet.")
        return 0
    for build in builds:
        print(f"  {_describe(build)}")
    return 0


def command_check(arguments, bearer):
    builds = _builds(arguments.bundle_id, bearer)
    existing = find_build(builds, arguments.version, arguments.build)
    if existing is None:
        print(f"Build {arguments.version} ({arguments.build}) is free.")
        return 0
    print(
        f"Build {arguments.version} ({arguments.build}) is already consumed: "
        f"{_describe(existing)}",
        file=sys.stderr,
    )
    return 1


def command_wait(arguments, bearer):
    deadline = time.monotonic() + arguments.timeout
    while True:
        build = find_build(_builds(arguments.bundle_id, bearer), arguments.version, arguments.build)
        if build is not None:
            outcome = classify(build["state"])
            print(f"  {_describe(build)}")
            if outcome == "valid":
                return 0
            if outcome == "failed":
                print(f"Build processing failed: {build['state']}", file=sys.stderr)
                return 1
        if time.monotonic() >= deadline:
            print(
                f"Build {arguments.version} ({arguments.build}) did not reach VALID "
                f"within {arguments.timeout}s.",
                file=sys.stderr,
            )
            return 1
        time.sleep(arguments.interval)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    for name in ("list", "check", "wait"):
        subparser = subparsers.add_parser(name)
        subparser.add_argument("--bundle-id", required=True)
        if name != "list":
            subparser.add_argument("--version", required=True)
            subparser.add_argument("--build", required=True)
        if name == "wait":
            subparser.add_argument("--timeout", type=int, default=1800)
            subparser.add_argument("--interval", type=int, default=30)

    arguments = parser.parse_args(argv)
    handlers = {"list": command_list, "check": command_check, "wait": command_wait}
    return handlers[arguments.command](arguments, _token())


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `uv run --project backend --no-sync pytest scripts/tests/test_asc_builds.py -q`
Expected: PASS, `6 passed`

- [ ] **Step 5: Verify the script against the live account**

The local Mac already has the key at `~/.appstoreconnect/private_keys/AuthKey_J9LWU3J23R.p8`.

Run:

```bash
ASC_KEY_ID=J9LWU3J23R ASC_ISSUER_ID=58adcd82-adbd-41a5-ae4c-90c6f3569bac uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py list --bundle-id br.com.rentivo.ios
```

Expected: a line per uploaded build, e.g. `1.0.1 (1) state=VALID uploaded=…`. If the output is `No builds uploaded yet.`, that is also a pass for this step — it only proves auth and parsing work.

- [ ] **Step 6: Verify lint and formatting**

Run: `uv run --project backend --no-sync ruff check . && uv run --project backend --no-sync ruff format --check .`
Expected: PASS with no findings in `scripts/`

- [ ] **Step 7: Commit**

```bash
git add scripts/asc_builds.py scripts/tests/conftest.py scripts/tests/test_asc_builds.py
git commit -m "feat(ci): add App Store Connect build query script"
```

---

### Task 3: Extract the iOS test steps, path-filter them, and run the script tests

**Files:**
- Create: `.github/actions/ios-unit-tests/action.yml`
- Modify: `.github/workflows/test-pr.yaml` (add `changes` job before `backend`, add `scripts` job, gate and shrink `ios:101-142`, update `release-gate:946-957`)

**Interfaces:**
- Consumes: `scripts/ios-ci.sh paths-changed`, `scripts/tests/ios-ci-test.sh`, `scripts/tests/test_asc_builds.py` from Tasks 1 and 2.
- Produces:
  - `./.github/actions/ios-unit-tests` — a composite action taking no inputs and producing no outputs, requiring a `macos-*` runner and a prior `actions/checkout`. Task 5's `verify` job uses it.
  - Job output `needs.changes.outputs.ios` (`'true'` / `'false'`).

Why a `changes` job rather than `on.pull_request.paths`: `test-pr.yaml` is reused via `workflow_call` from `deploy.yml` and `release.yml`, and `on:` path filters do not apply to `workflow_call`. Job-level `if:` works in every caller.

Why a composite action: `ios-release.yml`'s `verify` job needs the identical five-step sequence, and copying it would leave two copies to drift apart. `.github/actions/docker-build` establishes the pattern in this repo.

- [ ] **Step 1: Extract the iOS test steps into a composite action**

Create `.github/actions/ios-unit-tests/action.yml`. The step bodies and the explanatory comment move verbatim from the current `ios` job in `.github/workflows/test-pr.yaml:106-142`; composite steps additionally require `shell: bash` on every `run:`.

```yaml
name: iOS unit tests
description: Run the RentivoCore package suite and the Xcode-hosted RentivoTests target.

runs:
  using: composite
  steps:
    - name: Select newest installed Xcode
      shell: bash
      run: sudo xcode-select -s "$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)"
    - name: Cache Swift Package Manager artifacts
      uses: actions/cache@v4
      with:
        path: ios/.build
        key: ${{ runner.os }}-spm-${{ hashFiles('ios/Package.resolved') }}
        restore-keys: |
          ${{ runner.os }}-spm-
    - name: Run RentivoCore package tests
      shell: bash
      run: swift test --package-path ios
    # The Xcode-hosted `RentivoTests` target used to fail `xcodebuild test`: several files
    # under ios/RentivoTests/ imported RentivoCore unconditionally, but the target does not
    # link the RentivoCore SPM package. Fixed by applying the dual-mode
    # `#if canImport(RentivoCore) @testable import RentivoCore #else @testable import Rentivo
    # #endif` guard uniformly across the suite. Only unit tests run here — RentivoUITests is
    # intentionally kept out of the required PR path (slower, more simulator/timing-sensitive,
    # and at least one interaction in it was found unreliable with XCUITest's synthesized taps
    # during local verification; see its file-level comments and docs/runbooks/ios-release.md).
    - name: Resolve an available iOS Simulator destination
      id: simulator
      shell: bash
      run: |
        DESTINATION_ID=$(xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -showdestinations 2>/dev/null \
          | grep "platform:iOS Simulator" | grep "name:iPhone" | head -1 \
          | sed -E 's/.*id:([0-9A-Fa-f-]+).*/\1/')
        if [ -z "$DESTINATION_ID" ]; then
          echo "No iPhone Simulator destination available on this runner" >&2
          exit 1
        fi
        echo "id=$DESTINATION_ID" >> "$GITHUB_OUTPUT"
    - name: Run Xcode-hosted RentivoTests unit target
      shell: bash
      run: |
        xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo \
          -destination "platform=iOS Simulator,id=${{ steps.simulator.outputs.id }}" \
          -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
          test -only-testing:RentivoTests
```

- [ ] **Step 2: Add the `changes` job**

Insert immediately after the `jobs:` line (before `backend:`) in `.github/workflows/test-pr.yaml`:

```yaml
  changes:
    name: detect changed areas
    runs-on: ubuntu-latest
    outputs:
      ios: ${{ steps.filter.outputs.ios }}
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - name: Detect iOS-relevant changes
        id: filter
        env:
          BASE_SHA: ${{ github.event_name == 'pull_request' && github.event.pull_request.base.sha || github.event.before }}
        run: |
          set -euo pipefail
          ios="$(./scripts/ios-ci.sh paths-changed "${BASE_SHA:-}")"
          echo "iOS-relevant changes: $ios"
          echo "ios=$ios" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 3: Add the `scripts` job**

Insert directly after the `changes` job:

```yaml
  scripts:
    name: repository CI script tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: Install uv
        uses: astral-sh/setup-uv@v8
        with:
          enable-cache: true
      - name: Sync dependencies
        run: uv sync --all-extras --frozen
      - name: Run iOS CI helper shell tests
        run: ./scripts/tests/ios-ci-test.sh
      - name: Run App Store Connect script tests
        run: uv run --project backend --no-sync pytest scripts/tests/test_asc_builds.py -q
```

- [ ] **Step 4: Gate the `ios` job and replace its body with the composite action**

In `.github/workflows/test-pr.yaml`, replace the whole `ios` job (currently lines 101-142, from `  ios:` through the `test -only-testing:RentivoTests` line) with:

```yaml
  ios:
    name: iOS RentivoCore package tests
    runs-on: macos-15
    needs: changes
    if: needs.changes.outputs.ios == 'true'
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/ios-unit-tests
```

Every step body and the explanatory comment now live in the composite action from Step 1; nothing is deleted, only moved.

- [ ] **Step 5: Teach `release-gate` that a skipped `ios` job is acceptable**

In the `release-gate` job, replace the `needs` list and the verification script.

`needs` becomes:

```yaml
    needs: [changes, scripts, backend, frontend, ios, e2e, migrations, compose-config, functional-stack, production-startup, security-scan]
```

The `Verify every release gate succeeded` step's `run` becomes:

```bash
          failures="$(printf '%s' "$NEEDS_JSON" | jq -r '
            to_entries[]
            | select(.value.result != "success")
            | select((.key == "ios" and .value.result == "skipped") | not)
            | "\(.key)=\(.value.result)"')"
          if [ -n "$failures" ]; then
            printf 'Required release gates failed:\n%s\n' "$failures"
            exit 1
          fi
```

Only `ios` may be skipped; every other job still has to report `success`.

Then extend `required_jobs` in `backend/tests/test_preview_infrastructure.py`'s `test_image_builds_are_consolidated_under_the_complete_release_gate` — it asserts an exact set equality against `release-gate.needs`, so the two new jobs must be added there too. Task 0 already added `"ios"`; add `"changes"` and `"scripts"` so the set reads:

```python
    required_jobs = {
        "backend",
        "changes",
        "e2e",
        "frontend",
        "ios",
        "migrations",
        "compose-config",
        "functional-stack",
        "production-startup",
        "scripts",
        "security-scan",
    }
```

- [ ] **Step 6: Validate both YAML files parse**

Run:

```bash
uv run --project backend --no-sync python -c "import yaml; d=yaml.safe_load(open('.github/workflows/test-pr.yaml')); print(sorted(d['jobs'])); print(d['jobs']['ios']); a=yaml.safe_load(open('.github/actions/ios-unit-tests/action.yml')); print(len(a['runs']['steps']))"
```

Expected: the job list includes `changes`, `scripts`, `ios`, and `release-gate`; the `ios` job shows `needs: changes`, the `if:` guard, and exactly two steps; the action reports `5` steps.

- [ ] **Step 7: Confirm the jq gate logic by hand**

Run:

```bash
printf '%s' '{"ios":{"result":"skipped"},"backend":{"result":"success"}}' | jq -r 'to_entries[] | select(.value.result != "success") | select((.key == "ios" and .value.result == "skipped") | not) | "\(.key)=\(.value.result)"'
```

Expected: no output (empty).

Run:

```bash
printf '%s' '{"ios":{"result":"failure"},"backend":{"result":"skipped"}}' | jq -r 'to_entries[] | select(.value.result != "success") | select((.key == "ios" and .value.result == "skipped") | not) | "\(.key)=\(.value.result)"'
```

Expected:

```
ios=failure
backend=skipped
```

- [ ] **Step 8: Commit**

```bash
git add .github/actions/ios-unit-tests/action.yml .github/workflows/test-pr.yaml
git commit -m "ci: run iOS jobs only when iOS paths change and test CI scripts"
```

---

### Task 4: Configure repository secrets and variables

**Files:**
- No repository files. This task configures `jorgejr568/rentivo` on GitHub.

**Interfaces:**
- Consumes: nothing.
- Produces, for `.github/workflows/ios-release.yml`:
  - `secrets.APPSTORE_CONNECT_KEY_ID`
  - `secrets.APPSTORE_CONNECT_ISSUER_ID`
  - `secrets.APPSTORE_CONNECT_PRIVATE_KEY` (the full `.p8` file contents, `-----BEGIN PRIVATE KEY-----` through `-----END PRIVATE KEY-----`)
  - `vars.APPLE_TEAM_ID` = `Q87D3V95YZ`
  - `vars.IOS_BUNDLE_ID` = `br.com.rentivo.ios`

The Key ID and Issuer ID are secrets rather than variables because this repository is public and they identify the Apple account. The Team ID and bundle ID are already embedded in every signed binary and shipped in `project.pbxproj`, so they are variables.

**Blocked on the user:** Jorge is creating a dedicated App Store Connect API key for CI. Do not reuse `J9LWU3J23R` — that key is the local Mac's, and a CI-only key can be revoked independently. This task cannot complete until that key exists and its `.p8` is on disk.

- [ ] **Step 1: Confirm `gh` is on the right account**

Run:

```bash
gh auth status
```

Expected: `jorgejr568` is the active account. If not:

```bash
gh auth switch --user jorgejr568
```

- [ ] **Step 2: Set the non-secret variables**

Run:

```bash
gh variable set APPLE_TEAM_ID --repo jorgejr568/rentivo --body Q87D3V95YZ
```

Run:

```bash
gh variable set IOS_BUNDLE_ID --repo jorgejr568/rentivo --body br.com.rentivo.ios
```

- [ ] **Step 3: Set the account identifier secrets**

Substitute the new CI key's values. `<NEW_KEY_ID>` is the 10-character Key ID shown in App Store Connect → Users and Access → Integrations → App Store Connect API. The Issuer ID is the same for the whole account: `58adcd82-adbd-41a5-ae4c-90c6f3569bac`.

```bash
gh secret set APPSTORE_CONNECT_KEY_ID --repo jorgejr568/rentivo --body '<NEW_KEY_ID>'
```

```bash
gh secret set APPSTORE_CONNECT_ISSUER_ID --repo jorgejr568/rentivo --body '58adcd82-adbd-41a5-ae4c-90c6f3569bac'
```

- [ ] **Step 4: Set the private key secret from the file, never from a paste**

`gh secret set` reading from stdin never prints the key. Do not `cat` the file first.

```bash
gh secret set APPSTORE_CONNECT_PRIVATE_KEY --repo jorgejr568/rentivo < ~/Downloads/AuthKey_<NEW_KEY_ID>.p8
```

- [ ] **Step 5: Verify without revealing values**

Run:

```bash
gh secret list --repo jorgejr568/rentivo && gh variable list --repo jorgejr568/rentivo
```

Expected: `APPSTORE_CONNECT_KEY_ID`, `APPSTORE_CONNECT_ISSUER_ID`, and `APPSTORE_CONNECT_PRIVATE_KEY` in the secret list; `APPLE_TEAM_ID` and `IOS_BUNDLE_ID` with their values in the variable list.

- [ ] **Step 6: Move the downloaded key out of Downloads**

Apple allows downloading a `.p8` exactly once. Keep a copy where the local release flow expects it, with restrictive permissions:

```bash
mkdir -p ~/.appstoreconnect/private_keys && chmod 700 ~/.appstoreconnect/private_keys && mv ~/Downloads/AuthKey_<NEW_KEY_ID>.p8 ~/.appstoreconnect/private_keys/ && chmod 600 ~/.appstoreconnect/private_keys/AuthKey_<NEW_KEY_ID>.p8
```

- [ ] **Step 7: Nothing to commit**

This task changes no files. Record completion in the PR description instead.

---

### Task 5: The iOS release workflow

**Files:**
- Create: `.github/workflows/ios-release.yml`

**Interfaces:**
- Consumes: `scripts/ios-ci.sh marketing-version` (Task 1), `scripts/asc_builds.py check|wait` (Task 2), `./.github/actions/ios-unit-tests` (Task 3), the secrets and variables from Task 4.
- Produces: a build uploaded to App Store Connect, and a `ios-release-evidence-<version>-<build>` artifact containing `DistributionSummary.plist`, the `codesign` output, and the export log. **Never the `.ipa`** — public-repo artifacts are downloadable by anyone.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ios-release.yml`:

```yaml
name: iOS App Store Release

on:
  push:
    branches: [main]
    paths:
      - ios/Rentivo.xcodeproj/project.pbxproj
  workflow_dispatch:
    inputs:
      skip_upload:
        description: Archive, sign, and validate without uploading
        type: boolean
        default: false

permissions:
  contents: read

concurrency:
  group: ios-appstore-release
  cancel-in-progress: false

jobs:
  detect:
    name: detect marketing version change
    runs-on: ubuntu-latest
    outputs:
      release: ${{ steps.version.outputs.release }}
      marketing-version: ${{ steps.version.outputs.marketing-version }}
      build-number: ${{ github.run_number }}
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 2
      - name: Compare MARKETING_VERSION with the previous commit
        id: version
        env:
          EVENT_NAME: ${{ github.event_name }}
        run: |
          set -euo pipefail
          pbxproj=ios/Rentivo.xcodeproj/project.pbxproj
          current="$(./scripts/ios-ci.sh marketing-version "$pbxproj")"
          echo "marketing-version=$current" >> "$GITHUB_OUTPUT"
          if [ "$EVENT_NAME" = "workflow_dispatch" ]; then
            echo "Manual dispatch: releasing $current as build ${{ github.run_number }}."
            echo "release=true" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          previous_file="$(mktemp)"
          if ! git show "HEAD^:$pbxproj" > "$previous_file" 2>/dev/null; then
            echo "No previous revision of $pbxproj; releasing $current."
            echo "release=true" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          previous="$(./scripts/ios-ci.sh marketing-version "$previous_file")"
          if [ "$current" = "$previous" ]; then
            echo "MARKETING_VERSION unchanged at $current; nothing to release."
            echo "release=false" >> "$GITHUB_OUTPUT"
          else
            echo "MARKETING_VERSION $previous -> $current; releasing as build ${{ github.run_number }}."
            echo "release=true" >> "$GITHUB_OUTPUT"
          fi

  verify:
    name: iOS checks for the release commit
    runs-on: macos-15
    needs: detect
    if: needs.detect.outputs.release == 'true'
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@v7
      - name: Verify iOS OpenAPI contract copy is current
        run: ./scripts/sync-ios-openapi.sh check
      - uses: ./.github/actions/ios-unit-tests

  preflight:
    name: confirm the build number is free
    runs-on: ubuntu-latest
    needs: detect
    if: needs.detect.outputs.release == 'true'
    steps:
      - uses: actions/checkout@v7
      - name: Install uv
        uses: astral-sh/setup-uv@v8
        with:
          enable-cache: true
      - name: Install the App Store Connect API key
        env:
          ASC_KEY_ID: ${{ secrets.APPSTORE_CONNECT_KEY_ID }}
          ASC_PRIVATE_KEY: ${{ secrets.APPSTORE_CONNECT_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          umask 077
          mkdir -p "$HOME/.appstoreconnect/private_keys"
          printf '%s\n' "$ASC_PRIVATE_KEY" \
            > "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
      - name: Confirm the version and build number are unused
        env:
          ASC_KEY_ID: ${{ secrets.APPSTORE_CONNECT_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.APPSTORE_CONNECT_ISSUER_ID }}
        run: |
          uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py check \
            --bundle-id "${{ vars.IOS_BUNDLE_ID }}" \
            --version "${{ needs.detect.outputs.marketing-version }}" \
            --build "${{ needs.detect.outputs.build-number }}"

  release:
    name: archive, sign, and upload
    runs-on: macos-15
    needs: [detect, verify, preflight]
    timeout-minutes: 90
    env:
      ASC_KEY_ID: ${{ secrets.APPSTORE_CONNECT_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.APPSTORE_CONNECT_ISSUER_ID }}
      APPLE_TEAM_ID: ${{ vars.APPLE_TEAM_ID }}
      IOS_BUNDLE_ID: ${{ vars.IOS_BUNDLE_ID }}
      MARKETING_VERSION: ${{ needs.detect.outputs.marketing-version }}
      BUILD_NUMBER: ${{ needs.detect.outputs.build-number }}
    steps:
      - uses: actions/checkout@v7
      - name: Select newest installed Xcode
        run: sudo xcode-select -s "$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)"
      - name: Install uv
        uses: astral-sh/setup-uv@v8
        with:
          enable-cache: true
      - name: Install the App Store Connect API key
        env:
          ASC_PRIVATE_KEY: ${{ secrets.APPSTORE_CONNECT_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          umask 077
          mkdir -p "$HOME/.appstoreconnect/private_keys"
          printf '%s\n' "$ASC_PRIVATE_KEY" \
            > "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
      - name: Archive unsigned
        run: |
          set -euo pipefail
          xcodebuild archive \
            -project ios/Rentivo.xcodeproj \
            -scheme Rentivo \
            -configuration Release \
            -destination 'generic/platform=iOS' \
            -archivePath "$RUNNER_TEMP/Rentivo.xcarchive" \
            -skipPackagePluginValidation -skipMacroValidation \
            MARKETING_VERSION="$MARKETING_VERSION" \
            CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
      - name: Write export options
        run: |
          set -euo pipefail
          cat > "$RUNNER_TEMP/ExportOptions.plist" <<PLIST
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
          	<key>method</key>          <string>app-store-connect</string>
          	<key>teamID</key>          <string>${APPLE_TEAM_ID}</string>
          	<key>signingStyle</key>    <string>automatic</string>
          	<key>uploadSymbols</key>   <true/>
          	<key>destination</key>     <string>export</string>
          </dict>
          </plist>
          PLIST
      - name: Export signed IPA
        run: |
          set -euo pipefail
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/Rentivo.xcarchive" \
            -exportPath "$RUNNER_TEMP/export" \
            -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" \
            -allowProvisioningUpdates \
            -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" \
            -authenticationKeyID "$ASC_KEY_ID" \
            -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
            2>&1 | tee "$RUNNER_TEMP/export.log"
      - name: Verify the signature is a distribution signature
        run: |
          set -euo pipefail
          cd "$RUNNER_TEMP"
          rm -rf _verify
          unzip -q export/Rentivo.ipa -d _verify
          codesign -dvvv _verify/Payload/Rentivo.app > signature.txt 2>&1
          cat signature.txt
          grep -q 'Authority=Apple Distribution' signature.txt
          grep -q "TeamIdentifier=${APPLE_TEAM_ID}" signature.txt
      - name: Verify the embedded version numbers
        run: |
          set -euo pipefail
          plist="$RUNNER_TEMP/_verify/Payload/Rentivo.app/Info.plist"
          short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
          build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
          echo "CFBundleShortVersionString=$short CFBundleVersion=$build"
          [ "$short" = "$MARKETING_VERSION" ] || {
            echo "Expected CFBundleShortVersionString $MARKETING_VERSION, got $short" >&2
            exit 1
          }
          [ "$build" = "$BUILD_NUMBER" ] || {
            echo "Expected CFBundleVersion $BUILD_NUMBER, got $build" >&2
            exit 1
          }
      - name: Validate with App Store Connect
        run: |
          set -euo pipefail
          xcrun altool --validate-app -f "$RUNNER_TEMP/export/Rentivo.ipa" -t ios \
            --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
      - name: Upload to App Store Connect
        if: github.event_name != 'workflow_dispatch' || inputs.skip_upload != true
        run: |
          set -euo pipefail
          xcrun altool --upload-app -f "$RUNNER_TEMP/export/Rentivo.ipa" -t ios \
            --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
      - name: Wait for the build to reach VALID
        if: github.event_name != 'workflow_dispatch' || inputs.skip_upload != true
        run: |
          uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py wait \
            --bundle-id "$IOS_BUNDLE_ID" \
            --version "$MARKETING_VERSION" \
            --build "$BUILD_NUMBER" \
            --timeout 1800
      - name: Summarise the release
        if: always()
        run: |
          {
            echo "### iOS release"
            echo
            echo "- Marketing version: \`$MARKETING_VERSION\`"
            echo "- Build number: \`$BUILD_NUMBER\`"
            echo "- Commit: \`$GITHUB_SHA\`"
          } >> "$GITHUB_STEP_SUMMARY"
      - name: Upload release evidence
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: ios-release-evidence-${{ needs.detect.outputs.marketing-version }}-${{ needs.detect.outputs.build-number }}
          path: |
            ${{ runner.temp }}/export/DistributionSummary.plist
            ${{ runner.temp }}/signature.txt
            ${{ runner.temp }}/export.log
          if-no-files-found: warn
          retention-days: 30
```

- [ ] **Step 2: Validate the workflow YAML parses and the job graph is right**

Run:

```bash
uv run --project backend --no-sync python -c "import yaml; d=yaml.safe_load(open('.github/workflows/ios-release.yml')); print(sorted(d['jobs'])); print(d['jobs']['release']['needs'])"
```

Expected:

```
['detect', 'preflight', 'release', 'verify']
['detect', 'verify', 'preflight']
```

- [ ] **Step 3: Confirm the workflow never publishes the IPA**

Run:

```bash
grep -n "Rentivo.ipa" .github/workflows/ios-release.yml
```

Expected: matches only inside the verify/validate/upload `run:` blocks — **no** match under the `upload-artifact` `path:` list.

- [ ] **Step 4: Confirm the detect logic locally against real history**

`HEAD` currently sits on a commit that did *not* change the version, so the workflow must decline to release.

Run:

```bash
./scripts/ios-ci.sh marketing-version && git show "HEAD^:ios/Rentivo.xcodeproj/project.pbxproj" > /tmp/prev.pbxproj && ./scripts/ios-ci.sh marketing-version /tmp/prev.pbxproj
```

Expected: two identical lines (`1.0.1`), i.e. `release=false`. Commit `7ae492c` is the one that bumped `1.0.0 -> 1.0.1`; checking `7ae492c` against `7ae492c^` the same way must produce two *different* values.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ios-release.yml
git commit -m "feat(ci): release the iOS app when MARKETING_VERSION changes"
```

---

### Task 6: Rewrite the iOS release runbook

**Files:**
- Modify: `docs/runbooks/ios-release.md` (full rewrite — every factual claim in it is now wrong)
- Modify: `CLAUDE.md` (one line in the "Compose and release" section)

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: no code interfaces.

The current runbook states that bundle identifiers are placeholders (`app.rentivo.demo`), that `MARKETING_VERSION` is `0.1`, that no signing team is configured, and that no App Store Connect integration exists. All four are false: the bundle ID is `br.com.rentivo.ios`, the version is `1.0.1`, signing is cloud-managed via API key, and build `1.0.1` is already on App Store Connect.

- [ ] **Step 1: Replace `docs/runbooks/ios-release.md` entirely**

```markdown
# iOS Release Runbook

The iOS app ships to App Store Connect from CI. A release is triggered by one
thing: changing `MARKETING_VERSION` in `ios/Rentivo.xcodeproj/project.pbxproj`
and merging that change to `main`.

## How a release happens

1. Open a PR that bumps `MARKETING_VERSION` (for example `1.0.1` -> `1.0.2`).
   Leave `CURRENT_PROJECT_VERSION` alone — CI supplies the build number.
2. The PR runs the normal release gate. The macOS `ios` job runs only when the
   PR touches `ios/`, the iOS CI helper scripts, or either workflow file.
3. Merging to `main` starts `.github/workflows/ios-release.yml`, which:
   - diffs `project.pbxproj` against the previous commit and stops unless
     `MARKETING_VERSION` actually changed;
   - re-runs `swift test --package-path ios`, the Xcode-hosted `RentivoTests`
     target, and `./scripts/sync-ios-openapi.sh check` for that exact SHA;
   - asks App Store Connect whether that marketing version plus build number
     is already consumed, and fails fast if it is;
   - archives **unsigned**, exports **signed**, checks the signature is
     `Apple Distribution` for team `Q87D3V95YZ`, checks the embedded
     `CFBundleShortVersionString`/`CFBundleVersion`, validates, uploads, and
     polls until the build reports `state=VALID`.

The upload is automatic and irreversible. A build number is consumed
permanently and an uploaded build can only be expired, never deleted. There is
no approval step between merging a version bump and the upload.

## Versioning

- `MARKETING_VERSION` is the release train (`CFBundleShortVersionString`) and is
  the only value a human edits. Debug and Release must agree; CI refuses to
  guess if they diverge.
- The build number (`CFBundleVersion`) is `github.run_number`, injected at
  archive time. `CURRENT_PROJECT_VERSION` stays `1` in the project file.
- Re-running a failed workflow run reuses its run number. If a run fails after
  the upload succeeded, the preflight on the re-run fails with
  "already consumed" — dispatch a fresh run instead of re-running.

## Signing

There is no distribution certificate and no provisioning profile on the Apple
account, and none is needed. The archive is produced with
`CODE_SIGNING_ALLOWED=NO`, and `xcodebuild -exportArchive` with
`method: app-store-connect` and `-allowProvisioningUpdates` uses Xcode
cloud-managed distribution signing driven by the App Store Connect API key.

Archiving with signing enabled does **not** work on this account: automatic
signing asks for an *iOS App Development* profile during an archive, and
development profiles must enumerate registered devices. This team has none.
App Store distribution profiles have no device requirement, which is why all
signing is deferred to the export step.

## Credentials

| Where | Name | Value |
|---|---|---|
| Secret | `APPSTORE_CONNECT_KEY_ID` | CI-only App Store Connect API key ID |
| Secret | `APPSTORE_CONNECT_ISSUER_ID` | account issuer ID |
| Secret | `APPSTORE_CONNECT_PRIVATE_KEY` | full `.p8` contents |
| Variable | `APPLE_TEAM_ID` | `Q87D3V95YZ` |
| Variable | `IOS_BUNDLE_ID` | `br.com.rentivo.ios` |

The Key ID and Issuer ID are secrets rather than variables because this
repository is public. The `.p8` is written to
`~/.appstoreconnect/private_keys/AuthKey_<key id>.p8` on the runner, which is
where both `xcodebuild -authenticationKeyPath` and `xcrun altool --apiKey`
look. Its contents are never printed, and the signed `.ipa` is never uploaded
as a workflow artifact — public-repo artifacts are downloadable by anyone. The
run keeps `DistributionSummary.plist`, the `codesign` output, and the export
log for 30 days instead.

Rotating the key: create a new key in App Store Connect -> Users and Access ->
Integrations, run `gh secret set APPSTORE_CONNECT_PRIVATE_KEY --repo
jorgejr568/rentivo < AuthKey_<new>.p8` and `gh secret set
APPSTORE_CONNECT_KEY_ID`, then revoke the old key.

## Manual runs

`workflow_dispatch` releases whatever `MARKETING_VERSION` is currently on the
selected branch, without the version-change check. Its `skip_upload` input
archives, signs, and validates without uploading — use it to prove the signing
path still works without consuming a build number.

## TestFlight

There is no separate TestFlight build. TestFlight and App Store review consume
the same binary, so a build at `state=VALID` is already the TestFlight build.
What remains is distribution configuration in App Store Connect:

- **Internal testers** — assign in the TestFlight tab; no review, immediate.
- **External testers** — needs Beta App Review first.

Export compliance is already answered: `ios/Config/Rentivo-Info.plist` sets
`ITSAppUsesNonExemptEncryption` to `false`, so App Store Connect does not
prompt per build. If that key is removed the prompt returns, and the correct
value depends on the app's actual cryptography — ask rather than guess.

## Querying App Store Connect by hand

```bash
ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> \
  uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
  list --bundle-id br.com.rentivo.ios
```

`scripts/asc_builds.py` is CI tooling rather than application code, so it runs
with `uv run --with pyjwt` instead of `uv run --project backend`; adding
`pyjwt` to the backend's locked dependencies for a release script would be
worse. Its pure helpers are unit-tested under the backend environment by
`scripts/tests/test_asc_builds.py`.

## What CI still does not do

- `RentivoUITests` is not in the required path. It is slower and more
  timing-sensitive, and at least one interaction (tapping the small in-row
  buttons on the API-key list screen) was unreliable with XCUITest's
  synthesized taps during local verification. Run it locally with
  `xcodebuild test -only-testing:RentivoUITests` against a booted simulator.
- Nothing submits a build for App Store review, sets phased rollout, or
  updates store metadata. Those stay manual in App Store Connect.
- iOS releases are independent of `release.yml`; the app and the backend do not
  share a version or a cadence.
```

- [ ] **Step 2: Add the pointer in `CLAUDE.md`**

In the "Compose and release" section, after the paragraph ending
`See `docs/runbooks/production-release.md`.`, add:

```markdown
The iOS app releases independently: changing `MARKETING_VERSION` in
`ios/Rentivo.xcodeproj/project.pbxproj` on `main` triggers
`.github/workflows/ios-release.yml`, which archives, signs, and uploads to App
Store Connect. See `docs/runbooks/ios-release.md`.
```

- [ ] **Step 3: Verify no stale claims survive**

Run:

```bash
grep -rn "app\.rentivo\.demo\|No App Store Connect integration exists\|no live iOS release automation" docs/ CLAUDE.md
```

Expected: no output. (All three strings are present in the runbook today, so a non-empty result means the rewrite left stale text behind.)

- [ ] **Step 4: Verify the referenced files exist**

Run:

```bash
ls scripts/asc_builds.py scripts/ios-ci.sh .github/workflows/ios-release.yml ios/Config/Rentivo-Info.plist
```

Expected: all four listed, no errors.

- [ ] **Step 5: Commit**

```bash
git add docs/runbooks/ios-release.md CLAUDE.md
git commit -m "docs(ios): document the automated App Store release pipeline"
```

---

### Task 7: Open the PR and verify end to end

**Files:**
- No source changes. This task validates the pipeline.

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: a merged pipeline and a proven signing path.

The `push` trigger and `workflow_dispatch` only work once the workflow file is on `main`, so real verification is necessarily post-merge. Do it in this order — the dry run comes before any real upload.

- [ ] **Step 1: Push the branch and open the PR**

```bash
git push -u origin claude/ios-appstore-release-automation-3bc6a2
```

```bash
gh pr create --repo jorgejr568/rentivo --base main --title "feat(ci): automate iOS App Store releases on version change" --body-file .github/pull_request_template.md
```

Fill in every section of the template before submitting. Do not merge the PR — that is Jorge's call.

- [ ] **Step 2: Confirm the iOS job actually ran on this PR**

This PR touches `.github/workflows/test-pr.yaml` and `scripts/ios-ci.sh`, both in the trigger path set, so the macOS `ios` job must run.

```bash
gh pr checks --repo jorgejr568/rentivo --watch
```

Expected: `iOS RentivoCore package tests`, `repository CI script tests`, `detect changed areas`, and `all-checks-pass` all green. If `ios` shows as skipped, the path pattern in `scripts/ios-ci.sh` is wrong — fix it before merging.

- [ ] **Step 3: After merge, dry-run the release with `skip_upload`**

```bash
gh workflow run ios-release.yml --repo jorgejr568/rentivo --ref main -f skip_upload=true
```

```bash
gh run watch --repo jorgejr568/rentivo "$(gh run list --repo jorgejr568/rentivo --workflow=ios-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Expected: `detect`, `verify`, `preflight`, and `release` all succeed; the `Verify the signature is a distribution signature` step passes; `Upload to App Store Connect` and `Wait for the build to reach VALID` are skipped. **This is the step that proves cloud-managed signing works on a fresh runner** (Risk 2). If export fails with a certificate or profile error, stop and fall back to importing a distribution `.p12` into a temporary keychain.

- [ ] **Step 4: Confirm the dry run consumed nothing**

```bash
ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py list --bundle-id br.com.rentivo.ios
```

Expected: still only the pre-existing builds; nothing new from the dry run.

- [ ] **Step 5: Do a real release**

Open a second, tiny PR bumping `MARKETING_VERSION` from `1.0.1` to `1.0.2` in both build configurations of `ios/Rentivo.xcodeproj/project.pbxproj`. Merge it, then watch:

```bash
gh run watch --repo jorgejr568/rentivo "$(gh run list --repo jorgejr568/rentivo --workflow=ios-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Expected: the run finishes green and the final step reports `1.0.2 (<run number>) state=VALID`.

- [ ] **Step 6: Confirm the no-op path**

Push any commit to `main` that does not touch `project.pbxproj`, or one that touches it without changing the version.

Expected: `ios-release.yml` either does not trigger at all (path filter) or the `detect` job reports `MARKETING_VERSION unchanged`, and `verify`/`preflight`/`release` are skipped. **A second upload must not happen.**

- [ ] **Step 7: Confirm TestFlight**

In App Store Connect, the `1.0.2` build should be visible under TestFlight and assignable to internal testers with no further build.
