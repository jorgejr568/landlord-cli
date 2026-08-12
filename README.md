<h1 align="center">Rentivo</h1>

<p align="center">
  Apartment billing management with PDF invoice generation
</p>

<p align="center">
  <a href="https://github.com/jorgejr568/rentivo/actions/workflows/deploy.yml"><img src="https://github.com/jorgejr568/rentivo/actions/workflows/deploy.yml/badge.svg" alt="deploy"></a>
  <a href="https://codecov.io/gh/jorgejr568/rentivo"><img src="https://codecov.io/gh/jorgejr568/rentivo/branch/main/graph/badge.svg" alt="codecov"></a>
  <a href="https://github.com/jorgejr568/rentivo/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-blue" alt="GPL-3.0"></a>
</p>

Built for Brazilian landlords: tenant-facing output is in **PT-BR**, with
**BRL (R$)** currency and PIX QR codes on invoices.

## Features

- Recurring billing templates and one-click monthly bill generation
- PDF invoices, PIX QR codes, receipt attachments, and payment receipts
- React/Vite browser application backed by the versioned FastAPI API
- Native iOS and macOS (SwiftUI) and Android (Jetpack Compose) apps on the same
  contract
- API-key authentication with scopes and per-organization grants
- One-day hidden login keys for browser sessions, revoked on logout
- TOTP MFA, passkeys (WebAuthn), Google login, and password recovery
- Organizations with owner/admin/manager/viewer roles and email invites
- Background jobs for email, PDF rendering, exports, and storage cleanup
- KMS field encryption, audit logging with PII redaction, S3, and SES
- MariaDB, Alembic migrations, Nginx edge proxy, and optional Temporal/OTel

## Production topology

The default Compose manifest is the production service topology:

```text
MariaDB -> one-shot Alembic migration -> FastAPI API + worker
                                      -> React static frontend
                                      -> Nginx edge proxy
```

Nginx exposes the application on `127.0.0.1:8080` by default. It sends
`/api/v1` and public machine endpoints to FastAPI and browser routes to React.
API and worker start only after migration succeeds; Nginx waits for API
readiness and frontend health.

## Local development

Prerequisites: [uv](https://docs.astral.sh/uv/), Python 3.14 (see
`.python-version`; uv provisions it), Node.js 22+, npm, Docker, and Docker
Compose. Optional, for mobile work: a full Xcode installation for iOS (Swift
Testing is unavailable under CommandLineTools alone), and JDK 21 plus an
Android SDK for Android.

```bash
git clone https://github.com/jorgejr568/rentivo.git
cd rentivo
cp .env.example .env
cp .env.db.example .env.db
make install
make compose-dev
```

Open <http://localhost:8080>. The development override uses the same services
as production, bind-mounts backend and frontend source, enables Uvicorn/Vite
reload, and uses `.env.db` for local MariaDB provisioning. Restart the
worker after changing handlers because it does not auto-reload:

```bash
RENTIVO_APP_ENV_FILE=.env docker compose --env-file .env.db \
  -f docker-compose.yml -f docker-compose.dev.yml restart worker
```

For split-process development, start MariaDB with the split-env Compose command
in the development guide, run `make migrate`, then run `make frontend-dev`, the
FastAPI Uvicorn entrypoint, and `make worker` in separate terminals. See the
[development guide](docs/development.md) for exact commands.

## iOS app

`ios/Rentivo` is a SwiftUI client backed by the `RentivoCore` Swift package
(Domain and Data layers). Open `ios/Rentivo.xcodeproj` in Xcode to run it in
the simulator.

```bash
make ios-test            # swift test --package-path ios (requires full Xcode)
make ios-openapi-check   # verify ios/Rentivo/openapi.json matches frontend/openapi.json
```

Releases are automated: bumping `MARKETING_VERSION` in
`ios/Rentivo.xcodeproj/project.pbxproj` on `main` triggers
`.github/workflows/ios-release.yml`, which archives, signs with an Apple
Distribution certificate, uploads to App Store Connect, and distributes the
processed build to its TestFlight group. CI supplies the build number. See the
[iOS release runbook](docs/runbooks/ios-release.md) for the procedure and
triage.

## Android app

`android/` is a single-module Gradle project (`:app`, application ID
`app.rentivo`) written in Kotlin with Jetpack Compose, targeting minSdk 26 and
compile/target SDK 35. The build declares no JDK toolchain pin; CI runs on JDK
21 (Temurin), so use the same to stay aligned. An Android SDK is located
through `android/local.properties` or `ANDROID_HOME`. Open `android/` in
Android Studio to run it in an emulator.

```bash
make android-build           # ./gradlew assembleDebug
make android-test            # ./gradlew testDebugUnitTest (JVM only, no emulator)
make android-openapi-check   # verify android/app/openapi.json matches frontend/openapi.json
```

The release gate runs `assembleDebug`, `testDebugUnitTest`, and `lintDebug` on
`ubuntu-latest`, path-gated by `scripts/android-ci.sh`. There is no Android
release automation yet; unlike iOS, store builds are produced by hand.

Both mobile apps hand-write their wire DTOs. The committed `openapi.json`
copies are reference contracts kept byte-identical to `frontend/openapi.json`
by `make ios-openapi-check` and `make android-openapi-check`, not build inputs.
See the [mobile apps guide](docs/mobile.md).

## macOS app

`macos/Rentivo` is a native SwiftUI client for the Mac (bundle
`br.com.rentivo.macos`, macOS 14 minimum, Swift 6). It is not a third port of
the Domain and Data layers: `macos/Rentivo.xcodeproj` links the same
`RentivoCore` package from `ios/` through a local package reference, so only the
app layer — shell, design system, features — is macOS-authored. It therefore
keeps no `openapi.json` copy of its own and needs no contract sync step. Open
`macos/Rentivo.xcodeproj` in Xcode to run it.

```bash
make macos-build       # ad-hoc signed Debug build
make macos-test        # RentivoMacTests on platform=macOS (requires full Xcode)
make macos-dmg         # drag-to-Applications installer in dist/
make macos-app-icon    # regenerate the icon set from the iOS artwork
```

The macOS job runs on `macos-15`, path-gated by `scripts/macos-ci.sh` — which
also watches the `RentivoCore` sources under `ios/`, since a change there
changes this app. There is no macOS release automation: the DMG is the
distribution artifact, and it is not Developer ID signed or notarized. See the
[macOS app guide](docs/macos.md).

## Production configuration

Production uses separate database interpolation and application environment
files. Start from `.env.db.example` and `.env.example`, then store real values in
the deployment secret manager. `make stack-config` validates the source Compose
topology against those files; it does not deploy production.

Override the secret-managed file locations when needed:

```bash
make stack-config \
  RENTIVO_DB_ENV_FILE=/etc/rentivo/db.env \
  RENTIVO_APP_ENV_FILE=/etc/rentivo/app.env
```

Follow the [production release runbook](docs/runbooks/production-release.md)
for the only supported deployment path: protected automation consuming the
complete-gate-tested immutable SHA and image digests. Local `stack-build` and
`stack-up` outputs are never production release artifacts.

## Development and verification commands

| Command | Purpose |
|---|---|
| `make frontend-install` | Install locked frontend dependencies |
| `make frontend-dev` / `frontend-build` | Run Vite / build the production bundle |
| `make frontend-test-cov` | Run Vitest with 100% coverage thresholds |
| `make frontend-check` | Coverage, both typechecks, lint, and build |
| `make worker` | Run the configured background-job worker locally |
| `make migrate` | Upgrade a host-connected database to Alembic head |
| `make seed` | Seed local demonstration data |
| `make lint` / `fmt` | Check / fix Python formatting and lint |
| `make test` / `test-cov` | Run backend tests / explicit coverage report |
| `make scripts-test` | Run the standalone CI helper script tests |
| `make openapi-export` / `openapi-generate` | Refresh API snapshot / generated types |
| `make openapi-check` | Verify committed OpenAPI artifacts are current |
| `make ios-test` | Run the `RentivoCore` Swift package suite (requires full Xcode) |
| `make ios-openapi-sync` / `ios-openapi-check` | Refresh / verify the iOS contract copy |
| `make android-build` / `android-test` | Assemble the debug APK / run JVM unit tests |
| `make android-openapi-sync` / `android-openapi-check` | Refresh / verify the Android contract copy |
| `make e2e` / `e2e-update` | Run Playwright / update reviewed baselines |
| `make jaeger-up` / `jaeger-down` | Start / stop the observability profile |
| `make temporal-up` / `temporal-down` | Start / stop the Temporal profile |

## Configuration

All application variables use the `RENTIVO_` prefix. Copy `.env.example` for
local development and copy `.env.db.example` to `.env.db` for Compose database
provisioning. Production injects both files from its secret manager.

| Variable | Development default | Purpose |
|---|---|---|
| `RENTIVO_DB_URL` | MariaDB on `localhost:3306` | SQLAlchemy database URL |
| `RENTIVO_SECRET_KEY` | development placeholder | API-key hashing/session secret |
| `RENTIVO_PUBLIC_URL` | request-derived | Canonical public origin |
| `RENTIVO_STORAGE_BACKEND` | `local` | `local` or `s3` invoice storage |
| `RENTIVO_EMAIL_BACKEND` | `local` | local `.eml` or AWS SES |
| `RENTIVO_ENCRYPTION_BACKEND` | `base64` | development obfuscation or AWS KMS |
| `RENTIVO_JOB_BACKEND` | `database` | database polling or Temporal |

Production validation rejects development secrets, insecure cookies, localhost
origins, local storage/email, and reversible encryption. See the generated
[configuration reference](docs/configuration.md) for every setting.

## Architecture

The repository is a uv workspace with independently packaged backend and
frontend applications, plus a Swift Package Manager package shared by the iOS
and macOS apps and a Gradle project for the Android app.

```text
backend/
  rentivo/
    api/              FastAPI app, middleware, routes, and schemas
    models/           Pydantic domain models
    repositories/     Abstract contracts and SQLAlchemy Core implementations
    services/         Billing, bills, users, organizations, auth, and audit
    jobs/             Database and Temporal drivers, registry, and handlers
    workers/          Worker entrypoint
    email/            Transactional templates and rendering
    communications/   Message rendering, defaults, and moderation
    storage/          Local and S3 invoice storage
    encryption/       Base64/KMS field encryption and caches
    cache/            Memory, null, and Redis cache backends
    export/           Export serializers
    observability/    Structured logging and OpenTelemetry tracing
    pdf/              Invoice and receipt PDF generation
    scripts/          Maintenance and data migration commands
  alembic/            Schema migrations
frontend/
  src/                React/Vite/TypeScript application
  e2e/                Playwright workflows and reviewed visual baselines
ios/
  Config/             App Info.plist
  Package.swift       RentivoCore Swift package manifest
  Rentivo/            SwiftUI app; RentivoCore package Domain/Data sources
  Rentivo.xcodeproj   Xcode app project
  RentivoTests/       Shared tests: RentivoCore package suite and the Xcode-hosted target
  RentivoUITests/     Xcode UI tests
macos/
  Config/             App Info.plist and sandbox entitlements
  Rentivo/            SwiftUI app layer: App/, DesignSystem/, Features/, Resources/
  Rentivo.xcodeproj   Xcode app project; links RentivoCore from ../ios
  RentivoMacTests/    macOS app-layer unit tests
android/
  app/src/main/java/app/rentivo/
    domain/           Models, money, and validation
    data/             Repositories, mock store, and file store
    data/api/         Live API client, wire DTOs, and credential storage
    app/              Activity, root navigation, and app model
    designsystem/     Compose theme and shared components
    features/         Auth, home, bills, billings, organizations, account
scripts/               CI helpers and contract sync scripts
docs/                  Guides, runbooks, and generated references
infra/proxy/           Nginx edge configuration
```

## Documentation

| Document | Contents |
|---|---|
| [Documentation index](docs/README.md) | Map of every document in `docs/` |
| [Configuration](docs/configuration.md) | Environment variables and validation rules |
| [Development](docs/development.md) | Local and Compose development workflows |
| [Mobile apps](docs/mobile.md) | iOS/Android architecture, contract sync, and auth handoff |
| [macOS app](docs/macos.md) | macOS app layer, `RentivoCore` reuse, DMG packaging, and CI gating |
| [Job drivers](docs/jobs.md) | Database and optional Temporal job execution |
| [Observability](docs/observability.md) | Logging, traces, profiles, and production signals |
| [Production release](docs/runbooks/production-release.md) | Big-bang deployment and recovery runbook |
| [iOS release](docs/runbooks/ios-release.md) | iOS App Store release trigger, pipeline, and triage |
| [App privacy](docs/app-store/app-privacy.md) | App Store privacy questionnaire answers |
| [Contributing](CONTRIBUTING.md) | Workflow, conventions, tests, and PR expectations |
| [Security](SECURITY.md) | Private vulnerability reporting |
| [Changelog](CHANGELOG.md) | SemVer release history |

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | React, Vite, TypeScript |
| iOS app | Swift, SwiftUI, Swift Package Manager (RentivoCore) |
| macOS app | Swift, SwiftUI/AppKit, linking the same RentivoCore package |
| Android app | Kotlin, Jetpack Compose, Gradle |
| Backend API | FastAPI, Uvicorn |
| Database | MariaDB 11, SQLAlchemy Core |
| Migrations | Alembic |
| Edge | Nginx |
| Jobs | Database worker or optional Temporal |
| Auth | API keys, secure cookies, TOTP, WebAuthn |
| Storage / email | Local or S3 / local or SES |
| Encryption | AWS KMS in production |
| Observability | structlog, OpenTelemetry, Jaeger/CloudWatch |
| CI/CD | GitHub Actions |

## License

[GPL-3.0](LICENSE)
