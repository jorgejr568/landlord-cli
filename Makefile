IMAGE_NAME     := landlord-web
IMAGE_NAME_CLI := landlord-cli
CONTAINER      := landlord
CONTAINER_CLI  := landlord-cli

# --- Local development ---

.PHONY: install
install:
	python -m venv .venv
	.venv/bin/pip install -e .

.PHONY: run
run:
	.venv/bin/python -m landlord

.PHONY: migrate
migrate:
	.venv/bin/python -c "from landlord.db import initialize_db; initialize_db()"

.PHONY: regenerate-pdfs
regenerate-pdfs:
	.venv/bin/python -m landlord.scripts.regenerate_pdfs

.PHONY: regenerate-pdfs-dry
regenerate-pdfs-dry:
	.venv/bin/python -m landlord.scripts.regenerate_pdfs --dry-run

# --- Django Web (local) ---

.PHONY: web-run
web-run:
	cd web && ../.venv/bin/python manage.py runserver

.PHONY: web-migrate
web-migrate:
	cd web && ../.venv/bin/python manage.py migrate

.PHONY: web-createsuperuser
web-createsuperuser:
	cd web && ../.venv/bin/python manage.py createsuperuser

# --- Docker: Web (standalone) ---

.PHONY: build
build:
	docker build -t $(IMAGE_NAME) .

.PHONY: up
up:
	docker run -d --name $(CONTAINER) \
		--env-file .env \
		-p 8000:8000 \
		$(IMAGE_NAME)

.PHONY: down
down:
	docker rm -f $(CONTAINER) 2>/dev/null || true

.PHONY: restart
restart: down up

.PHONY: shell
shell:
	docker exec -it $(CONTAINER) bash

.PHONY: logs
logs:
	docker logs -f $(CONTAINER)

.PHONY: health
health:
	curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/

.PHONY: docker-migrate
docker-migrate:
	docker exec $(CONTAINER) sh -c "cd web && python manage.py migrate --no-input"

.PHONY: docker-createsuperuser
docker-createsuperuser:
	docker exec -it $(CONTAINER) sh -c "cd web && python manage.py createsuperuser"

.PHONY: docker-regenerate
docker-regenerate:
	docker exec $(CONTAINER) python -m landlord.scripts.regenerate_pdfs

# --- Docker: CLI (standalone) ---

.PHONY: build-cli
build-cli:
	docker build -f Dockerfile.cli -t $(IMAGE_NAME_CLI) .

.PHONY: up-cli
up-cli:
	docker run -d --name $(CONTAINER_CLI) \
		--env-file .env \
		-p 2019:2019 \
		$(IMAGE_NAME_CLI)

.PHONY: down-cli
down-cli:
	docker rm -f $(CONTAINER_CLI) 2>/dev/null || true

.PHONY: landlord
landlord:
	docker exec -it $(CONTAINER_CLI) python -m landlord

.PHONY: shell-cli
shell-cli:
	docker exec -it $(CONTAINER_CLI) bash

# --- Docker Compose ---

.PHONY: compose-up
compose-up:
	docker compose up -d --build

.PHONY: compose-down
compose-down:
	docker compose down

.PHONY: compose-restart
compose-restart:
	docker compose down
	docker compose up -d --build

.PHONY: compose-shell
compose-shell:
	docker compose exec landlord bash

.PHONY: compose-shell-cli
compose-shell-cli:
	docker compose exec cli bash

.PHONY: compose-landlord
compose-landlord:
	docker compose exec cli python -m landlord

.PHONY: compose-migrate
compose-migrate:
	docker compose exec landlord sh -c "cd web && python manage.py migrate --no-input"

.PHONY: compose-createsuperuser
compose-createsuperuser:
	docker compose exec landlord sh -c "cd web && python manage.py createsuperuser"

.PHONY: compose-regenerate
compose-regenerate:
	docker compose exec cli python -m landlord.scripts.regenerate_pdfs

.PHONY: compose-logs
compose-logs:
	docker compose logs -f
