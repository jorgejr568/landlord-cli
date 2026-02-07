# Landlord CLI

Interactive CLI for apartment billing management and PDF invoice generation. Built for Brazilian landlords — all tenant-facing output is in **PT-BR** with **BRL (R$)** currency and **PIX QR codes** on invoices.

## Features

- Create and manage recurring billing templates with multiple line items
- Generate professional PDF invoices with PIX QR codes for easy payment
- Store invoices locally or on S3 with presigned URLs
- SQLite or MariaDB as the database backend (via SQLAlchemy)
- Schema migrations with Alembic
- Docker-ready with health check endpoint

## Quick Start

```bash
make install              # create venv + install deps
cp .env.example .env      # configure settings
make migrate              # run database migrations
make run                  # start the interactive CLI
```

### Docker

```bash
make build                # build image
make up                   # start container
make billing              # run the CLI inside the container
```

## Configuration

Copy `.env.example` to `.env`. All variables use the `BILLING_` prefix.

### Database

| Variable | Default | Description |
|----------|---------|-------------|
| `BILLING_DB_BACKEND` | `sqlite` | Database backend (`sqlite` or `mariadb`) |
| `BILLING_DB_PATH` | `billing.db` | Path to SQLite file (SQLite only) |
| `BILLING_DB_URL` | | Full SQLAlchemy URL — overrides `DB_BACKEND` + `DB_PATH` |

### Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `BILLING_STORAGE_BACKEND` | `local` | `local` or `s3` |
| `BILLING_STORAGE_LOCAL_PATH` | `./invoices` | Local directory for PDFs |
| `BILLING_S3_BUCKET` | | S3 bucket name |
| `BILLING_S3_REGION` | | AWS region |
| `BILLING_S3_ACCESS_KEY_ID` | | AWS access key |
| `BILLING_S3_SECRET_ACCESS_KEY` | | AWS secret key |
| `BILLING_S3_ENDPOINT_URL` | | Custom S3 endpoint (MinIO, etc.) |
| `BILLING_S3_PRESIGNED_EXPIRY` | `604800` | Presigned URL expiry in seconds (default 7 days) |

### PIX

| Variable | Description |
|----------|-------------|
| `BILLING_PIX_KEY` | PIX key (CPF, email, phone, or random) |
| `BILLING_PIX_MERCHANT_NAME` | Merchant name for QR code |
| `BILLING_PIX_MERCHANT_CITY` | Merchant city for QR code |

## Makefile Reference

### Local

| Command | Description |
|---------|-------------|
| `make install` | Create virtualenv and install dependencies |
| `make run` | Run the billing CLI |
| `make migrate` | Run pending Alembic migrations |
| `make regenerate-pdfs` | Regenerate all invoice PDFs |
| `make regenerate-pdfs-dry` | Preview regeneration (dry run) |

### Docker

| Command | Description |
|---------|-------------|
| `make build` | Build the Docker image |
| `make up` / `make down` | Start / stop the container |
| `make billing` | Run the CLI in the container |
| `make shell` | Open a bash shell in the container |
| `make docker-migrate` | Run migrations in the container |
| `make docker-regenerate` | Regenerate PDFs in the container |
| `make logs` | Tail container logs |
| `make health` | Check the health endpoint |

### Docker Compose

| Command | Description |
|---------|-------------|
| `make compose-up` / `compose-down` | Start / stop with Compose |
| `make compose-billing` | Run the CLI via Compose |
| `make compose-shell` | Shell into the container |
| `make compose-migrate` | Run migrations via Compose |

## Architecture

```
billing/
  settings.py          # Pydantic Settings (env prefix BILLING_)
  db.py                # SQLAlchemy engine + connection
  models/              # Pydantic models (Billing, Bill, BillLineItem)
  repositories/        # Abstract base + SQLAlchemy Core implementation
  services/            # Business logic (billing + bill services)
  storage/             # Abstract base + Local / S3 implementations
  pdf/                 # fpdf2-based invoice generator
  cli/                 # Interactive menus (questionary + rich)
  scripts/             # Maintenance scripts (PDF regeneration)
```

## License

MIT
