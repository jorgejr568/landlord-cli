# SPEC-06 — Document Preview and pt-BR Locale Formatting

**Status:** Implementation-ready  
**Platform:** Rentivo iOS, SwiftUI, iOS 17+  
**Customer-facing language:** Portuguese (Brazil)  
**Code and type names:** English  
**Related work:** SPEC-02 owns the reusable currency field UI; SPEC-04 owns semantic design-system action tokens.

## Goal

Make downloaded documents useful before they are shared, remove machine identifiers from customer-facing document names, and make every date, month, year, integer, file-size, and BRL presentation deterministic for `pt_BR`.

The completed experience must:

- render a downloaded PDF inline in a full-height sheet with Quick Look;
- identify invoices and receipts with a name a customer can understand;
- share the file from a toolbar icon using a human-readable filename;
- render years without grouping (`2026`, never `2.026`);
- render Portuguese month/year labels with context-aware capitalization (`agosto de 2026` in a sentence, `Agosto de 2026` as a standalone heading);
- use one centavos-based BRL formatting/parsing contract in expense, billing-template, and bill-item forms;
- show the API-backed display name, type, size, and creation date for files when those fields are available;
- use the cream background and semantic action tokens from the design system rather than a hard-coded blue document/share treatment.

## Current-state audit

### Download and preview

- `Rentivo/Features/Bills/BillingOperationsViews.swift` defines `DownloadShareView`. It currently renders a blue `doc.text.fill` icon, `DownloadedFile.filename`, the caption `Arquivo baixado do Rentivo.`, and a large blue `ShareLink`; it does not render the downloaded bytes.
- `Rentivo/Features/Bills/DownloadedFileSheet.swift` owns presentation and correctly keeps the temporary file alive until the sheet is dismissed. Preserve that lifecycle guarantee.
- `Rentivo/Data/API/APIRentivoStore.swift` constructs invoice, receipt, uploaded-receipt, and attachment download names from ULIDs (`fatura-<bill id>`, `recibo-<bill id>`, and similar).
- `Rentivo/Data/API/DownloadedFileStore.swift` stores the bytes at a UUID filename with only the extension preserved. Consequently, sharing `file.fileURL` can expose a UUID even if `DownloadedFile.filename` is improved.
- The visible caption is spelled `Rentivo` correctly. A repository-wide iOS search found no misspelled customer copy for the product name. The caption is redundant once an inline preview exists and is removed by this spec rather than replaced.

### Locale and currency

- `Rentivo/Features/Bills/BillViews.swift` uses `Stepper("Ano: \(year)", ...)`. SwiftUI localizes the interpolated integer and applies the Brazilian thousands separator, producing `Ano: 2.026`.
- `Rentivo/Features/Bills/BillViews.swift`, `Rentivo/Features/Billings/BillingDetailView.swift`, and `Rentivo/Features/Home/HomeView.swift` call `.capitalized` on `agosto de 2026`, producing `Agosto De 2026`. Title-casing every word is not correct Portuguese.
- `DateOnly.displayFormatted` and the lowercase `ReferenceMonth.displayFormatted` values in `Rentivo/Domain/Models.swift` are correct today. They must be routed through the shared contract so feature code does not add its own capitalization.
- `Date.formattedPTBR` already pins `pt_BR`, but it is declared at the bottom of the feature-specific `Rentivo/Features/Account/SecurityViews.swift` even though Bills and API Keys also consume it.
- File sizes use `ByteCountFormatter.string` directly in two feature views, so they are not part of the shared, explicitly Brazilian presentation layer.
- The checked-out code already contains `CurrencyCentavosField` and currently uses it in the expense, recurring billing-item, and bill line-item paths. This spec makes its formatter/parser contract a regression requirement; SPEC-02 remains the owner of the component's visual and focus behavior.

### OpenAPI and export contract

The Xcode target runs Swift OpenAPI Generator from `Rentivo/openapi.json`; generated Swift sources are build products and are not committed. The app's runtime data layer currently uses manually maintained DTOs in `Rentivo/Data/API/RemoteDTOs.swift`. Both must continue to agree with the committed contract.

The current `AttachmentResponse` schema provides these fields:

- required: `uuid`, `name`, `filename`, `content_type`, `file_size`, `sort_order`;
- optional: `created_at`.

The current manual `RemoteAttachment` drops `filename`, `sort_order`, and `created_at`. These are real API fields and must be added to the domain model and UI. `ReceiptResponse` provides `filename`, `content_type`, `file_size`, `sort_order`, and `created_at`; the existing receipt domain model already retains them.

Exports do **not** currently land in the billing attachment list. `ExportCreateResponse` contains only `format` and `status: "queued"`; it has no export ID, filename, size, creation date, download URL, or listing endpoint. The backend job emails the generated CSV/XLSX to the requesting account and deletes its temporary storage object. Therefore:

- do not synthesize an export row in **Arquivos**;
- do not invent export metadata in an iOS DTO;
- update the export completion notice to describe email delivery;
- treat an export-history/listing feature as a separate backend contract change.

The emailed backend attachment already uses `faturas_<billing-slug>.<csv|xlsx>` rather than a job/storage UUID. That filename is not returned to the iOS app, so this spec neither rewrites it nor claims it as an in-app file.

## Scope

### In scope

- Quick Look preview sheet for downloaded PDFs and other Quick Look-supported local files.
- Human-readable display and share names for invoice, generated receipt, uploaded receipt, and billing attachment downloads.
- Safe temporary paths whose final filename matches the shared filename.
- A shared `pt_BR` formatter layer for dates, reference months, years, integers, file sizes, and BRL display.
- Adoption of the formatter layer in all currently discovered iOS date/integer customer displays.
- Attachment and receipt row metadata already provided by the OpenAPI contract.
- Correct export delivery copy based on the current API/backend behavior.

### Out of scope

- Building an export history or changing export delivery from email to **Arquivos**.
- Backend schema or endpoint changes.
- PDF generation or regeneration behavior.
- Editing, annotating, printing, paging, or searching inside PDFs beyond what Quick Look provides natively.
- Redesigning the reusable currency field; see SPEC-02.
- Defining new primary-action colors; consume the semantic token/style delivered by SPEC-04.
- Persisting downloaded files after the preview sheet is dismissed.

## Affected files

Paths are relative to `ios/`.

### Create

| Path | Responsibility |
| --- | --- |
| `Rentivo/Domain/LocaleFormatting.swift` | Single `pt_BR` locale and deterministic date, month/year, year, integer, file-size, and contextual capitalization formatting. Retain the existing `Date.formattedPTBR` call surface here. |
| `Rentivo/Domain/DocumentPresentation.swift` | Human display-name, safe share-filename, filename fallback, and file-type classification rules without SwiftUI dependencies. |
| `Rentivo/Features/Bills/QuickLookPreview.swift` | `QLPreviewController` SwiftUI bridge and its single-item data source. |
| `RentivoTests/LocaleFormattingTests.swift` | Locale fixtures and regression tests for every shared formatter. |
| `RentivoTests/DocumentPresentationTests.swift` | Document naming, fallback, sanitization, type classification, and metadata-line tests. |
| `RentivoTests/APIRentivoStoreAttachmentTests.swift` | End-to-end decoding/mapping coverage for every attachment field used by the UI. |

### Modify

| Path | Required change |
| --- | --- |
| `Rentivo/Domain/Models.swift` | Delegate `DateOnly` and `ReferenceMonth` display strings to the shared formatter; expose distinct sentence and standalone-heading month/year presentations. |
| `Rentivo/Domain/Money.swift` | Reuse the shared `pt_BR` locale while preserving `Money.formatted(locale:)` and its exact BRL output. |
| `Rentivo/Domain/Identifiers.swift` | Give `DownloadedFile` a human `displayName`; define `filename` as the share filename including its extension. |
| `Rentivo/Domain/BillingModels.swift` | Retain `Attachment.filename`, `Attachment.sortOrder`, and optional `Attachment.createdAt` from the real OpenAPI response; provide display-name fallback without losing the server filename. |
| `Rentivo/Domain/FormRules.swift` | Keep `MoneyInputRules` as the shared digits-to-centavos parser and use the same maximum-centavos source as `Money`. |
| `Rentivo/Data/Repositories.swift` | Carry the caller's document presentation/suggested filename through download repository methods so loaded billing/bill context is not re-fetched. |
| `Rentivo/Data/MockRentivoStore.swift` | Match the download protocol changes and return deterministic local document fixtures where preview tests need them. |
| `Rentivo/Data/API/RemoteDTOs.swift` | Decode the complete relevant `AttachmentResponse` fields: `name`, `filename`, `content_type`, `file_size`, `sort_order`, and optional `created_at`. Do not add fields to `RemoteExport`. |
| `Rentivo/Data/API/APIRentivoStore.swift` | Map the additional attachment fields and pass human document names from the repository boundary into `LiveAPIClient.download`. |
| `Rentivo/Data/API/LiveAPIClient.swift` | Preserve media-type extension resolution while producing a `DownloadedFile` whose display/share names and local URL are consistent. |
| `Rentivo/Data/API/DownloadedFileStore.swift` | Store each download in a collision-free private subdirectory with the sanitized share filename as the final path component; delete the whole per-download directory on dismissal. |
| `Rentivo/DesignSystem/RentivoTheme.swift` | Remove the feature-layer `ptBRCount` definition after moving this Foundation-only helper to the shared Domain formatter file. |
| `Rentivo/DesignSystem/RentivoCurrencyField.swift` | Format through the shared Money/BRL contract; no independent number or currency formatter. |
| `Rentivo/Features/Account/SecurityViews.swift` | Remove the feature-local `Date.formattedPTBR` definition after moving it to Domain. |
| `Rentivo/Features/Bills/DownloadedFileSheet.swift` | Present the full-height themed preview and preserve temporary-file cleanup across Quick Look and the system share sheet. |
| `Rentivo/Features/Bills/BillingOperationsViews.swift` | Replace `DownloadShareView`, upgrade **Arquivos** rows, pass attachment presentation metadata, keep expense currency formatting shared, and correct export-delivery copy. |
| `Rentivo/Features/Bills/BillViews.swift` | Fix year/month presentation, generate invoice/receipt names from loaded billing + competência, pass receipt filenames, and add receipt type/size/date metadata. |
| `Rentivo/Features/Billings/BillingDetailView.swift` | Replace `.capitalized` with standalone month/year formatting. |
| `Rentivo/Features/Billings/BillingFormView.swift` | Continue using the shared centavos currency input for recurring fixed items; raw centavos must never be presented. |
| `Rentivo/Features/Home/HomeView.swift` | Replace `.capitalized` with standalone month/year formatting and keep integer percentages on the shared integer contract. |
| `RentivoTests/DownloadedFileStoreTests.swift` | Assert human last-path components, collision isolation, and directory cleanup. |
| `RentivoTests/LiveAPIClientErrorMappingTests.swift` | Preserve media-type extension behavior while asserting the final human filename and URL. |
| `RentivoTests/ModelsTests.swift` | Replace/add reference-month assertions for sentence, standalone, and document-name contexts. |
| `RentivoTests/MoneyTests.swift` | Add the exact `350` and `120000` centavos regression fixtures. |
| `RentivoTests/NativeFormContractTests.swift` | Keep the shared ASCII-digits-to-centavos parser and overflow behavior pinned. |
| `RentivoTests/APIRentivoStoreBillingTests.swift` | Preserve receipt metadata mapping coverage and update fixtures where the contract requires it. |
| `RentivoTests/MultipartUploadEncodingTests.swift` | Update attachment response fixtures to the current OpenAPI-required shape. |
| `RentivoUITests/BillOperationsWizardUITests.swift` | Cover competência formatting, expense input, document preview, file rows, and export confirmation in the existing operations flow. |
| `RentivoUITests/BillingWizardUITests.swift` | Cover shared recurring-item currency entry and display. |

No manual entry is needed in `Rentivo.xcodeproj/project.pbxproj` because the project uses file-system-synchronized groups.

## Shared formatting contract

### Utility boundary

Create an English-named, Foundation-only namespace `BrazilianLocaleFormatting` in `Rentivo/Domain/LocaleFormatting.swift`. It is the only place that constructs `Locale(identifier: "pt_BR")` for customer presentation. Move the Foundation-only `ptBRCount` helper into this file as well. The namespace must expose focused operations rather than a mutable global `DateFormatter` or `NumberFormatter`.

Required operations and results:

| Operation | Example input | Required output |
| --- | --- | --- |
| Standard integer with grouping | `10000` | `10.000` |
| Year without grouping | `2026` | `2026` |
| Numeric calendar date | 10 August 2026 | `10/08/2026` |
| Reference month in sentence/value context | August 2026 | `agosto de 2026` |
| Reference month as standalone heading/card title | August 2026 | `Agosto de 2026` |
| Standalone month picker label | August | `Agosto` |
| Document month segment | August 2026 | `agosto 2026` |
| BRL money from centavos | `350` | `R$` + non-breaking space + `3,50` |
| BRL money from centavos | `120000` | `R$` + non-breaking space + `1.200,00` |
| Date/time used inside PT-BR copy | fixed `Date` fixture | Foundation's explicit `pt_BR` date result, never the device language's English month order |

Rules:

1. `year` is an identifier-like calendar component. Its number style always disables grouping, regardless of the current device locale.
2. Portuguese prepositions remain lowercase. Never call `.capitalized` or `.localizedCapitalized` on a complete month/year phrase.
3. Standalone capitalization changes only the first grapheme of the month phrase; it must not title-case `de`.
4. `ReferenceMonth.displayFormatted` remains the lowercase sentence/value form for compatibility. Add a clearly named standalone-heading presentation for headers and cards.
5. `DateOnly.displayFormatted` remains `dd/MM/yyyy`.
6. Move the existing `Date.formattedPTBR(date:time:)` extension to the shared file so Account, Bills, and future features use the same implementation. Preserve current calls with default arguments and add an injectable/defaulted time zone for deterministic tests; production defaults to the current system time zone, matching today's behavior.
7. `ptBRCount` uses the shared grouped integer (`1 arquivo`, `1.000 arquivos`) and retains the existing singular-only-for-one rule.
8. File sizes use a Foundation byte-count format with explicit `pt_BR`; feature views must not instantiate or call a formatter directly.
9. Wire dates, ISO strings, ULIDs, IDs, API payload integers, and receipt-capture timestamp filenames are not presentation values and must not be localized.

### Audit adoption

- **Bill competência step:** build the `Stepper` label from a preformatted year string. The visible result is `Ano: 2026`.
- **Bill picker:** show `Janeiro` through `Dezembro` as standalone month choices.
- **Bill review values:** use lowercase `agosto de 2026`.
- **Bill detail, billing detail cards, and Home bill cards:** use `Agosto de 2026`, with only `Agosto` capitalized.
- **API key, passkey, communication history, and bill status dates:** continue using `formattedPTBR`; their call sites need no new local formatter.
- **Counts and percentages:** use the standard integer operation. Percentages remain `0%`–`100%`; large counts receive Brazilian grouping.
- **Attachment and receipt sizes/dates:** use the shared file-size and date operations.

## Shared currency input contract

This spec owns the formatting/parsing layer; SPEC-02 owns the reusable field's UI, keyboard, focus, validation presentation, and accessibility details.

Required behavior everywhere an amount is edited:

1. State and API values are signed `Int` centavos. Do not introduce `Double` or `Float`.
2. `MoneyInputRules.centavos(from:)` is the sole parser for typed or pasted text. It extracts ASCII digits, treats them as centavos, returns zero for no digits, and clamps overflow to `Money.maximumPersistedCentavos`.
3. `Money.formatted()` is the sole customer display formatter and uses BRL + `pt_BR`.
4. The field uses a number pad and reformats after every edit: typing digits `3`, `5`, `0` results in `R$ 3,50`.
5. External binding changes reformat the field immediately.
6. `ExpenseFormView`, recurring fixed items in `BillingFormView`, and editable variable/extra amounts in `BillFormView` use the same component and behavior.
7. Fixed bill lines that are read-only use `Money.formatted()`.
8. A stored amount of `120000` must appear as `R$ 1.200,00`, never `120000` and never `R$ 120.000,00`.

## Document naming and temporary-file contract

### Human display names

The domain presentation helper must derive names from data already loaded by the view. It must not trigger an extra billing or bill request.

| Document | Display name | Share filename |
| --- | --- | --- |
| Invoice for billing `Apartamento 202`, August 2026 | `Fatura - Apartamento 202 - agosto 2026` | `Fatura - Apartamento 202 - agosto 2026.pdf` |
| Generated payment receipt for the same bill | `Recibo - Apartamento 202 - agosto 2026` | `Recibo - Apartamento 202 - agosto 2026.pdf` |
| Uploaded receipt | Nonblank server `filename` without its extension; otherwise `Comprovante - <billing> - <month segment>` | Original server filename when nonblank; otherwise the fallback display name plus the media-type extension |
| Billing attachment | Nonblank API `name`; otherwise API `filename`; final fallback `Arquivo` | API `filename` when nonblank; otherwise display name plus the media-type extension |

Additional rules:

- Trim customer-visible `name` and `filename` before deciding whether they are blank.
- Preserve the extension implied by the final response media type. If a supplied filename has no extension, append the media-type extension as `LiveAPIClient` does today.
- Sanitize only the filesystem/share filename, not the visible display name. Remove path separators, control characters, and header-injection characters; collapse an empty sanitized base to `arquivo`.
- Never show or share a bill, receipt, attachment, or temporary UUID/ULID as the preferred name when the semantic inputs above are available.
- Put each downloaded file at `RentivoDownloads/<unique directory>/<sanitized share filename>`. The unique directory prevents collisions while letting Quick Look and the system share sheet see the meaningful final path component.
- `DownloadedFileStore.remove(_:)` removes that per-download directory. `purge()` continues removing the whole app-owned downloads root on session invalidation.

### File type classification

Use the response `content_type` first and the server filename extension second. The row and fallback-preview symbol mapping is:

| Type | SF Symbol |
| --- | --- |
| PDF | `doc.richtext.fill` |
| JPEG, PNG, HEIC, or other image | `photo.fill` |
| CSV | `tablecells.fill` |
| XLS/XLSX | `tablecells.fill` |
| Other/unknown | `doc.fill` |

The symbol is presentational only. It must not change which media types the existing upload policy accepts.

## Preview sheet UX

### Presentation

1. Tapping **Abrir fatura em PDF**, **Abrir recibo**, **Abrir** on an uploaded receipt, or **Abrir** in **Arquivos** completes the authenticated download and presents the same `DownloadedFileSheet`.
2. Present the sheet at the large detent. The PDF/Quick Look content fills every point below the single navigation toolbar; do not wrap it in a card, add vertical padding, or retain the current icon/caption/button stack.
3. `QuickLookPreview` embeds a one-item `QLPreviewController` through `UIViewControllerRepresentable`. Its data source returns the local `DownloadedFile.fileURL`, and the Quick Look item title is `DownloadedFile.displayName`.
4. Use a single navigation bar. Its centered principal area shows `Prévia` and the human display name in a compact two-line treatment. The display name may truncate visually to one line but its full value must be exposed to VoiceOver.
5. A leading **Fechar** action dismisses the sheet. A trailing `square.and.arrow.up` toolbar icon invokes the system share sheet; its accessibility label is **Compartilhar ou salvar arquivo**.
6. The share item is the meaningful local URL, so the receiving app sees the human share filename rather than the temporary directory name.
7. The preview sheet background and safe areas use `RentivoColors.paper`. Toolbar actions use SPEC-04's semantic primary action token/style. Do not use `RentivoColors.blue` or a one-off blue `RentivoButtonStyle` in this sheet.
8. The document canvas may retain Quick Look's native white/background rendering; do not recolor PDF page pixels.
9. Keep the temporary file while Quick Look or the system share controller can read it. Delete it only after the outer preview binding is cleared/dismissed, preserving the lifecycle rationale already documented in `DownloadedFileSheet.swift`.

### Preview failure

If Quick Look cannot preview a present local file, replace only the canvas with a themed fallback containing the mapped file-type icon, display name, and **Não foi possível exibir a prévia deste arquivo.** The share toolbar item remains available.

If the local file no longer exists, use the same message and disable the share action. Closing and reopening the source action is the recovery path; this spec does not add retry state inside the preview.

### Accessibility

- The close and share toolbar controls retain at least the native 44-point hit target.
- The share icon's spoken label is `Compartilhar ou salvar arquivo`; do not expose only `square.and.arrow.up`.
- The preview container identifies the document by its full display name.
- Quick Look's native PDF accessibility, zooming, page navigation, and Dynamic Type behavior are preserved.
- The fallback icon is decorative once the display name and error message are spoken.

## Arquivos and receipt list UX

### Arquivos

For every `AttachmentResponse` row:

1. Use `name` after trimming as the primary label; fall back to `filename`; finally use `Arquivo`.
2. Use the content-type symbol instead of the generic `doc.fill` for every row.
3. Always show localized `file_size`, because it is required by the API.
4. Append the localized `created_at` date when non-null. The metadata line uses a middle dot separator, for example `<tamanho> • 19/08/2026`.
5. Keep `filename` in the domain even when `name` is shown; it is the download/share fallback.
6. Keep `sort_order` in the domain and preserve the server order. Do not re-sort by localized display name.
7. The **Abrir** action passes this same presentation metadata into the shared preview sheet.

### Uploaded receipts

Receipt rows already have real `filename`, `content_type`, `file_size`, `sort_order`, and optional `created_at` values. Apply the same symbol and metadata-line rules. Do not invent a receipt title field that is absent from `ReceiptResponse`; use its server filename as the primary label and the contextual `Comprovante - ...` fallback only when it is blank.

### Exports

Do not add queued exports to **Arquivos** with the current contract. After a successful request, replace `Exportação CSV enfileirada.` / `Exportação XLSX enfileirada.` with:

> Exportação solicitada. O arquivo será enviado para seu e-mail.

This text is accurate for both supported formats and does not promise an in-app file that the API cannot list.

## Exact PT-BR copy

| Context | Required copy |
| --- | --- |
| Preview screen label | `Prévia` |
| Close toolbar action | `Fechar` |
| Share toolbar accessibility label | `Compartilhar ou salvar arquivo` |
| Quick Look failure | `Não foi possível exibir a prévia deste arquivo.` |
| Bill year control example | `Ano: 2026` |
| Standalone bill month/year example | `Agosto de 2026` |
| Month/year inside a sentence or review value | `agosto de 2026` |
| Invoice document example | `Fatura - Apartamento 202 - agosto 2026` |
| Generated receipt document example | `Recibo - Apartamento 202 - agosto 2026` |
| Attachment final fallback | `Arquivo` |
| Uploaded receipt fallback prefix | `Comprovante` |
| Export success notice | `Exportação solicitada. O arquivo será enviado para seu e-mail.` |

Remove `Arquivo baixado do Rentivo.` from the preview. There is no replacement caption. Keep all other correctly spelled uses of `Rentivo` unchanged.

## Data and control flow

1. A feature view already owns the source model: billing + bill for invoice/recibo, `Receipt` for an uploaded receipt, or `Attachment` for **Arquivos**.
2. The view/domain presentation helper creates the display name and suggested share filename without network access.
3. The download repository passes that presentation to `LiveAPIClient` with the authenticated endpoint request.
4. `LiveAPIClient` resolves the actual media type/extension and asks `DownloadedFileStore` for a sanitized, collision-free destination whose final path component is the share filename.
5. The returned `DownloadedFile` contains the local URL, full display name, share filename, and media type.
6. `DownloadedFileSheet` embeds Quick Look and exposes share/close toolbar actions.
7. Dismissal clears the binding and removes the per-download directory. Session invalidation still purges the entire downloads root.

## Acceptance criteria

### Preview and naming

- [ ] Opening an invoice PDF displays rendered PDF pages inline; the previous blue icon-only screen is gone.
- [ ] The preview uses the large sheet height and the PDF fills the area below one toolbar.
- [ ] An August 2026 invoice for `Apartamento 202` is identified as `Fatura - Apartamento 202 - agosto 2026`.
- [ ] Sharing that invoice presents a file named `Fatura - Apartamento 202 - agosto 2026.pdf`, not a ULID or temporary UUID.
- [ ] Share is a toolbar icon with the spoken label `Compartilhar ou salvar arquivo`; there is no large blue share button.
- [ ] The sheet uses `RentivoColors.paper` and SPEC-04 semantic primary action styling; no preview action is hard-coded blue.
- [ ] Quick Look-supported uploaded PDFs and images use the same preview sheet.
- [ ] Unsupported preview content shows the specified fallback and can still be shared while the file exists.
- [ ] Dismissing preview removes only that download's private directory; logout/session invalidation removes all app-owned downloads.

### Locale and currency

- [ ] The competência year is `Ano: 2026` in the UI and VoiceOver, with no grouping separator.
- [ ] Standalone headings/cards show `Agosto de 2026`; no customer-visible string contains `Agosto De 2026`.
- [ ] Sentence/review values show `agosto de 2026`.
- [ ] No feature view calls `.capitalized`/`.localizedCapitalized` on a `ReferenceMonth` string.
- [ ] Customer date, integer, and file-size output uses the shared explicit `pt_BR` formatter layer; wire formats remain unchanged.
- [ ] Typing `350` in expense, recurring billing-item, variable bill-item, or extra bill-item amount displays `R$ 3,50` and binds `350` centavos.
- [ ] `120000` centavos is rendered as `R$ 1.200,00` on edit, review, and read-only displays.
- [ ] No customer-facing amount field displays raw centavos.

### Files and API fidelity

- [ ] **Arquivos** uses nonblank API `name`, then API `filename`, then `Arquivo`; it never prefers a resource ID.
- [ ] Attachment rows use `content_type`, `file_size`, and optional `created_at` from `AttachmentResponse` for their symbol and metadata.
- [ ] Receipt rows use their existing `ReceiptResponse` filename/type/size/date fields and the same presentation rules.
- [ ] Manual DTO fixtures include the relevant current OpenAPI fields and decode them into domain models.
- [ ] No new export metadata field or export row is introduced.
- [ ] Successful export requests show `Exportação solicitada. O arquivo será enviado para seu e-mail.`
- [ ] A repository-wide customer-copy check finds no misspelling of `Rentivo`.

## Test plan

### Formatter unit tests — `RentivoTests/LocaleFormattingTests.swift`

Use fixed `Locale(identifier: "pt_BR")` fixtures and fixed calendar/time-zone inputs. Do not rely on the machine's current locale, language, calendar, or time zone.

Cover at minimum:

1. `year(2026) == "2026"` and contains neither `.` nor `,`.
2. Standard integer `10000 == "10.000"`.
3. Every month index `1...12` produces the expected lowercase Portuguese month in sentence context and an uppercase first letter only in standalone context.
4. August 2026 produces `agosto de 2026`, `Agosto de 2026`, and the document segment `agosto 2026`.
5. March preserves the accent: `março de 2026` / `Março de 2026`.
6. A standalone result never contains ` De `.
7. `DateOnly(year: 2026, month: 8, day: 10)` remains `10/08/2026`.
8. A fixed `Date` near midnight is tested with an explicit `America/Sao_Paulo` time zone to prevent UTC day rollover.
9. File size `1_500_000` is exactly `1,5 MB` with the explicit `pt_BR` byte-count format; also cover zero and a sub-megabyte value.
10. `ptBRCount` covers `0`, `1`, `2`, and `1000` (`1.000 arquivos`).
11. Existing Money expectations remain exact, including the non-breaking space: `350 -> R$ 3,50`, `120000 -> R$ 1.200,00`, zero, and negative values.

### Document presentation unit tests — `RentivoTests/DocumentPresentationTests.swift`

Cover at minimum:

1. Invoice and generated-receipt names for `Apartamento 202` / August 2026.
2. Attachment display-name precedence: trimmed `name`, then `filename`, then `Arquivo`.
3. Uploaded receipt uses the server filename and the contextual fallback only when blank.
4. Share filename preserves/adds the extension resolved from PDF, JPEG, PNG, CSV, and XLSX media types.
5. Filename sanitization removes `/`, `:`, CR/LF, quotes, and control characters without altering the customer-visible title.
6. PDF, image, spreadsheet, and unknown file-type symbol classification.
7. Metadata line with size only and with size + fixed creation date.

### API/data-layer tests

- Add `APIRentivoStoreAttachmentTests.swift` with a response containing distinct `name` and `filename`, `content_type`, `file_size`, `sort_order`, and `created_at`; assert every value reaches `Attachment`.
- Keep the existing receipt test that asserts media type, byte count, and creation date; add presentation assertions for the row metadata.
- Update `MultipartUploadEncodingTests` attachment fixtures to include the OpenAPI-required fields without weakening multipart/header-injection checks.
- Extend `DownloadedFileStoreTests` to assert that two same-named files use different parent directories, both URLs end in the same human filename, removal deletes only one parent, and purge deletes the root.
- Extend `LiveAPIClient` download tests to assert that media-type extension correction and human filenames work together.
- Assert `RemoteExport` continues to decode only `format` and `status`; do not create expectations for absent fields.

### UI/integration tests

Using a deterministic local PDF fixture in the mock repository:

1. Launch in `pt_BR`, open an August 2026 bill, and assert `Agosto de 2026` plus `Ano: 2026` in the edit wizard.
2. Open the invoice and assert the preview sheet, human title, `Fechar`, and share accessibility label exist; assert the old `Arquivo baixado do Rentivo.` caption does not exist.
3. Verify there is a rendered Quick Look/PDF child rather than the old `doc.text.fill` placeholder.
4. Open **Arquivos** with one named PDF and one image; assert name fallback, distinct type symbols, size, and optional date behavior.
5. Enter `350` in expense and billing-item fields and assert `R$ 3,50` in both.
6. Request a CSV and an XLSX export and assert the same email-delivery success copy for each.

### Manual simulator/device checks

- Multi-page PDF scrolling, pinch zoom, rotation policy, and return from the system share controller.
- Save to Files, Mail, AirDrop, and a third-party share extension; confirm the human filename survives.
- VoiceOver order: preview label/name, close, share, then Quick Look content; share is not announced as an unlabeled icon.
- Dynamic Type at accessibility sizes: the title truncates without covering toolbar actions and the PDF retains the remaining height.
- Dismiss during/after share and repeat downloads to confirm no premature deletion or stale temporary files.

### Verification commands

- Run core/unit tests from `ios/` with `swift test`.
- Run the `Rentivo` Xcode scheme's unit and UI tests on an iOS 17+ simulator.
- Search iOS Swift sources for customer-facing `ReferenceMonth` strings followed by `.capitalized` or `.localizedCapitalized`; the result must be empty.
- Search the year control for direct numeric SwiftUI interpolation; it must use the no-grouping year formatter.
- Search preview code for `RentivoColors.blue` and `Arquivo baixado do Rentivo.`; neither may remain in the preview implementation.

## Implementation notes and sequencing

1. Land the Foundation-only formatter and document-presentation rules with unit tests first.
2. Extend the API/domain attachment mapping and update fixtures next.
3. Change temporary-file naming/lifecycle and repository download presentation before building Quick Look, so preview and share consume the final model.
4. Replace the preview sheet and then adopt naming at invoice, receipt, and attachment call sites.
5. Migrate locale/currency/file metadata call sites and finish with UI/regression tests.

This order keeps each boundary independently testable and prevents the Quick Look layer from compensating for machine names or locale bugs that belong in Domain/Data.
