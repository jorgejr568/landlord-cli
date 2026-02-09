# Landlord

Apartment billing management with PDF invoice generation — **CLI + Web UI**. Built for Brazilian landlords — all tenant-facing output is in **PT-BR** with **BRL (R$)** currency and **PIX QR codes** on invoices.

## Features

- Create and manage recurring billing templates with multiple line items
- Generate professional PDF invoices with PIX QR codes for easy payment
- **Web UI** (FastAPI) for browser-based management, or **interactive CLI**
- User management with bcrypt password hashing
- Store invoices locally or on S3 with presigned URLs
- MariaDB as the database backend (via SQLAlchemy)
- Schema migrations with Alembic
- Docker-ready with health check endpoint

## Quick Start

```bash
make install              # create venv + install deps
cp .env.example .env      # configure settings
docker compose up -d db   # start MariaDB
make migrate              # run database migrations
make run                  # start the interactive CLI
```

### Web UI

```bash
docker compose up -d db   # start MariaDB (if not running)
make migrate              # run database migrations (first time)
make web-createuser       # create a login user
make web-run              # start web UI at http://localhost:8000
```

### Docker Compose

```bash
make compose-up           # start MariaDB + web + CLI
make compose-createuser   # create a login user
```

## Configuration

Copy `.env.example` to `.env`. All variables use the `LANDLORD_` prefix.

### Database

| Variable | Default | Description |
|----------|---------|-------------|
| `LANDLORD_DB_URL` | `mysql://landlord:landlord@db:3306/landlord` | SQLAlchemy database URL (MariaDB) |

### Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `LANDLORD_STORAGE_BACKEND` | `local` | `local` or `s3` |
| `LANDLORD_STORAGE_LOCAL_PATH` | `./invoices` | Local directory for PDFs |
| `LANDLORD_S3_BUCKET` | | S3 bucket name |
| `LANDLORD_S3_REGION` | | AWS region |
| `LANDLORD_S3_ACCESS_KEY_ID` | | AWS access key |
| `LANDLORD_S3_SECRET_ACCESS_KEY` | | AWS secret key |
| `LANDLORD_S3_ENDPOINT_URL` | | Custom S3 endpoint (MinIO, etc.) |
| `LANDLORD_S3_PRESIGNED_EXPIRY` | `604800` | Presigned URL expiry in seconds (default 7 days) |

### PIX

| Variable | Description |
|----------|-------------|
| `LANDLORD_PIX_KEY` | PIX key (CPF, email, phone, or random) |
| `LANDLORD_PIX_MERCHANT_NAME` | Merchant name for QR code |
| `LANDLORD_PIX_MERCHANT_CITY` | Merchant city for QR code |

### Web

| Variable | Default | Description |
|----------|---------|-------------|
| `LANDLORD_SECRET_KEY` | `change-me-in-production` | Secret key for session signing |

## Makefile Reference

### Local

| Command | Description |
|---------|-------------|
| `make install` | Create virtualenv and install dependencies |
| `make run` | Run the CLI |
| `make migrate` | Run pending Alembic migrations |
| `make web-run` | Start the web UI (uvicorn, port 8000) |
| `make web-createuser` | Create a web login user |
| `make regenerate-pdfs` | Regenerate all invoice PDFs |
| `make regenerate-pdfs-dry` | Preview regeneration (dry run) |

### Docker (Web)

| Command | Description |
|---------|-------------|
| `make build` | Build the web Docker image |
| `make up` / `make down` | Start / stop the web container |
| `make docker-createuser` | Create a login user in the container |
| `make shell` | Open a bash shell in the container |
| `make docker-migrate` | Run migrations in the container |
| `make logs` | Tail container logs |
| `make health` | Check the health endpoint |

### Docker (CLI)

| Command | Description |
|---------|-------------|
| `make build-cli` | Build the CLI Docker image |
| `make up-cli` / `make down-cli` | Start / stop the CLI container |
| `make landlord` | Run the CLI in the container |
| `make shell-cli` | Open a bash shell in the CLI container |

### Docker Compose

| Command | Description |
|---------|-------------|
| `make compose-up` / `compose-down` | Start / stop with Compose |
| `make compose-landlord` | Run the CLI via Compose |
| `make compose-createuser` | Create a login user via Compose |
| `make compose-migrate` | Run migrations via Compose |

## Architecture

```
landlord/
  settings.py          # Pydantic Settings (env prefix LANDLORD_)
  db.py                # SQLAlchemy engine + connection
  models/              # Pydantic models (Billing, Bill, User)
  repositories/        # Abstract base + SQLAlchemy Core implementation
  services/            # Business logic (billing, bill, user services)
  storage/             # Abstract base + Local / S3 implementations
  pdf/                 # fpdf2-based invoice generator
  cli/                 # Interactive menus (questionary + rich)
  scripts/             # Maintenance scripts (PDF regeneration)
web/
  app.py               # FastAPI app, middleware, templates
  auth.py              # Login, logout, change password routes
  deps.py              # Auth middleware, service factories
  routes/              # Billing + bill CRUD routes
  templates/           # Jinja2 + Bootstrap 5
  static/              # CSS + JS
```

## License

MIT
