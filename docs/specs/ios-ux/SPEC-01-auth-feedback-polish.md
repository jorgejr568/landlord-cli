# SPEC-01 — Authentication and feedback polish

- **Status:** Ready for implementation
- **Platform:** Rentivo iOS, iOS 17+, SwiftUI
- **Conventions:** Identifiers, types, enum cases, comments, and tests are English. Every user-facing or accessibility string is PT-BR.

## Goal

Make sign-in, sign-up, second-factor verification, and session restoration clear and trustworthy without weakening Rentivo's neo-brutalist visual language. When this work is complete:

- every in-scope password can be revealed and hidden safely;
- sign-up explains a password mismatch inline;
- disabled primary buttons no longer look tappable;
- authentication links use one semantic color;
- TOTP entry is fast with keyboard entry, AutoFill, and paste;
- authentication errors explain recovery in plain language instead of exposing technical API copy;
- cold launch and session restoration never show an unbranded white frame.

This work does not change endpoints, payloads, password policy, challenge duration, or the OpenAPI schema. `LiveAPIError.problemCode` already preserves the stable codes needed by the UI. Friendly error mapping belongs in the presentation layer and must not alter the global error behavior used by unrelated features.

## Relevant current implementation

- `AuthViews.swift` owns `SignInForm`, `SignUpForm`, `MFAChallengeForm`, `AuthField`, `AuthLinkButton`, and the private `ptBRDescription` helper.
- The sign-in/sign-up password fields and all three fields in `ChangePasswordView` use `SecureField` directly.
- `AuthLinkButton` forces `RentivoColors.blue`; the external “Esqueceu sua senha?” link inherits the green tint set in `RentivoApp`.
- `RentivoButtonStyle` creates its disabled state by reducing the opacity and saturation of the active fill. This produces the sage-green/white treatment seen in review screenshots.
- Authentication buttons and `RentivoFormWizard` disable their buttons while also rendering a white `ProgressView`. The revised style must distinguish unavailable from busy so a white spinner does not end up on the new light disabled fill.
- `MFAChallengeForm` already sets the number pad and `.oneTimeCode` for TOTP, but uses a regular field, accepts any nonempty length for “Confirmar,” and does not auto-submit.
- The API exposes `invalid_credentials`, `login_rate_limited`, `email_already_registered`, `invalid_mfa_code`, `invalid_passkey`, `mfa_rate_limited`, `invalid_or_expired_challenge`, and, during authenticator enrollment, `invalid_totp_code`.
- A live `AppModel` already starts in `.restoring`. `RootView` renders only `ProgressView("Restaurando sessão…")`; `UILaunchScreen` is empty in the Info.plist, allowing a white flash before SwiftUI draws.

## Affected files

Paths are relative to `ios/`.

| File | Expected responsibility |
| --- | --- |
| `Rentivo/Features/Auth/AuthViews.swift` | Adopt the shared password input; manage sign-up focus/validation; use the link style; implement MFA input/states; consume friendly feedback. |
| `Rentivo/Features/Auth/AuthFeedback.swift` **(new)** | Hold testable confirmation, TOTP normalization/auto-submit, and contextual `problemCode` presentation rules. It must not perform transport. |
| `Rentivo/Features/Account/SecurityViews.swift` | Add visibility toggles to all three change-password fields and friendly `invalid_totp_code` feedback during authenticator enrollment. |
| `Rentivo/DesignSystem/RentivoTheme.swift` | Add semantic link, disabled-control, and code-typography tokens. |
| `Rentivo/DesignSystem/RentivoComponents.swift` | Add the shared password input; revise `RentivoButtonStyle` for unavailable and busy states; add/update previews. |
| `Rentivo/DesignSystem/RentivoFormWizard.swift` | Pass an explicit busy state to its primary button so progress keeps the correct visual treatment. |
| `Rentivo/App/RootView.swift` | Replace the generic restoring progress with a branded, full-screen restoration state. |
| `Config/Rentivo-Info.plist` | Configure the static `UILaunchScreen` background and logo. |
| `Rentivo/Resources/Assets.xcassets/RentivoLaunchBackground.colorset/Contents.json` **(new)** | Store an sRGB color identical to `RentivoColors.paper`. |
| `Rentivo/Resources/Assets.xcassets/RentivoLaunchLogo.imageset/Contents.json` and `Rentivo/Resources/Assets.xcassets/RentivoLaunchLogo.imageset/rentivo-launch-logo.pdf` **(new)** | Store a transparent vector export of the full `BrandMark`. |
| `RentivoTests/AuthFeedbackRulesTests.swift` **(new)** | Test confirmation, TOTP, and feedback mapping in the Xcode-hosted `RentivoTests` target. |
| `RentivoTests/MobileAuthClientTests.swift` | Test preservation of presentation-relevant `problemCode` values, including an expired challenge. |
| `RentivoTests/SecurityViewRulesTests.swift` | Test friendly `invalid_totp_code` presentation. |
| `RentivoTests/AppModelSessionFlowTests.swift` | Test the live `.restoring` initial state and authenticated, anonymous, and failure outcomes. |

`Rentivo` and `RentivoTests` are `PBXFileSystemSynchronizedRootGroup` groups. New Swift and asset files should join their targets automatically; no manual `project.pbxproj` edit is expected.

## Design-system contract

### Semantic tokens

Add semantic aliases in `RentivoColors`, retaining existing colors as their source:

| Use | Token | Value/source |
| --- | --- | --- |
| Active primary action | `primaryAction` | `RentivoColors.emerald` |
| Inline link | `link` | `RentivoColors.emerald` |
| Disabled control fill | `disabledControlFill` | `RentivoColors.paper` |
| Disabled label/icon/outline | `disabledControlForeground` | `RentivoColors.secondaryInk` |
| Error | `error` | `RentivoColors.coral` |

Do not use blue as a link fallback and do not apply opacity to the entire disabled button. `secondaryInk` on `paper` must meet WCAG AA at a minimum 4.5:1 for normal text. The green link token must retain the contrast already documented in `RentivoTheme` against both `paper` and `surface`.

Add `RentivoTypography.code` using the semantic `.title2` size, monospaced system design, and bold weight. It must scale with Dynamic Type. Do not reuse `money`; code and currency have different semantics even though both are monospaced.

`RentivoLaunchBackground` must repeat the exact sRGB values used by `paper`: red `0.97`, green `0.95`, blue `0.90`, alpha `1.0`. The asset must document that it stays synchronized with the SwiftUI token because the static launch screen exists before SwiftUI runtime values are available.

### Primary-button states

`RentivoButtonStyle` must represent four visual states even though SwiftUI interaction still uses `.disabled`:

| State | Appearance |
| --- | --- |
| Active | Requested accent fill (green by default), white label, 2 pt `ink` outline, and 3×3 `ink` hard shadow. |
| Pressed | Preserve the current offset/shadow-removal feedback and short animation. |
| Unavailable | `disabledControlFill`; `disabledControlForeground` label, icon, and 2 pt outline; no hard shadow; no offset; opacity 1; saturation 1. |
| Busy | Preserve the active fill/contrast, show white progress, prevent duplicate taps, and expose the accessibility value “Em andamento.” Only the control that started the request is busy; controls blocked by that request use the unavailable appearance. |

Busy must be an explicit component/style input, not inferred only from `Environment.isEnabled`. Update spinner-bearing call sites in authentication, TOTP enrollment, and `RentivoFormWizard`. This prevents white progress on a light disabled fill and prevents both “Usar chave de acesso” and “Confirmar” from showing progress for one MFA request. Other existing `RentivoButtonStyle` call sites automatically receive the new unavailable appearance.

### Shared password input

Add an English-named component such as `RentivoPasswordInput`. It represents one logical text entry and provides:

- one text binding;
- `SecureField` while hidden and `TextField` while visible;
- a trailing `eye`/`eye.slash` SF Symbol button with a minimum 44×44 pt hit target;
- caller-provided `.password` or `.newPassword` content type, submit label/action, accessibility identifier, and contextual accessibility name;
- disabled autocapitalization and autocorrection in both modes;
- value, focus, cursor, submit behavior, and Password AutoFill preservation when toggled;
- hidden-by-default state, independent for every field;
- automatic return to hidden when its view leaves the hierarchy or the app enters the background.

The component may be visually neutral so `AuthField` or the wizard owns the surrounding chrome, but the text entry and eye must form one row and must not create nested outlines. Password values must never enter accessibility labels, logs, notices, or the wizard review.

## Detailed behavior and acceptance criteria

### 1. Password visibility

Use `RentivoPasswordInput` for exactly these fields:

- sign-in: `login.password`;
- sign-up: `signup.password` and `signup.confirm`;
- change password: `password.form.current`, `password.form.new`, and `password.form.confirmation`.

Every field owns its visibility state. Toggling one field must not affect another, clear the value, or move focus outside the input. Preserve existing content types: `.password` for sign-in/current password and `.newPassword` for password creation, new password, and confirmations.

Give each eye button an identifier derived from its field with the English `.visibility` suffix, for example `login.password.visibility` and `password.form.new.visibility`.

#### Acceptance criteria

- All six fields start hidden and display a trailing eye control.
- One tap changes only the corresponding field between hidden and visible without losing its value or focus.
- Password AutoFill continues to recognize sign-in and new-password fields; Return/Go keeps its existing action.
- Leaving the screen, changing the password-wizard step, or backgrounding the app hides any visible password again.
- VoiceOver announces the toggle action/state without reading the password.

### 2. Inline sign-up confirmation validation

Separate local confirmation feedback from request feedback. Render the local error immediately below `AuthField("CONFIRMAR SENHA")`; keep `signup.error` for general/API failures. Use `signup.confirm.error` for this inline message.

State and triggers:

1. Confirmation starts untouched. Show no error while it is empty and has not been edited.
2. Mark it touched when the user edits it.
3. When both password values are nonempty and differ, show the error:
   - immediately when confirmation loses focus;
   - after **500 ms** with no change to `password` or `confirmPassword`;
   - immediately when Go/Return is pressed from confirmation.
4. Cancel pending validation when input changes. A stale task must not publish feedback for newer values.
5. Clear the error immediately when values match or confirmation becomes empty.
6. Keep the CTA disabled until the email is valid, `BcryptPasswordRules` accepts the password, confirmation matches, and no request is running. Never call sign-up for a mismatch.
7. API feedback remains below the form as a whole and neither replaces nor occupies the confirmation slot.

Use `AuthErrorLabel`, the error icon, and `RentivoColors.error`. Its appearance may animate height/opacity only, must respect Reduce Motion, and must not steal keyboard focus.

#### Acceptance criteria

- Different passwords show “As senhas não coincidem.” within 500 ms of a pause or immediately on blur/Go.
- No premature mismatch appears before confirmation interaction.
- Correcting confirmation clears the message without another blur.
- During mismatch, “Criar Conta” uses the unavailable treatment and no sign-up request occurs.
- The message sits directly under “Confirmar senha” with `signup.confirm.error`; remote errors remain at `signup.error`.

### 3. Disabled primary buttons

Apply the design-system states to every `RentivoButtonStyle` use, with explicit verification of these in-scope controls:

- “Entrar” before valid email/password;
- “Criar Conta” before a valid form and during mismatch;
- MFA “Confirmar” before six TOTP digits;
- authenticator-enrollment “Confirmar” before six digits;
- an unavailable wizard primary action;
- MFA factor buttons blocked while another factor is running.

Do not use `.opacity(0.45)` or `.saturation(0.6)` as the disabled appearance. Hit testing and the `.isEnabled` accessibility trait still come from `.disabled`; do not simulate disablement with `allowsHitTesting(false)`.

#### Acceptance criteria

- An unavailable button uses the muted cream fill, `secondaryInk` label/outline, no hard shadow, and does not react to taps.
- Disabled label contrast is at least 4.5:1. The state does not rely on color alone because the shadow also disappears.
- A busy button keeps the active fill, shows exactly one legible spinner, and rejects a second tap.
- In MFA, only the submitted factor shows progress; other factor controls look unavailable.
- `RentivoButtonStyle` previews show active, unavailable, and busy variants on both `paper` and `surface`.

### 4. Link color and semantics

Create one inline-link treatment using `RentivoColors.link`, `.footnote.weight(.bold)`, and an underline. Apply it to both the external `Link` and action `Button` instances:

- “Esqueceu sua senha?”;
- “Criar conta”;
- “Entrar”;
- “Usar código de recuperação”;
- “Usar código do aplicativo autenticador”;
- “Voltar”.

Do not change destinations or actions. None of these controls may inherit system blue or use `RentivoColors.blue`. Keep true `Link` semantics for the external URL and true `Button` semantics for in-app mode changes. A disabled inline link uses `disabledControlForeground`; an active link must not lose contrast through opacity.

#### Acceptance criteria

- Every listed link uses the same semantic green and underline in sign-in, sign-up, and MFA.
- No authentication inline link appears blue, including after switching back and forth between forms.
- VoiceOver continues to identify the external URL as a link and internal mode changes as clearly named buttons.
- Isolated link actions have at least a 44 pt-high tap area; an inline phrase remains comfortable without making unrelated sentence text tappable.

### 5. MFA TOTP entry and completion

In `MFAChallengeForm`'s `.totp` mode, replace the regular field with one large monospaced input. Do not use six independent text fields: one logical input is more reliable for AutoFill, paste, VoiceOver, compact widths, and Dynamic Type.

Required behavior:

- retain the visual label “CÓDIGO DO APLICATIVO AUTENTICADOR”;
- show “Digite os 6 dígitos exibidos no seu aplicativo autenticador.” immediately below the label and before the input;
- show placeholder “000000,” center the text, use `RentivoTypography.code`, a minimum 64 pt height, `paper` fill, 12 pt corner radius, and 2 pt `ink` outline; focus may change the outline to `link` without making it thinner;
- use `.textContentType(.oneTimeCode)`, `.keyboardType(.numberPad)`, no autocorrection, and no capitalization;
- normalize every edit to ASCII `0...9` and at most six characters. On paste, remove spaces/separators and accept the first six digits. Never suppress the system Paste menu;
- handle AutoFill and paste through the same binding change as keyboard input;
- when the count transitions from fewer than six to six, verify exactly once. Ignore triggers while a request is active or while that value is the last submitted value;
- retain “Confirmar” as an accessible/manual fallback, enabled only for six digits with no request running;
- disable editing during the request and show progress only on the TOTP action;
- for `invalid_mfa_code`, clear the code, restore input focus, and allow another attempt;
- for transient/unknown failure, preserve the six digits so “Confirmar” can retry without re-entry;
- when switching to recovery or back to TOTP, clear code, error, last submitted value, and operation state.

The `.recovery` mode retains its ASCII keyboard, capitalization, and current placeholder. It must not receive `.oneTimeCode` and must not auto-submit at six characters.

When the API returns `invalid_or_expired_challenge`, the challenge is terminal:

- clear and remove/disable factor inputs and factor actions;
- show the recovery-oriented error;
- replace the generic “Voltar” link with a primary “Voltar para entrar” CTA;
- call `onCancel` from that CTA, discard the `MFAChallenge`, and return to the credentials that `LoginView` already preserves. The user can then tap “Entrar” to obtain a new challenge;
- do not invent a local timer. `MFAChallenge` has no `expiresAt`, so the server remains the authority on expiration.

#### Acceptance criteria

- QuickType/one-time-code AutoFill appears when available, and reaching six digits verifies without another tap.
- Typing `123456`, pasting `123456`, or pasting `123 456` sends exactly `123456` once.
- Letters do not enter TOTP and input beyond six digits is truncated.
- An invalid code shows friendly feedback, clears the field, and restores focus; a network error preserves the digits.
- Recovery neither auto-submits nor offers system one-time-code content.
- An expired challenge cannot be retried and offers “Voltar para entrar,” returning to the populated credential form.

### 6. Friendly, auditable authentication errors

Replace `ptBRDescription(for:)` with a testable presentation mapper whose English context distinguishes sign-in, sign-up, TOTP, recovery, passkey, and TOTP enrollment. It must:

- branch on `LiveAPIError.problemCode`, never translated `detail` text;
- return a message and, where applicable, a terminal disposition/action;
- never display `error.localizedDescription` or `LiveAPIError.errorDescription` directly on authentication screens for known or unknown codes;
- use a contextual PT-BR fallback for transport failure, invalid response, or an unknown code;
- leave `LiveAPIError` and non-authentication error passthrough unchanged;
- never log a password, TOTP, recovery code, challenge token, or field contents.

Required mappings:

| Context | `problemCode` | Exact presentation |
| --- | --- | --- |
| Sign-in | `invalid_credentials` | “E-mail ou senha incorretos. Confira os dados e tente novamente.” |
| Sign-in | `login_rate_limited` | “Você fez muitas tentativas. Aguarde alguns minutos antes de tentar entrar novamente.” |
| Sign-up | `login_rate_limited` | “Você fez muitas tentativas. Aguarde alguns minutos antes de tentar criar a conta novamente.” |
| Sign-up | `email_already_registered` | “Este e-mail já está cadastrado. Entre com sua conta ou recupere a senha.” |
| MFA TOTP | `invalid_mfa_code` | “Esse código não funcionou. Confira os 6 dígitos no aplicativo autenticador e tente novamente.” |
| MFA recovery | `invalid_mfa_code` | “Esse código de recuperação não funcionou. Confira o código e tente novamente.” |
| MFA passkey | `invalid_passkey` | “Não foi possível verificar sua chave de acesso. Tente novamente ou use outro método.” |
| Any MFA factor | `mfa_rate_limited` | “Você fez muitas tentativas. Aguarde alguns minutos e tente novamente.” |
| Any MFA factor | `invalid_or_expired_challenge` | Terminal: “Esta verificação expirou. Volte e entre novamente para iniciar uma nova.” plus “Voltar para entrar”. |
| Authenticator enrollment | `invalid_totp_code` | “Esse código não funcionou. Confira os 6 dígitos no aplicativo autenticador e tente novamente.” |

Required fallbacks:

| Context | Exact message |
| --- | --- |
| Sign-in | “Não foi possível entrar. Tente novamente.” |
| Sign-up | “Não foi possível criar sua conta. Tente novamente.” |
| MFA TOTP | “Não foi possível verificar o código. Tente novamente.” |
| MFA recovery | “Não foi possível verificar o código de recuperação. Tente novamente.” |
| MFA passkey | “Não foi possível verificar sua chave de acesso. Tente novamente ou use outro método.” |
| Authenticator enrollment | “Não foi possível confirmar o código. Tente novamente.” |

In `SecurityViews` authenticator enrollment, specifically replace the “Código TOTP inválido” passthrough with this mapping. Other Security flows are outside this audit and retain their existing handling.

#### Acceptance criteria

- “Desafio de autenticação inválido ou expirado.” never appears in app MFA.
- “Código TOTP inválido” never appears during authenticator enrollment.
- Every known code produces the exact contextual message in the table.
- An invalid MFA code remains recoverable; `invalid_or_expired_challenge` is terminal and always provides the return action.
- An unknown/missing `problemCode` uses the contextual fallback and cannot leak technical or English API text.

### 7. Branded launch and session restoration

There are two distinct stages, and both must use the cream background:

1. **Static launch screen, before SwiftUI:** populate `UILaunchScreen` with `UIColorName = RentivoLaunchBackground`, `UIImageName = RentivoLaunchLogo`, and `UIImageRespectsSafeAreaInsets = true`. Use the centered full logo as a transparent vector image. Do not introduce a storyboard or animation.
2. **SwiftUI `.restoring` state:** add a dedicated view under `RootView` (or an equivalent App-layer file) using `RentivoColors.paper.ignoresSafeArea()`, `BrandMark()`, a small `ProgressView` tinted `RentivoColors.emerald`, and “Restaurando sua sessão…”. Center the group, use `RentivoSpacing.large`, and keep the mark visually stable through transition.

Do not impose a minimum display duration. As soon as `restoreSessionIfNeeded()` finishes, move directly to `AuthenticationView` or `AuthenticatedTabView`. Preserve current failure behavior: anonymous session plus “Não foi possível restaurar sua sessão. Entre novamente.”

Give the container the accessibility identifier `session.restore`. Expose the progress label only once. If the container announces “Rentivo,” hide any duplicate mark announcement from VoiceOver.

#### Acceptance criteria

- A live cold launch begins on cream with the logo and has no white frame before or between the static launch screen and SwiftUI.
- While restoration is pending, the app shows the brand, subtle progress, and “Restaurando sua sessão…”.
- The view covers the notch, Dynamic Island, home indicator, and all supported safe areas without white strips.
- Completion adds no artificial delay, flicker, or animation that ignores Reduce Motion.
- Restore success opens authenticated content; no session opens sign-in; failure opens sign-in with the existing notice.

## Exact PT-BR copy inventory

The error tables above are normative. In addition, use exactly:

| Use | Exact PT-BR copy |
| --- | --- |
| Sign-up confirmation error | `As senhas não coincidem.` |
| TOTP helper | `Digite os 6 dígitos exibidos no seu aplicativo autenticador.` |
| Expired-challenge CTA | `Voltar para entrar` |
| Restoration label | `Restaurando sua sessão…` |
| Busy-button accessibility value | `Em andamento` |
| Visibility hint while hidden | `Exibe o conteúdo deste campo.` |
| Visibility hint while visible | `Oculta o conteúdo deste campo.` |
| TOTP VoiceOver label | `Código do aplicativo autenticador` |
| TOTP VoiceOver hint | `Digite ou cole 6 dígitos. A verificação começa automaticamente ao completar o código.` |
| TOTP VoiceOver value template | `<n> de 6 dígitos preenchidos` |

Exact visibility-button labels:

| Field | Hidden | Visible |
| --- | --- | --- |
| Sign-in — password | `Mostrar senha` | `Ocultar senha` |
| Sign-up — password | `Mostrar senha` | `Ocultar senha` |
| Sign-up — confirmation | `Mostrar confirmação da senha` | `Ocultar confirmação da senha` |
| Change — current password | `Mostrar senha atual` | `Ocultar senha atual` |
| Change — new password | `Mostrar nova senha` | `Ocultar nova senha` |
| Change — new-password confirmation | `Mostrar confirmação da nova senha` | `Ocultar confirmação da nova senha` |

Link text does not change. Preserve exactly “Esqueceu sua senha?”, “Criar conta”, “Entrar”, “Usar código de recuperação”, “Usar código do aplicativo autenticador”, and “Voltar,” including PT-BR accents. Any constant or enum organizing these strings must have an English identifier.

## Accessibility requirements

- **VoiceOver:** Visibility toggles are separate buttons with the table's label/hint; each field retains its own label. Never place password values in the toggle or surrounding accessibility labels. While hidden, preserve secure-entry behavior; after the user explicitly reveals a field, allow normal editable-text feedback according to their VoiceOver typing settings. TOTP is one editable element, not six elements, and announces only the filled count rather than digits.
- **Errors:** Use icon plus text, never color alone. After blur/Go, announce a newly shown inline error once without permanently stealing focus. Pause-based validation must not announce repeatedly while typing; expose the current error through the field's accessibility description/hint for discovery.
- **Focus:** Invalid code restores focus to TOTP. Terminal error moves accessibility focus to its message and places “Voltar para entrar” next in order. The eye toggle preserves text-entry focus.
- **Dynamic Type:** Use semantic fonts. TOTP, helpers, errors, and links wrap at accessibility sizes; no copy truncates. Do not use `minimumScaleFactor` to hide overflow.
- **Contrast:** Normal text and links require 4.5:1; component boundaries and essential icons require 3:1. Verify `paper` and `surface`, including disabled controls.
- **Targets:** Eyes, isolated links, and CTAs are at least 44×44 pt. TOTP is at least 64 pt tall.
- **Motion:** Validation transitions respect Reduce Motion. Native indeterminate progress is allowed without decorative animation.
- **Switch Control/hardware keyboard:** Order is field → eye → next control. Return/Go remains functional. TOTP auto-submit does not remove “Confirmar.”

## Test plan

### Automated — `RentivoTests` target

`Package.swift` excludes views, design system, and `AppModel` from `RentivoCore`. Presentation rules must therefore be exercised in the Xcode-hosted **`RentivoTests`** target. Tests referring to `Rentivo` should follow the existing `#if canImport(Rentivo)` pattern so `swift test --package-path ios` can still compile the shared test folder.

1. **Add `AuthFeedbackRulesTests.swift`:**
   - untouched/empty confirmation produces no error;
   - mismatch produces exactly “As senhas não coincidem.” and match clears it;
   - TOTP normalization covers typing, `123 456`, letters, non-ASCII Unicode numerals, and excess digits;
   - auto-submit is true only for `< 6 → 6`, and false while busy or already submitted;
   - the full `problemCode` × context table produces exact copy and terminality;
   - an uncoded error uses every contextual fallback and never returns raw `detail`.
2. **Extend `MobileAuthClientTests.swift`:**
   - in addition to `errorDescription`, assert `problemCode` for `login_rate_limited`, `email_already_registered`, and `invalid_mfa_code`;
   - add an `invalid_or_expired_challenge` TOTP response and prove its code/status reach presentation intact;
   - add `mfa_rate_limited` if it is not already covered.
3. **Extend `SecurityViewRulesTests.swift`:**
   - `invalid_totp_code` maps to friendly copy;
   - an unknown error maps to the authenticator-enrollment fallback.
4. **Extend `AppModelSessionFlowTests.swift`:**
   - a live dependency starts `.restoring`;
   - a restore with a session ends authenticated;
   - a restore without a session ends anonymous;
   - a restore error ends anonymous and preserves the exact current notice.
5. **Component state:** If button visuals are represented by an equatable state model, test that unavailable has no shadow and selects muted tokens while busy preserves the accent. Do not assert private SwiftUI pixels in unit tests.

### Manual and visual verification

- Preview active, unavailable, and busy buttons on `paper` and `surface`, using green and custom blue accents.
- Preview sign-in, sign-up mismatch, normal/busy/invalid/expired MFA, and restoration.
- Verify a compact-width iPhone and a current iPhone at Default and Accessibility XXXL text sizes.
- With VoiceOver, traverse all six password fields/toggles, sign-up error, TOTP, terminal error, and recovery CTA.
- Paste `123456` and `123 456`; use QuickType one-time code; verify one request per completion.
- Enable Reduce Motion and confirm content does not jump or depend on animation.
- Record a cold launch after process termination with both fast and artificially slow restore. Inspect frame by frame for white between static launch and `.restoring`.
- Simulate `invalid_mfa_code`, `mfa_rate_limited`, `invalid_or_expired_challenge`, an uncoded error, and network failure; compare all copy with this spec.

### Verification commands

- `make ios-test`
- `make ios-openapi-check`
- Run the CI-equivalent app target command with an available simulator: `xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -destination "platform=iOS Simulator,id=<SIMULATOR_ID>" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO test -only-testing:RentivoTests`

`make ios-test` alone is insufficient: it runs only the `RentivoCore` package, while this change primarily affects `Features`, `DesignSystem`, and `App`.

## Out of scope

- Backend changes, challenge duration/attempt-limit changes, or RFC 7807 changes.
- A native forgot-password flow; the existing link continues opening its current production destination.
- Redesigning recovery codes or passkey enrollment.
- Changing unrelated feature errors, except the explicitly listed authenticator-enrollment feedback.
- Adding a snapshot, OTP-input, or localization dependency.

## Definition of done

All acceptance criteria for the seven findings are met; user-facing copy matches this document byte for byte; `RentivoTests` covers rules and mappings; iOS checks pass; and manual review confirms VoiceOver, Dynamic Type, contrast, AutoFill/paste, and a cold launch without a white flash.
