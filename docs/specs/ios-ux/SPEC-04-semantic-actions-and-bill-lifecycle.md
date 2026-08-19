# SPEC-04 — Semantic actions and bill lifecycle

## Status and scope

- Product: Rentivo iOS
- UI framework: SwiftUI
- Customer-facing language: PT-BR
- Code, comments, identifiers, and test names: English
- Minimum supported OS: iOS 17
- Scope: app-chrome action styles, status/identity badges, billing financial colors, and the bill-detail lifecycle presentation
- Out of scope: backend state-machine changes, OpenAPI changes, changing bill permissions, changing document-theme colors selected by customers, and redesigning unrelated forms

This specification supersedes the `RentivoColors.blue` information mapping in SPEC-03. Informational app chrome is neutral ink under this specification. Customer-configurable document colors in `ThemeEditorView` are not app-chrome tokens and remain unrestricted.

## Goal

Make color and hierarchy describe an action's meaning consistently, and turn the bill lifecycle from an alarming stack of equally prominent buttons into a clear status-and-next-step flow.

Success means:

1. Primary, secondary, and destructive actions use design-system roles rather than arbitrary colors at each call site.
2. Every persistent destructive action in this scope is visibly destructive and requires confirmation.
3. Bill detail shows at most one primary lifecycle CTA; alternatives live under `Mais ações` and cancellation is isolated at the end of that menu.
4. Rollbacks remain consequential and confirmable, but never look destructive.
5. Bill status is understandable from text and icon as well as color.
6. Zero money is neutral; positive/negative meaning appears only when the amount has that meaning.
7. No blue or lilac remains in Rentivo app chrome covered by this audit.

## Evidence in the current code

- `RentivoButtonStyle` accepts any `Color`, so call sites directly choose `blue`, `coral`, or the default `emerald`. The type cannot enforce semantic intent.
- `RentivoApp` sets a global emerald tint. A full-width destructive button that uses system `.bordered` can therefore inherit a green treatment even when the `Button` has `role: .destructive`. `Excluir cobrança` and `Excluir fatura` currently rely on that combination.
- `APIKeyCard` uses blue for `Editar` and solid coral for `Revogar`; the corresponding delete buttons elsewhere use a different visual treatment.
- `StatusBadge` maps `.sent` to `blue` and `.published` to `lilac`, while other states use ink, emerald, coral, and amber.
- `BillingDetailView.financialSummary` always sends coral for `Despesas` and blue for `Resultado`, including `R$ 0,00`.
- `BillDetailView.lifecycle` renders every `effectiveTransitionAction` as a full-width prominent button. Every non-danger action is green, and every action whose raw `style` equals exactly `"danger"` is red.
- The raw transition style is not stable enough to be the iOS presentation contract: the current code and fixtures contain both `"danger"` and `"destructive"`. Rollbacks can also be marked dangerous by the server/fallback even though they are not deletion or cancellation.
- `Bill.effectiveTransitionActions` correctly preserves server-authoritative availability. The redesign must retain that behavior and change only presentation, ordering, and the minimum confirmation policy.
- The only lifecycle history available to the view is the current `BillStatus` and `statusUpdatedAt`. There is no event history from which to infer the exact state at which a cancelled bill was cancelled.

## Product and architecture decisions

### Centralize semantics, not raw hues

The Design System owns three action roles:

| Role | Meaning | Treatment |
| --- | --- | --- |
| Primary | The single recommended next action in the current context | Emerald fill, white label/icon, existing ink border and hard shadow |
| Secondary | Navigation, editing, alternatives, or reversible changes | Surface fill, ink label/icon, 2 pt ink outline; retain the existing `RentivoSecondaryButtonStyle` geometry |
| Destructive | Persistent delete, revoke, or cancellation | Coral label/icon, 14%-coral-tinted surface, 2 pt coral outline; no emerald tint |

Keep the current minimum height of 48 pt, 14 pt continuous corner radius, press feedback, and disabled opacity/saturation behavior for all three roles. Disabled destructive controls remain recognizably coral-tinted; they must not turn sage green.

`RentivoButtonStyle` becomes primary-only and must no longer accept a free-form `color`. Keep `RentivoSecondaryButtonStyle`, and add `RentivoDestructiveButtonStyle`. Do not preserve a production escape hatch that accepts arbitrary `Color` values.

Native toolbar items, menu rows, swipe actions, alerts, and confirmation dialogs may continue using platform styles. Destructive rows inside those containers must use `role: .destructive`. Full-width/card actions must use the Rentivo semantic styles explicitly rather than depending on global tint propagation.

### Separate semantic tone from component type

Badges, icons, and money do not need button styles, but they use the same limited semantic tones:

| Tone | Token | Meaning |
| --- | --- | --- |
| Neutral | `RentivoColors.ink` or `secondaryInk` | identity, draft, zero, information, reversible/ordinary state |
| Positive | `RentivoColors.emerald` | paid, successful, or strictly positive result |
| Warning | `RentivoColors.amber` | published/sent work in progress and pending attention |
| Negative | `RentivoColors.coral` | overdue, cancelled, destructive, or strictly negative result |

Centralize the tone-to-color resolution in a Design System enum named `RentivoSemanticTone`, with the cases `neutral`, `positive`, `warning`, and `negative`. Feature code chooses a semantic role/tone; it must not pass `blue`, `lilac`, or a raw color to an action/status component.

After all call sites in this audit migrate, remove `RentivoColors.blue` and `RentivoColors.lilac` from `RentivoTheme.swift` and update its palette/contrast documentation. Custom hex colors rendered inside document previews remain unaffected.

### Keep server authority, add an iOS presentation classifier

`Bill.effectiveTransitionActions` remains the source of truth for which targets are currently permitted. Do not reconstruct permissions from `BillStatus.allowedTransitions` when the server supplied actions.

Add a pure view-layer classifier named `BillLifecyclePresentationPolicy` that consumes the current status plus `effectiveTransitionActions` and produces a `BillLifecyclePresentation` containing:

- zero or one primary action;
- ordered secondary/menu actions;
- a destructive flag derived from the target, not the raw server style;
- a rollback flag derived from the source/target relationship;
- the effective confirmation requirement.

Each menu entry carries one of three presentation kinds: forward alternative, rollback/restoration, or destructive cancellation. `BillLifecycleView` consumes this presentation value and never reclassifies an action from its label or raw style.

The server's `label` remains the visible action copy. The server's `requiresConfirmation` remains honored, but iOS may strengthen it for cancellation and rollback. The raw `style` string may be retained in the domain model for wire compatibility; bill-detail layout and severity must not branch on it.

No change is required under `Rentivo/Domain/`, `Rentivo/Data/`, the backend, or either OpenAPI copy.

## Behavior by finding

### 1. Destructive actions

Use the destructive Rentivo style for the visible triggers `Excluir cobrança`, `Excluir fatura`, and `Revogar`. In the lifecycle menu, `Cancelar fatura` uses the native destructive menu role. `Excluir organização`, found in the same button/color audit, also adopts the same full-width destructive style.

For this scope, a persistent destructive action means deleting a saved entity, revoking access, or cancelling a bill. These actions always pass through a confirmation surface, even if a remote transition incorrectly reports `requiresConfirmation == false`.

Local edits that have not been saved, such as `Remover item` in a form, are excluded from the mandatory-confirmation rule because the user can still discard the whole draft. Native destructive swipe/menu actions outside the named audit retain their current behavior.

Confirmation requirements:

| Action | Dialog title | Confirm action | Message |
| --- | --- | --- | --- |
| Delete billing | `Excluir esta cobrança?` | `Excluir cobrança` | `Faturas, despesas e arquivos desta cobrança também serão removidos. Esta ação não pode ser desfeita.` |
| Delete bill | `Excluir esta fatura?` | `Excluir fatura` | `A fatura e seus comprovantes serão removidos permanentemente. Esta ação não pode ser desfeita.` |
| Revoke API key | `Revogar esta chave de integração?` | `Revogar chave` | Preserve `Qualquer integração usando "{nome}" perderá acesso imediatamente. Esta ação não pode ser desfeita.` |
| Cancel bill | `Cancelar esta fatura?` | `Cancelar fatura` | `A fatura sairá do ciclo de cobrança. Confirme para continuar.` |

Every confirmation includes the existing `Cancelar` cancel-role action. The destructive confirm action is red through the native role; the platform owns its rendered dialog order. Dismissing the dialog performs no mutation and restores focus to the trigger where the platform supports it.

Do not describe bill cancellation as irreversible: server-authoritative actions may later offer a restoration transition. Deletion and API-key revocation may use the explicit irreversible message above.

### 2. Button and badge token audit

Apply the following role matrix to all discovered production call sites:

| Current surface | Path | New semantic treatment |
| --- | --- | --- |
| API key `Editar` | `Features/Account/APIKeyViews.swift` | Secondary ink-outline |
| API key `Revogar` | `Features/Account/APIKeyViews.swift` | Destructive coral-tinted/outlined; existing confirmation retained |
| `Aparência dos documentos` | `Features/Billings/BillingDetailView.swift` | Secondary ink-outline |
| `Aparência da organização` | `Features/Organizations/OrganizationViews.swift` | Secondary ink-outline |
| `Abrir fatura em PDF` | `Features/Bills/BillViews.swift` | Primary emerald |
| Download-preview file glyph | `Features/Bills/BillingOperationsViews.swift` | Emerald; the adjacent label states what is available |
| `Compartilhar ou salvar arquivo` | `Features/Bills/BillingOperationsViews.swift` | Primary emerald |
| Auth secondary text actions | `Features/Auth/AuthViews.swift` | Ink text plus underline/standard text-link affordance; never blue-only |
| MFA `Usar chave de acesso` alternative | `Features/Auth/AuthViews.swift` | Secondary ink-outline |
| Information notice icon | `DesignSystem/RentivoComponents.swift` | Neutral ink; `info.circle.fill` and information copy still communicate kind |
| Design-system `Ver detalhes` preview | `DesignSystem/RentivoComponents.swift` | Secondary ink-outline |
| Home `Resultado` icon | `Features/Home/HomeView.swift` | Sign-based: emerald positive, coral negative, ink zero |
| Home collection-rate icon | `Features/Home/HomeView.swift` | Neutral ink instead of lilac |
| Organization `você` identity badge | `Features/Organizations/OrganizationViews.swift` | Neutral ink capsule/tint, visible `você` text |
| Current-user non-admin icon | `Features/Organizations/OrganizationViews.swift` | Emerald; admin crown remains amber |

Status badges use the status palette in finding 5 below. This matrix removes every current `RentivoColors.blue` and `RentivoColors.lilac` use from `Rentivo/Features` and `Rentivo/DesignSystem`, not merely the four initially observed buttons.

The `você` marker must become a real neutral badge rather than unadorned colored text: ink or secondary-ink foreground, the same tone at 14% opacity behind it, capsule shape, and the literal label `você`. Its purpose is identity, not success, so it is not green. Keep the current-user icon beside the row so sighted users have a second identity cue; VoiceOver receives a textual identity label as specified under Accessibility.

### 3. Bill lifecycle hierarchy

Replace the current `ForEach` of full-width prominent buttons in `BillDetailView.lifecycle` with a lifecycle component containing, in this order:

1. `Ciclo da fatura` section title.
2. The status timeline/stepper.
3. One full-width primary CTA when the server offers the natural next target.
4. One full-width secondary `Mais ações` menu when any non-primary action exists.
5. The existing `Status atualizado em …` metadata.

The natural primary target is deterministic:

| Current status | Primary target, only when present in `effectiveTransitionActions` |
| --- | --- |
| `draft` | `published` |
| `published` | `sent` |
| `sent` | `paid` |
| `delayedPayment` | `paid` |
| `paid` | None |
| `cancelled` | None |

The first three rows implement the required Rascunho → Publicada → Enviada → Paga path. `delayedPayment` → `paid` is also primary because payment is the resolving next step for an overdue bill.

If the server does not offer the natural target, show no primary CTA. Do not promote the first available alternative. If no actions exist, keep the timeline and the exact terminal message `Esta fatura está em um estado final.`, but render neither CTA nor menu.

All remaining actions go into `Mais ações`. Group and order them as follows while preserving server order within each group:

1. Forward alternatives, such as direct Publicada → Paga or Enviada → Pagamento atrasado.
2. Rollbacks/restorations, such as `Voltar para publicado`, `Reverter pagamento`, or reopening a cancelled bill.
3. A divider, then `Cancelar fatura` as the last destructive item when cancellation is available.

If cancellation is the only action, the menu contains only that destructive item and does not render a meaningless leading divider. Menu rows other than cancellation use neutral ink. A warning destination such as overdue can retain its warning icon, but its text/button role is not destructive. Rollbacks are always neutral, even when `BillTransition.style` says `danger` or `destructive`.

Use the exact new menu label `Mais ações` with `ellipsis.circle`. Its accessibility label is `Mais ações do ciclo da fatura`. Keep the existing target-based action and confirmation identifiers so UI tests and assistive automation can address a transition independently of its label.

#### Rollback and confirmation policy

Treat a transition as a rollback/restoration when it moves from a later canonical state to an earlier one, including at minimum Publicada → Rascunho, Enviada → Publicada, Paga → Enviada, and Cancelada → Rascunho. Rollbacks:

- are secondary menu items;
- use ink, never coral;
- always require confirmation, even if the server says otherwise;
- retain the server-provided action label;
- use the message `O status da fatura voltará para uma etapa anterior. Confirme para continuar.`

Cancellation is not a rollback. It is destructive, last in the menu, and always uses the cancellation-specific dialog above.

For other transitions, show a confirmation whenever `action.requiresConfirmation` is true, using the existing generic message `Confirme a alteração de status desta fatura.` The confirming action repeats the visible action label. Primary placement and confirmation are independent: a natural primary CTA may still open confirmation if the server requires it.

#### Loading, success, and failure

- Once a transition begins, disable both the primary CTA and `Mais ações` to prevent concurrent requests.
- The triggering primary CTA retains its existing small progress indicator. For a menu-triggered action, close the menu and change the secondary control's accessible/visible state to `Atualizando status…` with a progress indicator until the request completes.
- Continue to invoke the existing `transition(from:to:)`, optimistic-concurrency guard, reload, and `onMutation` path. Do not optimistically move the timeline before the server succeeds.
- On success, the refreshed status updates the badge, timeline, CTA, and menu together. Preserve the existing success notice behavior.
- On failure, keep the current status/timeline, show the existing warning notice, and re-enable the controls.

### 4. Visual status timeline/stepper

The lifecycle component always shows the canonical path and conditionally shows a branch:

```text
Rascunho  →  Publicada  →  Enviada  →  Paga
                              └──────→  Pagamento atrasado  →  Paga
qualquer estado ativo  ─────────────→  Cancelada
```

This is a presentation of states, not an event-history view.

For a canonical current status:

- Earlier stages use a checkmark plus positive green to mean completed.
- The current stage uses its status icon, label, and status tone from the palette below.
- Future stages use an open circle, secondary ink, and reduced emphasis.
- Connector lines/arrows are decorative and hidden from accessibility.

For `delayedPayment`, show Rascunho, Publicada, and Enviada as completed and mark the `Pagamento atrasado` branch as current/negative. Keep Paga visible as the resolving future state.

For `cancelled`, show the canonical path in neutral muted treatment and a separate `Cancelada` branch as current/negative. Because the model has no history, do not claim that a specific canonical stage was completed immediately before cancellation. Do not infer history from `statusUpdatedAt`, document availability, or available transitions.

Use a horizontal stepper when it fits without truncation at standard Dynamic Type sizes and a vertical stepper as the deterministic fallback. At accessibility Dynamic Type sizes, always use the vertical layout. `ViewThatFits` or an equivalent measured layout may select the standard-size fallback; do not shrink status labels below their text style or horizontally scroll the lifecycle. The status timeline must remain understandable with Differentiate Without Color enabled.

### 5. Money semantic colors, including zero

Apply the following rules in `BillingDetailView.financialSummary`:

| Row | Negative | Zero | Positive |
| --- | --- | --- | --- |
| `Recebido` | Ink | Ink | Emerald |
| `Despesas` | Ink | Ink | Coral |
| `Resultado` | Coral | Ink | Emerald |

Represent this decision with a pure `FinancialAmountPresentation` resolver whose input kind is `received`, `expense`, or `result` and whose output is a `RentivoSemanticTone`. This provides the unit-test seam without moving UI semantics into `Money`.

Expenses are expected to be nonnegative, so the negative case is neutral rather than inventing a refund meaning. The required behavior is that coral appears only when expenses are strictly greater than zero. `Resultado` is calculated exactly as today (`paid - expenses`) and uses its sign. `R$ 0,00` is always ink.

Keep `MoneyText` monospaced formatting and PT-BR currency output. Expose the row label and amount together to VoiceOver, for example `Resultado: menos R$ 120,00` according to the formatter's spoken result. Do not use color or a trend icon as the only indication of a negative result.

Use the same sign-based result tone for the Home `Resultado` icon so the off-palette blue is removed. Home's monetary value can remain ink as it is today; this scope does not require making every dashboard amount colored.

### 6. Bill status pill palette

Centralize all bill-status visual metadata used by `StatusBadge` and the timeline:

| `BillStatus` | Visible PT-BR label | Tone | Required SF Symbol |
| --- | --- | --- | --- |
| `draft` | `Rascunho` | Neutral (`secondaryInk`) | `pencil.circle` |
| `published` | `Publicada` | Warning (`amber`) | `megaphone.fill` |
| `sent` | `Enviada` | Warning (`amber`) | `paperplane.fill` |
| `paid` | `Paga` | Positive (`emerald`) | `checkmark.seal.fill` |
| `delayedPayment` | `Pagamento atrasado` | Negative (`coral`) | `clock.badge.exclamationmark.fill` |
| `cancelled` | `Cancelada` | Negative (`coral`) | `xmark.circle.fill` |

Expose this mapping through one `BillStatusPresentation` value so badge and timeline cannot drift.

`published` and `sent` intentionally share amber because both are active, unpaid stages. Their labels and different icons distinguish them. `delayedPayment` and `cancelled` intentionally share coral because both need negative attention; again, icon and label carry the specific meaning.

Retain the current capsule, 14%-opacity semantic background, 1.5 pt semantic stroke, and metadata type. Add the status symbol before the label. A pill never contains color without the icon and full label. The composed accessibility label remains `Status: {label}`; do not redundantly announce the SF Symbol name.

Pending operational indicators that are not `BillStatus` values, such as PDF rendering, use amber plus their existing clock/progress label. They must not introduce a blue pseudo-status.

## Exact PT-BR copy

### New visible strings

- Lifecycle secondary menu: `Mais ações`
- Menu-triggered busy state: `Atualizando status…`
- Bill deletion message: `A fatura e seus comprovantes serão removidos permanentemente. Esta ação não pode ser desfeita.`
- Bill cancellation title: `Cancelar esta fatura?`
- Bill cancellation message: `A fatura sairá do ciclo de cobrança. Confirme para continuar.`
- Rollback confirmation message: `O status da fatura voltará para uma etapa anterior. Confirme para continuar.`

### Updated visible strings

- Billing deletion message: `Faturas, despesas e arquivos desta cobrança também serão removidos. Esta ação não pode ser desfeita.`

### Existing strings to preserve

- Section title: `Ciclo da fatura`
- Terminal message: `Esta fatura está em um estado final.`
- Generic transition confirmation: `Confirme a alteração de status desta fatura.`
- Destructive triggers/actions: `Excluir cobrança`, `Excluir fatura`, `Revogar`, `Revogar chave`, `Cancelar fatura`
- File actions: `Abrir fatura em PDF`, `Compartilhar ou salvar arquivo`
- Status labels: `Rascunho`, `Publicada`, `Enviada`, `Paga`, `Pagamento atrasado`, `Cancelada`
- Identity badge: `você`
- Confirmation cancel action: `Cancelar`

Transition labels continue to come from `BillTransition.label`; examples such as `Publicar fatura`, `Marcar como enviada`, `Marcar como pago`, `Marcar pagamento atrasado`, `Voltar para publicado`, and `Reverter pagamento` must not be rewritten merely to implement hierarchy. The iOS presentation classifier uses target/source for role and placement, never localized label text.

### Accessibility-only strings

- Lifecycle menu label: `Mais ações do ciclo da fatura`
- Timeline current stage: `{status}, status atual`
- Timeline completed stage: `{status}, etapa concluída`
- Timeline future stage: `{status}, próxima etapa`
- Current-user identity: `Você, usuário atual`

## Accessibility requirements

- Color is never the sole signal. Every status has a visible label and icon; every destructive action has destructive wording/icon plus a confirmation; every timeline state has a shape/icon and text state.
- Keep every custom button and menu trigger at least 44 × 44 pt; the standard full-width styles remain 48 pt high.
- `StatusBadge` is one accessibility element with `Status: {label}`. Hide its decorative symbol name from VoiceOver.
- Each timeline stage is one accessibility element in chronological reading order. Use the exact state suffixes above. Hide connector lines and arrows.
- The delayed/cancelled branch follows the canonical steps in VoiceOver order and announces itself as the current status. Do not expose a fabricated completed stage for cancellation.
- `Mais ações` is a visible text label, not an icon-only ellipsis. Provide the accessibility label `Mais ações do ciclo da fatura` and the exact hint `Mostra outras mudanças de status`.
- Menu items retain their complete action label. `Cancelar fatura` exposes the destructive trait through the native role. Rollbacks do not expose a destructive trait.
- When `Atualizando status…` begins, announce the state change without moving VoiceOver focus away from the lifecycle region. On completion, the refreshed status must be available on the next focus pass.
- The `você` badge and current-user icon are grouped with the member row so VoiceOver announces the e-mail, role, and `Você, usuário atual` once.
- Financial rows combine label and formatted amount in their accessibility label. Negative/positive/zero meaning must be understandable from the signed/spoken value and row label, not color alone.
- Support all Dynamic Type sizes without truncating action labels, status labels, money, or confirmation messages. Use a vertical timeline at accessibility sizes.
- Verify VoiceOver, Switch Control, Differentiate Without Color, Increase Contrast, and Reduce Motion. The lifecycle requires no decorative motion; if progress changes are animated, Reduce Motion uses opacity only.
- Coral/amber/emerald text and icons on their 14% tints must continue meeting WCAG AA. Boundaries must remain perceptible with Increase Contrast and without relying only on the hard shadow.

## Affected files

Paths are relative to the audited `/Users/j/src/jorgejr568/landlord-cli/.claude/worktrees/rentivo-ui-ux-review-9ee035/ios` root.

### Production files

| Path | Required change |
| --- | --- |
| `Rentivo/DesignSystem/RentivoTheme.swift` | Add `RentivoSemanticTone`, document the reduced cream/ink/emerald/amber/coral palette, and remove blue/lilac tokens after migration. |
| `Rentivo/DesignSystem/RentivoComponents.swift` | Make button APIs semantic, add destructive style, repalette/add icons to `StatusBadge`, move shared bill-status visual metadata here, update information notice and previews. |
| `Rentivo/Features/Bills/BillLifecycleView.swift` (new) | Own the status timeline, primary/menu layout, action classifier, ordering, rollback detection, and effective confirmation policy. Keeping this focused behavior in a new file avoids further expanding the existing 1,000+ line bill view. |
| `Rentivo/Features/Bills/BillViews.swift` | Replace the stacked lifecycle loop with the lifecycle component; preserve mutation/loading paths and identifiers; repalette PDF and delete actions; add deletion/cancellation/rollback confirmations; remove the file-private status-symbol mapping after centralization. |
| `Rentivo/Features/Billings/BillingDetailView.swift` | Apply secondary/destructive styles, update deletion copy, and resolve received/expense/result tones from amount sign. |
| `Rentivo/Features/Bills/BillingOperationsViews.swift` | Repalette the downloaded-file glyph and share/save primary action. |
| `Rentivo/Features/Account/APIKeyViews.swift` | Make edit secondary and revoke destructive while retaining the existing revoke confirmation. |
| `Rentivo/Features/Organizations/OrganizationViews.swift` | Repalette appearance/delete actions, add the neutral `você` badge, and repalette the current-user icon. |
| `Rentivo/Features/Auth/AuthViews.swift` | Replace blue secondary text actions and the blue passkey action with neutral/secondary roles. |
| `Rentivo/Features/Home/HomeView.swift` | Remove blue/lilac summary icons and apply sign-based tone to the `Resultado` icon. |

`Rentivo.xcodeproj/project.pbxproj` uses file-system-synchronized groups, so adding the new Swift files should not require a manual project-file edit. Do not edit project membership unless Xcode proves the new files are not included in the app/test targets.

No production change is expected in `Rentivo/Domain/BillingModels.swift` or `Rentivo/Data/API/APIRentivoStore.swift`. In particular, preserve `effectiveTransitionActions`, target availability, optimistic concurrency, and wire decoding.

### Test files

| Path | Required coverage |
| --- | --- |
| `RentivoTests/BillLifecyclePresentationTests.swift` (new) | Primary selection, menu grouping/order, rollback neutrality, cancellation severity, missing-natural-target behavior, and confirmation strengthening. Guard app-only tests with `#if canImport(Rentivo)` so the RentivoCore package suite still compiles. |
| `RentivoTests/SemanticPresentationTests.swift` (new) | All six status tones/symbols and positive/zero/negative financial tone resolution. Use semantic enums/results rather than comparing rendered SwiftUI `Color` values. |
| `RentivoTests/BillLifecycleTests.swift` | Preserve domain transition and server-authority coverage; update only if presentation helpers deliberately reuse existing fixtures. Do not move UI hierarchy rules into the domain model merely to test them here. |
| `RentivoUITests/RentivoUITests.swift` | Update lifecycle journey helpers and add direct-primary/menu/confirmation/accessibility-identifier regressions. |

## Acceptance criteria

### Semantic styles and palette

1. `RentivoButtonStyle` has no production initializer/property accepting an arbitrary `Color`; call sites choose primary, secondary, or destructive semantics.
2. `Editar`, appearance navigation, auth alternatives, PDF open, file sharing, revoke, and full-width delete actions match the role matrix above.
3. `Excluir cobrança`, `Excluir fatura`, `Revogar`, and full-width `Excluir organização` never render emerald/sage in enabled or disabled states.
4. Every named persistent destructive action opens its required confirmation before mutation. Cancelling/dismissing performs no mutation.
5. No production reference to `RentivoColors.blue` or `RentivoColors.lilac` remains under `Rentivo/Features` or `Rentivo/DesignSystem`; the unused tokens are removed from `RentivoTheme.swift`.
6. Information remains distinguishable through `info.circle.fill` and text after becoming neutral ink.

### Bill lifecycle

7. A draft bill with a `published` action shows that action as the only primary CTA and moves cancellation into `Mais ações`.
8. A published bill with `sent`, `paid`, rollback, and cancel actions shows only `sent` as primary. The others appear in the specified menu order.
9. A sent bill with `paid`, delayed, published rollback, and cancelled targets shows only `paid` as primary. Delayed and rollback are neutral menu actions; cancellation is destructive and last after a divider.
10. An overdue bill shows `paid` as primary when available. Paid or cancelled bills never invent a primary action.
11. When the server omits the natural target, no other action is promoted. When all actions are empty, neither CTA nor `Mais ações` appears.
12. Rollback actions are neutral even if the incoming raw style is `danger` or `destructive`, and they always open the rollback confirmation.
13. Cancellation is destructive and always opens the cancellation confirmation even if incoming `requiresConfirmation` is false or the raw style is unknown.
14. Server action availability and target remain authoritative. The redesign does not expose an action absent from `effectiveTransitionActions`.
15. While a transition is running, primary and menu controls are disabled, a progress state is visible/announced, and a second request cannot start.
16. A failed transition leaves the status/timeline unchanged, re-enables controls, and shows the existing warning notice. A successful transition reloads badge, timeline, and actions together.

### Timeline and statuses

17. The canonical Rascunho → Publicada → Enviada → Paga path is always visible in the lifecycle section.
18. `Pagamento atrasado` appears as a branch from Enviada and identifies Paga as the possible resolving future state.
19. `Cancelada` appears as a separate branch without claiming an unsupported prior state/history.
20. At default and largest accessibility text sizes, every step label remains visible without truncation or horizontal scrolling.
21. Every status badge uses the exact palette/symbol/label matrix. Blue `Enviada` and lilac `Publicada` no longer occur.
22. With grayscale or Differentiate Without Color, status and progress remain understandable from icon, text, and completion/current/future markers.

### Money

23. `Despesas: R$ 0,00` and `Resultado: R$ 0,00` use ink; neither uses coral, blue, or emerald.
24. Strictly positive expenses use coral; zero or negative expenses use ink.
25. Strictly positive result uses emerald, strictly negative result uses coral, and exactly zero result uses ink.
26. `Recebido` is emerald only when strictly positive and ink at zero.
27. Financial accessibility labels expose row name plus formatted amount, including a negative result, without depending on color.

## Test plan

### Unit tests

Add app-target presentation tests around pure semantic results rather than rendered colors.

Lifecycle classifier cases:

- Draft with published + cancelled: published is primary; cancelled is the final destructive menu item and confirms even when remote confirmation is false.
- Published with sent + paid + draft + cancelled in shuffled server order: sent is primary; paid precedes rollback; rollback precedes cancellation; cancellation remains last.
- Sent with paid + delayedPayment + published + cancelled: paid is primary; delayed is a non-destructive alternative; published is a neutral confirmed rollback; cancelled is destructive.
- Paid with sent labelled `Reverter pagamento` and raw style `danger`: no primary; the menu action is neutral and confirmed.
- Cancelled with draft restoration: no primary; restoration is neutral and confirmed.
- Delayed payment with paid: paid is primary.
- Missing natural target with another forward action: no primary; alternative stays in the menu.
- Empty actions: terminal presentation with no CTA/menu.
- Raw styles `primary`, `secondary`, `danger`, `destructive`, and an unknown string do not override source/target severity.
- Server `requiresConfirmation == true` is preserved for any action; cancellation and rollback become true even when the server supplies false.

Semantic presentation cases:

- Assert the tone and SF Symbol for every `BillStatus.allCases` value.
- Assert received, expense, and result tone for `-1`, `0`, and `1` centavo boundaries.
- Assert the Home result icon uses negative/neutral/positive tones at the same boundaries.
- Assert neutral information and current-user identity do not resolve to positive, warning, or negative.

`make ios-test` must still pass for `RentivoCore`; app-only test bodies must be conditionally compiled as noted above. Run the Xcode-hosted `RentivoTests` target because Design System and Features are excluded from the Swift package.

### UI tests

Preserve the existing identifiers `bill.transition.{target}` and `bill.transition.confirm.{target}`. Add the exact identifiers `bill.lifecycle.timeline`, `bill.lifecycle.more-actions`, `billing.delete`, and `bill.delete` so tests do not locate hierarchy or destructive actions only by translated text.

1. Open the canonical draft. Assert one direct transition button for `published`, assert `bill.lifecycle.more-actions` exists, and assert cancellation is not a second full-width direct button.
2. Execute draft → published → sent → paid through the direct primary CTA. The existing Home and billing-detail journeys must remain on the pushed bill detail while the underlying lists refresh.
3. Open `Mais ações` on a state with cancellation, tap `Cancelar fatura`, assert the cancellation confirmation and message, then choose `Cancelar` and assert status remains unchanged.
4. Repeat and confirm cancellation in a disposable/resettable fixture; assert the Cancelada badge/branch and absence of a primary CTA.
5. Exercise bill and billing delete triggers, dismiss each confirmation, and assert the entity/screen remains. Confirm only in a resettable fixture.
6. In viewer mode, assert neither a primary lifecycle button nor `Mais ações` exists and retain `Ciclo disponível somente para quem pode gerenciar faturas.`
7. At an accessibility Dynamic Type launch size, assert the lifecycle exposes all canonical labels and the visible `Mais ações` label.

Do not attempt to assert RGB values through XCUITest. Use identifiers/traits for hierarchy and confirmations, and cover tone mapping with the pure unit tests plus visual verification.

### Manual visual and accessibility matrix

Verify on a compact iPhone and iPad, at default and largest accessibility text sizes:

- API-key card: `Editar` versus `Revogar`, including disabled/pressed appearances and revoke confirmation.
- Billing detail: zero, positive, and negative result; zero and positive expenses; appearance/delete buttons.
- Bill detail for all six statuses, including each primary CTA/menu combination.
- Server-action fixtures containing rollback styles `danger` and `destructive`.
- PDF render pending, PDF available, download preview, and share/save action.
- Organization current user as admin and non-admin, including the neutral `você` badge.
- Login/MFA alternative actions and information notices after blue removal.
- Grayscale, Differentiate Without Color, Increase Contrast, VoiceOver, Switch Control, and Reduce Motion.

For VoiceOver, confirm chronological timeline order, one announcement per badge/step, menu label/hint, destructive traits only on cancellation, and combined financial row labels. For visual QA, confirm there is never more than one emerald lifecycle CTA and one secondary menu trigger on screen.

### Verification commands

From the repository root:

1. Run `make ios-test` to protect the shared RentivoCore package suite.
2. Resolve an available iPhone simulator with the same approach used by `.github/actions/ios-unit-tests/action.yml`, then run the Xcode `RentivoTests` target with `xcodebuild -project ios/Rentivo.xcodeproj -scheme Rentivo -destination "platform=iOS Simulator,id={destination-id}" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO test -only-testing:RentivoTests`.
3. Run `RentivoUITests` locally from Xcode (or the equivalent `xcodebuild` target) for the lifecycle journeys; UI tests remain outside the required PR CI path.
4. Search for forbidden app-chrome tokens with `rg 'RentivoColors\.(blue|lilac)|RentivoButtonStyle\(color:' ios/Rentivo/Features ios/Rentivo/DesignSystem`; the command must return no matches.

## Implementation sequencing and definition of done

1. Introduce/test semantic tones and action styles, then migrate all audited call sites and remove blue/lilac tokens.
2. Add/test the pure lifecycle presentation classifier.
3. Build the timeline and one-CTA/menu lifecycle UI on top of that classifier, preserving the existing transition request path.
4. Apply money sign rules and destructive confirmation copy.
5. Update UI tests and complete the manual accessibility/visual matrix.

The work is done when every acceptance criterion passes, both unit-test layers pass, lifecycle UI tests pass locally, the forbidden-token search is empty, and no Domain/Data/OpenAPI change was introduced for a presentation-only redesign.
