# Security Policy

## Supported versions

Only the latest release (and `main`) receives security fixes.

The iOS app ships on its own version track, tagged `ios/v<MARKETING_VERSION>` (for example `ios/v1.2`); only its latest App Store release is supported. The Android app has no release channel yet, so it is supported only as source on `main`.

## Reporting a vulnerability

Please report vulnerabilities privately via [GitHub Security Advisories](https://github.com/jorgejr568/rentivo/security/advisories/new) — do **not** open a public issue. You should get a response within a week.

## Security-relevant documentation

- Field encryption (KMS) and the email blind index: [docs/configuration.md](docs/configuration.md)
- Audit logging and PII redaction: `backend/rentivo/pii_redaction.py` (the mask shapes and the redacted key set) and `backend/rentivo/services/audit_service.py` (the audit write path that applies them)
- Past security review: [docs/security/2026-05-02-fastapi-audit.md](docs/security/2026-05-02-fastapi-audit.md)
