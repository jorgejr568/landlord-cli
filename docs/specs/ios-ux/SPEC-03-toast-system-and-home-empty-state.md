# SPEC-03 — Toast system and Home empty state

## Status and scope

- Product: Rentivo iOS
- UI framework: SwiftUI
- Customer-facing language: PT-BR
- Code and test symbol language: English
- Minimum supported OS in the project: iOS 17
- Scope: transient global feedback, authenticated tab scaffold, bottom content clearance, and the Home dashboard's no-billings presentation
- Out of scope: API/domain changes, a custom replacement for `TabView`, changing the billing-creation flow, and converting modal-local validation/errors into global toasts

## Goal

Make transient feedback noticeable without covering system or navigation controls, guarantee that it leaves the interface predictably, and make every tab-backed screen usable above the floating tab bar. For a brand-new account, make the first useful action the visual priority and avoid presenting zero values as either an error or a populated dashboard.

Success means:

1. A toast never intersects the Dynamic Island, status bar, navigation bar, close/back controls, keyboard, or tab bar.
2. A toast is transient, manually dismissible, scoped to the feature where it was produced, and cannot become a backlog.
3. Content can always be scrolled fully above the floating tab bar.
4. The tab bar has a stable cream background through which content cannot be read.
5. A no-billings Home screen leads with onboarding, not four zero-value cards.
6. An overdue balance uses the error color only when the amount is greater than zero.

## Current implementation and cause

- `RootView` presents `app.notice` with a top-aligned overlay. The overlay is outside the navigation layout and therefore does not reserve the status/navigation safe area. This is why it can cover the Dynamic Island and leading close/back controls.
- `AppModel` stores one optional `AppNotice`, but it has no timeout, cancellation task, navigation ownership, or replacement policy beyond direct assignment. A notice consequently remains until the close button is used or another assignment clears it.
- The four authenticated areas are separate `NavigationStack`s inside a native `TabView`. There is no shared contract for the extra clearance required by the floating tab bar.
- `HomeContent` always renders the four-card summary grid before branching on `hasBillings`. A new account therefore sees four zero cards before the existing `Comece por aqui` card.
- The Home greeting always renders the overdue amount in `RentivoColors.coral`, including `R$ 0,00`.
- `HomeView` uses a `ScrollView` and `AccountView` uses a `List`; neither adds an explicit bottom clearance for the floating tab bar. The defect is therefore not specific to one scroll-container type.

## Product decisions

### Toast position: bottom, above the tab bar

Use a bottom toast, not a corrected top banner.

The authenticated app has persistent top navigation controls and a persistent bottom tab bar. The toast must occupy a safe-area inset immediately above the tab bar. On an unauthenticated screen, it occupies the bottom safe-area inset. If the software keyboard is visible, it sits above the keyboard. This placement removes the conflict with the Dynamic Island and top-leading close/back buttons and keeps transient feedback near the area where actions usually complete.

The toast host must participate in safe-area layout rather than use a screen-edge offset. When visible, its height and gap are reserved so scrollable content is not hidden behind it. Placement requirements are:

- Horizontal margin: `RentivoSpacing.page` (24 pt) on compact widths.
- Maximum width: 560 pt, centered, on regular widths.
- Bottom gap: `RentivoSpacing.medium` (12 pt) above the top edge of the visible tab bar, keyboard, or bottom safe area, whichever is highest.
- No part of the toast, including its shadow, may intersect navigation chrome.
- Do not use a top overlay fallback on devices without a tab bar.

### One notice, newest wins

Retain a single visible-notice model and make replacement explicit. Do not introduce a queue.

If a notice arrives while another is visible, replace the old notice in place and restart the lifetime for the new notice. A queued sequence would surface stale confirmations after the user has moved on, which is the failure this work is intended to remove. There must never be two toast views in the hierarchy at once, including during transitions.

### Navigation ownership

A toast belongs to the feature area that is active when the operation completes. It remains through the immediate modal dismissal that reveals that area, but is dismissed as soon as the user enters a different feature area.

A feature area is a user-recognizable destination, not merely a tab. At minimum distinguish:

- Authentication
- Home
- Billing list
- Billing detail and bill operations
- Organization list/detail
- Invitations
- Account
- Security
- API keys
- Appearance/theme
- Demo scenarios

Each tab root and pushed destination must report its stable area identifier to the notice owner. A tab selection or navigation action should report its destination as the transition begins; destination activation is a fallback for deep links/restoration. Changing tabs, pushing to another area, or popping back to another area dismisses a notice whose owner differs from the newly active area. The exit animation may run during the navigation transition, but the old toast must be absent when the destination transition completes. Presenting a full-screen wizard does not reassign a notice to the wizard: global confirmations from a wizard belong to the underlying destination that will be revealed on dismissal. Modal-local failures remain inline, consistent with the existing comments and behavior in the form/sheet views.

Session-transition notices need an explicit destination area because the session and UI root change in the same operation:

- Successful sign-in: Home
- Failed session restoration: Authentication
- Session expiry: Authentication
- Successful account deletion: Authentication

The existing password-change confirmation belongs to Security, the PIX confirmation belongs to Account, and API-key revocation belongs to API keys. Thus `Senha alterada com sucesso.` remains on the Security destination after the password wizard closes but disappears before `Chaves de integração` is shown.

## Detailed behavior

### Notice state and lifecycle

`AppNotice` continues to contain a unique identity, kind, and message. Extend the presentation state so the notice owner can also track its feature area and dismissal lifecycle. Keep this responsibility in the app/UI state layer; feature views should continue to request a notice rather than schedule their own timers.

Required lifecycle:

1. A new notice replaces any visible notice and cancels the previous notice's pending dismissal.
2. The toast enters and becomes the only visible toast.
3. Standard lifetime is 4.0 seconds, measured from the point the new toast is mounted for presentation.
4. At 4.0 seconds, dismiss it if and only if the visible notice still has the same identity. An old timer must never dismiss its replacement.
5. Explicit close, committed swipe, feature-area change, sign-out cleanup, or app transition away from the active scene cancels the timer and dismisses immediately.
6. If VoiceOver is running, use an 8.0-second lifetime. The toast still has both close and swipe actions.
7. A notice posted with the same text is still a new notice: it receives a new identity and a fresh lifetime.

The dismissal operation should have one entry point used by timeout, close, swipe, navigation, and session cleanup. This avoids animation or task-cancellation differences between dismissal paths. The timer duration/clock must be injectable or otherwise controllable in unit tests; production uses the values above.

### Animation

With Reduce Motion off:

- Entry: move upward by 16 pt while fading from zero to full opacity over 220 ms with an ease-out curve.
- Timeout/close/navigation exit: move downward by 12 pt while fading to zero over 160 ms with an ease-in curve.
- Replacement: update the existing slot with a 150 ms opacity crossfade. Do not animate two cards past one another.
- A cancelled swipe returns to rest with a short, non-bouncy spring, approximately 250 ms.

With Reduce Motion on:

- Entry, exit, and replacement use opacity only, 150 ms or less.
- Do not translate, scale, or spring the toast.
- Timing and dismissal semantics are otherwise unchanged.

### Manual dismissal and hit targets

- Preserve the trailing close control with accessibility label `Fechar aviso`.
- Its tappable frame must be at least 44 × 44 pt even though the glyph remains visually small.
- Keep at least 12 pt between message text and the close target, and keep the target within the card's content padding; it must not touch the screen edge.
- Support a horizontal swipe in either direction. Commit dismissal when the drag reaches 80 pt or the predicted end translation reaches 40% of the toast width. Otherwise return to rest.
- Pause the timeout while the toast is being dragged. If the swipe is cancelled, resume the remaining lifetime with a minimum of 1.0 second so it does not disappear immediately under the user's finger.
- The swipe direction must not compete with vertical scrolling.

### Visual treatment

Preserve the current Rentivo card language: opaque `RentivoColors.surface`, continuous rounded rectangle, ink border, and hard ink shadow. Keep the semantic icon/color mapping already used by `NoticeBanner`:

- Success: `checkmark.circle.fill` and `RentivoColors.emerald`
- Information: `info.circle.fill` and `RentivoColors.blue`
- Warning: `exclamationmark.triangle.fill` and `RentivoColors.amber`

Text uses the existing semibold subheadline treatment and `RentivoColors.ink`. It wraps without truncation. The layout must grow for Dynamic Type and keep the icon and close control aligned to the first line rather than vertically compressing the message.

Rename the view from `NoticeBanner` to a toast-oriented English code name if doing so makes ownership clearer; customer-facing copy is unaffected. Keep or add stable accessibility identifiers for the toast container and close button so UI tests do not locate notices by translated message text alone.

## App-wide bottom-content contract

Create one reusable design-system/scaffold rule for tab-backed scrollable content. Do not fix Home and Account with unrelated hard-coded paddings.

The effective bottom clearance is the system/container safe area contributed by the visible tab bar plus `RentivoSpacing.large` (20 pt). Do not add a second hard-coded tab-bar height: the native bar can change height by device, orientation, Dynamic Type, and OS release. Use container safe-area behavior and a shared inset/margin modifier so the rule works with both `ScrollView` and `List`.

At the bottom scroll position:

- The bottom edge of the last actionable or readable element must be at least 20 pt above the tab bar's visible top edge.
- When a toast is visible, its own safe-area inset is added above the bar, and scrollable content can move fully above the toast as well.
- Short content that does not naturally scroll must still gain enough scroll range to reveal its last element above the bar.
- The rule applies to all four tab roots and every pushed screen on which the tab bar remains visible.
- Full-screen wizards keep their existing bottom action inset and must not receive the tab-bar clearance while the tab bar is absent.

The known regression checks are the complete `Comece por aqui` CTA on Home and the complete `Termos de uso` row on Account. Also audit every existing `ScrollView`/`List` under the tab stacks; the test plan below lists the source files.

## Floating tab-bar treatment

Keep the native `TabView` for platform behavior and accessibility, but force a persistent, opaque cream background:

- Background fill: fully opaque `RentivoColors.surface`.
- Background visibility: always visible; it must not switch to transparent based on a `List` or `ScrollView` resting position.
- Selected item tint remains `RentivoColors.emerald`; unselected labels/icons must retain sufficient contrast against `surface`.
- Preserve the system tab-bar shape and selection behavior. Do not build a custom set of buttons solely to reproduce the floating pill.
- On OS versions whose system material still composites content into the floating shape, add an opaque `surface` backing at the scaffold level behind that shape. The rendered acceptance criterion is that underlying text and dividers are not legible through the bar, regardless of the API used to achieve it.
- Reduce Transparency does not need an alternate visual because the default is already opaque.

Apply the tab-bar background preference consistently to all four tab contents; SwiftUI resolves a bar's preferred style from the active tab.

## Home dashboard states

### Accounts with one or more billings

Keep the current populated-dashboard order and four-card grid. Continue to show overdue, attention, quick actions, upcoming bills, and activity based on available data.

The overdue summary has two semantic presentations:

- `overdue > .zero`: keep `Saldo em atraso`, `clock.badge.exclamationmark`, and `RentivoColors.coral` for both icon/emphasis and amount.
- `overdue <= .zero`: keep `Saldo em atraso`, change the symbol to `checkmark.circle.fill`, use `RentivoColors.emerald` for the symbol, and use `RentivoColors.ink` for `R$ 0,00`. De-emphasize the zero amount to a semibold subheadline rather than the prominent overdue treatment. No coral/red may appear in this row.

The label and formatted amount must be exposed together to VoiceOver as, for example, `Saldo em atraso: R$ 0,00`. The icon change ensures that status is not conveyed by color alone.

### Accounts with no billings: onboarding-first variant

Use `HomeData.hasBillings == false` as the state discriminator; do not infer the state from all summary numbers being zero. A populated account can legitimately have zero financial activity.

Render in this order:

1. Greeting and current portfolio subtitle.
2. The `Comece por aqui` hero card.
3. Recent activity only when activities exist.

In this state:

- Do not render the four-card summary grid.
- Do not render the overdue row, quick actions, attention section, or upcoming-bills section.
- Do not render an empty `Atividade recente` section. If real recent activity exists even without billings, show it below the hero.
- Move the existing no-billings card immediately below the greeting and give it the strongest section priority: full width, current card border/shadow, sparkles icon, comfortable vertical spacing, and the existing full-width primary CTA.
- The CTA continues to select the Cobranças tab. Do not label it as direct creation until the app supports opening the creation flow across tabs.

This approach removes misleading zero analytics entirely while preserving the populated dashboard unchanged. The financial summary appears after the first billing is created and Home reloads through the existing `dataRevision`/load path.

## Customer-facing copy

No new visible customer-facing string is required. Preserve these exact PT-BR strings in the onboarding hero:

- Section title: `Comece por aqui`
- Card title: `Nenhuma cobrança cadastrada ainda`
- Body: `Crie sua primeira cobrança recorrente na aba Cobranças para começar a acompanhar recebimentos, despesas e faturas por aqui.`
- CTA: `Ver cobranças`
- Overdue label: `Saldo em atraso`

This work also preserves existing notice copy, including `Sessão conectada ao Rentivo.`, `PIX pessoal atualizado.`, `Senha alterada com sucesso.`, and `Chave revogada.`

New accessibility-only announcement prefixes must use these exact strings:

- Success: `Sucesso: {mensagem}`
- Information: `Informação: {mensagem}`
- Warning: `Atenção: {mensagem}`
- Close button: `Fechar aviso` (existing string, retained)

`{mensagem}` is the existing notice text without changing punctuation, for example `Sucesso: Senha alterada com sucesso.` Do not duplicate the prefix visually in the toast.

## Accessibility requirements

- When a new toast becomes visible, post one VoiceOver announcement using the kind-specific prefix above. Use the platform announcement notification intended for brief UI updates; do not move VoiceOver focus away from the current control.
- Replacement produces one announcement for the replacement only. Dismissal produces no announcement.
- The visible toast exposes its message and semantic kind, and exposes `Fechar aviso` as a separate button/action.
- The close button is reachable with VoiceOver and Switch Control. A custom accessibility action named `Fechar aviso` may mirror the button, but must invoke the same dismissal path.
- Support all Dynamic Type sizes without truncating toast text, onboarding copy, the Home CTA, or tab labels. At accessibility sizes, content may wrap and the toast may become taller.
- Respect Reduce Motion as specified above.
- Test Increased Contrast and Reduce Transparency. The toast and tab bar remain opaque, and boundaries/icons remain distinguishable without relying on shadow alone.
- Do not use color alone for success/warning or overdue state; retain semantic icons and labels.

## Affected files

### Required implementation files

| Path relative to `ios/` | Required change |
| --- | --- |
| `Rentivo/App/AppModel.swift` | Own notice replacement, timeout cancellation, feature-area scope, and a single dismissal API; update session-transition scopes. |
| `Rentivo/App/RootView.swift` | Replace the top overlay with the bottom safe-area presenter; apply the tab-bar background and shared tab-content contract; report tab-area changes. |
| `Rentivo/App/RentivoApp.swift` | Only if needed for deterministic DEBUG/UI-test launch states for a visible notice or fresh account. No production behavior belongs in launch arguments. |
| `Rentivo/DesignSystem/RentivoComponents.swift` | Update/rename `NoticeBanner`, add gesture, hit-target, layout, identifiers, and VoiceOver announcement behavior. |
| `Rentivo/DesignSystem/RentivoTheme.swift` | Add shared spacing/style support for tab-content clearance and the opaque tab-bar surface; keep the rule reusable. |
| `Rentivo/Features/Home/HomeView.swift` | Add onboarding-first ordering, suppress zero analytics in the no-billings state, and apply the conditional overdue presentation. |
| `Rentivo/Features/Account/AccountView.swift` | Verify/apply the shared `List` bottom-content contract and mark Account as a feature area. |
| `Rentivo/Features/Account/SecurityViews.swift` | Mark Security as a feature area and ensure password success is owned by Security. |
| `Rentivo/Features/Account/APIKeyViews.swift` | Mark API keys as a feature area and keep revoke feedback scoped there. |

### Navigation and bottom-clearance audit

These are real tab-backed destinations or scroll containers found in the current source. They require an area marker and/or verification that the shared bottom-content rule reaches them; only add local layout changes where the shared scaffold cannot cover the container correctly.

- `Rentivo/Features/Billings/BillingListView.swift`
- `Rentivo/Features/Billings/BillingDetailView.swift`
- `Rentivo/Features/Bills/BillViews.swift`
- `Rentivo/Features/Bills/BillingOperationsViews.swift`
- `Rentivo/Features/Organizations/OrganizationViews.swift`
- `Rentivo/Features/Organizations/InvitationViews.swift`
- `Rentivo/Features/Account/ThemeViews.swift`
- `Rentivo/Features/Demo/DemoScenariosView.swift`
- `Rentivo/DesignSystem/RentivoFormWizard.swift` (regression audit only; its full-screen bottom action inset must not be doubled)

### Tests

| Path relative to `ios/` | Required coverage |
| --- | --- |
| `RentivoTests/AppModelSessionFlowTests.swift` | Preserve sign-in/sign-out/deletion notice expectations and add destination-scope expectations where applicable. |
| `RentivoTests/AppModelNativeAuthTests.swift` | Preserve native-auth notice copy/kind and assert Home ownership. |
| `RentivoTests/AppNoticePresentationTests.swift` (new) | Deterministic lifecycle, replacement, timeout-race, manual dismissal, and feature-area tests. |
| `RentivoTests/HomePresentationRulesTests.swift` (new, or equivalent tests colocated with an extracted internal rule) | No-billings mode and overdue semantic styling decisions. |
| `RentivoUITests/RentivoUITests.swift` | End-to-end toast timeout/navigation/geometry and Home/Account/tab-bar regressions. |

No change is expected under `Rentivo/Domain/`, `Rentivo/Data/`, or either OpenAPI copy.

## Acceptance criteria

### Toast system

1. Given any supported iPhone with a Dynamic Island, when a notice appears, its frame does not intersect the status bar or navigation bar because it is rendered at the bottom.
2. In the authenticated app, the toast's bottom edge, including shadow, is at least 12 pt above the visible tab bar. With a keyboard, it is at least 12 pt above the keyboard.
3. A standard notice begins dismissal at 4.0 seconds and is gone after its 160 ms exit animation. Test tolerance for scheduling is ±300 ms.
4. With VoiceOver running, a notice uses the 8.0-second lifetime and announces exactly one kind-prefixed PT-BR message without stealing focus.
5. Tapping `Fechar aviso` dismisses the toast and cancels its timer.
6. A horizontal swipe meeting either threshold dismisses the toast; a shorter swipe returns it to rest and leaves at least 1.0 second of lifetime.
7. Creating notice B while notice A is visible shows only B, restarts the timer, and prevents A's timer from dismissing B.
8. Moving from Security to API keys begins dismissal of `Senha alterada com sucesso.` with the navigation transition, and the toast is absent when the API-key transition completes. Changing tabs has the same behavior.
9. A success posted by a dismissing modal remains visible on its intended underlying feature area and is not dismissed by that modal's close transition.
10. Reduce Motion produces fade-only transitions with no translation, scaling, or spring.

### Tab scaffold and content clearance

11. On every tab and tab-backed pushed destination, the last readable/actionable element can be scrolled so its bottom is at least 20 pt above the tab bar.
12. On Home with no billings, the entire `Ver cobranças` CTA is visible and tappable above the bar on the smallest supported portrait device and at the largest accessibility text size.
13. On Account, the entire `Termos de uso` row can be positioned above the bar and activated. The final destructive actions also remain reachable.
14. The tab bar background is continuously visible and fully cream/opaque at every scroll position. High-contrast text placed underneath it is not legible through the bar.
15. The native tab items, selection state, labels, and VoiceOver behavior remain intact.
16. A full-screen wizard's existing bottom action area is not moved upward by a duplicate tab-bar inset.

### Home

17. With `hasBillings == false`, Home renders greeting → `Comece por aqui` hero → nonempty recent activity, in that order.
18. With `hasBillings == false`, the four stat cards, overdue row, quick actions, attention section, upcoming bills, and empty recent-activity placeholder are absent.
19. The hero uses the exact existing PT-BR copy and `Ver cobranças` selects the Cobranças tab.
20. With one or more billings and overdue equal to zero, `Saldo em atraso: R$ 0,00` uses an emerald checkmark and ink amount; no coral/red is used in that row.
21. With overdue greater than zero, the current warning icon and coral amount remain.
22. The populated dashboard still renders its four summary cards and existing conditional sections.

## Test plan

### Unit tests

Use a controllable clock/duration so tests do not sleep for four seconds.

- Show A, advance to just before the deadline, and assert A remains.
- Advance to the deadline and assert A dismisses.
- Show A, then B; complete A's old deadline and assert B remains; complete B's deadline and assert dismissal.
- Exercise close, swipe-commit callback, feature-area change, scene deactivation, and session cleanup through the same dismissal path.
- Assert same-area activation does not dismiss, while Security → API keys and any tab change do.
- Assert session restoration failure/account deletion/sign-in notices own Authentication/Home as specified.
- Assert the VoiceOver duration policy is 8.0 seconds and the default is 4.0 seconds.
- Assert `hasBillings == false` selects onboarding-first mode independently of summary values.
- Assert `hasBillings == true` with all zero summary values remains populated mode.
- Assert overdue styling for negative/zero versus positive cent values; only positive maps to the warning presentation.

### UI tests

Add stable identifiers such as a toast container, close button, Home summary grid, onboarding hero, overdue row, and tab scaffold/background probe as needed.

1. Launch directly into an authenticated deterministic notice state. Assert one toast, assert its frame is below the navigation bar and above the tab bar, then assert it disappears within 4.6 seconds.
2. Relaunch, dismiss by close, and assert immediate removal.
3. Relaunch, swipe the toast horizontally past threshold, and assert removal.
4. Show a notice, change to another tab/feature, and assert it no longer exists on the destination.
5. Exercise a real success that dismisses a modal (password or PIX where test setup permits) and assert the toast appears on the underlying destination.
6. Enable the existing demo empty mode, open Home, and assert the hero exists, summary grid does not, empty recent-activity copy does not, and the CTA switches to Cobranças.
7. Scroll Home and Account to their bottoms and compare element frames with the tab-bar frame. Assert the 20 pt clearance for the Home CTA, `Termos de uso`, and the final Account actions.
8. Capture a screenshot with deliberately high-contrast content behind the floating bar and verify no text is readable through its cream surface.

### Manual visual/accessibility matrix

- iPhone with Dynamic Island, compact iPhone, and iPad.
- iOS 17 and the current shipping iOS SDK/runtime, because native tab-bar shape/material behavior differs by OS.
- Portrait and landscape where supported.
- Default text and largest accessibility text.
- VoiceOver, Switch Control, Reduce Motion, Increase Contrast, and Reduce Transparency.
- Keyboard visible on a screen capable of producing a notice.
- Populated Home with zero overdue, populated Home with overdue greater than zero, and no-billings Home.
- Scroll positions at top, middle, and bottom on Home, Billing list/detail, Organization list/detail, Account, Security, API keys, and Demo scenarios.

## Implementation notes and sequencing

1. Implement/test notice lifecycle and feature ownership before moving the presenter; this makes replacement and stale-task behavior deterministic.
2. Move the presenter into the bottom safe-area layout and add gesture/accessibility behavior.
3. Apply the shared tab content inset and opaque tab-bar background at the authenticated scaffold, then fix only the individual containers that fail the geometry acceptance test.
4. Apply Home presentation rules and identifiers.
5. Run unit/UI tests and the manual device/accessibility matrix.

Relevant platform references:

- [SwiftUI `safeAreaInset`](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)) reserves space for inset content instead of merely drawing over it.
- [SwiftUI `toolbarBackground`](https://developer.apple.com/documentation/swiftui/view/toolbarbackground(_:for:)-7lv0f) supports forcing bar background visibility instead of allowing scroll position to make it transparent.
- [UIKit accessibility announcements](https://developer.apple.com/documentation/uikit/uiaccessibility/notification/announcement) are intended for brief UI updates such as a transient toast.
