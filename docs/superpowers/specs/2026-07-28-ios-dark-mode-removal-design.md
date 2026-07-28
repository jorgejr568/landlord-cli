# iOS Dark Mode Removal

## Goal

The iOS app renders in light appearance only, regardless of the device's system
appearance setting. Dark mode support is removed from the codebase rather than
merely overridden, so no dead dark-variant values or compensating workarounds
remain.

## Background

The app currently follows the system appearance. Support is implemented entirely
in the design system:

- `ios/Rentivo/DesignSystem/RentivoTheme.swift` defines
  `Color(light:dark:)`, which wraps a dynamic `UIColor` provider that reads
  `traitCollection.userInterfaceStyle`. All 10 `RentivoColors` tokens carry a
  light and a dark sRGB triple.
- `ios/Rentivo/DesignSystem/RentivoComponents.swift` defines
  `RentivoButtonStyle.fill`, which resolves the button's accent against a forced
  light trait collection. This workaround exists only because the tokens
  brighten in dark mode, and that brightness fails contrast against the button's
  white label.

There is no `UIUserInterfaceStyle` key in `ios/Config/Rentivo-Info.plist` and no
`preferredColorScheme` modifier anywhere in the app.

`UIKit` is imported in exactly two files — the two named above — and in both it
exists solely for this machinery. Nothing else in `DesignSystem/` or `App/`
uses UIKit.

## Non-goals

The `secondaryDark` field and the color fields in
`ios/Rentivo/Features/Account/ThemeViews.swift` are the API's billing-document
theming: the colors rendered onto a generated invoice. They are unrelated to
iOS appearance and are not touched.

No user-facing appearance setting is added. Light-only is unconditional.

## Design

Three files change. The 146 `RentivoColors.` call sites across 19 files are
untouched, because every token keeps its current name.

### 1. Lock the appearance

Add to `ios/Config/Rentivo-Info.plist`:

```xml
<key>UIUserInterfaceStyle</key>
<string>Light</string>
```

This is the load-bearing change. It forces light appearance on every window the
app owns, including the UIKit-drawn chrome that the color tokens never
controlled: `Form` and `List` backgrounds, navigation bars, alerts, action
sheets, the keyboard, and the web authentication session used by
`MobileWebAuthenticator`.

The plist is checked in and used directly — the app target sets
`GENERATE_INFOPLIST_FILE = NO` with `INFOPLIST_FILE = Config/Rentivo-Info.plist`
— so this is a plain file edit with no Xcode build-setting change.

### 2. Collapse the color tokens

In `RentivoTheme.swift`:

- Delete the `extension Color { init(light:dark:) }` block.
- Delete `import UIKit`.
- Rewrite each of the 10 `RentivoColors` tokens as a
  `Color(red:green:blue:)` literal carrying its existing **light** triple
  verbatim:

  | Token | Value |
  |---|---|
  | `paper` | `(0.97, 0.95, 0.90)` |
  | `surface` | `(1.00, 0.99, 0.96)` |
  | `ink` | `(0.12, 0.12, 0.18)` |
  | `secondaryInk` | `(0.34, 0.34, 0.40)` |
  | `emerald` | `(0.026, 0.456, 0.318)` |
  | `emeraldLight` | `(0.87, 0.96, 0.93)` |
  | `amber` | `(0.539, 0.36, 0.093)` |
  | `coral` | `(0.681, 0.254, 0.205)` |
  | `blue` | `(0.16, 0.395, 0.714)` |
  | `lilac` | `(0.446, 0.346, 0.655)` |

The dynamic `UIColor` provider and `Color(red:green:blue:)` are both sRGB, so
the rendered light appearance is unchanged.

Update the `RentivoColors` doc comment: drop the light/dark adaptive framing,
keep the WCAG AA contrast claim. Those ratios were measured against the light
palette and still hold.

### 3. Remove the button workaround

In `RentivoComponents.swift`:

- Delete the `fill` computed property from `RentivoButtonStyle`.
- Delete `import UIKit`.
- Use `color` directly in `makeBody`, including the pressed state
  (`configuration.isPressed ? color.opacity(0.75) : color`).

The white-on-accent contrast guarantee (>=4.5:1) is preserved. It becomes
structural — the token *is* the light value — instead of being restored at
runtime.

Rewrite the doc comment to state the guarantee rather than explain a workaround
that no longer exists.

## Alternatives considered

**Lock the appearance only (plist key, no code change).** Correct rendering for
a one-line diff, but every token keeps a dark triple that can never resolve, and
`RentivoButtonStyle` keeps a workaround whose stated justification no longer
applies. Rejected: it leaves misleading code and comments for the next reader,
and the goal is removal, not override.

**Collapse the tokens only (no plist key).** Rejected as broken. Without the
plist key, system-drawn chrome still goes dark on a dark device while the custom
tokens stay light, producing dark `Form` backgrounds under near-black `ink`
text. `ThemeEditorView` is a pure `Form` and would be unreadable.

## Verification

No automated coverage exists for this change. `ios/Package.swift` excludes
`DesignSystem` from the `RentivoCore` target (`exclude: ["App", "DesignSystem",
"Features", "Resources"]`), so `make ios-test` does not exercise the theme and a
green suite proves nothing about the change. Verification is therefore manual
and must be performed, not assumed:

1. Build the app.
2. Run in the simulator with the device set to **Dark Appearance**
   (Settings > Developer > Dark Appearance, or Features > Toggle Appearance).
3. Confirm the app renders light throughout. Check specifically:
   - `ThemeEditorView` (Account > Aparência) — pure `Form`, the first screen
     that would break if the plist key were missing or ineffective.
   - A screen with solid `RentivoButtonStyle` buttons — white labels legible
     against the accent fill.
   - A navigation bar and a presented alert — UIKit chrome the tokens never
     controlled.
4. `grep -rin "dark\|UIUserInterfaceStyle" ios/Rentivo/DesignSystem` returns
   nothing, confirming removal is total.
5. `make ios-test` still passes, confirming no regression elsewhere. Requires a
   full Xcode toolchain.
