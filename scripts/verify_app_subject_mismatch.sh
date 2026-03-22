#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"
APP_ID="${APP_ID:-app-owner-$(date +%s)}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-template-demo}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-app-subject-mismatch}"
MISMATCH_APP_ID="${MISMATCH_APP_ID:-app-mismatch-$(date +%s)}"

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
  python3 - "$path" <<'PY'
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
PY
}

sql_escape() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "%s" "$value"
}

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$expected" == "$actual" ]] || fail "$message (expected=$expected actual=$actual)"
}

assert_non_empty() {
  local actual="$1"
  local message="$2"
  [[ -n "$actual" ]] || fail "$message"
}

assert_contains() {
  local text="$1"
  local needle="$2"
  local message="$3"
  [[ "$text" == *"$needle"* ]] || fail "$message (needle=$needle body=$text)"
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
  [[ "$success" == "true" ]] || fail "$label failed unexpectedly: $body"
}

assert_api_failure_contains() {
  local body="$1"
  local needle="$2"
  local label="$3"
  local success
  success="$(printf '%s' "$body" | json_get "success")"
  [[ "$success" == "false" ]] || fail "$label unexpectedly succeeded: $body"
  assert_contains "$body" "$needle" "$label failure message mismatch"
}

sql_scalar() {
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

require_cmd curl
require_cmd psql
require_cmd python3

[[ "$APP_ID" != "$MISMATCH_APP_ID" ]] || fail "APP_ID and MISMATCH_APP_ID must be different"

cat <<MSG
BASE_URL=${BASE_URL}
PGHOST=${PGHOST}
PGPORT=${PGPORT}
PGDATABASE=${PGDATABASE}
PGUSER=${PGUSER}
PGPASSWORD=<hidden>
APP_ID=${APP_ID}
APP_TEMPLATE_ID=${APP_TEMPLATE_ID}
REQUEST_ID_PREFIX=${REQUEST_ID_PREFIX}
REQUEST_ID=${REQUEST_ID}
MISMATCH_APP_ID=${MISMATCH_APP_ID}
MSG

echo
echo "== A1) APP apply =="
APPLY_RESPONSE="$(api_post "${BASE_URL}/app-certificates/apply" "{\"requestId\":\"${REQUEST_ID}\",\"templateId\":\"${APP_TEMPLATE_ID}\",\"appId\":\"${APP_ID}\"}")"
printf '%s\n' "$APPLY_RESPONSE"
assert_api_success "$APPLY_RESPONSE" "APP apply"
assert_equals "$REQUEST_ID" "$(printf '%s' "$APPLY_RESPONSE" | json_get "data.requestId")" "requestId mismatch after apply"

echo
echo "== A2) Query certificate status by requestId =="
STATUS_RESPONSE="$(api_get "${BASE_URL}/certificates/${REQUEST_ID}")"
printf '%s\n' "$STATUS_RESPONSE"
assert_api_success "$STATUS_RESPONSE" "status query"
CERT_SERIAL="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.certSerial")"
ISSUER_ID="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.issuerId")"
assert_non_empty "$CERT_SERIAL" "certSerial is empty after status query"
assert_non_empty "$ISSUER_ID" "issuerId is empty after status query"

echo
echo "== A3) Sync core_active =="
SYNC_RESPONSE="$(api_post "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID}" '{}')"
printf '%s\n' "$SYNC_RESPONSE"
assert_api_success "$SYNC_RESPONSE" "sync-core-active"

echo
echo "== A4) Current query to resolve shard =="
CURRENT_QUERY="$(api_post "${BASE_URL}/app-certificates/current/query" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"\"}")"
printf '%s\n' "$CURRENT_QUERY"
assert_api_success "$CURRENT_QUERY" "current query"
REAL_SUBJECT_ID="$(printf '%s' "$CURRENT_QUERY" | json_get "data.subjectId")"
SHARD_ID="$(printf '%s' "$CURRENT_QUERY" | json_get "data.shardId")"
assert_equals "$APP_ID" "$REAL_SUBJECT_ID" "real subjectId mismatch"
assert_non_empty "$SHARD_ID" "shardId is empty"
CORE_ACTIVE_TABLE="$(printf 'core_active_%02d' "$SHARD_ID")"

echo
echo "== B1) Revoke mismatch request =="
REVOKE_OUTBOX_BEFORE="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_outbox WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' AND event_type = 'REVOKE';")"
REVOKE_MISMATCH_RESPONSE="$(api_post "${BASE_URL}/app-certificates/revoke" "{\"appId\":\"${MISMATCH_APP_ID}\",\"installId\":\"\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$REVOKE_MISMATCH_RESPONSE"
assert_api_failure_contains "$REVOKE_MISMATCH_RESPONSE" "subject does not match certificate owner" "revoke mismatch"

echo
echo "== B2) SQL checks after revoke mismatch =="
CORE_ACTIVE_AFTER_REVOKE_MISMATCH="$(sql_scalar "SELECT COUNT(*) FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
REVOCATION_CURRENT_AFTER_REVOKE_MISMATCH="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_current WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
REVOKE_OUTBOX_AFTER="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_outbox WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' AND event_type = 'REVOKE';")"
assert_equals "1" "$CORE_ACTIVE_AFTER_REVOKE_MISMATCH" "certificate should remain in core_active after revoke mismatch"
assert_equals "0" "$REVOCATION_CURRENT_AFTER_REVOKE_MISMATCH" "revocation_current should remain empty after revoke mismatch"
assert_equals "$REVOKE_OUTBOX_BEFORE" "$REVOKE_OUTBOX_AFTER" "REVOKE outbox should not change after revoke mismatch"

echo
echo "== C1) Real revoke to prepare recover mismatch =="
REAL_REVOKE_RESPONSE="$(api_post "${BASE_URL}/app-certificates/revoke" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$REAL_REVOKE_RESPONSE"
assert_api_success "$REAL_REVOKE_RESPONSE" "real revoke"

echo
echo "== C2) Recover mismatch request =="
RECOVER_OUTBOX_BEFORE="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_outbox WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' AND event_type = 'RECOVER';")"
RECOVER_MISMATCH_RESPONSE="$(api_post "${BASE_URL}/app-certificates/recover" "{\"appId\":\"${MISMATCH_APP_ID}\",\"installId\":\"\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$RECOVER_MISMATCH_RESPONSE"
assert_api_failure_contains "$RECOVER_MISMATCH_RESPONSE" "subject does not match certificate owner" "recover mismatch"

echo
echo "== C3) SQL checks after recover mismatch =="
REVOCATION_CURRENT_AFTER_RECOVER_MISMATCH="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_current WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
CORE_ACTIVE_AFTER_RECOVER_MISMATCH="$(sql_scalar "SELECT COUNT(*) FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
RECOVER_OUTBOX_AFTER="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_outbox WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' AND event_type = 'RECOVER';")"
assert_equals "1" "$REVOCATION_CURRENT_AFTER_RECOVER_MISMATCH" "revocation_current should still contain certificate after recover mismatch"
assert_equals "0" "$CORE_ACTIVE_AFTER_RECOVER_MISMATCH" "recover mismatch should not write certificate back into core_active"
assert_equals "$RECOVER_OUTBOX_BEFORE" "$RECOVER_OUTBOX_AFTER" "RECOVER outbox should not change after recover mismatch"

echo
echo "[PASS] APP subject mismatch failure path verified"
echo "requestId=${REQUEST_ID}"
echo "realSubjectId=${REAL_SUBJECT_ID}"
echo "mismatchAppId=${MISMATCH_APP_ID}"
echo "certSerial=${CERT_SERIAL}"
echo "issuerId=${ISSUER_ID}"
echo "coreActiveTable=${CORE_ACTIVE_TABLE}"
