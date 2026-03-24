#!/usr/bin/env bash
set -e

PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"

run_sql() {
  local sql="$1"
  PGPASSWORD="$PGPASSWORD" psql \
    -h "$PGHOST" \
    -p "$PGPORT" \
    -U "$PGUSER" \
    -d "$PGDATABASE" \
    -v ON_ERROR_STOP=1 \
    -X -qAt \
    -c "$sql"
}

echo "Verify is_current column dropped"
COLUMN_RESULT="$(run_sql "
SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE table_schema IN ('pki_app', 'pki_ecu')
  AND table_name LIKE 'core_active_%'
  AND column_name = 'is_current';
")"

if [[ -n "$COLUMN_RESULT" ]]; then
  echo "WARNING: is_current column still exists:"
  printf '%s\n' "$COLUMN_RESULT"
else
  echo "OK: no is_current column found in pki_app/pki_ecu core_active_xx tables"
fi

echo
echo "Verify is_current index dropped"
INDEX_RESULT="$(run_sql "
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname IN ('pki_app', 'pki_ecu')
  AND tablename LIKE 'core_active_%'
  AND indexdef ILIKE '%is_current%';
")"

if [[ -n "$INDEX_RESULT" ]]; then
  echo "WARNING: indexes referencing is_current still exist:"
  printf '%s\n' "$INDEX_RESULT"
else
  echo "OK: no indexes referencing is_current found in pki_app/pki_ecu core_active_xx tables"
fi
