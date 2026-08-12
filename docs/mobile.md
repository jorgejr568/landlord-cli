# Mobile Apps

Rentivo ships two native clients — `ios/` (SwiftUI) and `android/` (Kotlin and
Jetpack Compose) — that are 1:1 ports of each other. Both are thin clients over
the same FastAPI contract the browser uses: no local database, no offline mode,
no mobile-only endpoints beyond the two authentication routes described below.

This guide covers what the two apps share and where they differ. For the
day-to-day commands, see [`development.md`](development.md); for the iOS
release procedure, see [`runbooks/ios-release.md`](runbooks/ios-release.md).

There is a third native client, `macos/`, but it is not a third port: it links
the `RentivoCore` package from `ios/` and only ports the app layer. Every
statement below about parity, DTOs, contract copies, and release automation
covers iOS and Android alone — see [`macos.md`](macos.md) for how the Mac app
diverges. Anything in the Domain and Data layers described here is shared with
it, so a change to `ios/Rentivo/Domain` or `ios/Rentivo/Data` is a change to the
macOS app as well.

## Parity

The apps deliberately mirror each other, so a change to one is a reviewable
diff against the other:

| Concern | iOS | Android |
|---|---|---|
| UI framework | SwiftUI | Jetpack Compose |
| Layers | `Domain/`, `Data/`, `Data/API/`, `App/`, `DesignSystem/`, `Features/` | `domain/`, `data/`, `data/api/`, `app/`, `designsystem/`, `features/` |
| Feature set | Auth, home, bills, billings, organizations, account | Same |
| Wire DTOs | Hand-written `Codable` (`ios/Rentivo/Data/API/RemoteDTOs.swift`) | Hand-written `kotlinx.serialization` (`android/app/src/main/java/app/rentivo/data/api/RemoteDTOs.kt`) |
| Token storage | Keychain (`KeychainCredentialStore`) | `EncryptedSharedPreferences` (`EncryptedCredentialStore`) |
| Appearance | Light only, portrait only | Light only, portrait only |
| Release automation | Yes (App Store Connect) | None yet |

Customer-facing copy is PT-BR in both apps, written as inline string literals.
Neither app has localization resources: there are no `.lproj` directories on
iOS, and `android/app/src/main/res/values/strings.xml` holds only the app name.
Code, comments, and identifiers stay English.

Platform coupling is kept at the edge. On Android, `app/MainActivity.kt` is
deliberately the only Android-coupled file in the app shell — everything below
it is plain JVM code, which is what lets the whole domain and data layer be
unit-tested without an emulator. iOS achieves the same split by packaging
`Domain` and `Data` as a platform-agnostic Swift package.

## API contract sync

`frontend/openapi.json` is the source of truth. Each app keeps a byte-identical
copy:

- `ios/Rentivo/openapi.json` — `make ios-openapi-sync` / `make ios-openapi-check`
- `android/app/openapi.json` — `make android-openapi-sync` / `make android-openapi-check`

Both `check` targets are a plain `cmp` against `frontend/openapi.json`
(`scripts/sync-ios-openapi.sh`, `scripts/sync-android-openapi.sh`) and run in
CI, so a schema change that does not refresh both copies fails the gate.

These copies are **reference contracts, not build inputs.** No generator runs
against them; both apps hand-write their wire DTOs. The committed copy is what
makes API drift visible in review — when it changes, the diff tells you which
DTOs to update by hand. Refresh both in the same change as the OpenAPI
snapshot itself.

One loose end: the Xcode app target still carries the
`swift-openapi-generator`, `swift-openapi-runtime`, and
`swift-openapi-urlsession` package references
(`ios/Rentivo.xcodeproj/project.pbxproj`), but no source file imports generated
output. The `RentivoCore` package does not reference the generator at all.
Removing the leftover Xcode dependency is a tracked follow-up.

## Authentication handoff

Neither app has a password field. Sign-in is handed to the system browser so
the native apps never touch credentials, and so MFA, Google sign-in, and
Turnstile stay implemented once, on the web.

1. The app generates a random `state` and opens
   `<base>/login?mobile_state=<state>` — iOS in an
   `ASWebAuthenticationSession`, Android in a Chrome Custom Tab.
2. The web login page (`frontend/src/features/auth/LoginPage.tsx`) authenticates
   the user normally, then calls `POST /api/v1/auth/mobile/authorize`, which
   issues a single-use authorization challenge.
3. The page redirects to
   `rentivo://auth/callback?code=<authorization_code>&state=<state>`.
4. The app validates the scheme, host, path, and returned `state`, then posts
   the code to `POST /api/v1/auth/mobile/exchange`. The backend consumes the
   one-time challenge and completes the login with `source="mobile"`, returning
   the bearer token in the response body (`credential_transport: "body"`) rather
   than a cookie.
5. The token is persisted — Keychain on iOS, `EncryptedSharedPreferences` on
   Android — and sent as `Authorization: Bearer …` on every subsequent request.

On launch the app calls `GET /api/v1/auth/session` with the stored token to
restore the session; a 401 there clears it. During normal use, a 401 raises a
session-expired signal — a `liveAPIClientSessionExpired` `NotificationCenter`
post on iOS, a `sessionExpired` `Flow` on Android — which the app model observes
to drop back to the anonymous state.

Logout round-trips through the browser too: the app opens
`<base>/mobile-logout?state=<state>` and waits for
`rentivo://auth/logout?state=<state>`, so the shared browser cookie jar is
cleared alongside the local token. The browser session is deliberately
non-ephemeral on iOS (`prefersEphemeralWebBrowserSession = false`) so login and
logout see the same cookies as the website.

The flow logic itself is pure and unit-tested on both platforms
(`MobileWebAuthenticationFlow` in `ios/Rentivo/Data/API/MobileWebAuthenticator.swift`
and `android/app/src/main/java/app/rentivo/data/api/MobileWebAuthenticationFlow.kt`),
including rejection of mismatched state, empty codes, and percent-encoded path
tricks.

## iOS

**Layout.** The app lives in `ios/Rentivo`. Its `Domain` and `Data` layers are
packaged as the `RentivoCore` Swift package defined by `ios/Package.swift`
(Swift tools 6.0, macOS 14 / iOS 17 minimums, **zero package dependencies**).
`App`, `DesignSystem`, `Features`, and `Resources` are excluded from the package
and exist only in the Xcode target. Bundle identifier: `br.com.rentivo.ios`.

**Build and run.**

```bash
open ios/Rentivo.xcodeproj    # run in the simulator
make ios-test                 # swift test --package-path ios
```

`make ios-test` requires a full Xcode install — Swift Testing is not available
in Command Line Tools alone — and covers the Domain and Data layers only.

**CI.** `.github/actions/ios-unit-tests/action.yml` on `macos-15` runners does
more: `swift test --package-path ios`, then the Xcode-hosted target through
`xcodebuild … test -only-testing:RentivoTests` against a resolved iPhone
simulator destination. `RentivoUITests` is intentionally excluded from the
required PR path (slower and timing-sensitive under XCUITest's synthesized
taps). A green `make ios-test` is therefore weaker than a green CI run; the
shared test files compile in both modes through a `#if canImport(RentivoCore)`
guard. The job is path-gated by `scripts/ios-ci.sh paths-changed`.

**Release.** Bumping `MARKETING_VERSION` in
`ios/Rentivo.xcodeproj/project.pbxproj` on `main` triggers
`.github/workflows/ios-release.yml`, which archives, signs, uploads to App
Store Connect, and distributes to TestFlight. The build number is
`github.run_number`, not a value in the project file. The workflow creates no
tag and no GitHub Release; tagging the release commit `ios/v<MARKETING_VERSION>`
is a manual operator step after the upload reports `state=VALID`. Full procedure
and triage: [`runbooks/ios-release.md`](runbooks/ios-release.md).

## Android

**Layout.** A Gradle project rooted at `android/` with a single `:app` module;
package and `applicationId` are both `app.rentivo`.

| Setting | Value |
|---|---|
| Gradle wrapper | 8.13 |
| AGP / Kotlin | 8.7.3 / 2.1.20 |
| `minSdk` | 26 |
| `compileSdk` / `targetSdk` | 35 |
| JVM target | 17 |
| JDK to run Gradle | **21** (CI convention; no toolchain pin) |

The build declares no Gradle toolchain, so nothing forces a particular JDK —
use 21 to match CI (Temurin 21 in
`.github/actions/android-unit-tests/action.yml`). Gradle also needs the Android
SDK location, from `android/local.properties` (gitignored — create it locally)
or `ANDROID_HOME`.

**Build and test.**

```bash
make android-build           # cd android && ./gradlew assembleDebug
make android-test            # cd android && ./gradlew testDebugUnitTest
```

Tests are pure JVM — 30 test classes under `android/app/src/test`. There is no
`androidTest` source set, so no emulator or connected device is ever involved.

**CI.** `.github/actions/android-unit-tests/action.yml` on `ubuntu-latest` runs
`./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug` and then
verifies the OpenAPI copy. There is no Make target for `lintDebug`, so
`make android-test` is weaker than CI — run lint from `android/` directly
before pushing if you want parity. The job is path-gated by
`scripts/android-ci.sh paths-changed`, which triggers on `android/`, the
composite action, the Android CI and sync scripts, the CI script's own shell
test (`scripts/tests/android-ci-test.sh`), `frontend/openapi.json`, and the
workflow file.

**Release.** There is none yet. `versionCode` is `1` and `versionName` is
`1.0.0`, there is no signing configuration, and no workflow builds, signs, or
uploads a store artifact — store builds would have to be produced by hand. An
`android-release` runbook, matching the iOS one, will be needed when release
automation ships.

## Local development and mock mode

Both clients hardcode the production base URL:

- iOS — `LiveAPIClient.productionURL` (`ios/Rentivo/Data/API/LiveAPIClient.swift`)
- Android — `LiveAPIClient.PRODUCTION_URL` and
  `MobileWebAuthenticationFlow.PRODUCTION_BASE_URL`

There is no setting, environment variable, build flavor, or scheme that points
a build at a local backend. Running either app against the development Compose
stack is not supported today; changing the URL means editing the source.

The supported offline path is the built-in mock/demo mode, which swaps the live
dependency graph for in-memory fixtures. It is gated to non-shippable builds:

```bash
# iOS: DEBUG builds only, via launch arguments
--ui-testing            # or --screenshot-authenticated

# Android: debuggable builds only
adb shell am start -n app.rentivo/.app.MainActivity --ez ui-testing true
```

Release builds never enter mock mode and always talk to production.

## Security notes

- **No credentials in the app.** Passwords, MFA, and federated sign-in happen
  in the browser; the app only ever holds a bearer token obtained by exchanging
  a one-time code.
- **Token at rest.** iOS uses a generic-password Keychain item with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, re-asserted on every
  update. Android uses `EncryptedSharedPreferences` (`AES256_SIV` keys,
  `AES256_GCM` values) over a hardware-backed `MasterKey`.
- **No response caching on iOS.** `LiveAPIClient.makeSession()` sets
  `urlCache = nil` and `reloadIgnoringLocalCacheData`. This is deliberate:
  the default configuration binds to the disk-backed `URLCache.shared`, which
  wrote authenticated payloads into the app container and — because these
  routes send no `Cache-Control` — served heuristically fresh copies, once
  causing a PDF render poll to re-read its own cached `pending` response
  forever.
- **Minimal Android surface.** The manifest requests only `INTERNET`, sets
  `allowBackup="false"`, declares the `rentivo://auth` deep link on a single
  `singleTask` activity, and exposes a `FileProvider` limited to one cache
  path (`RentivoDownloads/`) so the share sheet can open a downloaded document
  and nothing else.
- **State validation.** Callback URLs are accepted only when scheme, host,
  path, and `state` all match the value the app generated for that attempt.
