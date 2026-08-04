#!/usr/bin/env bash
#
# Apply the example schemas (migrations) and their seed data to the local
# Supabase Postgres database.
#
# Order matters between the two groups, not within them:
#   1. Timestamped migration files (NNNNNNNNNNNNNN_*.sql) create the schemas,
#      enums, shared permissions, tables, functions and triggers.
#   2. *_seed.sql files insert demo data.
#
# Every module (desk, blog, crm, store, hr, finance, inventory,
# manufacturing, procurement, quality, lms, pm, ...) is self-contained and
# has no foreign keys into any other module's schema, so both groups can run
# in any order within themselves — they're sorted here only for a
# deterministic, readable log.
#
# These migrations are NOT idempotent: `create schema`, `create type`, and
# `create table` all fail if run twice. To reload cleanly, run
# `npx supabase db reset` first, then re-run this script.
#
# Connection: set DATABASE_URL to override. When unset and `psql` is not on
# PATH, the script falls back to `docker exec` into the Supabase DB container.
#
# Usage:
#   ./supabase/examples/apply.sh
#   DATABASE_URL=postgresql://... ./supabase/examples/apply.sh
#   npm run examples

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_supasheet}"

# Pick how to talk to Postgres.
if command -v psql >/dev/null 2>&1; then
  run_psql() { psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f - ; }
elif command -v docker >/dev/null 2>&1; then
  run_psql() { docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -f - ; }
else
  echo "error: neither 'psql' nor 'docker' is available on PATH" >&2
  exit 1
fi

apply() {
  local f="$1"
  if run_psql < "$DIR/$f" >/dev/null; then
    echo ">>> OK:     $f"
  else
    echo ">>> FAILED: $f" >&2
    exit 1
  fi
}

echo "########## MIGRATIONS ##########"
for f in $(ls "$DIR" | grep -E '^[0-9]{14}_.*\.sql$' | sort); do
  apply "$f"
done

echo "########## SEEDS ##########"
for f in $(ls "$DIR" | grep -E '_seed\.sql$' | sort); do
  apply "$f"
done

echo "########## DONE ##########"
