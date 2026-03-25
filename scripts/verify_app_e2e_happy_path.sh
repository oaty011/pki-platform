#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
REVOCATION_BASE_URL="${REVOCATION_BASE_URL:-http://localhost:18084}"
PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"
APP_ID="${APP_ID:-app-e2e-$(date +%s)}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-template-demo}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-app-e2e}"
TEST_CSR_DIR="${TEST_CSR_DIR:-.local/test-csr}"

REQUEST_ID="${APP_TEMPLATE_ID}:${APP_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')"
REQUEST_ID_FILE_SAFE="${REQUEST_ID//:/_}"
CSR_KEY_PATH="${TEST_CSR_DIR}/${REQUEST_ID_FILE_SAFE}.key.pem"
CSR_PATH="${TEST_CSR_DIR}/${REQUEST_ID_FILE_SAFE}.csr.pem"
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

assert_empty() {
  local actual="$1"
  local message="$2"
  [[ -z "$actual" ]] || fail "$message (actual=$actual)"
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
  [[ "$success" == "true" ]] || fail "$label failed: $body"
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
require_cmd openssl

mkdir -p "$TEST_CSR_DIR"

cat <<MSG
BASE_URL=${BASE_URL}
REVOCATION_BASE_URL=${REVOCATION_BASE_URL}
PGHOST=${PGHOST}
PGPORT=${PGPORT}
PGDATABASE=${PGDATABASE}
PGUSER=${PGUSER}
PGPASSWORD=<hidden>
APP_ID=${APP_ID}
APP_TEMPLATE_ID=${APP_TEMPLATE_ID}
REQUEST_ID_PREFIX=${REQUEST_ID_PREFIX}
REQUEST_ID=${REQUEST_ID}
TEST_CSR_DIR=${TEST_CSR_DIR}
MSG

echo
echo "== 1) Generate APP key and CSR =="
openssl genrsa -out "$CSR_KEY_PATH" 2048 >/dev/null 2>&1 || fail "failed to generate APP private key"
openssl req -new -sha256 \
  -key "$CSR_KEY_PATH" \
  -subj "/CN=${APP_ID}/OU=ignored-by-platform/O=ignored/C=CN" \
  -out "$CSR_PATH" >/dev/null 2>&1 || fail "failed to generate APP CSR"
CSR_CONTENT="$(cat "$CSR_PATH")"
assert_non_empty "$CSR_CONTENT" "CSR content is empty"

echo
echo "== 2) APP apply =="
APPLY_BODY="$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "templateId": sys.argv[2], "appId": sys.argv[3], "csr": open(sys.argv[4]).read()}))' "$REQUEST_ID" "$APP_TEMPLATE_ID" "$APP_ID" "$CSR_PATH")"
APPLY_RESPONSE="$(api_post "${BASE_URL}/app-certificates/apply" "$APPLY_BODY")"
printf '%s\n' "$APPLY_RESPONSE"
assert_api_success "$APPLY_RESPONSE" "APP apply"
assert_equals "$REQUEST_ID" "$(printf '%s' "$APPLY_RESPONSE" | json_get "data.requestId")" "requestId mismatch after apply"
assert_equals "ISSUED" "$(printf '%s' "$APPLY_RESPONSE" | json_get "data.status")" "apply status mismatch"

echo
echo "== 3) Query certificate status by requestId =="
STATUS_RESPONSE="$(api_get "${BASE_URL}/certificates/${REQUEST_ID}")"
printf '%s\n' "$STATUS_RESPONSE"
assert_api_success "$STATUS_RESPONSE" "status query"
CERT_SERIAL="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.certSerial")"
ISSUER_ID="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.issuerId")"
assert_non_empty "$CERT_SERIAL" "certSerial is empty after status query"
assert_non_empty "$ISSUER_ID" "issuerId is empty after status query"
assert_equals "ISSUED" "$(printf '%s' "$STATUS_RESPONSE" | json_get "data.status")" "certificate status mismatch"

echo
echo "== 4) Sync core_active =="
SYNC_RESPONSE="$(api_post "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID}" '{}')"
printf '%s\n' "$SYNC_RESPONSE"
assert_api_success "$SYNC_RESPONSE" "sync-core-active"
assert_equals "done" "$(printf '%s' "$SYNC_RESPONSE" | json_get "data.syncStatus")" "sync status mismatch"

echo
echo "== 5) First APP current query =="
CURRENT_QUERY_1="$(api_post "${BASE_URL}/app-certificates/current/query" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"\"}")"
printf '%s\n' "$CURRENT_QUERY_1"
assert_api_success "$CURRENT_QUERY_1" "first current query"
assert_equals "$APP_ID" "$(printf '%s' "$CURRENT_QUERY_1" | json_get "data.subjectId")" "current query subjectId mismatch"
assert_equals "$APP_ORGANIZATION" "$(printf '%s' "$CURRENT_QUERY_1" | json_get "data.organization")" "current query organization mismatch"
SHARD_ID="$(printf '%s' "$CURRENT_QUERY_1" | json_get "data.shardId")"
assert_non_empty "$SHARD_ID" "shardId is empty in current query"
CORE_ACTIVE_TABLE="$(printf 'core_active_%02d' "$SHARD_ID")"
assert_equals "$CERT_SERIAL" "$(printf '%s' "$CURRENT_QUERY_1" | json_get "data.currentActiveCertificate.certSerial")" "currentActiveCertificate certSerial mismatch"
assert_equals "$ISSUER_ID" "$(printf '%s' "$CURRENT_QUERY_1" | json_get "data.currentActiveCertificate.issuerId")" "currentActiveCertificate issuerId mismatch"

echo
echo "== 6) SQL checks after sync-core-active =="
ISSUE_FACT_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id = '$(sql_escape "$REQUEST_ID")';")"
CORE_ACTIVE_EXISTS_AFTER_SYNC="$(sql_scalar "SELECT COUNT(*) FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
CORE_ACTIVE_NOT_AFTER_AFTER_SYNC="$(sql_scalar "SELECT COALESCE(CAST(not_after AS text), '') FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' LIMIT 1;")"
assert_equals "1" "$ISSUE_FACT_COUNT" "issue_fact row count mismatch"
assert_equals "1" "$CORE_ACTIVE_EXISTS_AFTER_SYNC" "core_active row missing after sync"
assert_non_empty "$CORE_ACTIVE_NOT_AFTER_AFTER_SYNC" "core_active not_after is empty after sync"

echo
echo "== 7) APP revoke =="
REVOKE_RESPONSE="$(api_post "${REVOCATION_BASE_URL}/app-certificates/revoke" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$REVOKE_RESPONSE"
assert_api_success "$REVOKE_RESPONSE" "APP revoke"
assert_equals "revoked" "$(printf '%s' "$REVOKE_RESPONSE" | json_get "data.action")" "revoke action mismatch"

echo
echo "== 8) SQL checks after revoke =="
CORE_ACTIVE_EXISTS_AFTER_REVOKE="$(sql_scalar "SELECT COUNT(*) FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
REVOCATION_CURRENT_AFTER_REVOKE="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_current WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
OUTBOX_REVOKE_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_outbox WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' AND event_type = 'REVOKE';")"
assert_equals "0" "$CORE_ACTIVE_EXISTS_AFTER_REVOKE" "core_active row still exists after revoke"
assert_equals "1" "$REVOCATION_CURRENT_AFTER_REVOKE" "revocation_current row missing after revoke"
assert_equals "1" "$OUTBOX_REVOKE_COUNT" "REVOKE outbox count mismatch"

echo
echo "== 9) APP recover =="
RECOVER_RESPONSE="$(api_post "${REVOCATION_BASE_URL}/app-certificates/recover" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$RECOVER_RESPONSE"
assert_api_success "$RECOVER_RESPONSE" "APP recover"
assert_equals "recovered" "$(printf '%s' "$RECOVER_RESPONSE" | json_get "data.action")" "recover action mismatch"

echo
echo "== 10) SQL checks after recover =="
CORE_ACTIVE_EXISTS_AFTER_RECOVER="$(sql_scalar "SELECT COUNT(*) FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
CORE_ACTIVE_NOT_AFTER_AFTER_RECOVER="$(sql_scalar "SELECT COALESCE(CAST(not_after AS text), '') FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' LIMIT 1;")"
ISSUE_FACT_NOT_AFTER="$(sql_scalar "SELECT COALESCE(CAST(not_after AS text), '') FROM pki_issuance.certificate_issue_fact WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' ORDER BY created_at DESC LIMIT 1;")"
NOT_AFTER_MATCH="$(sql_scalar "SELECT CASE WHEN (SELECT not_after FROM pki_issuance.certificate_issue_fact WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' ORDER BY created_at DESC LIMIT 1) = (SELECT not_after FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' LIMIT 1) THEN 'true' ELSE 'false' END;")"
REVOCATION_CURRENT_AFTER_RECOVER="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_current WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
OUTBOX_RECOVER_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_outbox WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' AND event_type = 'RECOVER';")"
assert_equals "1" "$CORE_ACTIVE_EXISTS_AFTER_RECOVER" "core_active row missing after recover"
assert_non_empty "$CORE_ACTIVE_NOT_AFTER_AFTER_RECOVER" "recovered row not_after is empty"
assert_non_empty "$ISSUE_FACT_NOT_AFTER" "issue_fact not_after is empty"
assert_equals "true" "$NOT_AFTER_MATCH" "recovered not_after does not match issue_fact"
assert_equals "0" "$REVOCATION_CURRENT_AFTER_RECOVER" "revocation_current row still exists after recover"
assert_equals "1" "$OUTBOX_RECOVER_COUNT" "RECOVER outbox count mismatch"

echo
echo "== 11) Second APP current query =="
CURRENT_QUERY_2="$(api_post "${BASE_URL}/app-certificates/current/query" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"\"}")"
printf '%s\n' "$CURRENT_QUERY_2"
assert_api_success "$CURRENT_QUERY_2" "second current query"
assert_equals "$APP_ID" "$(printf '%s' "$CURRENT_QUERY_2" | json_get "data.subjectId")" "second current query subjectId mismatch"
assert_equals "$APP_ORGANIZATION" "$(printf '%s' "$CURRENT_QUERY_2" | json_get "data.organization")" "second current query organization mismatch"
assert_equals "$SHARD_ID" "$(printf '%s' "$CURRENT_QUERY_2" | json_get "data.shardId")" "second current query shardId mismatch"
assert_equals "$CERT_SERIAL" "$(printf '%s' "$CURRENT_QUERY_2" | json_get "data.currentActiveCertificate.certSerial")" "default query should return latest active certificate after recover"
assert_equals "$ISSUER_ID" "$(printf '%s' "$CURRENT_QUERY_2" | json_get "data.currentActiveCertificate.issuerId")" "default query latest active issuerId mismatch after recover"

echo
echo "[PASS] APP E2E happy path verified"
echo "requestId=${REQUEST_ID}"
echo "certSerial=${CERT_SERIAL}"
echo "issuerId=${ISSUER_ID}"
echo "coreActiveTable=${CORE_ACTIVE_TABLE}"
