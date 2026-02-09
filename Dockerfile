FROM python:3.10-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    default-mysql-client \
    libmariadb-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml .
RUN mkdir -p landlord web && touch landlord/__init__.py web/__init__.py
RUN pip install --no-cache-dir .

COPY . .
RUN pip install --no-cache-dir .

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')"

CMD ["sh", "-c", "python -c 'from landlord.db import initialize_db; initialize_db()' && uvicorn web.app:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'"]
