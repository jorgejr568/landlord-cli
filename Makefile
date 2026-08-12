PYTHON  := uv run --project backend python
PYTEST  := uv run --project backend pytest
RUFF    := uv run --project backend ruff
ALEMBIC := uv run --project backend alembic -c backend/alembic.ini
NPM_FRONTEND := npm --prefix frontend

RENTIVO_DB_ENV_FILE ?= .env.db
RENTIVO_APP_ENV_FILE ?= .env
RENTIVO_DEV_DB_ENV_FILE ?= .env.db
STACK_COMPOSE := RENTIVO_APP_ENV_FILE="$(RENTIVO_APP_ENV_FILE)" docker compose --env-file "$(RENTIVO_DB_ENV_FILE)"
DEV_COMPOSE := RENTIVO_APP_ENV_FILE="$(RENTIVO_APP_ENV_FILE)" docker compose --env-file "$(RENTIVO_DEV_DB_ENV_FILE)" -f docker-compose.yml -f docker-compose.dev.yml

# --- Local development ---

.PHONY: install
install:
	uv sync --all-extras
	uv run --project backend pre-commit install

.PHONY: migrate
migrate:
	$(ALEMBIC) upgrade head

.PHONY: migrate-fresh
migrate-fresh:
	$(PYTHON) -c "\
from rentivo.db import get_engine; \
from sqlalchemy import text; \
e = get_engine(); \
conn = e.connect(); \
conn.execute(text('SET FOREIGN_KEY_CHECKS = 0')); \
tables = [r[0] for r in conn.execute(text('SHOW TABLES')).fetchall()]; \
[conn.execute(text(f'DROP TABLE \`{t}\`')) for t in tables]; \
conn.execute(text('SET FOREIGN_KEY_CHECKS = 1')); \
conn.commit(); conn.close(); \
print(f'Dropped {len(tables)} tables.'); \
from rentivo.db import initialize_db; initialize_db(); \
print('Migrations applied.')"

.PHONY: regenerate-pdfs
regenerate-pdfs:
	$(PYTHON) -m rentivo.scripts.regenerate_pdfs

.PHONY: regenerate-pdfs-dry
regenerate-pdfs-dry:
	$(PYTHON) -m rentivo.scripts.regenerate_pdfs --dry-run

.PHONY: regenerate-recibos
regenerate-recibos:
	$(PYTHON) -m rentivo.scripts.regenerate_recibos

.PHONY: regenerate-recibos-dry
regenerate-recibos-dry:
	$(PYTHON) -m rentivo.scripts.regenerate_recibos --dry-run

.PHONY: backfill-encryption
backfill-encryption:
	$(PYTHON) -m rentivo.scripts.backfill_encryption

.PHONY: backfill-encryption-dry
backfill-encryption-dry:
	$(PYTHON) -m rentivo.scripts.backfill_encryption --dry-run

.PHONY: backfill-encryption-reset-blind-index
backfill-encryption-reset-blind-index:
	$(PYTHON) -m rentivo.scripts.backfill_encryption --reset-blind-index

.PHONY: redact-audit-logs
redact-audit-logs:
	$(PYTHON) -m rentivo.scripts.redact_audit_logs

.PHONY: redact-audit-logs-dry
redact-audit-logs-dry:
	$(PYTHON) -m rentivo.scripts.redact_audit_logs --dry-run

.PHONY: encrypt-job-payloads
encrypt-job-payloads:
	$(PYTHON) -m rentivo.scripts.encrypt_job_payloads

.PHONY: encrypt-job-payloads-dry
encrypt-job-payloads-dry:
	$(PYTHON) -m rentivo.scripts.encrypt_job_payloads --dry-run

.PHONY: seed
seed:
	$(PYTHON) -m rentivo.scripts.seed

# --- Lint & Format ---

.PHONY: fmt
fmt:
	$(RUFF) format .
	$(RUFF) check --fix .

.PHONY: lint
lint:
	$(RUFF) check .
	$(RUFF) format --check .

# --- Tests ---

.PHONY: test
test:
	$(PYTEST) -c backend/pyproject.toml -n auto

.PHONY: test-cov
test-cov:
	$(PYTEST) -c backend/pyproject.toml -n auto --cov --cov-config=backend/pyproject.toml --cov-report=term-missing

.PHONY: e2e
e2e:
	$(NPM_FRONTEND) run e2e

.PHONY: e2e-update
e2e-update:
	$(NPM_FRONTEND) run e2e:update

# --- React frontend & OpenAPI contract ---

.PHONY: frontend-install
frontend-install:
	$(NPM_FRONTEND) ci

.PHONY: frontend-dev
frontend-dev:
	$(NPM_FRONTEND) run dev

.PHONY: frontend-build
frontend-build:
	$(NPM_FRONTEND) run build

.PHONY: frontend-test-cov
frontend-test-cov:
	$(NPM_FRONTEND) test -- --run --coverage

.PHONY: frontend-check
frontend-check: frontend-test-cov
	$(NPM_FRONTEND) run typecheck
	$(NPM_FRONTEND) run typecheck:e2e
	$(NPM_FRONTEND) run lint
	$(NPM_FRONTEND) run build

.PHONY: openapi-export
openapi-export:
	$(NPM_FRONTEND) run api:snapshot

.PHONY: openapi-generate
openapi-generate:
	$(NPM_FRONTEND) run api:generate

.PHONY: openapi-check
openapi-check:
	$(NPM_FRONTEND) run api:check

.PHONY: ios-openapi-sync ios-openapi-check ios-test
ios-openapi-sync:
	./scripts/sync-ios-openapi.sh sync

ios-openapi-check:
	./scripts/sync-ios-openapi.sh check

ios-test:
	swift test --package-path ios

# The macOS app is ad-hoc signed for local builds; `macos-dmg` packages the
# drag-to-Applications installer into dist/.
MACOS_XCODEBUILD := xcodebuild -project macos/Rentivo.xcodeproj -scheme Rentivo

.PHONY: macos-build macos-test macos-dmg macos-app-icon
macos-build:
	$(MACOS_XCODEBUILD) -configuration Debug build CODE_SIGN_IDENTITY=-

macos-test:
	$(MACOS_XCODEBUILD) -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO

macos-dmg:
	./scripts/macos-dmg.sh

macos-app-icon:
	./scripts/macos-app-icon.sh

# Gradle needs a JDK 21 toolchain on PATH or in JAVA_HOME, and the Android SDK
# location in android/local.properties (or ANDROID_HOME).
.PHONY: android-openapi-sync android-openapi-check android-build android-test
android-openapi-sync:
	./scripts/sync-android-openapi.sh sync

android-openapi-check:
	./scripts/sync-android-openapi.sh check

android-build:
	cd android && ./gradlew assembleDebug

android-test:
	cd android && ./gradlew testDebugUnitTest

# Standalone CI scripts: outside backend/pyproject.toml's testpaths, so neither
# `make test` nor the pre-commit hook reaches them.
.PHONY: scripts-test
scripts-test:
	./scripts/tests/ios-ci-test.sh
	./scripts/tests/macos-ci-test.sh
	./scripts/tests/android-ci-test.sh
	./scripts/tests/ci-changed-areas-test.sh
	$(PYTEST) scripts/tests/test_asc_builds.py -q

# --- Worker (local) ---

.PHONY: worker
worker:
	$(PYTHON) -m rentivo.workers

# --- Docker: Worker (standalone) ---

IMAGE_NAME_WORKER := rentivo-worker
CONTAINER_WORKER  := rentivo-worker

.PHONY: build-worker
build-worker:
	docker build -f backend/Dockerfile.worker -t $(IMAGE_NAME_WORKER) .

.PHONY: up-worker
up-worker:
	docker run -d --name $(CONTAINER_WORKER) \
		--env-file .env \
		$(IMAGE_NAME_WORKER)

.PHONY: down-worker
down-worker:
	docker rm -f $(CONTAINER_WORKER) 2>/dev/null || true

.PHONY: logs-worker
logs-worker:
	docker logs -f $(CONTAINER_WORKER)

.PHONY: shell-worker
shell-worker:
	docker exec -it $(CONTAINER_WORKER) bash

# --- Docker Compose ---

.PHONY: compose-up
compose-up:
	$(DEV_COMPOSE) up -d --build

.PHONY: compose-down
compose-down:
	$(DEV_COMPOSE) down

.PHONY: compose-restart
compose-restart:
	$(DEV_COMPOSE) down
	$(DEV_COMPOSE) up -d --build

.PHONY: compose-dev
compose-dev:
	$(DEV_COMPOSE) up -d --build

.PHONY: compose-dev-down
compose-dev-down:
	$(DEV_COMPOSE) down

.PHONY: compose-shell
compose-shell:
	$(DEV_COMPOSE) exec api bash

.PHONY: compose-worker
compose-worker:
	$(DEV_COMPOSE) up -d --build worker

.PHONY: compose-logs-worker
compose-logs-worker:
	$(DEV_COMPOSE) logs -f worker

.PHONY: compose-migrate
compose-migrate:
	$(DEV_COMPOSE) run --rm migrate

.PHONY: compose-migrate-fresh
compose-migrate-fresh:
	$(DEV_COMPOSE) exec api python -c "\
from rentivo.db import get_engine; \
from sqlalchemy import text; \
e = get_engine(); \
conn = e.connect(); \
conn.execute(text('SET FOREIGN_KEY_CHECKS = 0')); \
tables = [r[0] for r in conn.execute(text('SHOW TABLES')).fetchall()]; \
[conn.execute(text(f'DROP TABLE \`{t}\`')) for t in tables]; \
conn.execute(text('SET FOREIGN_KEY_CHECKS = 1')); \
conn.commit(); conn.close(); \
print(f'Dropped {len(tables)} tables.')"
	$(DEV_COMPOSE) run --rm migrate

.PHONY: compose-createuser
compose-createuser:
	$(DEV_COMPOSE) exec -it api python -c "from rentivo.repositories.factory import get_user_repository; from rentivo.services.user_service import UserService; svc = UserService(get_user_repository()); username = input('Username: '); password = __import__('getpass').getpass('Password: '); svc.create_user(username, password); print(f'User {username} created.')"

.PHONY: compose-regenerate
compose-regenerate:
	$(DEV_COMPOSE) exec api python -m rentivo.scripts.regenerate_pdfs

.PHONY: compose-regenerate-recibos
compose-regenerate-recibos:
	$(DEV_COMPOSE) exec api python -m rentivo.scripts.regenerate_recibos

.PHONY: compose-logs
compose-logs:
	$(DEV_COMPOSE) logs -f

# --- Production stack ---

.PHONY: stack-config
stack-config:
	$(STACK_COMPOSE) config --quiet

.PHONY: stack-build
stack-build:
	$(STACK_COMPOSE) build validate migrate api worker frontend

.PHONY: stack-migrate
stack-migrate:
	$(STACK_COMPOSE) run --rm migrate

.PHONY: stack-up
stack-up:
	$(STACK_COMPOSE) up -d --build

.PHONY: stack-stop
stack-stop:
	$(STACK_COMPOSE) stop proxy frontend api worker

.PHONY: jaeger-up
jaeger-up:
	$(DEV_COMPOSE) --profile observability up -d jaeger
	@echo "Jaeger UI: http://localhost:16686"
	@echo "Set RENTIVO_OTEL_ENABLED=true and RENTIVO_OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318 (compose) to send traces."

.PHONY: jaeger-down
jaeger-down:
	$(DEV_COMPOSE) --profile observability stop jaeger

.PHONY: temporal-up
temporal-up:
	$(DEV_COMPOSE) --profile temporal up -d temporal temporal-ui
	@echo "Temporal UI at http://localhost:8233 — set RENTIVO_JOB_BACKEND=temporal and RENTIVO_TEMPORAL_HOST=temporal:7233 (compose) or localhost:7233 (host)."

.PHONY: temporal-down
temporal-down:
	$(DEV_COMPOSE) --profile temporal stop temporal temporal-ui
