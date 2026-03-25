#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
REVOCATION_BASE_URL="${REVOCATION_BASE_URL:-http://localhost:18084}"
PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-template-demo}"
APP_ID="${APP_ID:-revoke-concurrency-$(date +%s)}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-revoke-concurrency}"
CONCURRENCY="${CONCURRENCY:-5}"

REQUEST_ID="${APP_TEMPLATE_ID}:${APP_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

require_cmd curl
require_cmd psql
require_cmd python3

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
REQUEST_ID=${REQUEST_ID}
CONCURRENCY=${CONCURRENCY}
MSG

echo
echo "== 1) Prepare active certificate =="
APPLY_RESPONSE="$(api_post "${BASE_URL}/app-certificates/apply" "{\"requestId\":\"${REQUEST_ID}\",\"templateId\":\"${APP_TEMPLATE_ID}\",\"appId\":\"${APP_ID}\"}")"
printf '%s\n' "$APPLY_RESPONSE"
assert_api_success "$APPLY_RESPONSE" "APP apply"

STATUS_RESPONSE="$(api_get "${BASE_URL}/certificates/${REQUEST_ID}")"
printf '%s\n' "$STATUS_RESPONSE"
assert_api_success "$STATUS_RESPONSE" "status query"
CERT_SERIAL="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.certSerial")"
ISSUER_ID="$(printf '%s' "$STATUS_RESPONSE" | json_get "data.issuerId")"
assert_non_empty "$CERT_SERIAL" "certSerial is empty"
assert_non_empty "$ISSUER_ID" "issuerId is empty"

SYNC_RESPONSE="$(api_post "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID}" '{}')"
printf '%s\n' "$SYNC_RESPONSE"
assert_api_success "$SYNC_RESPONSE" "sync-core-active"

CURRENT_QUERY="$(api_post "${BASE_URL}/app-certificates/current/query" "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"\"}")"
printf '%s\n' "$CURRENT_QUERY"
assert_api_success "$CURRENT_QUERY" "current query"
SHARD_ID="$(printf '%s' "$CURRENT_QUERY" | json_get "data.shardId")"
assert_non_empty "$SHARD_ID" "shardId is empty"
CORE_ACTIVE_TABLE="$(printf 'core_active_%02d' "$SHARD_ID")"

echo
echo "== 2) Concurrent revoke =="
for i in $(seq 1 "$CONCURRENCY"); do
  (
    api_post "${REVOCATION_BASE_URL}/app-certificates/revoke" \
      "{\"appId\":\"${APP_ID}\",\"installId\":\"\",\"certSerial\":\"${CERT_SERIAL}\",\"issuerId\":\"${ISSUER_ID}\"}" \
      > "${TMP_DIR}/response_${i}.json"
  ) &
done
wait

for file in "${TMP_DIR}"/response_*.json; do
  echo "--- $(basename "$file") ---"
  cat "$file"
  echo
done

echo
echo "== 3) SQL checks =="
CORE_ACTIVE_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_app.${CORE_ACTIVE_TABLE} WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
REVOCATION_CURRENT_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_current WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")';")"
REVOKE_OUTBOX_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_revocation.revocation_outbox WHERE cert_serial = '$(sql_escape "$CERT_SERIAL")' AND issuer_id = '$(sql_escape "$ISSUER_ID")' AND event_type = 'REVOKE';")"

echo "core_active_count=${CORE_ACTIVE_COUNT}"
echo "revocation_current_count=${REVOCATION_CURRENT_COUNT}"
echo "revoke_outbox_count=${REVOKE_OUTBOX_COUNT}"

assert_equals "0" "$CORE_ACTIVE_COUNT" "concurrent revoke left certificate in core_active"
assert_equals "1" "$REVOCATION_CURRENT_COUNT" "concurrent revoke did not leave exactly one revocation_current row"
assert_equals "1" "$REVOKE_OUTBOX_COUNT" "concurrent revoke created duplicate REVOKE outbox rows"

echo
echo "[PASS] revoke idempotency concurrency verification passed"
