# Rentivo iOS — Manual Test Flows

A repeatable, step-by-step script for manually verifying every user-facing flow in the
Rentivo iOS app. Written so a human (or an agent) with no prior context can execute a
scenario exactly and get the same result every time — like a Cucumber/Gherkin feature
file, but in plain numbered steps.

Re-run this whenever `ios/Rentivo/Features/` changes in a way that could affect behavior,
or before a release, to catch regressions the automated suites (`RentivoTests`,
`RentivoUITests`) don't cover.

## How to read a scenario

- **Given** — starting state required before the steps make sense (account state, data
  that must already exist).
- Numbered steps are actions or checks, in order. Each action names the exact on-screen
  label (PT-BR, verbatim) and, in parentheses, its `accessibilityIdentifier` when one
  exists — useful both for a human hunting for the right button and for turning a
  scenario into an XCUITest later.
- **Alternate flows** are lettered branches off a specific step (e.g. `5a.`) — a different
  path through the same scenario (an error path, a cancel, a different choice). They
  rejoin or end the scenario; where they rejoin is noted.
- Screens are named after their `navigationTitle` or sheet title. "Full-screen wizard"
  means a `RentivoFormWizard` cover (`.rentivoFullScreenWizard`); every wizard shares the
  same bottom bar: **Continuar** (`wizard.continue`) advances a step, **Voltar**
  (`wizard.back`) returns one, the **X** in the top-left (`wizard.close`) dismisses —
  asking "Descartar alterações?" once you're past step 1 — and the final step's primary
  button (`wizard.commit`) submits.

## Prerequisites (test environment setup)

1. Start the dev backend stack (port 8080 is commonly held by other local services, so
   override it): `RENTIVO_PORT=18080 make compose-dev`. Confirm it's up:
   `curl http://localhost:18080/api/v1/health` → `{"status":"ok"}`.
2. The iOS app hardcodes `LiveAPIClient.productionURL`. A DEBUG build reads an override
   instead (see `docs/mobile.md`): after installing a Debug build on the simulator, run
   `xcrun simctl spawn <udid> defaults write br.com.rentivo.ios RentivoAPIBaseURL
   "http://localhost:18080"` — do this once per simulator device, it persists.
3. Build for the simulator and install:
   ```
   xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -configuration Debug \
     -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <path> \
     -skipPackagePluginValidation -skipMacroValidation build
   xcrun simctl install <udid> <path>/Build/Products/Debug-iphonesimulator/Rentivo.app
   xcrun simctl launch <udid> br.com.rentivo.ios
   ```
4. Every scenario below assumes a **fresh account** unless its Given says otherwise —
   create one via [A2](#a2-sign-up) or, faster for setup, `POST /api/v1/auth/mobile/signup`
   `{"email": "...", "password": "..."}` against the dev backend directly.
5. Where a scenario needs TOTP, compute codes from the secret shown on screen with any
   RFC 6238 TOTP generator (30s step, 6 digits, SHA1) — e.g. `pyotp.TOTP(secret).now()`.
6. Money fields accept only digits and treat them as cents-of-the-typed-number read
   right-to-left (e.g. typing `150000` produces R$ 1.500,00) — expected behavior, not a bug.
7. **iOS hazard, not an app bug:** the system "Usar Senha Forte?" (Suggest Strong Password)
   sheet pops up over the very first edit of almost any fresh password field on the
   Simulator and steals subsequent keystrokes. If you're driving this by hand, dismiss it
   (its **X**, top-right of the sheet) immediately, then type the password again in one
   go. If you instead tap **"Preencher Senha Forte"**, iOS will autofill *both* the field
   you're in and (once you reach it) the matching confirmation field with a generated
   password you don't know — harmless for a one-off "does signup succeed" check, but it
   leaves you unable to log back into that account later, so avoid it for any scenario
   that logs in again afterward.

## Environment used for the pass below

Backend: dev Compose stack at `http://localhost:18080`. Accounts:
`qa.primary@example.com` / `qa-primary-2026` (primary, becomes an org admin),
`qa.invitee@example.com` / `qa-invitee-2026` (second account, used for invite/accept and
viewer-role scenarios).

## Table of contents

- [A. Authentication & session](#a-authentication--session)
- [B. Home dashboard (Início)](#b-home-dashboard-início)
- [C. Account (Conta)](#c-account-conta)
- [D. Billings (Cobranças)](#d-billings-cobranças)
- [E. Bills (Faturas)](#e-bills-faturas)
- [F. Communications](#f-communications)
- [G. Billing operations (Despesas, Arquivos, Exportar)](#g-billing-operations-despesas-arquivos-exportar)
- [H. Organizations (Organizações)](#h-organizations-organizações)

---

## A. Authentication & session

### A1. App launch with no stored session

**Given** the app has never been signed in on this device (or was signed out).

1. Launch the app.
2. The **Boas-vindas** screen appears directly — title "Boas-vindas", subtitle "Entre com
   sua conta Rentivo para acessar seus dados.", an E-MAIL field (`login.email`,
   placeholder "voce@exemplo.com.br"), a SENHA field (`login.password`, placeholder "Sua
   senha"), a green **"Entrar"** button (`login.submit`, disabled while a field is empty),
   a link **"Esqueceu sua senha?"** (`login.forgot`), and text "Ainda não tem uma conta?"
   with a **"Criar conta"** link (`login.signup`).

*There is no separate splash/loading screen visible to a human before this — `RootView`'s
`.restoring` spinner ("Restaurando sessão…") only shows while a stored token is being
validated (see A6), which doesn't apply here.*

### A2. Sign up

**Given** anonymous state (A1), and the email below has never been used.

1. Tap **"Criar conta"** (`login.signup`).
2. The form swaps in place to **Criar conta** — title "Criar conta", subtitle "Crie sua
   conta Rentivo para organizar as cobranças dos seus imóveis.", fields E-MAIL
   (`signup.email`), SENHA (`signup.password`, placeholder "Crie uma senha"), CONFIRMAR
   SENHA (`signup.confirm`, placeholder "Repita a senha"), button **"Criar Conta"**
   (`signup.submit`, disabled until email is valid, the password is accepted, and both
   password fields match), and a **"Já tem uma conta? Entrar"** link (`signup.login`).
3. Tap the E-MAIL field and type a fresh address, e.g. `qa.new@example.com`.
4. Tap the SENHA field and type a password (see the strong-password-sheet hazard above).
5. Tap CONFIRMAR SENHA and type the **same** password.
6. Tap **"Criar Conta"** (`signup.submit`).
7. The request completes (`POST /api/v1/auth/mobile/signup`, ~4s tarpitted on the backend
   even on success) and the app lands directly on the authenticated **Início** tab with a
   top banner "Sessão conectada ao Rentivo." — no email verification step exists.

**Alternate A2a — passwords don't match.** At step 5, type a *different* string into
CONFIRMAR SENHA. The **"Criar Conta"** button stays disabled (grey) — there's no separate
inline "as senhas não coincidem" text while both fields still have content; the button
simply never activates. Fix by correcting either field to match; the scenario then
rejoins step 6.

**Alternate A2b — email already registered.** Complete steps 1–6 with an email that
already has an account. The server rejects the signup with `409` and the form shows the
mapped PT-BR message in the `signup.error` label instead of navigating away. Stay on the
Criar conta screen; correct the email and retry, or tap **"Entrar"** (`signup.login`) to
switch to Sign In instead.

### A3. Sign in — success

**Given** anonymous state, and an existing account with no MFA enrolled (e.g. seed one via
`POST /api/v1/auth/mobile/signup {"email":"qa.primary@example.com","password":"qa-primary-2026"}`
directly against the backend, once, ahead of time).

1. From **Boas-vindas** (A1), tap the E-MAIL field (`login.email`) and type
   `qa.primary@example.com`.
2. Tap the SENHA field (`login.password`) and type `qa-primary-2026`.
3. Tap **"Entrar"** (`login.submit`).
4. `POST /api/v1/auth/mobile/login` returns `200`; the app lands on **Início**,
   authenticated, with the "Sessão conectada ao Rentivo." banner.

### A4. Sign in — wrong password

**Given** an existing account.

1. Repeat A3 steps 1–3 with an incorrect password.
2. The button shows its loading state briefly — the backend deliberately delays every
   failed mobile login attempt by ~4 seconds regardless of the reason, so don't mistake
   the pause for a hang.
3. `POST /api/v1/auth/mobile/login` returns `401`; the form stays on Sign In and shows the
   server's PT-BR message in the `login.error` label (icon `exclamationmark.circle.fill`).
4. **Rate limit to be aware of when scripting repeated failures:** 4 attempts per minute
   per (email, IP) pair and 10 failures/minute per IP — space out retries in an automated
   run or you'll get a rate-limit response instead of the credential error you meant to
   test.

### A5. Sign out

**Given** authenticated state.

1. Tap the **Conta** tab.
2. Scroll to the bottom section and tap destructive **"Sair"**.
3. The button briefly reads "Saindo..." with a spinner; `POST /api/v1/auth/logout` fires
   (best-effort — the client goes anonymous either way), the keychain token and any
   downloaded files are purged, and the app returns to **Boas-vindas** (A1).

### A6. Session restore on relaunch

**Given** authenticated state (a token is stored in the Keychain).

1. Force-quit and relaunch the app (or, in the simulator,
   `xcrun simctl terminate <udid> br.com.rentivo.ios && xcrun simctl launch <udid> br.com.rentivo.ios`).
2. Briefly, `RootView` shows a centered spinner with the label "Restaurando sessão…".
3. `GET /api/v1/auth/session` is called with the stored token; on success the app lands
   directly on **Início**, still authenticated, with **no** re-login required.

**Alternate A6a — the stored token is no longer valid** (revoked, expired, or the account
was deleted elsewhere). Step 3's request returns `401`; the app purges the token and
downloaded files and lands on **Boas-vindas** (A1) instead — no error dialog, just a
silent drop to the login screen. If this happens while the user is *already* inside the
authenticated app (e.g. token expires mid-session), the same purge happens and a banner
reads "Sua sessão expirou." before returning to Sign In.

### A7. MFA challenge on login

**Given** an account with TOTP already enrolled (see [C5](#c5-two-factor-totp-setup) to set
one up first) belonging to an organization that enforces MFA, or that has enrolled TOTP
voluntarily.

1. Repeat A3 steps 1–3 with that account's correct password.
2. Instead of landing on Início, `POST /api/v1/auth/mobile/login` returns `202` and the
   form swaps to **Verificação em duas etapas** — subtitle "Confirme que é você para
   concluir a entrada."
3. If TOTP is offered: a field labeled "CÓDIGO DO APLICATIVO AUTENTICADOR"
   (`login.mfa.code`, numeric keyboard, placeholder "000000"). Tap it and type the current
   6-digit code from the account's authenticator secret.
4. Tap **"Confirmar"** (`login.mfa.submit`, stays disabled until the field is non-blank).
5. `POST /api/v1/auth/mfa/totp/verify` returns `200`; the app lands on **Início**,
   authenticated.

**Alternate A7a — use a recovery code instead.** At step 3, if both TOTP and recovery
codes are available, tap **"Usar código de recuperação"** (`login.mfa.recovery`) first —
the field relabels to "CÓDIGO DE RECUPERAÇÃO" (placeholder "XXXX-XXXX", plain keyboard).
Type one of the account's unused recovery codes and continue from step 4
(`POST /api/v1/auth/mfa/recovery/verify` instead). The same toggle flips back to
**"Usar código do aplicativo autenticador"** to switch back.

**Alternate A7b — use a passkey instead.** If the challenge offers a passkey, a blue
**"Usar chave de acesso"** button (`login.mfa.passkey`) appears above the code field.
Tapping it opens the system Face ID/Touch ID/passkey sheet (no app UI — nothing to
document beyond "the OS sheet appears"); completing it signs the user in directly.
Cancelling the system sheet is silently swallowed — you're left on the MFA screen with no
error shown, free to try again or use a different method.

**Alternate A7c — wrong code.** At step 4, submit an incorrect/expired code. The request
fails and the `login.mfa.error` label shows the rejection message; the field is *not*
auto-cleared — clear it yourself before retrying with a fresh code (TOTP codes are
30-second windows).

**Alternate A7d — go back.** From the MFA screen, tap link-style **"Voltar"**
(`login.mfa.cancel`) to return to Sign In with the previously typed email and password
preserved in the fields.

---

## B. Home dashboard (Início)

### B1. Empty portfolio

**Given** authenticated, and the account owns zero billings.

1. Land on / tap the **Início** tab.
2. `navigationTitle` "Início". Greeting "Olá!", subtitle "Seu portfólio está conectado ao
   Rentivo.", a "Saldo em atraso" row (R$ 0,00), the four summary cards (**Recebido**,
   **Despesas**, **Resultado**, **Taxa de recebimento** — all zero), then, in place of the
   usual "Atenção necessária"/"Ações rápidas"/"Próximas faturas" sections, a single
   **"Comece por aqui"** section with a card: headline "Nenhuma cobrança cadastrada
   ainda", body "Crie sua primeira cobrança recorrente na aba Cobranças para começar a
   acompanhar recebimentos, despesas e faturas por aqui."
3. Scroll to the bottom: **"Atividade recente"** section, text "Nenhuma atividade
   recente."

### B2. Populated portfolio

**Given** authenticated, with at least one billing that has bills (see [D1](#d1-create-a-billing)
and [E1](#e1-create-a-bill-draft) first).

1. Tap **Início**.
2. The four summary cards now show real totals (Recebido/Despesas/Resultado in R$, Taxa
   de recebimento as a %).
3. If any bill is overdue: an **"Atenção necessária"** card appears above quick actions,
   text "Há {N} fatura(s) em acompanhamento" + a **"Ver cobranças"** button that switches
   the tab to Cobranças (it does *not* open the create-billing sheet).
4. **"Ações rápidas"** section → **"Ver cobranças"** button, same tab-switch behavior.
5. **"Próximas faturas"** section lists up to 4 cards (draft/published/sent bills only —
   paid/cancelled/delayed bills don't appear here) — id `home.bill.card.{billID}` — each
   showing billing name, capitalized reference month, status badge, due date, total.
6. Tap one of those cards. It pushes straight to **Fatura** (`BillDetailView`, see
   [E2](#e2-bill-detail-composição-and-async-pdf-render)) — the same destination as
   opening the bill from its billing's detail screen.
7. Pull down from the top of the list to refresh; the four cards and the lists reload from
   the server.

**Alternate B2a** — if the portfolio has billings but zero bills anywhere, "Comece por
aqui" still does **not** show (that's gated purely on `billings.count == 0`, not on
whether any bill exists) — you'll see the normal cards (all zero) with "Ações rápidas"
and no "Próximas faturas" section.

---

## C. Account (Conta)

### C1. Set up personal PIX

**Given** authenticated. Doing this first unblocks bill generation for personal billings
that inherit PIX (see [D1](#d1-create-a-billing)).

1. Tap **Conta**. `navigationTitle` "Conta". Card "Sua conta" (app icon + your email).
   **Perfil** section: **"Dados e PIX"** (subtitle "Chave e dados do recebedor") and
   **"Segurança"** (subtitle "Senha, TOTP e chaves de acesso"). **Personalização e
   integrações** section: **"Chaves de integração"** and **"Aparência"**. **Sobre e
   suporte** section: **"Suporte"**, **"Política de privacidade"**, **"Termos de uso"**
   (all three open the system browser). Bottom: destructive **"Sair"** and **"Excluir
   conta"**.
2. Tap **"Dados e PIX"**. Full-screen wizard, title "Dados e PIX", "Etapa 1 de 3",
   **"Chave"** — card "Chave PIX pessoal" ("Escolha o tipo e informe a chave usada para
   receber pagamentos."), with **Tipo de chave** and **Chave PIX** fields.
3. Select **E-mail**, type `qa.primary@example.com`, and tap **"Continuar"**. Repeat the
   mask/validation check with CPF, CNPJ, Telefone and Aleatória; changing type with a
   non-empty key must show **"Alterar tipo de chave?"** before clearing it.
4. Step 2/3, **"Recebedor"** — card "Dados do recebedor" ("Estes dados acompanham a chave
   nas cobranças pessoais.") with **Nome do recebedor** and **Cidade** fields, and a
   second card **"Herança"**: "↝ Cobranças pessoais sem PIX próprio herdam esta
   configuração."
5. Fill both fields (e.g. `QA Primary` / `Sao Paulo` — the city field keeps what you type;
   the backend uppercases it when it generates the EMV payload). Tap **"Continuar"**.
6. Step 3/3, **"Revisão"** — card **"Conta"** (E-mail only; there is no Ambiente row),
   card **"PIX pessoal"** (Tipo da chave, masked Chave, Recebedor, Cidade). Tap **"Mostrar
   chave"** to inspect the normalized key, then **"Ocultar chave"**. Going back and
   returning to review must hide it again. The commit button reads **"Salvar PIX"**.
7. Tap **"Salvar PIX"**. `POST /api/v1/security/pix` returns `200`; wizard dismisses,
   banner "PIX pessoal atualizado."

**Alternate C1a — remove PIX.** On a previously configured account, tap the destructive
**"Remover chave"** action on step 1. Confirm **"Remover chave PIX?"** / **"Remover
chave"**. Removal is sent immediately and shows "PIX pessoal removido." An empty form is
never treated as removal. The action is absent with no persisted key and in viewer mode.

**Alternate C1b — load failure.** If the initial summary fetch fails (e.g. backend
unreachable), the Chave step shows an inline error and a **"Tentar novamente"** button
(`profile.pix.retry`) instead of the field; the commit button stays disabled (label
"Carregando perfil…") until the retry succeeds.

### C2. Theme editor

**Given** authenticated. This exact 5-step wizard is reused for three different targets —
personal (from Conta), a specific organization (from its detail screen's "Aparência da
organização"), and a specific billing (from its detail screen's "Aparência dos
documentos") — only the "Herança" copy differs by target.

1. Tap **Conta → "Aparência"**. Full-screen wizard, title "Aparência", "Etapa 1 de 5",
   **"Tipografia"** — two menu pickers, "Fonte de títulos" and "Fonte de texto" (10 font
   choices each: Montserrat, Roboto, Lora, Playfair Display, Open Sans, Source Sans 3,
   Merriweather, Raleway, Oswald, Nunito).
2. Pick fonts, tap **"Continuar"**.
3. Step 2/5, **"Cores principais"** — hex color fields **Primária**, **Primária clara**,
   **Secundária**.
4. Step 3/5, **"Texto e contraste"** — hex fields **Secundária escura**, **Texto**, **Texto
   de contraste**. An invalid hex string (not `#RRGGBB`) shows "Use uma cor hexadecimal no
   formato #RRGGBB." in the validation panel.
5. Step 4/5, **"Prévia"** — a "Herança" card (Responsável / Tema aplicado rows — the
   latter one of "Cobrança"/"Organização"/"Usuário"/"Padrão Rentivo"), then **"Prévia ao
   vivo"**: a live mock-invoice render that updates as you edit colors, plus any contrast
   warnings.
6. Step 5/5, **"Revisão"** — Herança card again, then **"Resumo do tema"**: Fonte de
   títulos, Fonte de texto, Cor primária with a color swatch, and a Configuração row summarizing what will
   happen ("Tema herdado" / "Personalização deste nível" / "Restaurar herança").
7. Tap **"Salvar tema"**. `PUT /api/v1/themes/user` returns `200`; banner "Aparência
   atualizada."

**Alternate C2a — restore inheritance.** On step 4 or 5, if a stored override already
exists at this level, a destructive **"Restaurar herança"** button is available; tapping
it arms a reset (button relabels to **"Manter personalização"**, an emerald "Restauração
selecionada" label appears). Completing the wizard from an armed reset changes the final
button to **"Restaurar tema"** and calls `DELETE` instead of `PUT`; banner "A aparência
padrão foi restaurada."

**Alternate C2b — read-only access.** If you can only view this level's theme (e.g.
viewing an organization's theme as a non-admin), every field is disabled and the final
button reads **"Concluir"**, just dismissing without saving.

### C3. Change password

**Given** authenticated.

1. Tap **Conta → Segurança → "Alterar senha"** (`security.password.change`). Full-screen
   screen, title "Alterar senha", with **Senha atual**, **Nova senha** and **Confirmar nova
   senha** visible together. There is no Etapa label, progress segment, Voltar or Continuar.
2. Toggle each independent reveal button and confirm its text and focus are preserved.
3. Type the current password and the same new password in both new-password fields.
4. Tap the sole fixed CTA **"Alterar senha"**. `POST /api/v1/security/change-password`
   returns `204`; banner "Senha alterada
   com sucesso." Sign out and back in with the new password to confirm it took effect (see
   [A5](#a5-sign-out)/[A3](#a3-sign-in--success)).

**Alternate C3a — wrong current password / mismatch.** An incorrect current password
surfaces the server's rejection inline under **"Não foi possível alterar"**; empty or
mismatched fields show their own message and focus the first invalid field.

### C4. Two-factor (TOTP) setup

**Given** authenticated, TOTP not yet enabled.

1. Tap **Conta → Segurança**. Under **"Autenticação em duas etapas"**: "Aplicativo
   autenticador: Desativado", button **"Configurar aplicativo autenticador"**.
2. Tap it. A sheet opens, title "Autenticador": "Configure seu autenticador" +
   instructions, the raw secret (monospaced, tap-and-hold to copy), a **Código do
   autenticador** field (numeric, 6 digits).
3. Compute the current code from the shown secret (any RFC 6238 generator) and type it.
4. Tap **"Confirmar"**. `POST /api/v1/security/totp/confirm` returns `200`; the sheet is
   replaced by the **Recuperação** sheet: "Códigos de recuperação" + 10 monospaced codes in
   a grid, **"Copiar códigos"**, a Share button. Tap **"Concluir"** to dismiss.
5. Back on Segurança: "Aplicativo autenticador: Ativado", a destructive **"Desativar"**
   button, and **"Gerar novos códigos de recuperação"**.

**Alternate C4a — wrong code.** At step 4, submit an incorrect/expired 6-digit code. The
sheet stays open and shows the rejection inline (id `security.totp.error`) instead of
dismissing — clear the field and retry with a fresh code (30-second windows).

**Alternate C4b — disable.** From Segurança with TOTP enabled, tap **"Desativar"**. An
alert appears: "Desativar autenticação em duas etapas" / "Confirme sua senha para
desativar o aplicativo autenticador." with a password field; buttons **"Desativar"**
(disabled until the password is non-blank) / **"Cancelar"**. Confirming calls
`POST /api/v1/security/totp/disable`.

**Alternate C4c — org-enforced, can't disable.** If any organization you belong to
enforces MFA and this is your only factor, the disable call is rejected with `409`
`mfa_required_by_organization` ("Você não pode desativar MFA enquanto pertence a uma
organização que exige MFA.") — the alert stays open showing that message; you cannot
disable until either the org relaxes the policy or you add a second factor.

**Alternate C4d — locked out of Segurança entirely.** If an organization newly enforces
MFA while you have none set up, `GET /api/v1/security` itself starts returning `403`
`mfa_setup_required`, and Segurança renders a dedicated recovery screen instead of the
normal list: `ContentUnavailableView` "Configuração obrigatória" / "Sua organização exige
autenticação em duas etapas. Configure o aplicativo autenticador para continuar usando o
Rentivo.", with a single button **"Configurar aplicativo autenticador"** that opens the
same enrollment sheet as step 2 above. Completing enrollment through it resolves the
lockout and the normal Segurança screen appears on next load. See [H6](#h6-mfa-policy-toggle)
for how to reproduce this from the organization side.

### C5. API keys (Chaves de integração)

**Given** authenticated.

1. Tap **Conta → "Chaves de integração"**. If empty: title "Nenhuma chave de integração" /
   "Crie uma chave para conectar outro serviço ao Rentivo e escolher o que ele pode
   acessar." + action **"Criar chave"**. In viewer mode the message is "Não há chaves de
   integração nesta conta." and no action is shown; otherwise use the toolbar **"+"**
   (`api-key.create`).
2. Full-screen wizard, "Etapa 1 de 4", **"Identificação"** — one **Nome** field.
3. Type a name (e.g. `Sim test key`). Tap **"Continuar"**.
4. Step 2/4, **"Escopos e validade"** — **"Escopos seguros"** contains a toggle per
   available scope (loads async; a **"Nenhum escopo
   de integração está disponível."** message + retry appears if the fetch fails or returns
   empty). Turn on at least one, e.g. **"Ler cobranças"**. The **"Validade da chave"**
   section below contains the **"Expira em"** date picker; editing shows it read-only.
5. Step 3/4, **"Acessos"** — a toggle per workspace (Pessoal + each organization you belong
   to). Turn on **Pessoal**.
6. Step 4/4, **"Revisão"** — Nome, Escopos (count), Acessos (count), Expira em. Commit
   **"Criar chave"**.
7. Tap it. `POST /api/v1/api-keys` returns `201`; a **Segredo da chave** sheet appears:
   "Copie agora — Este segredo não será exibido novamente.", the secret (monospaced,
   selectable), **"Copiar segredo"**, Share button, **"Já copiei"** to dismiss — this is
   the only time the app ever shows the full secret.
8. Back on the list, the new key's card shows its name, a `hint` (partial secret, e.g.
   `rntv-v1-abcd••••ef`), the chosen scopes, dates, and access count, plus **"Editar"** /
   **"Revogar"** buttons.

**Alternate C5a — revoke.** Tap **"Revogar"** on a key. Confirmation dialog: "Revogar esta
chave de integração?" / "Qualquer integração usando \"{name}\" perderá acesso
imediatamente. Esta ação não pode ser desfeita." Buttons **"Revogar chave"** (destructive)
/ **"Cancelar"**. Confirming calls `DELETE /api/v1/api-keys/{id}` (`204`); banner "Chave
revogada." and the card shows a "Revogada" badge, both action buttons gone.

**Alternate C5b — edit.** Tap **"Editar"** on a key. Same four-step wizard; expiration is
read-only in step 2, while scopes/access can change. Commit label "Salvar
chave"; `PATCH /api/v1/api-keys/{id}`.

### C6. Account deletion

**Given** authenticated, not the sole admin of a staffed organization.

1. Tap **Conta**, scroll to the bottom, tap destructive **"Excluir conta"**.
2. Native alert: "Excluir sua conta?" / "Essa ação é permanente. Suas cobranças e seus
   dados pessoais serão excluídos." A **Senha** field; buttons **"Cancelar"** / **"Excluir
   conta"** (disabled until the password is accepted).
3. Type your password, tap **"Excluir conta"**. `POST /api/v1/security/delete-account`
   signs you out and returns to **Boas-vindas**.

**Alternate C6a — blocked as sole org admin.** If you're the only admin of an organization
with other members, the **"Excluir conta"** button is disabled outright and a coral note
explains: "Transfira a administração das organizações em que você é o único administrador
antes de excluir a conta." — resolve that in [H5](#h5-organization-members-role-change-and-removal)
first (promote another member to admin) before this flow is available.

---

## D. Billings (Cobranças)

### D1. Create a billing

**Given** authenticated, on the **Cobranças** tab.

1. If the list is empty: `navigationTitle` "Cobranças", a search bar (placeholder "Buscar
   por nome, responsável ou descri…"), a `ContentUnavailableView` "Nenhuma cobrança ainda"
   / "Crie sua primeira cobrança para começar a gerar faturas." with an action button
   **"Nova cobrança"**. If the list is non-empty instead, use the **"+"** toolbar button
   (`billing.create`) in the top-right.
2. Tap **"Nova cobrança"**. A full-screen wizard cover opens: title "Nova cobrança", X
   close (top-left), "Etapa 1 de 5", heading **"Essenciais"**, card "Identificação" —
   "Defina a cobrança e seu responsável." — with a **Nome** field, a **Descrição** field
   (multiline), and (create-only) an owner picker defaulted to **"Pessoal"**.
3. Tap **Nome**, type e.g. `Apartamento 202`.
4. Tap **Descrição**, type e.g. `Aluguel e encargos apartamento 202`.
5. Tap **"Continuar"**.
6. Step 2/5, **"Itens recorrentes"** — card subtitle "Use valor zero para itens variáveis
   que serão preenchidos em cada fatura.", a green **"+ Adicionar item"** link, and
   "Subtotal fixo R$ 0,00".
7. Tap **"Adicionar item"**. A row **"Item 1"** appears with a red **"Remover"** button, a
   **Descrição do item** field, a **Fixo**/**Variável** segmented control (defaults to
   Fixo), and — only while Fixo is selected — a currency field.
8. Tap the description field, type `Aluguel`. Tap the currency field, type `120000` (the
   field reads digits right-to-left as cents, so this becomes R$ 1.200,00 — type the exact
   digit count you want the final amount to have).
9. Tap **"Adicionar item"** again for a second row ("Item 2"); this time tap **Variável**
   in its segmented control — the currency field disappears entirely for a variable item
   (its amount is filled in per-bill later, not here).
10. Tap **"Continuar"** (now showing **"Voltar"** on the left and **"Continuar"** on the
    right, both at the bottom bar — from here on every step keeps this two-button layout
    until the final step).
11. Step 3/5, **"PIX"** — card "Escolha se esta cobrança herda o PIX do responsável.",
    toggle **"Usar PIX personalizado"** (off by default), and, while off, a note "↝
    Herdando o PIX do responsável".
12. Leave it off to inherit (requires the owner to already have PIX configured — see
    [C1](#c1-set-up-personal-pix) — or the resulting billing will show "PIX pendente" and
    block bill creation, which is a valid thing to verify deliberately). Tap **"Continuar"**.
13. Step 4/5, **"Comunicação"** — two cards, **"Destinatários"** and **"Responder para"**,
    each with their own "+ Adicionar…" link.
14. Tap **"Adicionar destinatário"**. A row **"Destinatário 1"** appears with **"Remover"**,
    a **Nome do destinatário** field, and an **E-mail do destinatário** field. Fill both
    (e.g. `Maria Inquilina` / `maria.inquilina@example.com`).
15. Leave "Responder para" empty (optional) and tap **"Continuar"**.
16. Step 5/5, **"Revisão"** — card "Revise sua cobrança" listing Nome, Responsável, Itens
    (count), Subtotal fixo, PIX ("Herdado"/"Próprio"), Destinatários (count), Responder
    para (count). The final button reads **"Criar cobrança"** (would read "Salvar
    cobrança" if editing).
17. Tap **"Criar cobrança"**. `POST /api/v1/billings` returns `201`; the wizard dismisses,
    a top banner reads "Cobrança criada.", and the new card appears in the list.

**Alternate D1a — missing required fields.** Leaving Nome blank (or leaving zero items) and
tapping Continuar keeps you on the same step and reveals a **"Revise os campos"** panel
below the card, e.g. "Informe o nome da cobrança." or "Adicione ao menos um item
recorrente." — fix the field(s) named and retry.

**Alternate D1b — custom PIX.** At step 3, toggle **"Usar PIX personalizado"** on. Three
fields plus the selector appear: **Tipo de chave**, **Chave PIX própria**, **Nome do
recebedor**, **Cidade do recebedor**. Masks and messages match C1, and the review includes
the type plus a masked/revealable key. A billing with its own
complete PIX shows "PIX próprio" everywhere instead of "PIX pendente"/"PIX herdado", and
can generate bills immediately regardless of the owner's personal PIX state.

**Alternate D1c — organization owner.** At step 1, if the account belongs to any
organization, the owner picker offers it alongside "Pessoal"; organizations only load
after an async fetch, so the wizard's primary button is disabled (label "Carregando
responsáveis…") until that completes. Choosing an organization here is only available on
**create** — the owner can't be changed later from the edit wizard.

**Alternate D1d — discard.** From any step past the first, tap the **X** (top-left). A
confirmation dialog appears: "Descartar alterações?" / "As alterações não salvas serão
perdidas.", buttons **"Descartar"** (destructive, dismisses without saving) / **"Continuar
editando"** (cancel, stays on the current step). On step 1 exactly, the X dismisses
immediately with no confirmation.

### D2. Billing list — filter and search

**Given** at least one personal and one organization-owned billing exist.

1. On **Cobranças**, the segmented control under the search bar reads **"Todas"** /
   **"Pessoais"** / **"Organizações"** — defaults to Todas.
2. Tap **"Pessoais"**: only billings with `owner.type == user` remain.
3. Tap **"Organizações"**: only org-owned billings remain (if you have none, the segment
   shows the same empty state as D1 step 1, minus the "Nova cobrança" action if you lack
   create permission anywhere).
4. Tap the search bar and type part of a billing's name, owner, or description. The list
   filters live; if nothing matches, the system's standard "No results for '…'" view
   appears in place of the cards.

### D3. Billing detail

**Given** at least one billing exists.

1. From the list, tap a billing card. Pushes to **Detalhes** (inline title).
2. If you can edit: toolbar **"Editar"** — opens the same 5-step wizard as D1, pre-filled,
   titled "Editar cobrança" (owner picker absent — see D1c).
3. Header card: name, owner `Label`, PIX status/subtotal row.
4. **"Itens recorrentes"** card: every item with its type and amount.
5. **"Faturas"** section: when empty, a reusable inline block says "Nenhuma fatura
   gerada". With PIX ready it adds "Gere a primeira fatura desta cobrança." and
   **"Gerar fatura"**. With PIX pending it adds "Configure os dados do PIX antes de gerar
   a primeira fatura." and **"Configurar PIX"**, which opens the billing wizard directly
   on the PIX step. Without create permission it says "Ainda não há faturas nesta
   cobrança." and omits the action. Existing bills list as cards
   (id `bill.card.{billID}`) → pushes to [E2](#e2-bill-detail-composição-and-async-pdf-render).
6. **"Resumo financeiro"** card: Recebido / Despesas / Resultado.
7. **"Operações"** section — see [G](#g-billing-operations-despesas-arquivos-exportar).
8. **"Destinatários"** card: recipients and reply-to contacts from the wizard.
9. If permitted: blue **"Aparência dos documentos"** button → billing-scoped theme editor
   (same wizard as [C2](#c2-theme-editor), different `target`).
10. If permitted: destructive **"Excluir cobrança"** at the bottom.

### D4. Edit a billing

**Given** a billing you can edit.

1. From D3, tap **"Editar"**.
2. Walk the same 5 steps as D1 (owner picker absent), change a field — e.g. tap Nome and
   append text.
3. On the review step, the commit button reads **"Salvar cobrança"**.
4. Tap it. `PATCH /api/v1/billings/{id}` returns `200`; wizard dismisses, banner
   "Cobrança atualizada.", detail screen reflects the change.

### D5. Delete a billing

**Given** a billing you can delete (throwaway data recommended — this cascades).

1. From D3, scroll to the bottom and tap destructive **"Excluir cobrança"**.
2. A confirmation dialog appears: title "Excluir esta cobrança?", message "Faturas,
   despesas e arquivos desta cobrança também serão removidos." — buttons **"Excluir
   cobrança"** (destructive) / **"Cancelar"**.
3. Tap **"Excluir cobrança"**. `DELETE /api/v1/billings/{id}` returns `204`; a banner reads
   "Cobrança excluída." and the screen pops back to the list, which no longer shows the
   billing.

---

## E. Bills (Faturas)

### E1. Create a bill (draft)

**Given** a billing with complete PIX (own or inherited — see [C1](#c1-set-up-personal-pix)
/ [D1b](#d1-create-a-billing)) so the **"+"** on its detail screen is enabled.

1. From [D3](#d3-billing-detail), tap the green **"+"** (accessibility label "Gerar
   fatura") next to "Faturas". Full-screen wizard, title "Gerar fatura", "Etapa 1 de 5",
   **"Competência"** — card with a month menu (defaults to the current month) and a
   **"Ano: {year}"** stepper (range 2024–2035; note the year renders with a PT-BR
   thousands separator, e.g. "2.026" — cosmetic only).
2. Tap **"Continuar"**.
3. Step 2/5, **"Vencimento"** — a toggle **"Definir vencimento"** (on by default, an
   auto-computed due date already filled in) and, while on, a **Data de vencimento**
   `DatePicker`. Leave as-is or adjust. Tap **"Continuar"**.
4. Step 3/5, **"Itens"** — **"Itens fixos"** card (the billing's fixed items, read-only,
   description/amount inherited from the billing since this is a new bill), **"Itens
   variáveis"** card (empty here unless the billing has variable items — each shows an
   editable amount field), **"Itens extras"** card with **"+ Adicionar item extra"**. Tap
   **"Continuar"**.
5. Step 4/5, **"Observações"** — an optional multiline notes field. Tap **"Continuar"**.
6. Step 5/5, **"Revisar fatura"** — card **"Resumo"**: Competência (lowercase, e.g.
   "agosto de 2026" — note this is *not* capitalized, unlike the resulting bill card's
   title, which reads "Agosto De 2026" with a stray capital "De" — a cosmetic
   inconsistency worth knowing when asserting exact text), Vencimento, Itens (count),
   Total. Commit button **"Gerar fatura"**.
7. Tap it. `POST /api/v1/billings/{id}/bills` returns `201`; wizard dismisses, banner
   "Fatura criada como rascunho.", new bill card appears under Faturas with a grey
   **"Rascunho"** badge. The worker renders its PDF asynchronously in the background —
   see [E2](#e2-bill-detail-composição-and-async-pdf-render).

**Alternate E1a — variable items.** If the billing has a variable-type item, step 3 shows
it under "Itens variáveis" with an editable currency field (starts at R$ 0,00) — fill in
the actual amount for this billing cycle before continuing.

### E2. Bill detail: composição and async PDF render

**Given** a bill exists.

1. Tap a bill card (from billing detail's Faturas list, or Home's "Próximas faturas", or
   the search results). Pushes to **Fatura** (inline title).
2. Header card: billing name, capitalized reference month title (e.g. "Agosto De 2026" —
   see the E1 note above), a status badge, total, "Vencimento: {date}", and — once paid —
   "Pago em {date}" in emerald.
3. **"Composição"** card: every line item with its kind label and amount.
4. **"Ciclo da fatura"** section: one full-width button per status transition the server
   currently allows (see [E3](#e3-lifecycle-draft--published--sent--paid)); a caption
   "Status atualizado em {date}." underneath.
5. **"Documento"** section: while the worker hasn't finished rendering yet, a
   "Renderizando…" row with a spinner appears here and **"Abrir fatura em PDF"** stays
   disabled; once done (usually within a couple seconds against the local dev stack —
   watch worker logs for `pdf_render_succeeded` if you want to confirm exactly when), the
   spinner disappears and the button activates. **"Regenerar documento"** is available
   once a document exists.

**Alternate E2a — render failure.** If PDF generation fails server-side, the row reads
"Falha no PDF" instead of "Renderizando…", and the open/download button stays disabled —
use "Regenerar documento" to retry once available, or investigate worker logs.

### E3. Lifecycle: draft → published → sent → paid

**Given** a draft bill.

1. On the bill detail's **"Ciclo da fatura"** section, tap **"Publicar fatura"**
   (`bill.transition.published`). `POST .../transitions` returns `200` (no confirmation
   needed for this one); banner "Fatura marcada como publicada."; badge changes to
   **"Publicada"**; button set updates to **"Marcar como enviada"**, **"Marcar como
   pago"**, destructive **"Voltar para rascunho"**, destructive **"Cancelar fatura"**.
2. Tap **"Marcar como enviada"** (`bill.transition.sent`). `200`; banner "Fatura marcada
   como enviada."; badge **"Enviada"**; buttons become **"Marcar como pago"**, **"Marcar
   pagamento atrasado"**, destructive **"Voltar para publicado"**, destructive **"Cancelar
   fatura"**.
3. Tap **"Marcar como pago"** (`bill.transition.paid`). This one **requires
   confirmation**: a popover appears — "Confirme a alteração de status desta fatura." with
   a repeated **"Marcar como pago"** button inside it. Tap that button (not the original
   one behind it) to actually confirm.
4. `200`; banner "Fatura marcada como paga."; badge **"Paga"** (emerald); header shows
   "Pago em {date}"; buttons reduce to destructive **"Reverter pagamento"** and destructive
   **"Cancelar fatura"** — both also require the same confirmation-popover pattern as step
   3. From here, "Documento" gains an **"Abrir recibo"** button next to "Regenerar
   documento", and the **"Comprovantes"**/**"Comunicações"** sections and **"Enviar
   comunicação"**/**"Excluir fatura"** buttons appear below (they exist earlier in the
   lifecycle too, this is just when this walkthrough first scrolled down far enough to
   confirm them).

**Alternate E3a — delayed payment.** From "Enviada", tapping **"Marcar pagamento
atrasado"** (`bill.transition.delayed_payment`) instead sets the badge to **"Pagamento
atrasado"** — this is the status Home's "Atenção necessária" card counts (see
[B2](#b2-populated-portfolio)).

**Alternate E3b — cancel.** **"Cancelar fatura"** (`bill.transition.cancelled`) is
available from every non-final state, styled coral/destructive, and requires the same
confirmation-popover pattern. Once cancelled, the badge reads **"Cancelada"** and — per
the reference — this is a terminal state: the "Ciclo da fatura" section then shows only
"Esta fatura está em um estado final." with no further transition buttons.

**Alternate E3c — revert a step.** Every non-terminal state offers a destructive "Voltar
para {previous status}" button that walks the lifecycle backwards one step at a time
(also confirmation-gated) — useful for correcting a mis-click without deleting and
recreating the bill.

### E4. Open, download, and share the invoice PDF

**Given** a bill whose PDF has finished rendering (see E2).

1. Tap **"Abrir fatura em PDF"**. `GET .../invoice` returns `200`; a **Prévia** sheet
   opens: file icon, filename (`fatura-{bill-uuid}.pdf`), text "Arquivo baixado do
   Rentivo.", a blue **"Compartilhar ou salvar arquivo"** `ShareLink` button.
2. Tap **"Compartilhar ou salvar arquivo"** to invoke the system share sheet (Save to
   Files, AirDrop, etc.) if you want to persist the file for a later flow (e.g. as
   attachment test data in [G2](#g2-attachments)).
3. Tap **"Concluir"** (top-right) to dismiss back to the bill detail.

**Alternate E4a — recibo.** Once a bill is **Paga**, an **"Abrir recibo"** button appears
next to "Regenerar documento" and works identically (`GET .../recibo`), producing a
`recibo-*.pdf` in the same Prévia sheet.

### E5. Edit a draft bill

**Given** a bill in **draft** status only — editing is unavailable once published.

1. From bill detail, tap toolbar **"Editar"**. Same 5-step wizard as E1, opens as
   "Editar fatura".
2. Step 1 (Competência) is entirely disabled with the note "A competência não pode ser
   alterada depois que a fatura é criada." — you cannot change the reference month.
3. On step 3 (Itens), fixed/variable line items are now editable (not read-only as they
   were on create), and you can add/remove extras.
4. Change something (e.g. an extra item's amount), walk to the review step. Commit button
   reads **"Salvar fatura"**.
5. Tap it. `PATCH .../bills/{id}` returns `200`; banner "Fatura atualizada."

### E6. Regenerate the document

**Given** a bill with an existing PDF.

1. From bill detail's "Documento" section, tap **"Regenerar documento"**.
2. `POST .../regenerate` returns `202`; the render-status row shows "Renderizando…" again
   briefly while the worker re-renders, then clears. Useful after editing line items or
   after a theme change that should be reflected in the PDF.

### E7. Receipts (comprovantes)

**Given** a bill exists (any status).

1. Scroll to **"Comprovantes"**. If empty: "Nenhum comprovante anexado." Tap **"+
   Adicionar comprovante"**.
2. A confirmation dialog (titled "Adicionar comprovante") lists source options —
   **"Arquivos"**, **"Fotos"** (and **"Câmera"** on a real device, but the Simulator has no
   camera hardware so it's omitted here), plus **"Cancelar"**.
3. Tap **"Fotos"**. The system Photos picker opens (with the standard "Rentivo pode
   acessar apenas os itens que você seleciona" limited-access banner on a fresh grant).
   Tap any photo to select it — selection uploads immediately, no separate confirm step.
4. `POST .../receipts` (multipart) returns `201`; the picker dismisses and the row count
   updates, e.g. "1 comprovante".
5. Each receipt row has a **"⋯"** menu (accessibility label "Mais opções para {name}") with
   **"Abrir"** (same Prévia/download sheet as E4) and, if permitted, destructive
   **"Excluir"**.

**Alternate E7a — delete.** Tap **"Excluir"** in a receipt's menu. Confirmation dialog:
"Excluir este comprovante?" / "O comprovante será removido permanentemente desta fatura."
— buttons **"Excluir comprovante"** (destructive) / **"Cancelar"**. Confirming calls
`DELETE .../receipts/{id}` (`204`).

**Alternate E7b — reorder.** With 2+ receipts and reorder permission, a **"Inverter
ordem"** button appears above the list — reverses the display order via
`PUT .../receipt-order`.

**Alternate E7c — rejected uploads.** A 0-byte file, a file exceeding the configured size
cap, or a file/photo the app can't decode all fail client-side with a top banner message
instead of an inline error — watch for, respectively, "O arquivo está vazio. Escolha outro
e tente novamente.", "O comprovante é maior que {size}. Escolha um arquivo menor e tente
novamente.", or "Não foi possível abrir o arquivo. Escolha outro e tente novamente." /
"Não foi possível preparar a foto. Tire outra foto ou escolha um arquivo." / "Não foi
possível abrir a foto. Escolha outra e tente novamente."

> **Fixed while testing this flow (commit `6cfc0a2d`):** attaching a receipt photo shot at
> a typical phone-camera resolution (e.g. 4032x3024) used to balloon the invoice PDF that
> merges it in to ~29MB — the image was embedded at source resolution and losslessly
> (PNG) instead of being downscaled to print size and JPEG-compressed. A PDF that size
> risks silently failing to send in [F1](#f1-composer-wizard-and-send), since email
> providers commonly cap attachments around 25MB. Now downscaled to print DPI + JPEG
> quality 85 before embedding — the same test case now produces ~50KB.

### E8. Delete a bill

**Given** a bill you can delete (any status, though deleting a paid bill destroys its
payment record — use throwaway data).

1. From bill detail, scroll to the bottom, tap destructive **"Excluir fatura"**.
2. Confirmation dialog: "Excluir esta fatura?" (no message body) — buttons **"Excluir
   fatura"** (destructive) / **"Cancelar"**.
3. Tap **"Excluir fatura"**. `DELETE .../bills/{id}` returns `204`; screen pops back to the
   billing detail, whose Faturas list no longer shows the bill.

---

## F. Communications

### F1. Composer wizard and send

**Given** a billing with at least one recipient (see [D1](#d1-create-a-billing)) and a bill
whose PDF has finished rendering.

1. From bill detail, tap **"Enviar comunicação"**. With one available document the
   full-screen wizard starts at **"Destinatários"**, "Etapa 1 de 3". When both invoice
   and receipt are available, it starts at **"O que enviar"**, "Etapa 1 de 4", with a
   **Fatura** / **Recibo de pagamento** picker. There is no read-only Canal step.
2. **"Destinatários"** — subtitle "Cada destinatário recebe um e-mail separado
   com o PDF da fatura anexado.", one toggle per recipient configured on the billing (on
   by default). Tap **"Continuar"**.
3. **"Mensagem"** — subtitle "Personalize o texto e confira a prévia antes de enviar.",
   editable **Assunto** and **Mensagem** fields, and an **"Inserir dado"** menu for the five
   supported variables. Confirm the live counter reads "{n} de 4.096 caracteres" and the
   expanded **"Prévia da mensagem"** substitutes recipient/billing values and renders
   Markdown without executing HTML. An unknown `{{token}}` blocks advancement with the
   approved validation copy.
4. **"Revisar envio"** — rows Tipo, Destinatários with its unit, and Anexo, followed by
   the same rendered preview. The **"Salvar como modelo para próximos envios"** toggle is
   off by default; when enabled it offers **"Somente nesta cobrança"** and the applicable
   owner scope, and explains that subject and message replace the current model. There is
   no separate Modelo step.
6. Tap it. `POST /api/v1/billings/{id}/communications/send` returns `202`; wizard
   dismisses, banner "Envio iniciado. Acompanhe o status em Comunicações."; the detail is
   refreshed immediately and a new **"Na fila"** row appears under **"Comunicações"**.

**Alternate F1a — no recipients configured.** If the billing has none, step 2 shows "Nenhum
destinatário cadastrado. Adicione destinatários na cobrança antes de enviar." instead of
toggles, and there's nothing to advance with — go add one via
[D4](#d4-edit-a-billing) first.

**Alternate F1b — PDF still rendering.** If the invoice/recibo hasn't finished rendering
yet, step 5 shows "Aguarde a geração do PDF antes de enviar." and the send button stays
disabled.

**Alternate F1c — recibo channel.** With a **paid** bill, switch step 1's segment to
**Recibo de pagamento** — everything else follows the same shape, attaching the recibo PDF
instead.

### F2. Verify the rendered email

**Given** F1 was completed against the local dev stack (`RENTIVO_EMAIL_BACKEND=local`).

1. The worker writes every outgoing email as a `.eml` file instead of actually sending it.
   Find the newest one:
   `docker compose ... exec worker sh -c 'ls -t /app/outbox | head -1'`.
2. Inspect it (`docker compose ... exec worker cat /app/outbox/<file>.eml`, or parse with
   Python's `email` module). Confirm:
   - **Subject** matches the template with `{{unidade}}`/`{{mes}}` substituted, e.g.
     "Cobrança Apartamento 202 — agosto de 2026".
   - **To** matches the recipient's email.
   - **Body** (`text/plain` part) has every template variable substituted — recipient
     name, unit, month — and ends with a "Enviado por {sender email} através do Rentivo."
     footer.
   - A PDF attachment is present (`application/pdf` part) named `fatura-{month}.pdf` /
     `recibo-{month}.pdf`, and — since the [E7 fix](#e7-receipts-comprovantes) above — a
     reasonable size even if the bill has photo receipts attached.

---

## G. Billing operations (Despesas, Arquivos, Exportar)

These live under **"Operações"** on [billing detail](#d3-billing-detail) — up to three
rows depending on your permissions: **"Despesas"**, **"Arquivos"**, **"Exportar dados"**.

### G1. Expenses

**Given** a billing.

1. From billing detail, tap **"Operações" → "Despesas"**. `navigationTitle` "Despesas". If
   empty and editable: "Nenhuma despesa registrada" / "Registre a primeira despesa para
   acompanhar os custos desta cobrança." with inline **"Adicionar despesa"**. In viewer
   mode the description is "Não há despesas registradas nesta cobrança." and there is no
   CTA. Otherwise a
   section header "{N} despesa(s)" and one row per expense (description, amount, category
   icon+label).
2. Tap inline or toolbar **"Adicionar despesa"**. Full-screen wizard, "Etapa 1 de 3", **"Detalhes"** — a
   **Descrição** field and a **Categoria** menu (**IPTU**, **Condomínio**, **Manutenção**,
   **Seguro**, **Outros**). Fill both, tap **"Continuar"**.
3. Step 2/3, **"Valor e data"** — **Valor** and **Data** fields. Type `1000` and confirm
   the value displays **R$ 10,00** while editing, then tap **"Continuar"**.
4. Step 3/3, **"Revisar despesa"** — card **"Resumo"**: Descrição, Categoria, Valor, Data.
   Commit **"Salvar despesa"**.
5. Tap it. `POST .../expenses` returns `201`; wizard dismisses, new row appears in the
   list, and billing detail's "Resumo financeiro" → Despesas total updates.

**Alternate G1a — delete.** Swipe left on a row, tap the revealed destructive **"Excluir"**.
Confirmation dialog: "Excluir esta despesa?" / "A despesa será removida permanentemente do
registro desta cobrança." — buttons **"Excluir despesa"** (destructive) / **"Cancelar"**.
Confirming calls `DELETE .../expenses/{id}` (`204`).

**Alternate G1b — validation.** Leaving the description blank or the amount at zero and
tapping Continuar keeps you on the step; messages: "Informe uma descrição válida para a
despesa." / "Informe um valor maior que zero."

### G2. Attachments

**Given** a billing.

1. From billing detail, tap **"Operações" → "Arquivos"**. `navigationTitle` "Arquivos".
   If editable and empty: "Nenhum arquivo adicionado" / "Adicione documentos ou imagens
   para encontrá-los junto desta cobrança." with inline **"Adicionar arquivo"**. In viewer
   mode: "Não há arquivos nesta cobrança." and no CTA. Otherwise "{N} arquivo(s)" header
   and one row per file (name, byte count).
2. Tap toolbar **"Adicionar"** (disabled while an upload is already in flight). Opens the
   system `fileImporter` filtered to PDF/image types. Pick a file (e.g. the invoice PDF
   you saved in [E4](#e4-open-download-and-share-the-invoice-pdf)).
3. `POST .../attachments` (multipart) returns `201`; success toast "Arquivo enviado.",
   file appears in the list.
4. Tap the download icon (borderless, right side of a row) to open the same
   Prévia/download sheet documented in [E4](#e4-open-download-and-share-the-invoice-pdf)
   (`GET .../attachments/{id}`).

**Alternate G2a — delete.** Swipe left, tap **"Excluir"**. Dialog: "Excluir este arquivo?"
/ "O arquivo será removido permanentemente e não poderá ser recuperado." — buttons
**"Excluir arquivo"** (destructive) / **"Cancelar"**. `DELETE .../attachments/{id}` →
`204`.

### G3. Export data

**Given** a billing.

1. From billing detail, tap **"Operações" → "Exportar dados"**. Full-screen wizard,
   "Etapa 1 de 3", **"Formato"** — segmented **CSV** / **XLSX** picker.
2. Pick a format, tap **"Continuar"**.
3. Step 2/3, **"Conteúdo"** — a static list of what's included (currently just
   **"Faturas"**, no choice to make). Tap **"Continuar"**.
4. Step 3/3, **"Revisar exportação"** — card **"Resumo"**: Formato, Conteúdo. Commit
   **"Solicitar exportação"**.
5. Tap it. `POST .../exports` returns `202`; wizard dismisses, banner "Seu arquivo {FORMAT}
   está sendo preparado. Você o receberá no e-mail da sua conta." The worker generates the file out-of-band and emails it — check the
   outbox the same way as [F2](#f2-verify-the-rendered-email) for an `export_ready` event
   and an `.xlsx`/`.csv` attachment.

---

## H. Organizations (Organizações)

**Given** for this whole section: two accounts — a primary account that will become the
org admin, and a second account (create it fresh via
`POST /api/v1/auth/mobile/signup {"email":"...", "password":"..."}` — don't reuse an
account created much earlier in a long-lived dev-stack session; restarting the `api`
container mid-session appears to break email-based lookup — login, invite-by-email — for
accounts created before the restart even though the row is intact in the DB, while
freshly-created accounts work fine. Harmless for a real (non-restarted) backend, but worth
knowing if your manual-test session spans a backend restart).

### H1. Create an organization

**Given** authenticated, on the **Organizações** tab, zero organizations and zero pending
invitations.

1. Empty state: `ContentUnavailableView` "Nenhuma organização ainda" / "Organizações
   reúnem cobranças e membros sob papéis e permissões compartilhados. Crie uma para
   colaborar com sua equipe.", action **"Criar organização"**.
2. Tap it (or the toolbar **"Criar"** if the list isn't empty). Full-screen wizard, "Etapa
   1 de 3", **"Organização"** — card "Identidade da organização" ("Dê um nome claro para o
   espaço compartilhado."), one **Nome** field.
3. Type a name (e.g. `Imobiliária QA Test`). Tap **"Continuar"**.
4. Step 2/3, **"Recebimento PIX"** — card "Recebimento PIX" ("Escolha se a organização
   terá dados PIX próprios."), `Toggle` **"Usar PIX da organização"** (off by default,
   note "Sem PIX próprio. Cobranças podem usar o PIX pessoal do responsável."). Leave off,
   tap **"Continuar"**.
5. Step 3/3, **"Revisão"**. Commit **"Criar organização"**.
6. Tap it. `POST /api/v1/organizations` returns `201`; wizard dismisses, banner
   "Organização criada.", card appears in the list: name, **"Administrador"** role,
   **"1 membro"**, **"0 cobranças"**, **"MFA opcional"**.

**Alternate H1a — organization PIX.** At step 2, toggling **"Usar PIX da organização"** on
reveals the same four PIX fields as the billing wizard (Tipo de chave/Chave/Nome do
recebedor/Cidade), with the same masks, validation and masked/revealable review.

### H2. Organization detail

**Given** an organization you administer.

1. Tap its card from the list. `navigationTitle` "Organização". Toolbar **"Editar"** (if
   you can manage) → same 3-step wizard as H1, pre-filled, titled "Editar organização".
2. Header card: name, `Label` role (icon `person.badge.shield.checkmark`), `Label`
   **"PIX pendente"**/**"PIX configurado"**.
3. **"Membros"** section: a **person+** icon button (top-right of the section, opens
   [H3](#h3-invite-a-member)); one row per member — email, **"você"** badge if it's you,
   role caption; you (as admin) get a crown icon; other admins get a crown too (read-only
   to you unless you can manage); other non-admin members you can manage get a **"⋯"**
   menu offering every other role plus destructive **"Remover"**.
4. **"Política de segurança"** section: row "Autenticação em duas etapas" +
   **"Obrigatória para membros"**/**"Opcional"** caption, trailing `Toggle` (tapping opens
   a confirmation dialog rather than flipping directly — see [H6](#h6-mfa-policy-toggle)).
5. **"Cobranças"** section: org-owned billing names, or "Nenhuma cobrança pertence a esta
   organização."; if you have transferable personal billings, a **"Transferir cobrança
   para cá"** menu listing them.
6. Blue **"Aparência da organização"** button → the same theme editor wizard as
   [C2](#c2-theme-editor), scoped to this organization.
7. If you can manage: destructive **"Excluir organização"** at the bottom → see
   [H9](#h9-delete-organization-guard).

### H3. Invite a member

**Given** you administer an organization, and a second account exists (its email, not
logged in on this device).

1. From H2, tap the **person+** icon next to "Membros". Full-screen wizard, "Etapa 1 de
   3", **"Pessoa"** — card "Quem você quer convidar?" ("O convite será enviado para este
   endereço."), one **E-mail** field.
2. Type the invitee's email. Tap **"Continuar"**.

   **Alternate H3a — blank email.** Tapping Continuar with the field empty keeps you on
   this step and shows "Informe o e-mail." under the field.

3. Step 2/3, **"Nível de acesso"** — card "Escolha o nível de acesso" ("Escolha o que esta
   pessoa poderá fazer. Você pode alterar o nível de acesso depois."), three full cards
   (**Administrador**/**Gerente**/**Visualizador**) with their capability descriptions,
   checkmark and accessible selected state; Visualizador is the default. Then a note — "A autenticação multifator é
   opcional nesta organização." if the org doesn't enforce MFA, or a coral warning that
   the invitee will need to set up MFA to accept if it does. Leave on Visualizador, tap
   **"Continuar"**.
4. Step 3/3, **"Revisão"** — card **"Convite"**: E-mail, Nível de acesso, MFA
   (Obrigatório/Opcional). Commit **"Enviar convite"**.
5. Tap it. `POST /api/v1/organizations/{id}/invites` returns `201`; wizard dismisses,
   banner "Convite enviado."

**Alternate H3b — already invited/member/unknown email.** Any of "already a member",
"already has a pending invite", or "no account with that email" collapse to the same
generic `409` on this screen: section **"Não foi possível convidar"**, message "Não foi
possível enviar o convite. Confira se a pessoa já é membro ou tem um convite pendente."
The email field itself doesn't validate existence
client-side — a mistyped or non-existent email won't be caught until this point.

### H4. Second account accepts the invitation

**Given** H3 completed; sign out of the admin account (A5) and sign in as the invitee
(A3) — or use a second physical/simulated device.

1. Tap **Organizações**. Since the invitee has zero organizations of their own, the
   screen shows a Button card **"1 convite pendente"** (`organization.invitations.open`)
   *and*, below it, a hint card: "Aceite um convite pendente para entrar em uma
   organização, ou crie a sua para começar do zero." — both render even though the
   organization list itself is empty; this is what commit `efebb51a` fixed (previously the
   screen fell back to the plain "Nenhuma organização ainda" empty state here, with no way
   to reach the banner at all).
2. Tap the banner. Sheet **"Convites"**: card with org name, `Label` role (icon
   `person.badge.shield.checkmark`), "Convidado por {inviter email}", buttons
   **"Aceitar"** / **"Recusar"**.
3. Tap **"Aceitar"**. `POST /api/v1/invites/{id}/accept` returns `200`; inline confirmation
   "Convite aceito." replaces the row; the sheet's list becomes the "Nenhum convite
   pendente" empty state.
4. Dismiss the sheet. The organization now appears in the main list with the assigned
   role.

**Alternate H4a — decline.** Tap **"Recusar"** instead. `POST /api/v1/invites/{id}/decline`
→ inline confirmation "Convite recusado."; the org never appears for this account.

**Alternate H4b — accepting requires MFA setup.** If the org enforces MFA and the invitee
has none configured, accepting still succeeds, but the sheet dismisses immediately, the
   tab switches to **Conta**, and a warning notice appears: "Sua nova organização exige
   verificação em duas etapas. Em Conta, abra Segurança para configurar." From there the flow is the same TOTP
setup as [C4](#c4-two-factor-totp-setup) — and if `GET /api/v1/security` itself now 403s
with `mfa_setup_required` (this can happen even for the *inviter*/admin the moment they
flip the org's MFA policy — see H6), Segurança shows the dedicated recovery screen from
commit `4e075278` instead of a dead end.

### H5. Organization members: role change and removal

**Given** you administer an organization with at least one other member (H4).

1. On H2, tap the **"⋯"** menu on a non-you member row. All roles are listed; the current
   role has a checkmark and is disabled, so it cannot issue a redundant request. A divider
   precedes destructive **"Remover"**. The owner crown announces "Dono da organização".
2. Tap a different role, e.g. **"Gerente"**. `PATCH /api/v1/organizations/{id}/members/{userId}`
   returns `200`; the row's caption updates immediately.

**Alternate H5a — remove.** Tap **"Remover"** instead. No extra confirmation dialog on
this one — it fires `DELETE /api/v1/organizations/{id}/members/{userId}` (`204`)
immediately; the row disappears and the member count decrements.

### H6. MFA policy toggle

**Given** you administer an organization.

1. On H2, tap the **Toggle** in "Política de segurança" (whichever direction). This never
   flips the switch directly — it opens a confirmation dialog first: title dynamic
   ("Exigir autenticação em duas etapas?" if currently optional, "Tornar a autenticação
   em duas etapas opcional?" if currently required), message "A política será aplicada a
   todos os membros desta organização." When enabling, the confirmation also warns that
   the current administrator must configure it to keep using Rentivo. Buttons
   **"Confirmar"** / **"Cancelar"**.
2. Tap **"Confirmar"**. `PUT /api/v1/organizations/{id}/mfa-policy` returns `200`; the
   toggle updates and the "Autenticação em duas etapas" caption flips between "Obrigatória
   para membros"/"Opcional".

**Alternate H6a — you yourself now need MFA.** If you (the admin doing the toggling) don't
have MFA configured and you just turned enforcement **on**, the screen immediately routes
you to **Conta** with a warning notice: "A verificação em duas etapas agora é obrigatória.
Em Conta, abra Segurança para configurar." This is a hard, real lockout risk if not handled: every other
authenticated screen — including, previously, Segurança's own summary read — starts
403'ing with `mfa_setup_required`. Confirm you land on the dedicated **"Configuração
obrigatória"** recovery screen (id `security.mfa.setup-required`, fixed in `4e075278`) and
can complete TOTP setup ([C4](#c4-two-factor-totp-setup)) from there — this is the single
most important regression to re-check if `SecurityView` or the MFA-policy route ever
change again, since a break here locks a real user out of their own account with no
in-app recovery path.

### H7. Transfer a billing into an organization

**Given** you administer an organization and own a personal billing.

1. On H2's "Cobranças" section, tap **"Transferir cobrança para cá"** and pick a billing
   from the menu.
2. `POST /api/v1/organizations/{id}/billing-transfers` returns `200`; the billing now
   appears under this org's Cobranças list, and its owner badge everywhere else in the app
   switches from the personal icon to the organization's.

**Note — no reverse path exists.** There is no "transfer back to personal" action
anywhere in the app or API (`transfer_to_organization` is the only transfer method in the
backend). Once a billing is in an organization, the only way to detach it is to delete the
billing outright ([D5](#d5-delete-a-billing)) — keep that in mind before testing H7 on
real data, and see [H9](#h9-delete-organization-guard) for how this interacts with
deleting the organization itself.

### H8. Organization theme

**Given** you administer an organization.

Tap **"Aparência da organização"** on H2. Identical wizard to [C2](#c2-theme-editor) —
same 5 steps, same fields — just scoped to `target: .organization(id)` instead of
`.user`. `PUT /api/v1/themes/organizations/{id}` on save.

### H9. Delete organization (guard)

**Given** you administer an organization.

1. **With a linked billing** (H7): on H2, scroll down and tap destructive **"Excluir
   organização"**. Confirmation dialog: title "Excluir organização?", message "Primeiro
   transfira todas as cobranças vinculadas.", buttons **"Excluir"** (destructive) /
   **"Cancelar"**.
2. Tap **"Excluir"**. `DELETE /api/v1/organizations/{id}` returns **`409`**
   `organization_has_billings` — the org is **not** deleted; you stay on the detail
   screen. This guard (commit `3bee1542`) is the fix for a real data-loss bug: before it
   existed, this exact confirm button call succeeded and silently orphaned every billing
   the org owned (its bills, receipts, PDFs, and communications went with it, all
   unrecoverable) despite the dialog's own text promising otherwise.
3. **Clear the billing first** — per the H7 note, delete it ([D5](#d5-delete-a-billing))
   rather than transfer it out, since no reverse-transfer exists. Return to H2, tap
   **"Excluir organização"** again, confirm.
4. This time `DELETE /api/v1/organizations/{id}` returns **`204`**; the screen pops back
   to the organization list, which no longer shows it.

---
