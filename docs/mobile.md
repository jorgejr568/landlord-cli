# Mobile Apps

Rentivo ships two native clients — `ios/` (SwiftUI) and `android/` (Kotlin and
Jetpack Compose) — that are 1:1 ports of each other. Both are thin clients over
the same FastAPI contract the browser uses: no local database, no offline mode,
no mobile-only endpoints beyond the `/api/v1/auth/mobile/*` routes and the
Apple associated-domains file described below.

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
| Sign-in | Native e-mail/password + in-app MFA; browser handoff for Google and Turnstile-gated flows | Browser handoff only |
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

## Authentication

There are two ways in, and they are not equivalent.

**Native credentials are the primary path**: the iOS app signs in with e-mail
and password against `/api/v1/auth/mobile/*` and finishes TOTP, recovery-code,
and passkey challenges in-app, without ever opening a browser. **The browser
handoff is the secondary path**, kept for what the app cannot do itself —
Google sign-in and anything gated by Turnstile. Android has no native sign-in
screens yet and uses the handoff for every login; so does macOS (see
[`macos.md`](macos.md)), even though it links the same `RentivoCore` client.

### Native sign-in

`POST /api/v1/auth/mobile/login` and `POST /api/v1/auth/mobile/signup`
(`backend/rentivo/api/routes/auth.py`) accept `{email, password}` and nothing
else. Body transport is implicit: these routes never set cookies, so there is
no `credential_transport` to negotiate and no CSRF token to carry — the bearer
token comes back in the response body, the same way `/auth/mobile/exchange`
returns it. Both record the session with `source="mobile"`.

Login settles in one of two shapes: `200` with a session, or `202` with an MFA
challenge carrying `challenge_id`, `challenge_token`, and the accepted
`methods` (`totp`, `recovery`, `passkey`). The app finishes the challenge
against the same MFA routes the browser uses —
`/api/v1/auth/mfa/totp/verify`, `/api/v1/auth/mfa/recovery/verify`, and
`/api/v1/auth/mfa/passkeys/begin` plus `/complete` — repeating the whole pair
on every call: `challenge_id` identifies the challenge row and
`challenge_token` authenticates the caller against it, standing in for the
browser's challenge cookie.

The client surface lives in `RentivoCore`, so it is shared with macOS:

- `ios/Rentivo/Domain/MobileAuthModels.swift` — `MFAMethod`, `MFAChallenge`,
  `MobileLoginOutcome`, `PasskeyRequestOptions`, `PasskeyAssertionPayload`.
  Unknown `methods` strings are dropped at decode time rather than surfaced or
  raised, so a factor a future server offers cannot crash the login screen; a
  challenge whose methods are all unknown decodes to an empty array.
- `ios/Rentivo/Data/Repositories.swift` — the `AuthRepository` entry points
  (`mobileLogin`, `mobileSignup`, `verifyTotp`, `verifyRecoveryCode`,
  `beginPasskeyAssertion`, `completePasskeyAssertion`).
- `ios/Rentivo/Data/API/LiveAPIClient.swift` — the wire DTOs and the bearer
  token adoption shared with the handoff path.

None of these calls may be retried automatically. A retry burns one of the
four attempts per minute *and* doubles the delay the user waits, because every
failure is deliberately slow — see below.

### Abuse controls on the native path

A native client cannot render the Turnstile widget, so `/auth/mobile/*` drops
it and buys back the cost per attempt another way:

- **Two independent budgets, both charged on every attempt.** Action
  `mobile_auth_ip` is keyed on the client IP, `mobile_auth_email` on the
  trimmed and lowercased e-mail; each allows 4 attempts per 60 seconds.
  Failing either budget returns `429 login_rate_limited`. Charging both means
  an IP that exhausted its quota gets no free pass at a fresh e-mail, and vice
  versa.
- **A fixed 4-second tarpit in front of every failure** — bad credentials,
  rate limit, and `email_already_registered` alike. Success is never delayed.
  That is what makes stuffing expensive: four attempts cost sixteen seconds,
  not four milliseconds.
- **Success clears only the e-mail budget.** The IP budget stays spent, so a
  single host cannot launder an unlimited attempt stream through one account
  it does know the password for.

The tradeoff is real and worth stating plainly. Against an attacker with a
wide pool of IP addresses this is weaker than Turnstile: nothing here proves a
human or a real browser is present, only that attempts are slow and capped.
Per identity it is stronger — the web login has no tarpit and a 5-per-minute
budget keyed on the *pair* (e-mail, IP), so a single e-mail tolerates far more
probing there. `/auth/login` and `/auth/signup` keep Turnstile unchanged; only
the `/auth/mobile/*` pair trades it away.

### Passkeys

Passkeys work in the app because it presents the *website's* credentials: the
relying party is `webauthn_rp_id` (`rentivo.com.br` in production), not a
separate app-scoped RP. Apple only permits that when the domain and the app
vouch for each other:

- **Server side.** `GET /.well-known/apple-app-site-association`
  (`backend/rentivo/api/routes/public.py`) returns
  `{"webcredentials": {"apps": ["<team id>.br.com.rentivo.ios"]}}`. It is
  served at the document root because that is the only place iOS looks, and
  `infra/proxy/nginx.conf` proxies that exact path to the API so the SPA
  fallback never answers it — Apple fetches the path directly and follows no
  redirect. While `RENTIVO_APPLE_TEAM_ID` is empty the route returns **404**
  on purpose: without a team ID there is nothing truthful to publish.
- **App side.** The app declares the associated-domains entitlement
  `webcredentials:rentivo.com.br`.
- **Manual prerequisite, not automatable from this repository.** The
  Associated Domains capability has to be enabled for the App ID
  `br.com.rentivo.ios` in the Apple Developer portal **before the next release
  signing**. The entitlement in the project is only half of it; a provisioning
  profile issued without the capability will not carry it, and the archive
  step in [`runbooks/ios-release.md`](runbooks/ios-release.md) fails or ships
  a build where passkey sign-in silently never offers a credential.

### Browser handoff

The handoff remains the only way to reach Google sign-in and any Turnstile-
gated flow, and it is still what Android and macOS use for every sign-in.

1. The app generates a random `state` and opens
   `<base>/login?mobile_state=<state>` — iOS in an
   `ASWebAuthenticationSession`, Android in a Chrome Custom Tab.
2. The web login page (`frontend/src/features/auth/LoginPage.tsx`) authenticates
   the user normally, then calls `POST /api/v1/auth/mobile/authorize`, which
   issues a single-use authorization challenge. Pages the user can reach from
   there — signup and MFA verification — bounce back to
   `/login?mobile_state=<state>` after authenticating, so account creation and
   MFA also end in the authorize call instead of stranding the user on the web
   dashboard inside the in-app browser.
3. The page redirects to
   `rentivo://auth/callback?code=<authorization_code>&state=<state>`.
4. The app validates the scheme, host, path, and returned `state`, then posts
   the code to `POST /api/v1/auth/mobile/exchange`. The backend consumes the
   one-time challenge and completes the login with `source="mobile"`, returning
   the bearer token in the response body (`credential_transport: "body"`) rather
   than a cookie.
5. The token is persisted and used exactly like a natively obtained one.

The flow logic itself is pure and unit-tested on both platforms
(`MobileWebAuthenticationFlow` in `ios/Rentivo/Data/API/MobileWebAuthenticator.swift`
and `android/app/src/main/java/app/rentivo/data/api/MobileWebAuthenticationFlow.kt`),
including rejection of mismatched state, empty codes, and percent-encoded path
tricks.

### Session lifetime

Whichever path minted it, the token is stored the same way — Keychain on iOS,
`EncryptedSharedPreferences` on Android — and sent as
`Authorization: Bearer …` on every subsequent request.

On launch the app calls `GET /api/v1/auth/session` with the stored token to
restore the session; a 401 there clears it. During normal use, a 401 raises a
session-expired signal — a `liveAPIClientSessionExpired` `NotificationCenter`
post on iOS, a `sessionExpired` `Flow` on Android — which the app model observes
to drop back to the anonymous state.

Sign-out still round-trips through the browser, even for a session created
natively: the app revokes the token, drops local state unconditionally, then
opens `<base>/mobile-logout?state=<state>` and waits for
`rentivo://auth/logout?state=<state>`, so the shared browser cookie jar is
cleared alongside the local token. That round-trip is best-effort and never
blocks the sign-out that already happened; a cancelled sheet is a silent
outcome. Account deletion does the same, so the deleted account's web cookies
cannot survive into the next login sheet. The browser session is deliberately
non-ephemeral on iOS (`prefersEphemeralWebBrowserSession = false`) so login and
logout see the same cookies as the website.

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

**Release.** Any change under `ios/` landing on `main` triggers
`.github/workflows/ios-release.yml`, which archives, signs, uploads to App
Store Connect, and distributes to TestFlight — every merged iOS PR reaches
testers. The build number is `github.run_number`, not a value in the project
file, so `MARKETING_VERSION` in `ios/Rentivo.xcodeproj/project.pbxproj` names
the train while the run number distinguishes builds within it. The workflow
creates no tag and no GitHub Release; tagging a shipped version
`ios/v<MARKETING_VERSION>` is a manual operator step. Full procedure and
triage: [`runbooks/ios-release.md`](runbooks/ios-release.md).

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

- **Credentials in the app, on iOS only.** iOS accepts a password and MFA code
  and posts them to `/api/v1/auth/mobile/*`; nothing is stored but the
  resulting bearer token — the password is never written to the Keychain, and
  the passkey private key never leaves the device. Android still hands
  every sign-in to the browser and holds only a bearer token exchanged from a
  one-time code. Federated (Google) sign-in stays in the browser on both.
- **Turnstile traded for rate limits on the native path.** `/auth/mobile/*`
  has no bot check; it relies on the per-IP and per-e-mail budgets and the
  4-second failure tarpit described above. The web routes are unchanged.
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
