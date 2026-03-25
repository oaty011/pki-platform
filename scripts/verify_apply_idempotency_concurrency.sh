#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
PGHOST="${PGHOST:?PGHOST is required}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:?PGDATABASE is required}"
PGUSER="${PGUSER:?PGUSER is required}"
PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-template-demo}"
APP_ID="${APP_ID:-apply-concurrency-$(date +%s)}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-apply-concurrency}"
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

api_post() {
  local url="$1"
  local body="$2"
  curl -sS -X POST "$url" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

require_cmd curl
require_cmd psql
require_cmd python3

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
CONCURRENCY=${CONCURRENCY}
MSG

echo
echo "== 1) Cleanup previous verification rows =="
sql_scalar "DELETE FROM pki_issuance.certificate_issue_fact WHERE request_id = '$(sql_escape "$REQUEST_ID")';" >/dev/null

echo
echo "== 2) Concurrent apply with same requestId =="
for i in $(seq 1 "$CONCURRENCY"); do
  (
    HTTP_CODE="$(curl -sS -o "${TMP_DIR}/response_${i}.json" -w '%{http_code}' -X POST "${BASE_URL}/app-certificates/apply" \
      -H 'Content-Type: application/json' \
      -d "{\"requestId\":\"${REQUEST_ID}\",\"templateId\":\"${APP_TEMPLATE_ID}\",\"appId\":\"${APP_ID}\"}")" \
      || HTTP_CODE="000"
    printf '%s\n' "${HTTP_CODE}" > "${TMP_DIR}/response_${i}.http"
  ) &
done
wait

SUCCESS_COUNT=0
HTTP_NON_200_COUNT=0
SUCCESS_FALSE_COUNT=0
EMPTY_RESPONSE_COUNT=0
for file in "${TMP_DIR}"/response_*.json; do
  echo "--- $(basename "$file") ---"
  cat "$file"
  echo
  http_file="${file%.json}.http"
  http_code="$(cat "$http_file" 2>/dev/null || printf '000')"
  echo "http_code=${http_code}"
  if [[ "$http_code" != "200" ]]; then
    HTTP_NON_200_COUNT=$((HTTP_NON_200_COUNT + 1))
  fi
  if [[ ! -s "$file" ]]; then
    EMPTY_RESPONSE_COUNT=$((EMPTY_RESPONSE_COUNT + 1))
    continue
  fi
  success="$(json_get "success" < "$file")"
  if [[ "$success" == "true" ]]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    status="$(json_get "data.status" < "$file")"
    [[ "$status" == "ISSUED" ]] || fail "apply response status mismatch in $(basename "$file") (actual=$status)"
  else
    SUCCESS_FALSE_COUNT=$((SUCCESS_FALSE_COUNT + 1))
  fi
done

echo
echo "== 2.1) Interface checks =="
echo "http_non_200_count=${HTTP_NON_200_COUNT}"
echo "success_false_count=${SUCCESS_FALSE_COUNT}"
echo "empty_response_count=${EMPTY_RESPONSE_COUNT}"
echo "successful_responses=${SUCCESS_COUNT}"

assert_equals "0" "$HTTP_NON_200_COUNT" "concurrent apply returned non-200 responses"
assert_equals "0" "$SUCCESS_FALSE_COUNT" "concurrent apply returned success=false responses"
assert_equals "0" "$EMPTY_RESPONSE_COUNT" "concurrent apply returned empty responses"
assert_equals "$CONCURRENCY" "$SUCCESS_COUNT" "concurrent apply did not return stable success for all requests"

echo
echo "== 3) SQL checks =="
ROW_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id = '$(sql_escape "$REQUEST_ID")';")"
DISTINCT_CERT_COUNT="$(sql_scalar "SELECT COUNT(DISTINCT COALESCE(cert_serial, '')) FROM pki_issuance.certificate_issue_fact WHERE request_id = '$(sql_escape "$REQUEST_ID")';")"
STATUS_COUNT="$(sql_scalar "SELECT COUNT(*) FROM pki_issuance.certificate_issue_fact WHERE request_id = '$(sql_escape "$REQUEST_ID")' AND status = 'ISSUED';")"

echo "issue_fact row count for requestId=${REQUEST_ID}: ${ROW_COUNT}"
echo "distinct certSerial count for requestId=${REQUEST_ID}: ${DISTINCT_CERT_COUNT}"
echo "issued row count for requestId=${REQUEST_ID}: ${STATUS_COUNT}"
echo "successful responses: ${SUCCESS_COUNT}"

assert_equals "1" "$ROW_COUNT" "concurrent apply created duplicate issue_fact rows"
assert_equals "1" "$DISTINCT_CERT_COUNT" "concurrent apply produced inconsistent certSerial values"
assert_equals "1" "$STATUS_COUNT" "concurrent apply did not leave exactly one ISSUED row"

echo
echo "[PASS] apply idempotency concurrency verification passed"
