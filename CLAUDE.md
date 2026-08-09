# Rentivo

Rentivo is an apartment billing platform with a React/Vite client, a FastAPI
JSON API, background workers, PDF generation, and MariaDB in production.

## Local setup

```bash
make install
cp .env.example .env
cp .env.db.example .env.db
make compose-dev
```

The development stack is available at `http://localhost:8080`. The frontend
dev server proxies API requests to FastAPI through the same Nginx edge used by
the production-shaped Compose topology.

Useful commands:

```bash
make frontend-dev          # Vite development server
make worker                # background worker on the host
make compose-shell         # shell in the API container
make compose-createuser    # create a user through current services
make openapi-check         # verify OpenAPI snapshot and generated client
make frontend-check        # React coverage, types, lint, and build
make test                  # parallel backend suite
```

Always run Python tools through `uv run --project backend ...`; do not use bare
`python`, `pip`, or `pytest`.

## Architecture

- `backend/rentivo/api/` owns the FastAPI application, authentication,
  dependency wiring, CSRF handling, errors, schemas, and `/api/v1` routes.
- `backend/rentivo/services/` contains business rules. Route handlers should
  authorize and translate HTTP data, then delegate business behavior here.
- `backend/rentivo/repositories/` defines persistence protocols and SQLAlchemy
  implementations. Keep database access behind these abstractions.
- `backend/rentivo/models/` contains domain models. Money is integer centavos,
  never floating point.
- `backend/rentivo/workers/` and `backend/rentivo/jobs/` execute durable work
  using the configured database or Temporal backend.
- `backend/rentivo/storage/`, `encryption/`, `email/`, and `cache/` provide
  swappable local and production integrations. Do not bypass their factories.
- `frontend/src/` is the React application. Routing and providers live under
  `frontend/src/app/`; reusable UI lives under `frontend/src/components/`;
  generated API types and client code live under `frontend/src/api/`.
- `frontend/e2e/` contains Playwright projects for mocked UI coverage and the
  production-stack workflow.
- `ios/Rentivo` is the SwiftUI application. Its Domain and Data layers are
  packaged as the `RentivoCore` Swift package defined by `ios/Package.swift`
  (Swift tools 6.0, macOS 14 / iOS 17 minimums) and covered by
  `swift test --package-path ios`, which requires a full Xcode toolchain
  (Swift Testing is unavailable in CommandLineTools alone). See
  `docs/mobile.md`.
- `android/` is the Kotlin and Jetpack Compose application under the
  `app.rentivo` package. Its domain and data layers are pure JVM code covered
  by `make android-test`, which needs the Android SDK but no emulator. The
  build declares no JDK toolchain pin; CI runs on JDK 21 (Temurin), so use the
  same to stay aligned. See `docs/mobile.md`.

The browser talks only to the FastAPI contract. When an API schema changes,
update the committed OpenAPI snapshot and generated TypeScript client with the
existing npm/Make targets, then verify `make openapi-check`. The iOS app keeps
its own copy of the contract at `ios/Rentivo/openapi.json`, which must stay
byte-identical to `frontend/openapi.json`; refresh it with
`make ios-openapi-sync` and verify it with `make ios-openapi-check` whenever
the API schema changes. The Android app does the same with
`android/app/openapi.json`, refreshed by `make android-openapi-sync` and
verified by `make android-openapi-check`.

## HTTP and security

FastAPI is created by `rentivo.api.app:create_app`. Production traffic reaches
it through the Nginx proxy; forwarded headers are trusted only from the
configured proxy address. Production uses HTTPS origins, a matching WebAuthn
RP ID, secure `__Host-` cookies, and double-submit CSRF protection.

API mutation tests use the helpers and fixtures in
`backend/tests/api/conftest.py`. Preserve authorization checks at both the
route and domain-access layers. Never expose encrypted fields, credentials,
recovery codes, session tokens, or API-key material in logs or API responses.

## Persistence and integrations

Alembic owns schema changes. Generate revisions with:

```bash
uv run --project backend alembic -c backend/alembic.ini revision -m "description"
```

Production uses MariaDB, S3 storage, KMS field encryption, SES email, and the
configured database or Temporal job backend. Local substitutes exist for
tests and development only. Settings are documented in
`docs/configuration.md`; changes must remain synchronized with `.env.example`
and `backend/rentivo/settings.py`.

KMS ciphertext, blind indexes, S3 object keys, job idempotency, audit
redaction, and cache invalidation are storage contracts. Preserve them when
changing repositories or services. KMS key loss makes encrypted data
unrecoverable.

## Testing

Backend coverage is 100 percent and is configured in
`backend/pyproject.toml`. The normal suite uses SQLite and an ephemeral
Temporal test server where required; migration and concurrency contracts run
against MariaDB in CI. Frontend authored code also maintains 100 percent
coverage. The iOS `RentivoCore` package suite (`make ios-test`) runs on
`macos-15` CI runners with a full Xcode toolchain, where CI also runs the
Xcode-hosted `RentivoTests` target via `xcodebuild` (only `RentivoUITests` is
excluded); it is not part of the SQLite/Temporal or Vitest suites and has no
coverage gate configured yet.

Before opening a PR, run the checks relevant to the change:

```bash
make lint
make test
make openapi-check
make frontend-check
make e2e
make scripts-test            # if scripts/ or the CI script tests changed
make ios-openapi-check       # if the API schema changed
make ios-test                # if ios/ changed (requires full Xcode)
make android-openapi-check   # if the API schema changed
make android-test            # if android/ changed (JVM only, no emulator)
```

The complete release gate also renders production/development Compose,
round-trips migrations on MariaDB, boots functional and production-settings
stacks, runs dependency and configuration scans, and builds all production
images locally to catch Dockerfile breakage. Gate jobs are path-filtered by
`scripts/ci-changed-areas.sh`, which classifies the diff into `backend`,
`frontend`, `docker`, and `scripts` areas; a job whose input areas are
untouched is skipped and counts as passing, and any `.github/` change or an
unusable base marks every gate area as changed. The mobile jobs are filtered
separately: `scripts/ios-ci.sh paths-changed` gates the iOS job and
`scripts/android-ci.sh paths-changed` gates the Android job, which builds,
unit-tests, and lints `android/` and verifies its OpenAPI copy whenever
`android/` or `frontend/openapi.json` changes. Image vulnerability scanning is
not part of the gate: `.github/workflows/image-vulnerability-scan.yml` scans
the production images weekly and keeps the `Weekly image vulnerability report`
issue (label `image-vulnerability-report`) up to date. The frontend npm audit
works the same way: `.github/workflows/npm-audit-report.yml` audits
`frontend/package-lock.json` weekly and keeps the `Weekly npm audit report`
issue (label `npm-audit-report`) up to date.

## Compose and release

`docker-compose.yml` is the production service topology. The one-shot
`validate` service checks production settings before `migrate`; API and worker
start only after migration succeeds. `docker-compose.dev.yml` switches backend
services to development settings and enables Vite hot reload.

Images are defined by:

- `backend/Dockerfile.api`
- `backend/Dockerfile.worker`
- `frontend/Dockerfile`

The deployment workflow publishes API, worker, and frontend images for one Git
SHA, attests each exact digest, resolves and verifies OCI labels/provenance,
and tests the exact images without rebuilding. Protected deployment automation
validates production configuration and real integration reachability before
migration and rollout. See `docs/runbooks/production-release.md`.

The iOS app releases independently: changing `MARKETING_VERSION` in
`ios/Rentivo.xcodeproj/project.pbxproj` on `main` triggers
`.github/workflows/ios-release.yml`, which archives, signs, and uploads to App
Store Connect. See `docs/runbooks/ios-release.md`.

## Contribution rules

- Code, comments, and identifiers are English; customer-facing copy —
  including the iOS app's UI — is PT-BR.
- Preserve repository, storage, encryption, email, cache, and job abstractions.
- Keep dependencies locked with `uv.lock` and `frontend/package-lock.json`.
- Use Conventional Commit PR titles and complete every PR template section.
- Automated contributors create PRs but never merge them or push to `main`.
- Do not open public issues for vulnerabilities; follow `SECURITY.md`.
