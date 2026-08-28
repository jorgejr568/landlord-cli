# Retire Android and macOS Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Android and macOS applications and all repository capabilities and product references that exist solely to support them.

**Architecture:** Retire both applications atomically across source, backend integration, generated contracts, CI/tooling, and documentation. Preserve macOS references only where the operating system remains a necessary host for iOS development or a dependency artifact.

**Tech Stack:** FastAPI/Pydantic, OpenAPI, TypeScript, GitHub Actions, shell, Make, SwiftPM, Markdown

**Spec:** `docs/superpowers/specs/2026-08-28-retire-android-macos-apps-design.md`

## Global Constraints

- Delete the entire `android/` and `macos/` application trees.
- Remove Android Digital Asset Links behavior and configuration.
- Keep `frontend/openapi.json` and `ios/Rentivo/openapi.json` byte-identical.
- Keep macOS host references required for iOS SwiftPM tests, Xcode, CI runners, and dependency locks.
- Maintain backend coverage at 100%.
- Do not merge the pull request; a human merges it.

---

### Task 1: Remove Android Backend Integration and Refresh Contracts

**Files:**
- Modify: `backend/tests/api/test_mobile_auth.py`
- Modify: `backend/rentivo/api/routes/public.py`
- Modify: `backend/rentivo/settings.py`
- Modify: `.env.example`
- Modify: `infra/proxy/nginx.conf`
- Modify: `frontend/openapi.json`
- Modify: `frontend/src/lib/api/schema.d.ts`
- Modify: `ios/Rentivo/openapi.json`

**Interfaces:**
- Removes: `GET /.well-known/assetlinks.json`
- Removes: `Settings.android_package_name` and `Settings.android_cert_fingerprints`
- Produces: frontend and iOS OpenAPI snapshots without Android Asset Links

- [ ] **Step 1: Establish the endpoint-removal contract**

Delete the two Asset Links tests from `backend/tests/api/test_mobile_auth.py`, then run a repository search proving that the route and settings still exist and therefore implementation work remains:

```bash
rg -n 'android_asset_links|android_package_name|android_cert_fingerprints|assetlinks' backend .env.example infra/proxy/nginx.conf
```

Expected: matches in production code and configuration.

- [ ] **Step 2: Remove the production integration**

Delete the Asset Links route and any now-unused imports/helpers from `public.py`, remove both settings fields, remove the example environment variables and explanatory comments, and remove the dedicated Nginx location.

- [ ] **Step 3: Run focused backend tests**

```bash
env UV_CACHE_DIR=/tmp/rentivo-uv-cache uv run --project backend pytest -q backend/tests/api/test_mobile_auth.py backend/tests/test_env_example.py backend/tests/test_production_infrastructure.py
```

Expected: PASS.

- [ ] **Step 4: Regenerate API artifacts**

```bash
make openapi-export
make openapi-generate
make ios-openapi-sync
```

Expected: the Asset Links operation disappears from the frontend snapshot, generated TypeScript, and iOS snapshot.

- [ ] **Step 5: Verify contract consistency**

```bash
make openapi-check
make ios-openapi-check
```

Expected: PASS.

### Task 2: Delete Application Source and App-Specific Tooling

**Files:**
- Delete: `android/`
- Delete: `macos/`
- Delete: `.github/actions/android-unit-tests/`
- Delete: `.github/actions/macos-app-tests/`
- Delete: `scripts/android-ci.sh`
- Delete: `scripts/macos-ci.sh`
- Delete: `scripts/sync-android-openapi.sh`
- Delete: `scripts/macos-app-icon.sh`
- Delete: `scripts/macos-app-icon.swift`
- Delete: `scripts/macos-dmg.sh`
- Delete: `scripts/macos-dmg-background.swift`
- Delete: `scripts/tests/android-ci-test.sh`
- Delete: `scripts/tests/macos-ci-test.sh`
- Modify: `Makefile`

**Interfaces:**
- Removes: all Android Gradle and macOS Xcode application entry points
- Removes: `android-*` and `macos-*` Make targets
- Produces: a Makefile containing only supported application targets

- [ ] **Step 1: Delete tracked application and helper files**

Use an explicit patch to remove the named trees and files. Do not remove iOS files that contain macOS test-host compatibility.

- [ ] **Step 2: Remove Make targets**

Delete the complete macOS and Android target blocks and remove their helper tests from `scripts-test`.

- [ ] **Step 3: Verify tooling absence**

```bash
git ls-files android macos .github/actions/android-unit-tests .github/actions/macos-app-tests
rg -n 'android-(openapi|build|test)|macos-(build|run|test|dmg|app-icon)' Makefile scripts .github
```

Expected: no matches.

### Task 3: Simplify CI to Supported Products

**Files:**
- Modify: `.github/workflows/test-pr.yaml`
- Modify: `.github/pull_request_template.md`
- Modify: `scripts/ios-ci.sh`
- Modify: `scripts/tests/ios-ci-test.sh`
- Modify: `scripts/ci-changed-areas.sh`
- Modify: `scripts/tests/ci-changed-areas-test.sh` only if assertions mention retired products

**Interfaces:**
- Removes: `changes.outputs.android`, `changes.outputs.macos`, and the `android` and `macos` jobs
- Preserves: iOS, scripts, backend, frontend, E2E, migrations, infrastructure, image, and security gates

- [ ] **Step 1: Remove classifiers and jobs from the workflow**

Delete Android/macOS outputs, classifier invocations, script-test steps, jobs, downstream `needs` entries, and success-condition terms. Keep YAML dependency lists internally consistent.

- [ ] **Step 2: Update supported-client guidance**

Remove retired checks and screenshot guidance from the pull-request template. Rewrite iOS classifier comments and tests so they refer only to iOS work.

- [ ] **Step 3: Run CI helper tests**

```bash
make scripts-test
```

Expected: PASS.

- [ ] **Step 4: Inspect workflow references**

```bash
rg -n -i 'android|macos app|macos-app|needs:.*macos|needs:.*android' .github scripts Makefile
```

Expected: no retired-app references; generic `runs-on: macos-15` for iOS is allowed.

### Task 4: Remove Product Documentation and Stale Guidance

**Files:**
- Delete: `docs/macos.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `CONTRIBUTING.md`
- Modify: `README.md`
- Modify: `SECURITY.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/README.md`
- Modify: `docs/mobile.md`
- Modify: `docs/configuration.md`
- Modify: `docs/development.md`
- Modify: `docs/app-store/app-privacy.md`
- Modify: `docs/runbooks/ios-release.md`
- Modify: `docs/runbooks/production-release.md`
- Modify: `docs/specs/ios-ux/SPEC-05-ux-copy-empty-states-and-template-editor.md`
- Modify: other tracked prose returned by the reference scan

**Interfaces:**
- Produces: repository guidance describing browser and iOS clients only
- Preserves: operating-system references required to explain iOS/Xcode/CI/dependency behavior

- [ ] **Step 1: Remove app documentation**

Delete `docs/macos.md`. Remove Android/macOS application sections, support statements, release notes, setup requirements, architecture descriptions, checklists, and historical product claims from the listed documents.

- [ ] **Step 2: Rewrite mobile material for iOS**

Keep useful iOS authentication, architecture, contract-sync, privacy, testing, and release material. Change headings and prose from multi-platform “mobile apps” language when it implies Android remains supported.

- [ ] **Step 3: Audit remaining references**

```bash
rg -n -i --hidden --glob '!.git/**' --glob '!uv.lock' --glob '!frontend/package-lock.json' 'android|macos' .
```

Expected: every remaining match is either in the approved design/plan or is technically necessary for iOS host/toolchain support; no match describes a Rentivo Android or macOS app.

### Task 5: Full Verification and Delivery Commit

**Files:**
- Inspect: all changed files

**Interfaces:**
- Produces: one coherent retirement change ready for human review

- [ ] **Step 1: Run backend quality gates**

```bash
make lint
make test-cov
```

Expected: lint/format PASS and 100% backend coverage.

- [ ] **Step 2: Run frontend quality gates**

```bash
make openapi-check
make ios-openapi-check
make frontend-check
```

Expected: PASS.

- [ ] **Step 3: Run remaining platform and script tests**

```bash
make scripts-test
make ios-test
```

Expected: PASS.

- [ ] **Step 4: Inspect repository state**

```bash
git diff --check
git status --short
git diff --stat
git diff -- . ':(exclude)docs/superpowers/specs/2026-08-28-retire-android-macos-apps-design.md' ':(exclude)docs/superpowers/plans/2026-08-28-retire-android-macos-apps.md'
```

Expected: no whitespace errors and no unrelated modifications.

- [ ] **Step 5: Commit the implementation**

```bash
git add -A
git commit -m "chore: retire Android and macOS apps"
```

Expected: commit succeeds with repository hooks passing. Leave the change unmerged for human review.
