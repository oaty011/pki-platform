#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"
APP_ID="${APP_ID:-refresh-app-$(date +%s)}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-controller-sdk}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-refresh-app}"
TEST_CSR_DIR="${TEST_CSR_DIR:-.local/test-csr}"

REQUEST_ID="${REQUEST_ID_PREFIX}-$(date +%Y%m%d%H%M%S)"
CSR_KEY_PATH="${TEST_CSR_DIR}/${REQUEST_ID}.key.pem"
CSR_PATH="${TEST_CSR_DIR}/${REQUEST_ID}.csr.pem"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing required command: $1" >&2
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

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_non_empty() {
  local actual="$1"
  local message="$2"
  [[ -n "$actual" ]] || fail "$message"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$expected" == "$actual" ]] || fail "$message (expected=$expected actual=$actual)"
}

api_post() {
  local url="$1"
  local body="$2"
  curl -sS -X POST "$url" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

assert_api_success() {
  local body="$1"
  local label="$2"
  local success
  success="$(printf '%s' "$body" | json_get "success")"
  [[ "$success" == "true" ]] || fail "$label failed: $body"
}

assert_json_path_empty() {
  local body="$1"
  local path="$2"
  local message="$3"
  local value
  value="$(printf '%s' "$body" | json_get "$path")"
  [[ -z "$value" ]] || fail "$message (actual=$value)"
}

require_cmd curl
require_cmd python3
require_cmd psql
require_cmd openssl

mkdir -p "$TEST_CSR_DIR"

cat <<MSG
BASE_URL=${BASE_URL}
PGHOST=${PGHOST}
PGPORT=${PGPORT}
PGDATABASE=${PGDATABASE}
PGUSER=${PGUSER}
PGPASSWORD=<hidden>
APP_ID=${APP_ID}
APP_TEMPLATE_ID=${APP_TEMPLATE_ID}
REQUEST_ID=${REQUEST_ID}
TEST_CSR_DIR=${TEST_CSR_DIR}
MSG

echo
echo "== 1) Generate temporary APP key and CSR =="
openssl genrsa -out "$CSR_KEY_PATH" 2048 >/dev/null 2>&1 || fail "failed to generate APP private key"
openssl req -new -sha256 \
  -key "$CSR_KEY_PATH" \
  -subj "/CN=${APP_ID}/OU=ignored-by-platform/O=ignored/C=CN" \
  -out "$CSR_PATH" >/dev/null 2>&1 || fail "failed to generate APP CSR"

echo
echo "== 2) APP apply =="
APPLY_BODY="$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "templateId": sys.argv[2], "appId": sys.argv[3], "csr": open(sys.argv[4]).read()}))' "$REQUEST_ID" "$APP_TEMPLATE_ID" "$APP_ID" "$CSR_PATH")"
APPLY_RESPONSE="$(api_post "${BASE_URL}/app-certificates/apply" "$APPLY_BODY")"
printf '%s\n' "$APPLY_RESPONSE"
assert_api_success "$APPLY_RESPONSE" "APP apply"

echo
echo "== 3) Sync core_active =="
SYNC_RESPONSE="$(api_post "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID}" '{}')"
printf '%s\n' "$SYNC_RESPONSE"
assert_api_success "$SYNC_RESPONSE" "sync-core-active"
assert_equals "done" "$(printf '%s' "$SYNC_RESPONSE" | json_get "data.syncStatus")" "sync status mismatch"

echo
echo "== 4) Query current APP certificate =="
CURRENT_QUERY="$(api_post "${BASE_URL}/app-certificates/current/query" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"\"}")"
printf '%s\n' "$CURRENT_QUERY"
assert_api_success "$CURRENT_QUERY" "current query"
SUBJECT_ID="$(printf '%s' "$CURRENT_QUERY" | json_get "data.subjectId")"
ORGANIZATION="$(printf '%s' "$CURRENT_QUERY" | json_get "data.organization")"
SHARD_ID="$(printf '%s' "$CURRENT_QUERY" | json_get "data.shardId")"
CERT_SERIAL="$(printf '%s' "$CURRENT_QUERY" | json_get "data.currentActiveCertificate.certSerial")"
ISSUER_ID="$(printf '%s' "$CURRENT_QUERY" | json_get "data.currentActiveCertificate.issuerId")"
assert_non_empty "$SUBJECT_ID" "subjectId is empty"
assert_non_empty "$ORGANIZATION" "organization is empty"
assert_non_empty "$SHARD_ID" "shardId is empty"
assert_non_empty "$CERT_SERIAL" "certSerial is empty"
assert_non_empty "$ISSUER_ID" "issuerId is empty"
assert_json_path_empty "$CURRENT_QUERY" "data.currentActiveCertificate.isCurrent" "current query should not expose isCurrent"
CORE_ACTIVE_TABLE="$(printf 'core_active_%02d' "$SHARD_ID")"

echo
echo "== 5) Query updated_at before refresh =="
UPDATED_AT_BEFORE="$(sql_scalar "SELECT COALESCE(CAST(updated_at AS text), '') FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' LIMIT 1;")"
CREATED_AT_BEFORE="$(sql_scalar "SELECT COALESCE(CAST(created_at AS text), '') FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' LIMIT 1;")"
assert_non_empty "$UPDATED_AT_BEFORE" "updated_at before refresh is empty"
assert_non_empty "$CREATED_AT_BEFORE" "created_at before refresh is empty"
echo "created_at=${CREATED_AT_BEFORE}"
echo "updated_at(before)=${UPDATED_AT_BEFORE}"

sleep 1

echo
echo "== 6) Refresh certificate status =="
REFRESH_RESPONSE="$(api_post "${BASE_URL}/certificates/refresh-status" "{\"subjectId\":\"${SUBJECT_ID}\",\"organization\":\"${ORGANIZATION}\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$REFRESH_RESPONSE"
assert_api_success "$REFRESH_RESPONSE" "refresh-status"
assert_equals "true" "$(printf '%s' "$REFRESH_RESPONSE" | json_get "data.refreshed")" "refresh-status did not return refreshed=true"

echo
echo "== 7) Query updated_at after refresh =="
UPDATED_AT_AFTER="$(sql_scalar "SELECT COALESCE(CAST(updated_at AS text), '') FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' LIMIT 1;")"
assert_non_empty "$UPDATED_AT_AFTER" "updated_at after refresh is empty"
echo "updated_at(after)=${UPDATED_AT_AFTER}"

IS_LATER="$(python3 -c 'import sys; from datetime import datetime; before = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")); after = datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00")); print("true" if after > before else "false")' "$UPDATED_AT_BEFORE" "$UPDATED_AT_AFTER")"
assert_equals "true" "$IS_LATER" "updated_at was not refreshed to a later timestamp"

echo
echo "[PASS] refresh-status verification passed"
echo "requestId=${REQUEST_ID}"
echo "certSerial=${CERT_SERIAL}"
echo "issuerId=${ISSUER_ID}"
echo "coreActiveTable=${CORE_ACTIVE_TABLE}"
