# Landlord CLI

Apartment billing management CLI app with PDF invoice generation.

## Running

```bash
# Local
make run

# Docker
make landlord
make shell    # for a bash session in the container
```

## Scripts

```bash
# Local
make regenerate-pdfs
make regenerate-pdfs-dry

# Docker
make docker-regenerate
```

## Docker

```bash
make build       # build image
make up          # start container (reads .env, exposes health check on port 2019)
make down        # stop and remove
make restart     # down + up
make logs        # tail logs
make health      # curl the health endpoint
```

## Architecture

- **Settings**: `landlord/settings.py` — Pydantic Settings, env prefix `LANDLORD_`, reads `.env`
- **Database**: `landlord/db.py` — SQLAlchemy engine + connection. Schema managed by Alembic. Configurable backend via `LANDLORD_DB_URL`
- **Repositories**: `landlord/repositories/` — Abstract base classes in `base.py`, SQLAlchemy Core impl in `sqlalchemy.py`, factory in `factory.py`
- **Storage**: `landlord/storage/` — Same pattern. `LocalStorage` writes to `./invoices/`, `S3Storage` uploads to a private bucket with presigned URLs. Configurable via `LANDLORD_STORAGE_BACKEND`
- **PDF**: `landlord/pdf/invoice.py` — fpdf2-based invoice with navy/green color palette
- **Services**: `landlord/services/` — Business logic layer wiring repos + storage + PDF
- **CLI**: `landlord/cli/` — Interactive menus using `questionary` + `rich`
- **Health check**: `healthcheck.py` — HTTP server on port 2019, returns 200 for all requests

## S3 Storage

- S3 key pattern: `{billing_uuid}/{bill_uuid}.pdf`
- `pdf_path` column stores the S3 key, not a URL
- Presigned URLs (7-day expiry) are generated on the fly via `get_invoice_url()` / `get_presigned_url()`
- Set `LANDLORD_STORAGE_BACKEND=s3` and configure `LANDLORD_S3_*` env vars

## Conventions

- All customer-facing text (CLI prompts, PDF content) in **PT-BR**
- Currency in **BRL** (R$), formatted via `landlord.models.format_brl()`
- Money stored as **centavos (int)** in the database — never use floats for money
- Code (variable names, comments) in English

## Key Rules

- **NEVER delete `landlord.db` or `invoices/`** without explicit user confirmation
- Do not use floats for monetary values — always centavos (int)
- Keep repository and storage abstractions — they exist so backends can be swapped (MariaDB, S3)
