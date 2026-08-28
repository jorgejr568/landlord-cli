# iOS App

Rentivo's native client lives under `ios/`. It is a thin SwiftUI client over
the same FastAPI contract used by the browser: there is no local database,
offline mode, or iOS-only business logic. For day-to-day commands, see
[`development.md`](development.md); for releases, see
[`runbooks/ios-release.md`](runbooks/ios-release.md).

## Architecture

The application is split into these layers:

- `Domain/` — identifiers, money, validation, and business models;
- `Data/` and `Data/API/` — repositories, wire DTOs, authentication, and the
  live API client;
- `App/` — dependency wiring, session state, and root navigation;
- `DesignSystem/` — visual tokens and reusable controls;
- `Features/` — authentication, home, bills, billings, organizations, and
  account screens;
- `Resources/` — assets and app resources.

`Domain/` and `Data/` form the `RentivoCore` Swift package declared by
`ios/Package.swift`. The other layers belong only to the Xcode app target.
Customer-facing copy is PT-BR; code, comments, and identifiers are English.

## API contract sync

The app keeps a reference copy of the public API contract at
`ios/Rentivo/openapi.json`. It must remain byte-identical to
`frontend/openapi.json`:

```bash
make ios-openapi-sync
make ios-openapi-check
```

The copy documents the server contract but is not a build input. Wire DTOs are
hand-written in `ios/Rentivo/Data/API/RemoteDTOs.swift`, so schema changes must
update the DTOs and their tests explicitly.

## Authentication

The app can authenticate an e-mail and password directly against
`/api/v1/auth/mobile/*`, including TOTP, recovery-code, and passkey challenges.
The resulting bearer token is stored in the Keychain.

On launch, the app restores the session with `GET /api/v1/auth/session`. A 401
clears the stored token and returns to the anonymous state. Sign-out revokes
the bearer token before clearing local authentication state.

The API also publishes `/.well-known/apple-app-site-association` when
`RENTIVO_APPLE_TEAM_ID` is configured, allowing the app to reuse passkeys for
the site's relying-party ID.

## Local development and demo mode

Open `ios/Rentivo.xcodeproj` in Xcode for simulator development. A DEBUG build
can point at another API origin through the `RENTIVO_API_BASE_URL` environment
variable on the Run scheme; release builds always use the production URL.

The built-in mock/demo mode swaps the live repository for deterministic
fixtures without network or credential storage. UI tests enable it with launch
arguments such as `--ui-testing` and `--screenshot-authenticated`.

## Build and test

```bash
make ios-test
make ios-openapi-check
```

`make ios-test` runs the `RentivoCore` package suite and requires a full Xcode
installation because Swift Testing is unavailable in Command Line Tools alone.
CI runs that package suite and the Xcode-hosted `RentivoTests` target against a
resolved iPhone simulator. `RentivoUITests` is intentionally excluded from the
normal package job.

The iOS path classifier is `scripts/ios-ci.sh paths-changed`. It watches the
app sources, package inputs, iOS composite action, contract sync helper, helper
tests, and relevant workflow files.

## Release

Any shipped change under `ios/` that lands on `main` triggers
`.github/workflows/ios-release.yml`. The workflow verifies the contract and
tests, archives the app, exports with App Store distribution signing, uploads
to App Store Connect, and distributes the processed build to TestFlight.

`MARKETING_VERSION` identifies the release train, while the GitHub Actions run
number supplies the build number. See
[`runbooks/ios-release.md`](runbooks/ios-release.md) for the complete operator
procedure and triage steps.

## Security properties

- Passwords and MFA codes are submitted only to authentication endpoints and
  are never written to the Keychain.
- Passkey private keys remain in the system credential provider.
- Bearer tokens use a generic-password Keychain item with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- The live URL session disables response caching and uses
  `reloadIgnoringLocalCacheData`.
- Receipt and generated-document files are written to the app container with
  iOS data-protection options before presentation or sharing.
