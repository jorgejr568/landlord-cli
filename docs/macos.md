# macOS App

`macos/` is a native SwiftUI client for the Mac — the third native app in the
repository, after `ios/` and `android/`. Like them it is a thin client over the
same FastAPI contract the browser uses: no local database, no offline mode, no
macOS-only endpoints.

It differs from the other two in one structural way. iOS and Android are 1:1
ports of each other, each with its own Domain and Data layer. macOS **ports only
the app layer** — presentation — and links the existing `RentivoCore` Swift
package from `ios/` for everything below it. There is no second copy of the
domain model, the API client, the DTOs, or the authentication flow.

For the shared authentication design and the iOS/Android comparison, see
[`mobile.md`](mobile.md); for day-to-day commands, see
[`development.md`](development.md).

## Project layout

| Item | Value |
|---|---|
| Xcode project | `macos/Rentivo.xcodeproj` |
| Scheme | `Rentivo` (shared) |
| Bundle identifier | `br.com.rentivo.macos` |
| Deployment target | macOS 14.0 |
| Swift version | 6.0 |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | `1.0` / `1` |
| Test target | `RentivoMacTests` (`br.com.rentivo.macos.tests`) |

Sources live under `macos/Rentivo` in three groups that mirror the iOS app's:

- `App/` — `RentivoMacApp` (the `App` scene), `RootView`, `MainSplitView`,
  and `AppModel`.
- `DesignSystem/` — `RentivoTheme.swift`, `RentivoComponents.swift`,
  `RentivoCurrencyField.swift`, the same three files iOS has.
- `Features/` — `Account`, `Auth`, `Billings`, `Bills`, `Demo`, `Home`,
  `Organizations`, the same seven directories iOS has.

`Config/Rentivo-Info.plist` and `Config/Rentivo.entitlements` are checked in
rather than generated (`GENERATE_INFOPLIST_FILE = NO`), so the URL scheme, the
sandbox entitlements, and the hardened-runtime setting are reviewable in the
diff. Both the app and test target use file-system-synchronized groups, so
adding a Swift file under `macos/Rentivo` needs no project-file edit.

## Reuse instead of a port

The project carries a single package reference — an `XCLocalSwiftPackageReference`
with `relativePath = ../ios` — and the app target depends on the `RentivoCore`
product. `ios/Package.swift` already declares `.macOS(.v14)` alongside
`.iOS(.v17)` and has zero package dependencies, so it builds for the Mac
unchanged.

Three consequences follow:

- **No macOS OpenAPI copy.** `ios/Rentivo/openapi.json` and
  `android/app/openapi.json` are the two committed contract copies, kept
  byte-identical to `frontend/openapi.json`. macOS consumes the package, not a
  contract copy of its own, so there is no `make macos-openapi-sync` or
  `make macos-openapi-check` — an API schema change requires no macOS-specific
  sync step. The DTO updates it implies land once, in `RentivoCore`, and both
  Apple apps pick them up.
- **Domain and Data changes are shared.** A change to
  `ios/Rentivo/Domain/` or `ios/Rentivo/Data/` is a change to the macOS app.
  That is why the macOS CI job is gated on those paths (see
  [CI](#ci) below).
- **The app layer is the port.** `macos/Rentivo/App`,
  `DesignSystem`, and `Features` are macOS-authored code that reads the same
  `AppModel` API surface and the same `RentivoCore` types as the iOS app layer
  does. Divergence between the two is intentional and local to presentation.

## Shell and navigation

Where iOS shows a bottom `TabView`, macOS shows a `NavigationSplitView` with a
source-list sidebar and a detail column — the platform-native way to expose four
peer sections in a resizable window. The four sections are the same:
Início, Cobranças, Organizações, Conta.

`AppTab` is `CaseIterable` on macOS (it is not on iOS) so the sidebar and the
menu bar can both be driven from one ordered list. `RentivoMacApp` builds two
menus from it:

- **Ir para** — one item per section, bound to <kbd>⌘1</kbd> through
  <kbd>⌘4</kbd> in sidebar order, disabled while signed out.
- **Conta** — "Sair da conta" on <kbd>⇧⌘Q</kbd>.

The File menu's `New` placeholder is removed rather than left dead: nothing in
the app is "new" from the menu bar, every create action lives inside a section.

`MainSplitView` owns one `NavigationPath` per section outside the stacks
themselves. The detail column renders a single `NavigationStack` at a time, so a
section's stack is torn down when the user switches away; hoisting the paths is
what makes a section return to the screen the user left it on.

The window opens at 1200×760 and is pinned to `.preferredColorScheme(.light)`.
The design system is light-appearance-only on every platform, so the window opts
out of the system appearance rather than rendering fixed light tokens against
dark chrome.

## macOS adaptations

Feature behavior is the iOS behavior unless the platform makes it wrong. The
deliberate differences:

| Concern | iOS | macOS |
|---|---|---|
| Section switching | Bottom `TabView` | Sidebar + <kbd>⌘1</kbd>–<kbd>⌘4</kbd> |
| Refresh | Pull-to-refresh | Toolbar "Atualizar" button |
| Receipt sources | Arquivos, Câmera, Fotos | File importer + Finder drag-and-drop |
| Downloaded file | `ShareLink` sheet only | "Salvar como…", "Abrir", then `ShareLink` |
| Wide layouts | N/A (fixed width, portrait) | Side-by-side columns above a width threshold |
| Appearance | Light only | Light only |

**Receipts.** `ReceiptIntake` (`macos/Rentivo/Features/Bills/ReceiptIntake.swift`)
collapses the iOS trio of sources into two. There is no camera picker worth
presenting on a Mac and `UIImagePickerController` has no AppKit counterpart; the
photo library is reachable from the standard open panel's sidebar. The second
path is a `dropDestination(for: URL.self)` on the receipts section, which takes
a file dragged out of Finder. Both paths end in the same `FileUpload`, validated
and renamed by the same `RentivoCore` rules, so the bytes that reach the server
are identical on both platforms. Files from the open panel or a drag are read
through a security-scoped resource, claimed for the read and released
immediately after, as the sandbox requires. Non-accepted image formats are
re-encoded as JPEG through `NSBitmapImageRep`, which returns upright pixels — the
iOS path has to redraw a `UIImage` to bake EXIF rotation in, this one does not.

**Downloads.** `DownloadShareView`
(`macos/Rentivo/Features/Bills/DownloadedFileSheet.swift`) offers "Salvar como…"
(a `fileExporter` seeded with the server's media type and the filename stem),
"Abrir" (`NSWorkspace`), and a `ShareLink` as the third option. iOS leans
entirely on `ShareLink`, whose sheet includes "Salvar em Arquivos"; on a Mac
those two intents are direct buttons. The temporary file is removed when the
sheet's binding loses its value, never from inside the sheet, because
`ShareLink` needs the file on disk for as long as it is presented.

**Wide windows.** `HomeView` measures its detail column and lays its cards out
in two columns above 980 points, one below. Both layouts render the same
sections in the same order.

## Authentication

The browser handoff, because it *is* the iOS code: `MobileWebAuthenticator`
lives in `ios/Rentivo/Data/API/MobileWebAuthenticator.swift` inside
`RentivoCore` and is used unchanged. The app has no password field; sign-in
opens `ASWebAuthenticationSession` against `<base>/login?mobile_state=<state>`
and completes on a `rentivo://auth/callback` redirect whose scheme, host, path,
and `state` are all validated before the code is exchanged. The full sequence
is documented in [`mobile.md` § Browser handoff](mobile.md#browser-handoff).

iOS has since moved its primary sign-in to native e-mail/password against
`/api/v1/auth/mobile/*`, with MFA and passkeys handled in-app. That client
surface sits in `RentivoCore` and is therefore already linked here, but the
macOS app layer does not use it — the Mac still signs in through the browser
on every path. See
[`mobile.md` § Native sign-in](mobile.md#native-sign-in).

Two macOS-relevant details:

- The browser session is deliberately non-ephemeral
  (`prefersEphemeralWebBrowserSession = false`), so login and logout see the
  same cookies as Safari — the user's existing website session carries over
  instead of forcing a fresh login in an isolated web view.
- `rentivo` is registered as a URL scheme in `macos/Config/Rentivo-Info.plist`,
  matching the iOS registration.

Sign-out revokes the token, drops local state unconditionally, and then makes a
best-effort browser round-trip to clear the shared cookie jar; a cancelled sheet
there is a silent, expected outcome, not an error.

`AppModel.observeSessionExpiry()` watches for `liveAPIClientSessionExpired` and
drops back to the anonymous state, guarded so that a 401 raised by the logout
POST itself does not flash "Sua sessão expirou" over a deliberate sign-out.

### Token at rest

`KeychainCredentialStore` (`ios/Rentivo/Data/API/CredentialStore.swift`) is
shared with iOS and branches on platform. iOS has only the data-protection
keychain, so the flag is implicit. On macOS a plain `SecItem` call lands in the
legacy file-based keychain, so the store requests the data-protection keychain
explicitly with `kSecUseDataProtectionKeychain`.

That request is rejected with `errSecMissingEntitlement` when the process has no
provisioned application identifier — which is exactly the case for the ad-hoc
signed local builds `make macos-build` produces and for the test runner. The
store detects that specific status, falls back to the legacy keychain, and
remembers the choice for the rest of the process, dropping the accessibility
class the legacy keychain does not understand. A properly provisioned build
never takes the fallback.

## Sandbox and signing

`macos/Config/Rentivo.entitlements` requests three things and nothing else:

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client` — talking to the API
- `com.apple.security.files.user-selected.read-write` — receipts in, downloads
  out, both through user-driven pickers and drags

`ENABLE_HARDENED_RUNTIME = YES` is set in the project. Local builds are ad-hoc
signed (`CODE_SIGN_IDENTITY=-`), which makes Xcode disable the hardened runtime
for that build; the setting still applies to a properly signed one.

## Demo mode

The same mock dependency graph the iOS app uses, gated to `DEBUG` builds through
launch arguments in `RentivoMacApp.init()`:

| Argument | Effect |
|---|---|
| `--ui-testing` | Swap the live graph for `MockRentivoStore(fixtures: .canonical)` |
| `--screenshot-authenticated` | Same, plus sign in immediately and clear the welcome notice |
| `--screenshot-tab <section>` | With the above: open on `billings`, `organizations`, `account`, or `home` (the default for anything else) |

The signed-in demo state is visible in the UI: the sidebar footer shows a "Conta
de demonstração" badge whenever `usesLiveAPI` is false. `Features/Demo`
exposes the scenario switches (delay, empty state, viewer role, fail-next,
reset) that `AppModel` forwards to the mock store.

Release builds cannot enter demo mode and always talk to the production base
URL, which is hardcoded in `RentivoCore` exactly as it is for iOS. There is no
setting or scheme that points a build at a local backend.

## Build and test

```bash
open macos/Rentivo.xcodeproj   # run it from Xcode
make macos-build               # xcodebuild … -configuration Debug build CODE_SIGN_IDENTITY=-
make macos-run                 # macos-build, then open the built Rentivo.app
make macos-test                # xcodebuild … -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

`make macos-run` reads the product location back from the build settings
(Xcode's default DerivedData path is hashed) and launches a fresh instance, so
the binary you just built runs even when an older copy is already open.

All targets need a full Xcode install. `make macos-test` runs the
`RentivoMacTests` target — one file per feature plus `AppModel` and `AppTab` —
against a `platform=macOS` destination, so no simulator is involved. It
exercises the macOS app layer; the Domain and Data layers below it
are covered by `make ios-test` (`swift test --package-path ios`). Run both when
you change `RentivoCore`. There is no coverage gate on either suite.

`CODE_SIGNING_ALLOWED=NO` is sufficient for the test run: the test bundle's
`TEST_HOST` is the app itself running locally, so nothing needs an identity.

## CI

`.github/workflows/test-pr.yaml` has a `macos` job on `macos-15` that runs
`.github/actions/macos-app-tests`. The action selects the newest **non-beta**
Xcode (the runner images ship a beta whose name sorts after the release), caches
`~/Library/Developer/Xcode/DerivedData` keyed on `ios/Package.swift` and
`macos/Rentivo.xcodeproj/project.pbxproj` so the package resolve stays off the
critical path, then runs the same `xcodebuild … test` invocation as
`make macos-test`. Unlike the iOS job it resolves no simulator destination.

The job is path-gated by `scripts/macos-ci.sh paths-changed <base-sha>`, which
matches:

- `macos/`
- `.github/actions/macos-app-tests/`
- `ios/Package.swift`, `ios/Rentivo/Domain/`, `ios/Rentivo/Data/`,
  `ios/RentivoTests/` — the `RentivoCore` package inputs
- `scripts/macos-*.sh`, `scripts/macos-*.swift`,
  `scripts/tests/macos-ci-test.sh`
- `.github/workflows/test-pr.yaml`

The rest of `ios/` — the iOS app layer — is deliberately excluded, so an
iOS-only UI change does not spend a macOS runner. An unusable base (first push,
tag push, force push) reports `true` so the checks run rather than silently
vanish.

The helper itself is tested by `scripts/tests/macos-ci-test.sh`, which
`make scripts-test` runs alongside the iOS and Android equivalents.

## Packaging

```bash
make macos-dmg          # ./scripts/macos-dmg.sh
```

`scripts/macos-dmg.sh` produces `dist/Rentivo-<MARKETING_VERSION>.dmg`: a
compressed read-only image holding `Rentivo.app`, an `Applications` symlink, and
a generated Finder background telling the user where to drop the app. The
version is parsed out of `macos/Rentivo.xcodeproj/project.pbxproj` by the
`marketing_version` helper already in `scripts/ios-ci.sh`, which fails loudly
when the build configurations disagree.

With no arguments the script builds Release into a temporary DerivedData
directory first. To package a bundle built elsewhere, pass it positionally or as
`APP_PATH`:

```bash
APP_PATH=/path/to/Rentivo.app ./scripts/macos-dmg.sh
```

The Finder window layout — icon positions, background, icon and window size — is
applied with Finder scripting, which needs a logged-in GUI session. On a
headless runner that step is skipped with a warning and the image is still
produced; it just opens with the default Finder layout. Everything else is
verified before the script exits: the mounted image must contain a runnable
`Rentivo.app`, an `Applications` symlink pointing at `/Applications`, and the
background image. Every intermediate lives in a temporary directory, so
re-running converges on the same artifact.

`scripts/macos-dmg-background.swift` renders the background; its canvas and icon
centres must stay in step with the coordinates at the top of the shell script.

## App icon

```bash
make macos-app-icon     # ./scripts/macos-app-icon.sh
```

The iOS catalog holds the single source of truth for the artwork — one
1024×1024 PNG at
`ios/Rentivo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. macOS
needs ten sized PNGs laid out on the Apple icon grid, so the script derives them
with `scripts/macos-app-icon.swift` into
`macos/Rentivo/Resources/Assets.xcassets/AppIcon.appiconset` rather than keeping
a second copy of the artwork. It is idempotent: re-running it leaves the working
tree unchanged. Regenerate and commit the result whenever the iOS icon changes.

## Release

There is none yet. Unlike iOS — where bumping `MARKETING_VERSION` on `main`
triggers `.github/workflows/ios-release.yml` and an App Store Connect upload —
no workflow archives, signs, notarizes, or publishes the macOS app. `make
macos-dmg` on a developer machine is the distribution artifact today, and the
image it produces is ad-hoc signed unless you supply your own identity, so
Gatekeeper will warn on another Mac.

Shipping it properly needs a Developer ID identity, notarization, and a stapled
ticket, none of which exist in the repository. A `macos-release` runbook,
matching the iOS one, will be needed when that automation lands. Android is in
the same position (see [`mobile.md` § Android](mobile.md#android)).
