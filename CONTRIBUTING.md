# Contributing to Rentivo

Thanks for contributing! This guide covers the workflow; for environment setup see [docs/development.md](docs/development.md).

## TL;DR checklist

1. Fork / branch from `main`.
2. `make install && cp .env.example .env && cp .env.db.example .env.db && make compose-dev`
3. Write tests first where practical - **coverage must stay at 100%**.
4. `make lint && make test` (`make test-cov` when you need the coverage gate CI enforces).
5. Run the checks your change touches:
   - frontend or API schema: `make openapi-check && make frontend-check`, plus `make e2e` for UI flows.
   - `scripts/`: `make scripts-test`.
   - `ios/` or an API schema change: `make ios-test` and `make ios-openapi-check`.
6. Open a PR with a [Conventional Commit](https://www.conventionalcommits.org/) title and fill out every section of the PR template.

## Code conventions

- The browser UI is React/Vite under `frontend/src`; the JSON API is FastAPI under `backend/rentivo/api`; the native iOS client is SwiftUI under `ios/Rentivo`.
- Code, comments, and identifiers in **English**; all customer-facing text in **PT-BR** — React, PDF, email copy, and the iOS app UI alike.
- Money is stored as **centavos (int)** - never floats. Format with `rentivo.models.format_brl()`.
- Currency is **BRL (R$)**.
- Keep the repository, storage, encryption, email, cache, and job abstractions intact — backends must stay swappable.
- An API schema change must refresh the iOS OpenAPI copy: `ios/Rentivo/openapi.json` stays byte-identical to `frontend/openapi.json`. Run `make ios-openapi-sync`, then verify with `make ios-openapi-check`.
- Dependencies are managed with **uv**: edit `backend/pyproject.toml`, run `uv lock`, commit `uv.lock`. Never bare `pip`/`python`/`pytest` - use `uv run --project backend ...`.
- Lint and formatting are enforced by ruff (`make fmt` to fix).

## Tests

- `make test` runs the suite in parallel but does **not** measure coverage. `make test-cov` adds the coverage run and enforces **100%** (`fail_under = 100`), which is what CI's backend job does. New code needs tests or an explicit `# pragma: no cover` with justification.
- Most backend tests use in-memory SQLite. Temporal contracts start an ephemeral Temporal test server, and MariaDB CI covers migrations plus database-specific concurrency behavior.
- API mutation tests use the CSRF helpers and fixtures in `backend/tests/api/conftest.py`.
- `make frontend-check` runs the React coverage suite (100% for authored code), typechecks, lint, and the production build; `make openapi-check` verifies the committed FastAPI snapshot and generated TypeScript contract.
- `make e2e` runs Playwright workflows and visual parity. Use `make e2e-update` only after reviewing and approving an intentional UI difference.
- `make ios-test` runs the `RentivoCore` Swift package suite. It needs a full Xcode toolchain (Swift Testing is unavailable in CommandLineTools alone) and has no coverage gate configured.
- `make scripts-test` runs the shell and Python tests for `scripts/`. CI's `scripts` job is never path-filtered, because it owns the tests for the changed-area classifier that gates every other job.

## Database migrations

- Generate revisions with `uv run --project backend alembic -c backend/alembic.ini revision -m "description"` — **never hand-write revision IDs**.
- Migrations that drop or rename columns are breaking changes (see Versioning below).

## Commits & pull requests

- PR titles and merge commits follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `perf:`, `refactor:`, `chore:`, `docs:`, `test:`, `ci:`, `build:`, with optional scope (`feat(web): ...`). Breaking changes carry a `BREAKING CHANGE:` footer.
- Fill out **every** section of [.github/pull_request_template.md](.github/pull_request_template.md) — summary (lead with the why), what changed, test plan, screenshots for UI changes, config/deployment notes, risk & rollback.
- CI on PRs (`test-pr.yaml`) runs the `changes`, `scripts`, `backend`, `frontend`, `ios`, `e2e`, `migrations`, `compose-config`, `functional-stack`, `production-startup`, and `security-scan` jobs behind `release-gate`. The `production-images` matrix then builds API, worker, and frontend locally with `load: true` so Dockerfile breakage fails the gate, and `all-checks-pass` requires both phases.
- The `changes` job uses `scripts/ios-ci.sh paths-changed` to gate `ios`, while `scripts/ci-changed-areas.sh` produces the `backend`, `frontend`, `docker`, and `scripts` areas. Jobs whose inputs are untouched are skipped and count as passing. `scripts` and `security-scan` always run, and any `.github/` change (or an unusable base) marks every `ci-changed-areas.sh` area as changed. Outside pull requests (`workflow_call`, `workflow_dispatch`, push), the four general areas are forced to `true`; `ios` stays path-filtered on every event.
- The `security-scan` job covers backend dependency, secret, and configuration scans; image vulnerability scanning and the frontend npm audit are not part of the gate — the weekly `image-vulnerability-scan.yml` and `npm-audit-report.yml` workflows own them.
- The functional stack uses CI-only local email/storage/encryption backends. The production-startup job exercises production setting validation; deploy automation alone validates reachability of real production integrations.

## Merging policy — human-only

**Merges to `main` are performed by a human, never by an automated agent.** Agents and CI bots **open** pull requests and stop there; a human reviews and clicks merge.

This is enforced both behaviorally and at the repo level:

- `main` is a protected branch: **direct pushes are blocked for everyone (including admins)** - all changes land through a PR.
- **Auto-merge is disabled** repo-wide, so no agent can queue a merge to happen automatically.
- Force-pushes and branch deletion on `main` are blocked.

Rules for everyone, especially automated contributors:

- Never use the merge button, `gh pr merge`, squash/rebase/auto-merge, or any equivalent to land a PR. Open the PR and request human review.
- Never push directly to `main` (or any protected branch) to bypass the PR flow.
- If a task says "merge X", read it as "open a PR for X and request review". Only a human maintainer performs the actual merge.

See [AGENTS.md](AGENTS.md) for the agent-facing version of this rule.

## Versioning & releases

Rentivo follows [SemVer 2.0.0](https://semver.org/); the release history lives in [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog format). Releases are cut by maintainers: version bump + changelog PR (`chore(release): vX.Y.Z`), then a `vX.Y.Z` tag triggers the release workflow. When unsure which component to bump, bump higher.

The iOS app versions **independently** of the backend. Merging **any** change under `ios/` to `main` triggers `.github/workflows/ios-release.yml`, which archives, signs, uploads to App Store Connect, and distributes to TestFlight — so every iOS PR ships a build. `MARKETING_VERSION` in `ios/Rentivo.xcodeproj/project.pbxproj` is the release train and labels those builds; bump it when a change starts a new one. Shipped iOS versions are tagged `ios/v<MARKETING_VERSION>` (for example `ios/v1.2`); see [docs/runbooks/ios-release.md](docs/runbooks/ios-release.md).

## Security issues

Please do **not** open public issues for vulnerabilities - see [SECURITY.md](SECURITY.md).
