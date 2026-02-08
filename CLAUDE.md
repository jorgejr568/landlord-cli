# Landlord

Apartment billing management with PDF invoice generation — CLI + Django web UI.

## Running

```bash
# CLI (local)
make run

# Web (local)
make web-migrate         # first time only
make web-createsuperuser # first time only
make web-run             # http://localhost:8000
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

Two Dockerfiles:
- **`Dockerfile`** — Web app (Django + gunicorn on port 8000)
- **`Dockerfile.cli`** — CLI container (health check on port 2019)

```bash
# Web container (default)
make build       # build web image
make up          # start web container (port 8000)
make down        # stop and remove
make restart     # down + up
make logs        # tail logs
make health      # curl http://localhost:8000

# CLI container
make build-cli   # build CLI image
make up-cli      # start CLI container (port 2019)
make down-cli    # stop and remove
make landlord    # run CLI interactively
make shell-cli   # bash session

# Docker Compose (both services)
make compose-up            # start web + cli
make compose-down          # stop all
make compose-landlord      # run CLI in cli container
make compose-createsuperuser # create Django admin user
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

## Django Web App

The `web/` directory contains a Django web application that provides a browser-based UI for the same functionality as the CLI.

### Running

```bash
make web-migrate         # create Django auth tables (first time only)
make web-createsuperuser # create admin user (first time only)
make web-run             # start dev server at http://localhost:8000
```

### Architecture

- **Project config**: `web/landlord_web/` — Django settings, URLs, WSGI
- **Core app**: `web/core/` — models, views, forms, templates
- **Models**: Django ORM with `managed = False` — maps to existing Alembic-managed tables
- **Admin**: Full Django admin at `/admin/` with inline editing
- **Adapters**: `web/core/adapters.py` converts Django models to Pydantic models for PDF/PIX generation
- **Auth**: Single user via `createsuperuser`, login at `/login/`
- **Templates**: Bootstrap 5 via CDN, all customer-facing text in PT-BR

### Key URLs

| URL | Purpose |
|-----|---------|
| `/` | Billing list (home) |
| `/billings/create/` | Create new billing |
| `/billings/<id>/` | Billing detail + bills |
| `/billings/<id>/edit/` | Edit billing |
| `/billings/<id>/generate/` | Generate new bill |
| `/bills/<id>/` | Bill detail |
| `/bills/<id>/edit/` | Edit bill |
| `/bills/<id>/invoice/` | Download/view PDF |
| `/admin/` | Django admin |

## Key Rules

- **NEVER delete `landlord.db` or `invoices/`** without explicit user confirmation
- Do not use floats for monetary values — always centavos (int)
- Keep repository and storage abstractions — they exist so backends can be swapped (MariaDB, S3)
