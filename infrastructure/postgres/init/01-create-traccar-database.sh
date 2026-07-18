#!/usr/bin/env bash
set -Eeuo pipefail

: "${TRACCAR_DB:?TRACCAR_DB is required}"
: "${TRACCAR_DB_USER:?TRACCAR_DB_USER is required}"
: "${TRACCAR_DB_PASSWORD:?TRACCAR_DB_PASSWORD is required}"

psql \
  --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=traccar_db="$TRACCAR_DB" \
  --set=traccar_user="$TRACCAR_DB_USER" \
  --set=traccar_password="$TRACCAR_DB_PASSWORD" <<'EOSQL'
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L',
  :'traccar_user',
  :'traccar_password'
)
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = :'traccar_user'
)\gexec

SELECT format(
  'CREATE DATABASE %I OWNER %I',
  :'traccar_db',
  :'traccar_user'
)
WHERE NOT EXISTS (
  SELECT 1 FROM pg_database WHERE datname = :'traccar_db'
)\gexec

SELECT format(
  'GRANT ALL PRIVILEGES ON DATABASE %I TO %I',
  :'traccar_db',
  :'traccar_user'
)\gexec
EOSQL
