# Development Guide

Rentivo is a React/Vite application backed by FastAPI, a background worker, and
MariaDB. Nginx is the single browser entrypoint in the default Compose topology.

## Prerequisites

- [uv](https://docs.astral.sh/uv/) (provisions Python 3.14)
- Node.js 22+ and npm
- Docker and Docker Compose

Optional, and only needed for the native apps:

- A full Xcode install for `make ios-test` and the `macos-*` targets. Swift
  Testing, used by the iOS suite, is not available in Xcode Command Line Tools
  alone.
- JDK 21 plus the Android SDK for the `android-*` targets. The build declares
  no Gradle toolchain, so nothing pins the JDK — 21 is the version CI runs.
  Gradle also needs an SDK location from `android/local.properties`
  (gitignored) or `ANDROID_HOME`.

```bash
git clone https://github.com/jorgejr568/rentivo.git
cd rentivo
cp .env.example .env
cp .env.db.example .env.db
make install
```

## Compose development (recommended)

The development override layers `docker-compose.dev.yml` onto the production
service topology. It uses `.env.db` for local MariaDB values,
bind-mounts `backend/rentivo` and `frontend`, and enables Uvicorn and Vite
reload.

```bash
make compose-dev
open http://localhost:8080
```

Services are `db`, one-shot `validate`, one-shot `migrate`, `api`, `worker`,
`frontend`, and `proxy`. `validate` runs the production settings check and must
exit successfully before `migrate` starts; `api` and `worker` start only after
`migrate` completes. `jaeger`, `temporal`, and `temporal-ui` are also declared
but sit behind the `observability` and `temporal` Compose profiles, so they stay
down unless explicitly started (see [Optional profiles](#optional-profiles)).
The proxy listens on `127.0.0.1:8080`; MariaDB listens on `127.0.0.1:3306`.
The frontend and API are internal to Compose.

Backend and frontend edits reload automatically. The worker does not reload;
restart it after changing jobs or shared backend code:

```bash
RENTIVO_APP_ENV_FILE=.env docker compose --env-file .env.db \
  -f docker-compose.yml -f docker-compose.dev.yml restart worker
```

Useful commands:

```bash
make compose-logs           # follow all services
make compose-logs-worker    # follow worker only
make compose-shell          # shell in the API container
make compose-createuser     # create a login user
make compose-dev-down       # stop the development stack
```

`make compose-createuser` prompts for `Username:`, but the value it stores is
the user's e-mail address — logins are by e-mail, so type one.

All `compose-*` development helpers use this same `.env` plus `.env.db` contract
and the development override. Override `RENTIVO_DEV_DB_ENV_FILE` or
`RENTIVO_APP_ENV_FILE` when testing alternate local files.

## Split-process development

Run MariaDB in Compose and the applications on the host when debugging Python
or frontend tooling directly:

```bash
RENTIVO_APP_ENV_FILE=.env docker compose --env-file .env.db \
  -f docker-compose.yml -f docker-compose.dev.yml up -d db
make migrate
make frontend-install
```

Run these in separate terminals:

```bash
uv run --project backend uvicorn rentivo.api.app:create_app \
  --factory --reload --host 127.0.0.1 --port 8001
make frontend-dev
make worker
```

Open <http://localhost:5173>. Vite proxies `/api/v1` to
`http://127.0.0.1:8001`. Keep `.env` development origins/cookies aligned with
the address used in the browser. `make seed` adds optional demonstration data.

## Frontend and API contract

```bash
make frontend-install        # npm ci from the lockfile
make frontend-dev            # Vite development server
make frontend-build          # typecheck and production bundle
make frontend-test-cov       # Vitest with 100% coverage
make frontend-check          # the aggregate frontend gate
```

`make frontend-check` is the single command to run before a frontend PR: it
chains coverage, `typecheck`, `typecheck:e2e`, `lint`, and `build`.

`frontend/package.json` declares a `pretest` hook
(`scripts/tests/smoke-production-stack-test.sh`) that npm runs before Vitest.
A failure in that shell suite therefore aborts `npm test`, `make
frontend-test-cov`, and `make frontend-check` before a single React test runs —
read the first lines of the output rather than assuming a component broke.

FastAPI owns the OpenAPI contract. Refresh both committed artifacts after an
API route or schema change:

```bash
make openapi-export          # write frontend/openapi.json
make openapi-generate        # regenerate TypeScript API types
make openapi-check           # non-mutating CI freshness check
```

Do not hand-edit generated OpenAPI types.

`frontend/openapi.json` is the source of two further committed copies, one per
mobile app. Refresh them in the same change with `make ios-openapi-sync` and
`make android-openapi-sync`; see the iOS and Android sections below. There is no
third copy for macOS — that app links the `RentivoCore` package instead of
carrying its own contract.

## iOS development

The iOS app lives in `ios/Rentivo`; its Domain and Data layers are packaged as
the `RentivoCore` Swift package defined by `ios/Package.swift` (Swift tools
6.0, macOS 14 / iOS 17 minimums). Xcode is required — Swift Testing, used by
the `RentivoTests` target, is not available in Xcode Command Line Tools alone.

```bash
open ios/Rentivo.xcodeproj    # run the app in the simulator
make ios-test                 # swift test --package-path ios
```

`make ios-test` runs the package suite only, which covers the Domain and Data
layers — `App`, `DesignSystem`, `Features`, and `Resources` are excluded from
the package and are not exercised by it. CI runs the Xcode-hosted
`RentivoTests` target on top of that, so a green `make ios-test` is weaker than
a green CI run — see [mobile.md](mobile.md#ios) for exactly what CI adds.

The iOS app carries its own copy of the OpenAPI contract at
`ios/Rentivo/openapi.json`, which must stay byte-identical to
`frontend/openapi.json`:

```bash
make ios-openapi-sync     # copy frontend/openapi.json into ios/Rentivo
make ios-openapi-check    # non-mutating CI freshness check
```

Refresh the iOS copy in the same change as the frontend snapshot; it is a
reference contract, not a build input
([mobile.md](mobile.md#api-contract-sync)). Architecture and the authentication
handoff are described in [mobile.md](mobile.md).

## macOS development

The macOS app lives in `macos/Rentivo` and does **not** duplicate the Domain and
Data layers: `macos/Rentivo.xcodeproj` links the `RentivoCore` package from
`ios/` through a local package reference (`../ios`), so only `App/`,
`DesignSystem/`, `Features/`, and `Resources/` are macOS-authored. Xcode is
required.

```bash
open macos/Rentivo.xcodeproj   # run the app
make macos-build               # Debug build, ad-hoc signed
make macos-test                # RentivoMacTests on a platform=macOS destination
make macos-dmg                 # drag-to-Applications installer in dist/
make macos-app-icon            # regenerate the icon set from the iOS artwork
```

`make macos-test` covers the macOS app layer only; the layers below it belong to
`make ios-test`. Because both apps build from the same package, a change under
`ios/Rentivo/Domain` or `ios/Rentivo/Data` should run both — and it triggers the
macOS CI job, which is path-gated by `scripts/macos-ci.sh paths-changed`.

There is no `macos-openapi-*` target and no macOS release workflow. Packaging,
demo-mode launch arguments, and the platform adaptations (sidebar navigation,
Finder drag-and-drop receipts, save-panel downloads) are described in
[macos.md](macos.md).

## Android development

The Android app is a Gradle project rooted at `android/` with a single `:app`
module under the `app.rentivo` package, built with Jetpack Compose. It targets
`minSdk` 26 and `compileSdk`/`targetSdk` 35, and compiles to JVM target 17.
Gradle itself is wrapper 8.13 with AGP 8.7.3 and Kotlin 2.1.20; the build
declares no toolchain, so run it on **JDK 21** to match CI. Gradle also needs
the Android SDK location, taken from `android/local.properties` (gitignored, so
create it locally) or from `ANDROID_HOME`.

```bash
make android-build           # cd android && ./gradlew assembleDebug
make android-test            # cd android && ./gradlew testDebugUnitTest
```

The unit tests are pure JVM code — 30 test classes covering the domain and data
layers. There is no `androidTest` source set, so no emulator or connected
device is involved.

`make android-test` is weaker than CI: the CI composite action
(`.github/actions/android-unit-tests/action.yml`) also runs `:app:lintDebug`,
which has no Make target — run it directly from `android/` before pushing if
you want the same coverage locally. The Android job is path-gated by
`scripts/android-ci.sh paths-changed`; [mobile.md](mobile.md#android) lists what
triggers it.

The app keeps its own copy of the API contract at `android/app/openapi.json`,
byte-identical to `frontend/openapi.json`:

```bash
make android-openapi-sync     # copy frontend/openapi.json into android/app
make android-openapi-check    # non-mutating CI freshness check
```

As on iOS, that copy is a reference contract rather than a build input — the
wire DTOs are hand-written in
`android/app/src/main/java/app/rentivo/data/api/RemoteDTOs.kt`
([mobile.md](mobile.md#api-contract-sync)). See [mobile.md](mobile.md) for the
shared mobile architecture.

There is no release automation for Android yet — unlike iOS, no workflow
builds, signs, or uploads a release artifact.

## End-to-end and visual tests

```bash
make e2e                    # Playwright workflows, a11y, and visual checks
make e2e-update             # update reviewed visual baselines
```

The normal suite uses deterministic fixtures for fast workflow coverage. The
production-stack project, selected by `PLAYWRIGHT_PRODUCTION_STACK=1`, runs
without request interception against the MariaDB-backed Compose topology.
Treat snapshot changes as product changes: inspect desktop and mobile images
before committing them.

## HTTP security headers

The frontend Nginx image owns the browser-facing security headers. They live in
`frontend/nginx/security-headers.conf` and are `include`d by every block of
`frontend/nginx/default.conf`, because Nginx discards the whole inherited
`add_header` set as soon as a block declares an `add_header` of its own — and
both the `/assets/` and the `= /index.html` blocks set `Cache-Control`. The
`= /index.html` block is what serves the SPA document for every client-side
route, via the `try_files` internal redirect in `location /`.

The proxy (`infra/proxy/nginx.conf`) deliberately sets no response headers:
`docker-compose.dev.yml` replaces the frontend service with the Vite dev
server, so a policy applied at the proxy would break hot reload, and two layers
emitting a `Content-Security-Policy` would make the browser enforce the
intersection of both.

Alongside the two content-security policies, the same snippet sets three
unconditional headers: `X-Content-Type-Options: nosniff`,
`X-Frame-Options: DENY` (the legacy companion to `frame-ancestors`), and
`Referrer-Policy: strict-origin-when-cross-origin`.

Two policies ship together:

- `Content-Security-Policy` enforces only `base-uri`, `object-src`,
  `frame-ancestors`, and `form-action`. The application has no `<base>`
  element, no `<object>`/`<embed>`, no cross-origin form action, and is never
  framed, so these cannot break a working page.
- `Content-Security-Policy-Report-Only` carries the full resource policy
  (`script-src`, `style-src`, `font-src`, `img-src`, `connect-src`,
  `frame-src`). It stays report-only because Cloudflare Turnstile and Google
  Tag Manager are disabled in every automated environment and therefore
  untested, and because the Tag Manager container's contents are configured
  outside this repository.

To promote the resource policy to enforcing: confirm a production observation
window with no report-only violations for the Turnstile and Tag Manager flows,
then move the directives into the enforced `add_header` in
`frontend/nginx/security-headers.conf` and update the expected values in
`frontend/e2e/security.spec.ts` and `frontend/e2e/production-stack.spec.ts`.

`frontend/e2e/security.spec.ts` locks the committed Nginx source on every
`make e2e` run. The live headers and a zero-violation assertion are covered by
the `production-stack` Playwright project, which is the only suite that
exercises the real Nginx image.

## Tests, lint, and hooks

Run the checks relevant to what you changed:

```bash
make fmt                     # ruff format + autofix, before linting
make lint
make test
make test-cov
make frontend-check          # coverage, typechecks, lint, build
make openapi-check
make e2e
make scripts-test            # if scripts/ or the CI script tests changed
make ios-openapi-check       # if the API schema changed
make ios-test                # if ios/ changed; requires full Xcode
make android-openapi-check   # if the API schema changed
make android-test            # if android/ changed; JVM only, no emulator
```

Backend and authored frontend code enforce 100% coverage. Backend tests run in
parallel and normally use isolated SQLite databases. `make install` registers
pre-commit hooks for formatting, lint, and the full test suite. The iOS and
Android suites have no coverage gate configured.

## Jobs and worker

State-changing API flows enqueue background jobs for email, communications,
PDF/receipt rendering, exports, and storage cleanup. Run the worker with
`make worker` on the host or as the Compose `worker` service. New database-driver
handlers register through `@register("job.type")` in
`backend/rentivo/jobs/handlers/`.

The database driver is the production default. Temporal is optional and uses
the same worker entrypoint. Driver behavior and extension steps are documented
in [jobs.md](jobs.md).

With `RENTIVO_EMAIL_BACKEND=local`, sent messages are `.eml` files in
`./outbox` on the host or `/app/outbox` in the worker container.

## Optional profiles

OpenTelemetry is disabled by default. Start local Jaeger and enable tracing:

```bash
make jaeger-up
# .env when using Compose:
# RENTIVO_OTEL_ENABLED=true
# RENTIVO_OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318
```

Jaeger is at <http://localhost:16686>. Stop it with `make jaeger-down`.

Start the optional local Temporal cluster and UI:

```bash
make temporal-up
# Temporal: localhost:7233; UI: http://localhost:8233
make temporal-down
```

Inside Compose, use `RENTIVO_TEMPORAL_HOST=temporal:7233`; host processes use
`localhost:7233`. See [observability.md](observability.md) and
[jobs.md](jobs.md).

## Database migrations

Schema is managed by Alembic in `backend/alembic/versions/`.

```bash
make migrate
uv run --project backend alembic -c backend/alembic.ini heads
uv run --project backend alembic -c backend/alembic.ini revision -m "add foo"
```

`make migrate-fresh` and `make compose-migrate-fresh` drop all tables. Use them
only against disposable development databases. Let Alembic generate revision
IDs; never invent them by hand.

## Disposable production-topology rehearsal

Use production-equivalent disposable values in separate application and
database files to test source topology and startup ordering locally.

The two files play different roles. `RENTIVO_APP_ENV_FILE` is loaded into the
backend containers as their settings; `RENTIVO_DB_ENV_FILE` is Compose's
`--env-file`, so it must supply everything the Compose files interpolate. Seven
variables there are marked required in `docker-compose.yml` and fail the command
outright when missing, before any container starts:

- `RENTIVO_PUBLIC_ORIGIN` — the public HTTPS origin, applied to the API's
  public, app, and WebAuthn origins
- `RENTIVO_WEBAUTHN_RP_ID` — must equal that origin's hostname
- `RENTIVO_TRUSTED_TLS_TERMINATOR_CIDR` — the address or CIDR the proxy trusts
  for forwarded headers
- `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` —
  MariaDB container provisioning

`RENTIVO_PORT` (default `8080`), `MYSQL_PORT` (default `3306`),
`RENTIVO_PROXY_IP` (default `172.30.0.10`), and `RENTIVO_APP_SUBNET` (default
`172.30.0.0/24`) are optional overrides in the same file. `.env.db.example`
shows the shape.

```bash
make stack-config \
  RENTIVO_DB_ENV_FILE=/path/to/db.env \
  RENTIVO_APP_ENV_FILE=/path/to/app.env
make stack-build \
  RENTIVO_DB_ENV_FILE=/path/to/db.env \
  RENTIVO_APP_ENV_FILE=/path/to/app.env
make stack-up \
  RENTIVO_DB_ENV_FILE=/path/to/db.env \
  RENTIVO_APP_ENV_FILE=/path/to/app.env
```

`stack-up` runs the migration service before API and worker and exposes Nginx
on `RENTIVO_PORT` (default `8080`). Use `make stack-migrate` only for an explicit
migration-only rehearsal. These targets build local images and are not a
production deployment mechanism. Production releases and previous-version
redeploys use only protected automation with complete-gate-tested immutable
image digests; follow the
[production release runbook](runbooks/production-release.md).

## Maintenance scripts

| Command | Purpose |
|---|---|
| `make seed` | Add demonstration data to a development database |
| `make regenerate-pdfs` / `-dry` | Re-render invoice PDFs |
| `make regenerate-recibos` / `-dry` | Enqueue paid-bill receipt rendering |
| `make backfill-encryption` / `-dry` | Encrypt historical plaintext rows after enabling KMS |
| `make backfill-encryption-reset-blind-index` | Rebuild the user email blind index after key rotation |
| `make redact-audit-logs` / `-dry` | Redact historical audit-log PII |
| `make encrypt-job-payloads` / `-dry` | Encrypt historical plaintext job payloads |

## Troubleshooting

- **Port 3306 is busy:** override `MYSQL_PORT` and keep host-side
  `RENTIVO_DB_URL` aligned.
- **Port 8080 is busy:** set `RENTIVO_PORT` for the Compose proxy.
- **Container tries `localhost` for MariaDB:** use the default Compose
  environment; containers must connect to host `db`.
- **Production configuration is rejected:** production intentionally rejects
  development secrets, HTTP/localhost origins, insecure cookies, local
  email/storage, and base64 encryption.
- **Worker code seems stale:** restart the `worker` service; it has no reload.
- **Schema is stale after changing branches:** run `make migrate`, or rebuild a
  disposable development database with `make migrate-fresh`.
