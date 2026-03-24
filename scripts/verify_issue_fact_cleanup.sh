#!/usr/bin/env bash
set -euo pipefail

PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"

CLEANUP_RETENTION_DAYS="${CLEANUP_RETENTION_DAYS:-30}"
CLEANUP_BATCH_SIZE="${CLEANUP_BATCH_SIZE:-1}"
CLEANUP_WAIT_TIMEOUT_SECONDS="${CLEANUP_WAIT_TIMEOUT_SECONDS:-180}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-5}"

NOW_SUFFIX="$(date +%Y%m%d%H%M%S)"
OLD_REQUEST_ID_1="cleanup-old-1-${NOW_SUFFIX}"
OLD_REQUEST_ID_2="cleanup-old-2-${NOW_SUFFIX}"
NEW_REQUEST_ID="cleanup-new-${NOW_SUFFIX}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

sql() {
  local sql_text="$1"
  PGPASSWORD="$PGPASSWORD" psql \
    -h "$PGHOST" \
    -p "$PGPORT" \
    -U "$PGUSER" \
    -d "$PGDATABASE" \
    -v ON_ERROR_STOP=1 \
    -X -qAt \
    -c "$sql_text"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$expected" == "$actual" ]] || {
    echo "[FAIL] $message (expected=$expected actual=$actual)" >&2
    exit 1
  }
}

require_cmd psql

cat <<MSG
Cleanup verification target:
- issue_fact retention days: ${CLEANUP_RETENTION_DAYS}
- cleanup batch size: ${CLEANUP_BATCH_SIZE}
- wait timeout seconds: ${CLEANUP_WAIT_TIMEOUT_SECONDS}
- poll interval seconds: ${POLL_INTERVAL_SECONDS}

Before running:
- ensure pki-issuance-service is running
- ensure pki.issuance.issue-fact-cleanup.enabled=true
- ensure pki.issuance.issue-fact-cleanup.retention-days=${CLEANUP_RETENTION_DAYS}
- ensure pki.issuance.issue-fact-cleanup.batch-size=${CLEANUP_BATCH_SIZE}
- ensure the cleanup cron is frequent enough for this verification window
MSG

echo
echo "== 1) Insert cleanup verification rows =="
sql "DELETE FROM pki_issuance.certificate_issue_fact WHERE request_id IN ('${OLD_REQUEST_ID_1}', '${OLD_REQUEST_ID_2}', '${NEW_REQUEST_ID}');"
sql "
INSERT INTO pki_issuance.certificate_issue_fact (
  request_id, template_id, subject_id, organization, issuer_id, signer_id, cert_serial, certificate_pem, not_after, status, sync_status, created_at, updated_at
) VALUES
  ('${OLD_REQUEST_ID_1}', 'app-template-demo', 'cleanup-subject-old-1', 'DFMC', 'cleanup-issuer', 'cleanup-signer', 'cleanup-serial-old-1', 'pem', NOW() - INTERVAL '$((CLEANUP_RETENTION_DAYS + 1)) days', 'ISSUED', 'done', NOW() - INTERVAL '$((CLEANUP_RETENTION_DAYS + 1)) days', NOW() - INTERVAL '$((CLEANUP_RETENTION_DAYS + 1)) days'),
  ('${OLD_REQUEST_ID_2}', 'app-template-demo', 'cleanup-subject-old-2', 'DFMC', 'cleanup-issuer', 'cleanup-signer', 'cleanup-serial-old-2', 'pem', NOW() - INTERVAL '$((CLEANUP_RETENTION_DAYS + 1)) days', 'ISSUED', 'done', NOW() - INTERVAL '$((CLEANUP_RETENTION_DAYS + 1)) days', NOW() - INTERVAL '$((CLEANUP_RETENTION_DAYS + 1)) days'),
  ('${NEW_REQUEST_ID}', 'app-template-demo', 'cleanup-subject-new', 'DFMC', 'cleanup-issuer', 'cleanup-signer', 'cleanup-serial-new', 'pem', NOW() + INTERVAL '90 days', 'ISSUED', 'done', NOW(), NOW());
"

echo
echo "Verification SQL:"
cat <<SQL
SELECT request_id, created_at
FROM pki_issuance.certificate_issue_fact
WHERE request_id IN ('${OLD_REQUEST_ID_1}', '${OLD_REQUEST_ID_2}', '${NEW_REQUEST_ID}')
ORDER BY created_at ASC;
SQL

INITIAL_OLD_COUNT="$(sql "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id IN ('${OLD_REQUEST_ID_1}', '${OLD_REQUEST_ID_2}');")"
INITIAL_NEW_COUNT="$(sql "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id = '${NEW_REQUEST_ID}';")"
assert_equals "2" "$INITIAL_OLD_COUNT" "old cleanup rows were not inserted"
assert_equals "1" "$INITIAL_NEW_COUNT" "new cleanup row was not inserted"

echo
echo "== 2) Waiting for first cleanup batch =="
FIRST_BATCH_DEADLINE=$(( $(date +%s) + CLEANUP_WAIT_TIMEOUT_SECONDS ))
FIRST_BATCH_DELETED=0
while [[ $(date +%s) -lt $FIRST_BATCH_DEADLINE ]]; do
  REMAINING_OLD="$(sql "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id IN ('${OLD_REQUEST_ID_1}', '${OLD_REQUEST_ID_2}');")"
  REMAINING_NEW="$(sql "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id = '${NEW_REQUEST_ID}';")"
  echo "old_rows_remaining=${REMAINING_OLD}, new_rows_remaining=${REMAINING_NEW}"
  if [[ "$REMAINING_OLD" == "1" ]]; then
    FIRST_BATCH_DELETED=1
    break
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done

[[ "$FIRST_BATCH_DELETED" == "1" ]] || {
  echo "[FAIL] cleanup did not delete exactly one old row within the expected window" >&2
  exit 1
}
assert_equals "1" "$REMAINING_NEW" "cleanup deleted the fresh issue_fact row in the first batch"

echo
echo "== 3) Waiting for second cleanup batch =="
SECOND_BATCH_DEADLINE=$(( $(date +%s) + CLEANUP_WAIT_TIMEOUT_SECONDS ))
SECOND_BATCH_DELETED=0
while [[ $(date +%s) -lt $SECOND_BATCH_DEADLINE ]]; do
  REMAINING_OLD="$(sql "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id IN ('${OLD_REQUEST_ID_1}', '${OLD_REQUEST_ID_2}');")"
  REMAINING_NEW="$(sql "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id = '${NEW_REQUEST_ID}';")"
  echo "old_rows_remaining=${REMAINING_OLD}, new_rows_remaining=${REMAINING_NEW}"
  if [[ "$REMAINING_OLD" == "0" ]]; then
    SECOND_BATCH_DELETED=1
    break
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done

[[ "$SECOND_BATCH_DELETED" == "1" ]] || {
  echo "[FAIL] cleanup did not delete the remaining old row within the expected window" >&2
  exit 1
}
assert_equals "1" "$REMAINING_NEW" "cleanup deleted the fresh issue_fact row in the second batch"

echo
echo "Expected result:"
echo "- two expired rows are deleted in at least two scheduler passes when batch-size=${CLEANUP_BATCH_SIZE}"
echo "- the fresh row remains"
echo
echo "[PASS] issue_fact cleanup verification passed"
