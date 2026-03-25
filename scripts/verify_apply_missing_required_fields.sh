#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
APP_ID="${APP_ID:-apply-missing-app-$(date +%s)}"
DEVICE_ID="${DEVICE_ID:-apply-missing-device-$(date +%s)}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-controller-sdk}"
ECU_TEMPLATE_ID="${ECU_TEMPLATE_ID:-ecu-tbox}"
TEST_CSR_DIR="${TEST_CSR_DIR:-.local/test-csr}"

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

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_non_empty() {
  local actual="$1"
  local message="$2"
  [[ -n "$actual" ]] || fail "$message"
}

request_id() {
  local template_id="$1"
  local subject_id="$2"
  printf '%s:%s:%s:%s' \
    "$template_id" \
    "$subject_id" \
    "$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])')" \
    "$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')"
}

api_post_capture() {
  local url="$1"
  local body="$2"
  local body_file="$3"
  curl -sS -o "$body_file" -w '%{http_code}' -X POST "$url" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

assert_business_failure_any() {
  local http_code="$1"
  local body="$2"
  shift 2
  [[ "$http_code" == "400" ]] || fail "expected HTTP 400, got ${http_code}: ${body}"
  [[ "$(printf '%s' "$body" | json_get "success")" == "false" ]] || fail "expected success=false: ${body}"
  local message
  message="$(printf '%s' "$body" | json_get "message")"
  assert_non_empty "$message" "error message is empty"
  local expected
  for expected in "$@"; do
    [[ "$message" == *"$expected"* ]] && return 0
  done
  fail "unexpected error message: ${body}"
}

require_cmd curl
require_cmd python3
require_cmd openssl

mkdir -p "$TEST_CSR_DIR"

APP_KEY_PATH="${TEST_CSR_DIR}/apply-missing-app.key.pem"
APP_CSR_PATH="${TEST_CSR_DIR}/apply-missing-app.csr.pem"
ECU_KEY_PATH="${TEST_CSR_DIR}/apply-missing-ecu.key.pem"
ECU_CSR_PATH="${TEST_CSR_DIR}/apply-missing-ecu.csr.pem"
CASE1_BODY_FILE="$(mktemp)"
CASE2_BODY_FILE="$(mktemp)"
CASE3_BODY_FILE="$(mktemp)"
CASE4_BODY_FILE="$(mktemp)"
trap 'rm -f "$CASE1_BODY_FILE" "$CASE2_BODY_FILE" "$CASE3_BODY_FILE" "$CASE4_BODY_FILE"' EXIT

openssl genrsa -out "$APP_KEY_PATH" 2048 >/dev/null 2>&1 || fail "failed to generate APP private key"
openssl req -new -sha256 -key "$APP_KEY_PATH" -subj "/CN=${APP_ID}/OU=ignored/O=ignored/C=CN" -out "$APP_CSR_PATH" >/dev/null 2>&1 || fail "failed to generate APP CSR"
openssl genrsa -out "$ECU_KEY_PATH" 2048 >/dev/null 2>&1 || fail "failed to generate ECU private key"
openssl req -new -sha256 -key "$ECU_KEY_PATH" -subj "/CN=${DEVICE_ID}/OU=ignored/O=ignored/C=CN" -out "$ECU_CSR_PATH" >/dev/null 2>&1 || fail "failed to generate ECU CSR"

APP_CSR_CONTENT="$(cat "$APP_CSR_PATH")"
ECU_CSR_CONTENT="$(cat "$ECU_CSR_PATH")"

echo
echo "== 1) APP apply missing requestId should fail =="
CASE1_HTTP_CODE="$(api_post_capture "${BASE_URL}/app-certificates/apply" "$(python3 -c 'import json,sys; print(json.dumps({"templateId": sys.argv[1], "appId": sys.argv[2], "csr": sys.argv[3]}))' "$APP_TEMPLATE_ID" "$APP_ID" "$APP_CSR_CONTENT")" "$CASE1_BODY_FILE")"
CASE1_BODY="$(cat "$CASE1_BODY_FILE")"
printf '%s\n' "$CASE1_BODY"
assert_business_failure_any "$CASE1_HTTP_CODE" "$CASE1_BODY" "requestId and templateId are required"

echo
echo "== 2) APP apply missing templateId should fail =="
CASE2_REQUEST_ID="$(request_id "$APP_TEMPLATE_ID" "$APP_ID")"
CASE2_HTTP_CODE="$(api_post_capture "${BASE_URL}/app-certificates/apply" "$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "appId": sys.argv[2], "csr": sys.argv[3]}))' "$CASE2_REQUEST_ID" "$APP_ID" "$APP_CSR_CONTENT")" "$CASE2_BODY_FILE")"
CASE2_BODY="$(cat "$CASE2_BODY_FILE")"
printf '%s\n' "$CASE2_BODY"
assert_business_failure_any "$CASE2_HTTP_CODE" "$CASE2_BODY" "requestId and templateId are required"

echo
echo "== 3) ECU apply missing deviceId should fail =="
CASE3_REQUEST_ID="$(request_id "$ECU_TEMPLATE_ID" "$DEVICE_ID")"
CASE3_HTTP_CODE="$(api_post_capture "${BASE_URL}/ecu-certificates/apply" "$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "templateId": sys.argv[2], "csr": sys.argv[3]}))' "$CASE3_REQUEST_ID" "$ECU_TEMPLATE_ID" "$ECU_CSR_CONTENT")" "$CASE3_BODY_FILE")"
CASE3_BODY="$(cat "$CASE3_BODY_FILE")"
printf '%s\n' "$CASE3_BODY"
assert_business_failure_any "$CASE3_HTTP_CODE" "$CASE3_BODY" "deviceId is required"

echo
echo "== 4) APP apply missing csr should fail =="
CASE4_REQUEST_ID="$(request_id "$APP_TEMPLATE_ID" "$APP_ID")"
CASE4_HTTP_CODE="$(api_post_capture "${BASE_URL}/app-certificates/apply" "$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "templateId": sys.argv[2], "appId": sys.argv[3]}))' "$CASE4_REQUEST_ID" "$APP_TEMPLATE_ID" "$APP_ID")" "$CASE4_BODY_FILE")"
CASE4_BODY="$(cat "$CASE4_BODY_FILE")"
printf '%s\n' "$CASE4_BODY"
assert_business_failure_any "$CASE4_HTTP_CODE" "$CASE4_BODY" "csr is required"

echo
echo "[PASS] apply missing required fields verification passed"
