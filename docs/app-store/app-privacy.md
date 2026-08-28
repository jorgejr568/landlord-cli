# App Store Connect — App Privacy questionnaire answers

Answers for the iOS app (bundle `br.com.rentivo.ios`). The app collects data
only through Rentivo's own API for app functionality. The API can optionally
send landlord-authored communication text to OpenRouter for server-side
content-safety analysis. No third-party analytics, ads, moderation, or crash
SDKs are embedded in the iOS binary; web analytics (Google Tag Manager) runs
only on the website.

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
| User Content | Other User Content | Tenant/recipient names and e-mails, plus landlord-authored communication text |

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
- **OpenRouter:** when the optional remote moderation backend is enabled,
  communication text is processed by OpenRouter solely for App Functionality.
  It remains linked user content, is not used for tracking, and does not add an
  SDK to the mobile binary.
- **Tracking (ATT):** answer **No** — no data is used to track users across
  other companies' apps or websites; no AdSupport/ATT prompt needed.
- Keep this file in sync with `frontend/src/features/legal/PrivacyPolicyPage.tsx`
  whenever data practices change.
