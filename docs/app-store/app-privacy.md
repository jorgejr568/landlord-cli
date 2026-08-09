# App Store Connect — App Privacy questionnaire answers

Answers for the iOS app (bundle `br.com.rentivo.ios`). The app collects data
only through Rentivo's own API for app functionality. No third-party
analytics, ads, or crash SDKs are embedded in the iOS binary; web analytics
(Google Tag Manager) runs only on the website.

## Does the app collect data? → Yes

All items below: **Collected**, **Linked to the user's identity**,
**NOT used for tracking**, purpose **App Functionality** only.

| ASC category | ASC data type | What it actually is |
| --- | --- | --- |
| Contact Info | Email Address | Account e-mail (login, transactional e-mail) |
| Contact Info | Name | PIX merchant name on the user profile |
| Financial Info | Payment Info | PIX key used to generate charge QR codes |
| Financial Info | Other Financial Info | Rent charges, bills, expenses, receipt amounts |
| Identifiers | User ID | Internal account id tying data to the account |
| User Content | Photos or Videos | Payment proofs and billing attachments uploaded by the user (PDF or image) |
| User Content | Other User Content | Tenant/recipient names and e-mails entered by the user |

Photos or Videos is declared because the app has two upload paths, both
accepting `[UTType.pdf, UTType.image]` through `.fileImporter`, and a
photographed receipt is the routine case rather than an edge case:

- "Adicionar comprovante" on the bill detail screen
  (`ios/Rentivo/Features/Bills/BillViews.swift`) sends the file as the
  `receipt_files` multipart part of
  `POST /api/v1/billings/{billing_uuid}/bills/{bill_uuid}/receipts`.
- Billing attachments
  (`ios/Rentivo/Features/Bills/BillingOperationsViews.swift`) send it to
  `POST /api/v1/billings/{billing_uuid}/attachments`.

The file leaves the device and is stored server-side against the account, which
is collection under Apple's definition. It is *not* library access: there is no
`PHPhotoLibrary`/`PhotosPicker` usage and no `NSPhotoLibraryUsageDescription`
prompt — the document picker returns only the single file the user chose.

## Everything else → Not collected

Location, Health & Fitness, Messages, Audio, Browsing History, Search History,
Purchases, Usage Data, Diagnostics, Sensitive Info, Contacts, Other Data.

Notes:
- **Tracking (ATT):** answer **No** — no data is used to track users across
  other companies' apps or websites; no AdSupport/ATT prompt needed.
- The login step opens `rentivo.com.br` in an in-app browser session
  (`ASWebAuthenticationSession`). If GTM page-analytics on `/login` is ever
  considered in-scope collection, add Usage Data → Product Interaction
  (Analytics, not linked). Current declaration treats the binary itself as
  the boundary, which matches Apple's guidance for web-login flows.
- Keep this file in sync with `frontend/src/features/legal/PrivacyPolicyPage.tsx`
  whenever data practices change.
- **Android:** `android/` is a 1:1 port of this app with the same two uploads
  (`ActivityResultContracts.OpenDocument()` in
  `app/rentivo/features/bills/BillViews.kt` and `BillingOperationsViews.kt`,
  hitting the same endpoints), so it will need an equivalent Google Play
  **Data Safety** declaration covering the same data — including the uploaded
  files — with the same no-tracking answer. Play uses its own taxonomy and asks
  separately about collection versus sharing, so it is a translation of these
  answers rather than a copy. Nothing is due yet: there is no Play listing and
  no Android release automation — `android/` appears in `.github/workflows/`
  only as the PR-gate `android` job.
