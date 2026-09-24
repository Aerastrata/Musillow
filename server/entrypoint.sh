#!/bin/sh
set -e

# Wait for Postgres, then apply migrations and start the API.
echo "Running database migrations..."
alembic upgrade head

echo "Starting API..."
# --proxy-headers + trusting all forwarded IPs: correct scheme/client IP when
# running behind a reverse proxy (Nginx Proxy Manager terminating TLS).
exec uvicorn app.main:app --host 0.0.0.0 --port 8080 \
    --proxy-headers --forwarded-allow-ips="*"
