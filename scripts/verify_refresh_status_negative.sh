#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"
APP_ID="${APP_ID:-refresh-negative-app-$(date +%s)}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-controller-sdk}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-refresh-negative-app}"
TEST_CSR_DIR="${TEST_CSR_DIR:-.local/test-csr}"
MISMATCH_SUBJECT_ID="${MISMATCH_SUBJECT_ID:-mismatch-subject-$(date +%s)}"

REQUEST_ID="${APP_TEMPLATE_ID}:${APP_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')"
REQUEST_ID_FILE_SAFE="${REQUEST_ID//:/_}"
CSR_KEY_PATH="${TEST_CSR_DIR}/${REQUEST_ID_FILE_SAFE}.key.pem"
CSR_PATH="${TEST_CSR_DIR}/${REQUEST_ID_FILE_SAFE}.csr.pem"

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

assert_api_failure() {
  local body="$1"
  local label="$2"
  local success
  success="$(printf '%s' "$body" | json_get "success")"
  [[ "$success" == "false" ]] || fail "$label unexpectedly succeeded: $body"
}

assert_contains_any() {
  local body="$1"
  shift
  local expected
  for expected in "$@"; do
    [[ "$body" == *"$expected"* ]] && return 0
  done
  fail "response did not contain any expected message: $body"
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
MISMATCH_SUBJECT_ID=${MISMATCH_SUBJECT_ID}
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
CORE_ACTIVE_TABLE="$(printf 'core_active_%02d' "$SHARD_ID")"

echo
echo "== 5) subject mismatch should fail =="
SUBJECT_MISMATCH_RESPONSE="$(api_post "${BASE_URL}/certificates/refresh-status" "{\"subjectId\":\"${MISMATCH_SUBJECT_ID}\",\"organization\":\"${ORGANIZATION}\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$SUBJECT_MISMATCH_RESPONSE"
assert_api_failure "$SUBJECT_MISMATCH_RESPONSE" "subject mismatch refresh-status"
assert_contains_any \
  "$SUBJECT_MISMATCH_RESPONSE" \
  "certificate is not in core_active, refresh-status is not allowed" \
  "subject does not match certificate owner"

echo
echo "== 6) wrong issuerId should fail =="
WRONG_ISSUER_RESPONSE="$(api_post "${BASE_URL}/certificates/refresh-status" "{\"subjectId\":\"${SUBJECT_ID}\",\"organization\":\"${ORGANIZATION}\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}-wrong\"}")"
printf '%s\n' "$WRONG_ISSUER_RESPONSE"
assert_api_failure "$WRONG_ISSUER_RESPONSE" "wrong issuerId refresh-status"
[[ "$WRONG_ISSUER_RESPONSE" == *"certificate is not in core_active"* ]] || fail "wrong issuerId error message not found"

echo
echo "== 7) cert not in core_active should fail =="
DELETE_SQL="DELETE FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';"
sql_scalar "$DELETE_SQL" >/dev/null || fail "failed to remove core_active row for negative verification"
MISSING_CERT_RESPONSE="$(api_post "${BASE_URL}/certificates/refresh-status" "{\"subjectId\":\"${SUBJECT_ID}\",\"organization\":\"${ORGANIZATION}\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}")"
printf '%s\n' "$MISSING_CERT_RESPONSE"
assert_api_failure "$MISSING_CERT_RESPONSE" "missing cert refresh-status"
[[ "$MISSING_CERT_RESPONSE" == *"certificate is not in core_active"* ]] || fail "missing cert error message not found"

echo
echo "[PASS] refresh-status negative verification passed"
echo "requestId=${REQUEST_ID}"
echo "certSerial=${CERT_SERIAL}"
echo "issuerId=${ISSUER_ID}"
echo "coreActiveTable=${CORE_ACTIVE_TABLE}"
