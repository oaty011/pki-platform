#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"
APP_ID="${APP_ID:-compensation-app-$(date +%s)}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-template-demo}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-compensation-app}"
COMPENSATION_WAIT_TIMEOUT_SECONDS="${COMPENSATION_WAIT_TIMEOUT_SECONDS:-180}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-5}"

REQUEST_ID="${REQUEST_ID_PREFIX}-$(date +%Y%m%d%H%M%S)"
APP_ORGANIZATION="DFMC"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

json_get() {
  local path="$1"
  python3 -c '
import json
import sys

path = [p for p in sys.argv[1].split(".") if p]
data = json.load(sys.stdin)
cur = data
for part in path:
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print("")
        sys.exit(0)

if cur is None:
    print("")
elif isinstance(cur, bool):
    print("true" if cur else "false")
else:
    print(cur)
' "$path"
}

sql_escape() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "%s" "$value"
}

sql_scalar() {
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

assert_non_empty() {
  local actual="$1"
  local message="$2"
  [[ -n "$actual" ]] || {
    echo "[FAIL] $message" >&2
    exit 1
  }
}

api_post() {
  local url="$1"
  local body="$2"
  curl -sS -X POST "$url" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

api_get() {
  local url="$1"
  curl -sS "$url"
}

assert_api_success() {
  local body="$1"
  local label="$2"
  local success
  success="$(printf '%s' "$body" | json_get "success")"
  [[ "$success" == "true" ]] || {
    echo "[FAIL] $label failed: $body" >&2
    exit 1
  }
}

require_cmd curl
require_cmd psql
require_cmd python3

cat <<MSG
Compensation verification target:
- BASE_URL=${BASE_URL}
- APP_ID=${APP_ID}
- APP_TEMPLATE_ID=${APP_TEMPLATE_ID}
- REQUEST_ID=${REQUEST_ID}
- wait timeout seconds: ${COMPENSATION_WAIT_TIMEOUT_SECONDS}
- poll interval seconds: ${POLL_INTERVAL_SECONDS}

Before running:
- ensure pki-issuance-service is running
- ensure pki.issuance.sync-core-active-compensation.enabled=true
- ensure the compensation cron is frequent enough for this verification window
- do not call /certificates/sync-core-active/${REQUEST_ID} manually
MSG

echo
echo "== 1) Apply APP certificate without manual sync =="
APPLY_RESPONSE="$(api_post "${BASE_URL}/app-certificates/apply" "{\"requestId\":\"${REQUEST_ID}\",\"templateId\":\"${APP_TEMPLATE_ID}\",\"appId\":\"${APP_ID}\"}")"
printf '%s\n' "$APPLY_RESPONSE"
assert_api_success "$APPLY_RESPONSE" "APP apply"

echo
echo "== 2) Query initial status =="
STATUS_RESPONSE="$(api_get "${BASE_URL}/certificates/${REQUEST_ID}")"
printf '%s\n' "$STATUS_RESPONSE"
assert_api_success "$STATUS_RESPONSE" "status query"
CERT_SERIAL="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.certSerial")"
ISSUER_ID="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.issuerId")"
SYNC_STATUS="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.syncStatus")"
assert_non_empty "$CERT_SERIAL" "certSerial is empty after status query"
assert_non_empty "$ISSUER_ID" "issuerId is empty after status query"
assert_equals "pending" "$SYNC_STATUS" "initial sync_status should be pending"

echo
echo "== 3) Resolve shard by current query before compensation =="
CURRENT_QUERY="$(api_post "${BASE_URL}/app-certificates/current/query" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"\"}")"
printf '%s\n' "$CURRENT_QUERY"
assert_api_success "$CURRENT_QUERY" "current query"
SHARD_ID="$(printf '%s' "$CURRENT_QUERY" | json_get "data.shardId")"
assert_non_empty "$SHARD_ID" "shardId is empty"
CORE_ACTIVE_TABLE="$(printf 'core_active_%02d' "$SHARD_ID")"

echo
echo "Verification SQL:"
cat <<SQL
SELECT request_id, status, sync_status, cert_serial, issuer_id, subject_id, organization, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE request_id = '${REQUEST_ID}';

SELECT cert_serial, issuer_id, subject_id, not_after, first_activated_at, created_at, updated_at
FROM pki_app.${CORE_ACTIVE_TABLE}
WHERE cert_serial = '${CERT_SERIAL}'
  AND issuer_id = '${ISSUER_ID}';
SQL

echo
echo "== 4) Wait for compensation task =="
DEADLINE=$(( $(date +%s) + COMPENSATION_WAIT_TIMEOUT_SECONDS ))
while [[ $(date +%s) -lt $DEADLINE ]]; do
  SYNC_STATUS_NOW="$(sql_scalar "SELECT sync_status FROM pki_issuance.certificate_issue_fact WHERE request_id = '$(sql_escape "$REQUEST_ID")';")"
  CORE_ACTIVE_EXISTS="$(sql_scalar "SELECT COUNT(*) FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
  echo "sync_status=${SYNC_STATUS_NOW}, core_active_exists=${CORE_ACTIVE_EXISTS}"
  if [[ "$SYNC_STATUS_NOW" == "done" && "$CORE_ACTIVE_EXISTS" == "1" ]]; then
    break
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done

assert_equals "done" "$SYNC_STATUS_NOW" "sync_status was not compensated to done"
assert_equals "1" "$CORE_ACTIVE_EXISTS" "core_active row was not created by compensation"

echo
echo "Expected result:"
echo "- the ISSUED issue_fact row starts with sync_status=pending"
echo "- the compensation task changes sync_status to done"
echo "- the certificate appears in the resolved core_active shard without manual sync-core-active invocation"
echo
echo "[PASS] sync-core-active compensation verification passed"
