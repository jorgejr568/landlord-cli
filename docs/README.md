# Documentation Index

Every document in `docs/`, grouped by what you are trying to do. Repository
conventions live at the top level; operational procedures live under
`runbooks/`.

## Getting started and development

| Document | Answers |
|---|---|
| [`../README.md`](../README.md) | What is Rentivo, what is in the repository, and how do I run it? |
| [`development.md`](development.md) | How do I set up a local environment and run the checks for a change? |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | What is expected of a pull request — branches, conventions, tests? |
| [`../AGENTS.md`](../AGENTS.md) | Which rules are non-negotiable for automated contributors? |
| [`../CLAUDE.md`](../CLAUDE.md) | Where does each layer live, and which command verifies it? |

## Configuration and operations

| Document | Answers |
|---|---|
| [`configuration.md`](configuration.md) | What does each `RENTIVO_` environment variable do, and what values are valid? |
| [`jobs.md`](jobs.md) | How does background work execute, retry, and get retained under each job driver? |
| [`observability.md`](observability.md) | What does the application log and trace, and what should production alert on? |

## Runbooks

| Document | Answers |
|---|---|
| [`runbooks/production-release.md`](runbooks/production-release.md) | How do I deploy the web stack, verify it, and roll back? |
| [`runbooks/ios-release.md`](runbooks/ios-release.md) | How is an iOS build released to App Store Connect, and what do I do when it fails? |

## Native apps

| Document | Answers |
|---|---|
| [`mobile.md`](mobile.md) | How are the iOS and Android apps structured, how do they stay on contract, and how does sign-in work? |
| [`macos.md`](macos.md) | How does the macOS app reuse `RentivoCore`, where does it diverge from iOS, and how is it packaged? |
| [`app-store/app-privacy.md`](app-store/app-privacy.md) | What do we answer on the App Store Connect App Privacy questionnaire? |

## Security and compliance

| Document | Answers |
|---|---|
| [`../SECURITY.md`](../SECURITY.md) | Which versions are supported, and how do I report a vulnerability privately? |
| [`security/2026-05-02-fastapi-audit.md`](security/2026-05-02-fastapi-audit.md) | What did the FastAPI validation, ReDoS, and SQL-identifier audit find? |

## History

| Document | Answers |
|---|---|
| [`../CHANGELOG.md`](../CHANGELOG.md) | What changed in each release? |
| [`superpowers/`](superpowers/) | Historical planning artifacts (specs and plans) for past feature work. Kept for provenance; not maintained as current documentation. |
