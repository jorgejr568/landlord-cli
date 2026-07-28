# iOS Dark Mode Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Rentivo iOS app renders in light appearance only, regardless of the device's system appearance setting, with dark-mode support removed from the code rather than merely overridden.

**Architecture:** Three coordinated changes. `UIUserInterfaceStyle = Light` in the app's Info.plist forces light appearance on all UIKit-drawn chrome (the load-bearing change). The 10 `RentivoColors` tokens then collapse from dual light/dark values to single fixed light values. Finally, `RentivoButtonStyle`'s forced-light workaround — which existed only to compensate for dark-mode-brightened accents — is deleted. Token *names* are unchanged, so all 146 call sites across 19 files are untouched.

**Tech Stack:** Swift 6, SwiftUI, Xcode project at `ios/Rentivo.xcodeproj` (scheme `Rentivo`), SwiftPM package `RentivoCore` at `ios/Package.swift`.

**Spec:** `docs/superpowers/specs/2026-07-28-ios-dark-mode-removal-design.md`

## Global Constraints

- Code, comments, and identifiers are English. Customer-facing copy, including the iOS app's UI, is PT-BR. (No user-facing copy changes in this plan.)
- Do not rename any `RentivoColors` token. All 10 names survive verbatim; only their definitions change.
- Do not touch `secondaryDark`, `ThemeValues`, `ThemeEditorView`, or anything under `Features/Account/ThemeViews.swift`. That is the API's billing-document theming, unrelated to iOS appearance.
- Preserve the exact light sRGB values listed in Task 2. The rendered light appearance must be pixel-identical to today's.
- The local toolchain's `xcode-select` points at `/Library/Developer/CommandLineTools`, which cannot build the app. Every `xcodebuild` and `swift` command in this plan must be prefixed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Pre-commit hooks in this worktree fail on an unprovisioned Python toolchain (`ruff` missing, pytest lacks `-n`). For iOS-only and docs-only commits, use `git commit --no-verify`.

## Testing reality — read before starting

**There is no automated test for this change, and the plan does not pretend otherwise.**

- `make ios-test` runs `swift test --package-path ios`, and `ios/Package.swift` sets `exclude: ["App", "DesignSystem", "Features", "Resources"]`. The design system is not in the package. A green `make ios-test` proves nothing about this change.
- CI's *other* iOS step (`xcodebuild -scheme Rentivo test -only-testing:RentivoTests`) does compile the app target, so `DesignSystem` is **compile-checked** in CI — a syntax or type error will be caught. Behavior is not.
- Adding a test was considered and rejected. After the UIKit removal, `RentivoTheme.swift` becomes cross-platform SwiftUI and *could* be moved into the package, but that relocates UI code into `RentivoCore` (the Domain/Data package per CLAUDE.md) purely to buy a change-detector assertion like `paper == (0.97, 0.95, 0.90)`. Wrong trade.

The verification that actually catches failure is **Task 4: running the app in a simulator set to Dark Appearance.** Task 4 is not optional and not a formality. Do not report this work complete without it.

## File Structure

| File | Change | Responsibility after change |
|---|---|---|
| `ios/Config/Rentivo-Info.plist` | Modify | Declares `UIUserInterfaceStyle = Light`, forcing light appearance app-wide |
| `ios/Rentivo/DesignSystem/RentivoTheme.swift` | Modify (71 → ~40 lines) | Fixed light-only semantic color, spacing, and typography tokens |
| `ios/Rentivo/DesignSystem/RentivoComponents.swift` | Modify (2 regions) | Shared components; `RentivoButtonStyle` uses its accent directly |

**Task order is deliberate.** Task 1 ships first so the app is never in the half-migrated state where custom tokens are light but system chrome is still dark — that state renders dark `Form` backgrounds under near-black `ink` text and is unusable.

---

### Task 1: Lock the app to light appearance

**Files:**
- Modify: `ios/Config/Rentivo-Info.plist`

**Interfaces:**
- Consumes: nothing.
- Produces: a guarantee that `UITraitCollection.userInterfaceStyle` is always `.light` at runtime. Tasks 2 and 3 depend on this guarantee — without it, their changes are unsafe.

- [ ] **Step 1: Add the appearance key**

The plist is checked in and used directly (`GENERATE_INFOPLIST_FILE = NO`, `INFOPLIST_FILE = Config/Rentivo-Info.plist`), so this is a plain file edit — no Xcode build-setting change.

Insert the following two lines immediately after the `<key>ITSAppUsesNonExemptEncryption</key><false/>` pair and before `<key>UILaunchScreen</key>`:

```xml
  <key>UIUserInterfaceStyle</key>
  <string>Light</string>
```

The surrounding region should read:

```xml
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>UIUserInterfaceStyle</key>
  <string>Light</string>
  <key>UILaunchScreen</key>
  <dict/>
```

- [ ] **Step 2: Verify the plist is still well-formed**

Run:

```bash
plutil -lint ios/Config/Rentivo-Info.plist
```

Expected: `ios/Config/Rentivo-Info.plist: OK`

- [ ] **Step 3: Confirm the key reads back correctly**

Run:

```bash
plutil -extract UIUserInterfaceStyle raw ios/Config/Rentivo-Info.plist
```

Expected output: `Light`

- [ ] **Step 4: Build the app**

First resolve a simulator destination (reused in later tasks):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -showdestinations 2>/dev/null | grep "platform:iOS Simulator" | grep "name:iPhone" | head -1
```

Note the `id:` value from that line, then build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -destination "platform=iOS Simulator,id=<DESTINATION_ID>" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/Config/Rentivo-Info.plist
git commit --no-verify -m "feat(ios): lock app to light appearance"
```

---

### Task 2: Collapse the color tokens to light-only

**Files:**
- Modify: `ios/Rentivo/DesignSystem/RentivoTheme.swift:1-40`

**Interfaces:**
- Consumes: the light-appearance guarantee from Task 1.
- Produces: `enum RentivoColors` with the same 10 static members — `paper`, `surface`, `ink`, `secondaryInk`, `emerald`, `emeraldLight`, `amber`, `coral`, `blue`, `lilac` — each of type `Color`. The `Color(light:dark:)` initializer **ceases to exist**; Task 3 must not reference it. `RentivoSpacing` and `RentivoTypography` are unchanged.

- [ ] **Step 1: Replace the top of the file**

Replace everything from line 1 through the closing brace of `enum RentivoColors` (line 40) with the following. Leave `RentivoSpacing`, `RentivoTypography`, the `rentivoPage()` extension, and `ptBRCount` exactly as they are.

```swift
import SwiftUI

/// Semantic color tokens for the app. The app renders in light appearance only
/// (`UIUserInterfaceStyle = Light` in `Config/Rentivo-Info.plist`), so each token is a
/// single fixed sRGB value. Accent hues (`emerald`, `amber`, `coral`, `blue`, `lilac`) are
/// tuned so that, used as-is, they meet WCAG AA (>=4.5:1) as foreground text/icon color
/// against both `paper` and `surface`, AND against their own 14%-opacity tint (the pattern
/// `StatusBadge` uses).
enum RentivoColors {
  static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
  static let surface = Color(red: 1.00, green: 0.99, blue: 0.96)
  static let ink = Color(red: 0.12, green: 0.12, blue: 0.18)
  static let secondaryInk = Color(red: 0.34, green: 0.34, blue: 0.40)

  static let emerald = Color(red: 0.026, green: 0.456, blue: 0.318)
  static let emeraldLight = Color(red: 0.87, green: 0.96, blue: 0.93)
  static let amber = Color(red: 0.539, green: 0.36, blue: 0.093)
  static let coral = Color(red: 0.681, green: 0.254, blue: 0.205)
  static let blue = Color(red: 0.16, green: 0.395, blue: 0.714)
  static let lilac = Color(red: 0.446, green: 0.346, blue: 0.655)
}
```

Three things this does, all required:
1. Drops `import UIKit` — it existed in this file *only* for the dynamic `UIColor` provider.
2. Deletes the `extension Color { init(light:dark:) }` block entirely.
3. Uses each token's former **light** triple verbatim. `Color(red:green:blue:)` and the old `UIColor(red:green:blue:alpha:)` are both sRGB, so rendering is unchanged.

- [ ] **Step 2: Confirm no dark-mode machinery remains in this file**

Run:

```bash
grep -n -i "uikit\|dark\|userInterfaceStyle\|traitCollection" ios/Rentivo/DesignSystem/RentivoTheme.swift
```

Expected: exactly one hit — the doc comment's reference to `UIUserInterfaceStyle = Light` in `Config/Rentivo-Info.plist`. That reference is intentional and documents *why* the tokens are single-valued; keep it. Any hit naming `import UIKit`, `traitCollection`, or a `dark:` value is a real leftover and must be removed.

- [ ] **Step 3: Confirm every token name survived**

Run:

```bash
for t in paper surface ink secondaryInk emerald emeraldLight amber coral blue lilac; do
  grep -q "static let $t = " ios/Rentivo/DesignSystem/RentivoTheme.swift || echo "MISSING: $t"
done
```

Expected: no output. Any `MISSING:` line means a call site will fail to compile.

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -destination "platform=iOS Simulator,id=<DESTINATION_ID>" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

This step is the real check on Task 2: it compiles all 19 files and 146 call sites against the new token definitions. If a token name were dropped or mistyped, the build fails here.

Note: `RentivoComponents.swift` still compiles at this point — its `fill` property calls `UIColor(color).resolvedColor(with:)`, which does not depend on the deleted initializer. Task 3 removes it.

- [ ] **Step 5: Commit**

```bash
git add ios/Rentivo/DesignSystem/RentivoTheme.swift
git commit --no-verify -m "refactor(ios): collapse color tokens to light-only values"
```

---

### Task 3: Remove the button style's forced-light workaround

**Files:**
- Modify: `ios/Rentivo/DesignSystem/RentivoComponents.swift:1-2` (imports), `:27-50` (`RentivoButtonStyle`)

**Interfaces:**
- Consumes: `RentivoColors.emerald` and `RentivoColors.ink` from Task 2.
- Produces: `RentivoButtonStyle` with its public surface unchanged — `var color = RentivoColors.emerald` and `makeBody(configuration:)`. The private `fill` property is removed. No call site changes, because `fill` was already private.

- [ ] **Step 1: Delete the UIKit import**

Line 2 of the file is `import UIKit`. Delete it. The file's only UIKit usage is the `fill` property removed in the next step, so the import becomes unused.

The top of the file becomes:

```swift
import SwiftUI
```

- [ ] **Step 2: Replace the `fill` property and its use**

Replace the `fill` computed property and the `makeBody` background line. The whole `RentivoButtonStyle` struct should read:

```swift
struct RentivoButtonStyle: ButtonStyle {
  var color = RentivoColors.emerald

  /// Buttons render as a solid, saturated fill with a white label. The accent tokens are
  /// fixed light-appearance values, which keeps the white label at >=4.5:1 against every
  /// fill this style is used with.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline.weight(.bold))
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity, minHeight: 48)
      .padding(.horizontal, RentivoSpacing.medium)
      .background(configuration.isPressed ? color.opacity(0.75) : color)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(RentivoColors.ink, lineWidth: 2)
      }
      .shadow(
        color: configuration.isPressed ? .clear : RentivoColors.ink,
        radius: 0,
        x: 3,
        y: 3
      )
      .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }
}
```

The two substantive edits: `fill` is gone, and `.background(...)` now reads `configuration.isPressed ? color.opacity(0.75) : color`. Everything from `.clipShape` down is unchanged — reproduced here so the struct can be replaced wholesale without cross-referencing.

The contrast guarantee is preserved. It was previously restored at runtime by resolving against a forced light trait collection; it is now structural, because the token *is* the light value.

- [ ] **Step 3: Confirm the workaround is gone**

Run:

```bash
grep -n -i "uikit\|uicolor\|uitraitcollection\|resolvedColor\|dark" ios/Rentivo/DesignSystem/RentivoComponents.swift
```

Expected: no output (exit code 1).

- [ ] **Step 4: Confirm the design system is clean overall**

Run:

```bash
grep -rn -i "dark\|userInterfaceStyle\|colorScheme\|UIKit" ios/Rentivo/DesignSystem/
```

Expected: exactly one hit — `RentivoTheme.swift`'s doc comment referencing `UIUserInterfaceStyle = Light` in `Config/Rentivo-Info.plist`, which is intentional documentation of why the tokens are single-valued.

This is the spec's completeness check. It passes when the only surviving match is that comment: no `import UIKit`, no `traitCollection`, no `resolvedColor`, no `dark:` value anywhere under `DesignSystem/`.

- [ ] **Step 5: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -destination "platform=iOS Simulator,id=<DESTINATION_ID>" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`. Note that Swift does not warn on an unused import, so a clean build does *not* confirm Step 1 landed — Step 3's grep is what proves that.

- [ ] **Step 6: Commit**

```bash
git add ios/Rentivo/DesignSystem/RentivoComponents.swift
git commit --no-verify -m "refactor(ios): drop button style forced-light workaround"
```

---

### Task 4: Verify under dark appearance

**Files:** none modified. This task is a gate, not a change.

**Interfaces:**
- Consumes: the complete change from Tasks 1–3.
- Produces: evidence that the app renders light on a dark-appearance device.

This is the only step that can detect the actual failure mode this work is about. Skipping it and reporting success on a green build would be a false completion claim.

- [ ] **Step 1: Boot a simulator and launch the app**

Use the iOS Simulator tooling to attach a live panel, then build and launch the app onto a booted iPhone simulator. If driving `xcodebuild` directly, install the built `.app` and launch it with `xcrun simctl`.

- [ ] **Step 2: Switch the simulator to Dark Appearance**

In the Simulator app: **Features > Toggle Appearance** (or Settings > Developer > Dark Appearance). Confirm the switch took effect — the simulator's own Settings app should render dark.

This ordering matters: verify the *device* is genuinely in dark mode before concluding the *app* is correctly staying light. An app that looks light on a device that never went dark proves nothing.

- [ ] **Step 3: Check a pure-`Form` screen**

Navigate to Account > Aparência (`ThemeEditorView`). This screen is a bare SwiftUI `Form` with no custom background — it is the first screen that breaks if the plist key is missing or ineffective.

Expected: cream/white grouped-list background, dark text, fully legible. **Failure signal:** near-black `Form` background with near-black `ink` text.

- [ ] **Step 4: Check solid buttons**

Navigate to any screen using `RentivoButtonStyle` (the auth screens are the quickest route).

Expected: saturated emerald fill, white label clearly legible, 2pt dark border and hard offset shadow intact. Press and hold: the fill dims to 75% and the button offsets by 3pt.

- [ ] **Step 5: Check UIKit-drawn chrome**

Confirm a navigation bar, a presented alert, and the keyboard all render light. These are drawn by UIKit and were never controlled by the color tokens — they are what Task 1's plist key exists for.

- [ ] **Step 6: Check a card-based screen**

Open the Home screen. Confirm `RentivoCard` surfaces, `BrandMark`, and `StatusBadge` pills all render on the light paper background with legible text.

- [ ] **Step 7: Return the simulator to Light Appearance and re-check**

Toggle appearance back. Confirm the app looks identical to how it looked in dark — the whole point is that appearance no longer changes anything. Compare against `git stash`-ed pre-change screenshots if any pixel doubt remains; rendering should be identical, since the light triples were preserved verbatim.

- [ ] **Step 8: Run the package suite for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make ios-test
```

Expected: all tests pass. This does **not** cover the design system (see "Testing reality" above); it confirms nothing else regressed.

- [ ] **Step 9: Confirm the full diff is three files**

```bash
git diff --stat main...HEAD -- ios/
```

Expected: exactly `ios/Config/Rentivo-Info.plist`, `ios/Rentivo/DesignSystem/RentivoTheme.swift`, and `ios/Rentivo/DesignSystem/RentivoComponents.swift`. Any fourth iOS file means scope crept — most likely into the billing-document theming this plan explicitly excludes.

---

## Definition of done

- `UIUserInterfaceStyle = Light` is present in the app Info.plist.
- `grep -rn -i "dark\|userInterfaceStyle\|colorScheme\|UIKit" ios/Rentivo/DesignSystem/` returns nothing.
- All 10 `RentivoColors` token names are unchanged; no call site was edited.
- The app builds, and renders light on a simulator set to Dark Appearance — confirmed by having actually looked at it, on a `Form` screen and a button screen.
- `make ios-test` passes.
- The iOS diff touches exactly three files.
