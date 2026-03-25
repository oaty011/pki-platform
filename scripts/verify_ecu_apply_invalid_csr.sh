#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
DEVICE_ID="${DEVICE_ID:-ecu-invalid-csr-$(date +%s)}"
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
  local subject_id="$1"
  printf '%s:%s:%s:%s' \
    "$ECU_TEMPLATE_ID" \
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

assert_business_failure() {
  local http_code="$1"
  local body="$2"
  local expected_message="$3"
  [[ "$http_code" == "400" ]] || fail "expected HTTP 400, got ${http_code}: ${body}"
  [[ "$(printf '%s' "$body" | json_get "success")" == "false" ]] || fail "expected success=false: ${body}"
  local message
  message="$(printf '%s' "$body" | json_get "message")"
  assert_non_empty "$message" "error message is empty"
  [[ "$message" == *"$expected_message"* ]] || fail "expected message to contain '$expected_message': ${body}"
}

mutate_csr_signature() {
  local source_pem="$1"
  local target_pem="$2"
  python3 - "$source_pem" "$target_pem" <<'PY'
import base64
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
target = pathlib.Path(sys.argv[2])
body = "".join(line.strip() for line in source.splitlines() if "BEGIN" not in line and "END" not in line)
data = bytearray(base64.b64decode(body))
if len(data) < 32:
    raise SystemExit("CSR DER too short to mutate signature bytes")
idx = len(data) - 12
data[idx] ^= 0x01
encoded = base64.encodebytes(bytes(data)).decode().replace("\n", "")
wrapped = "\n".join(encoded[i:i+64] for i in range(0, len(encoded), 64))
target.write_text("-----BEGIN CERTIFICATE REQUEST-----\n" + wrapped + "\n-----END CERTIFICATE REQUEST-----\n")
PY
}

require_cmd curl
require_cmd python3
require_cmd openssl

mkdir -p "$TEST_CSR_DIR"

VALID_KEY_PATH="${TEST_CSR_DIR}/ecu-invalid-csr.key.pem"
VALID_CSR_PATH="${TEST_CSR_DIR}/ecu-invalid-csr.csr.pem"
BROKEN_CSR_PATH="${TEST_CSR_DIR}/ecu-invalid-csr-broken.csr.pem"
INVALID_BODY_FILE="$(mktemp)"
EMPTY_BODY_FILE="$(mktemp)"
BROKEN_BODY_FILE="$(mktemp)"
trap 'rm -f "$INVALID_BODY_FILE" "$EMPTY_BODY_FILE" "$BROKEN_BODY_FILE"' EXIT

cat <<MSG
BASE_URL=${BASE_URL}
DEVICE_ID=${DEVICE_ID}
ECU_TEMPLATE_ID=${ECU_TEMPLATE_ID}
TEST_CSR_DIR=${TEST_CSR_DIR}
MSG

echo
echo "== 1) Generate valid ECU CSR and tampered CSR =="
openssl genrsa -out "$VALID_KEY_PATH" 2048 >/dev/null 2>&1 || fail "failed to generate ECU private key"
openssl req -new -sha256 \
  -key "$VALID_KEY_PATH" \
  -subj "/CN=${DEVICE_ID}/OU=ignored-by-platform/O=ignored/C=CN" \
  -out "$VALID_CSR_PATH" >/dev/null 2>&1 || fail "failed to generate ECU CSR"
mutate_csr_signature "$VALID_CSR_PATH" "$BROKEN_CSR_PATH"

echo
echo "== 2) Empty CSR should fail =="
EMPTY_REQUEST_ID="$(request_id "${DEVICE_ID}-empty")"
EMPTY_HTTP_CODE="$(api_post_capture "${BASE_URL}/ecu-certificates/apply" "{\"requestId\":\"${EMPTY_REQUEST_ID}\",\"templateId\":\"${ECU_TEMPLATE_ID}\",\"deviceId\":\"${DEVICE_ID}\",\"csr\":\"\"}" "$EMPTY_BODY_FILE")"
EMPTY_BODY="$(cat "$EMPTY_BODY_FILE")"
printf '%s\n' "$EMPTY_BODY"
assert_business_failure "$EMPTY_HTTP_CODE" "$EMPTY_BODY" "csr is required"

echo
echo "== 3) Invalid CSR format should fail =="
INVALID_REQUEST_ID="$(request_id "${DEVICE_ID}-invalid")"
INVALID_HTTP_CODE="$(api_post_capture "${BASE_URL}/ecu-certificates/apply" "{\"requestId\":\"${INVALID_REQUEST_ID}\",\"templateId\":\"${ECU_TEMPLATE_ID}\",\"deviceId\":\"${DEVICE_ID}\",\"csr\":\"not a valid csr\"}" "$INVALID_BODY_FILE")"
INVALID_BODY="$(cat "$INVALID_BODY_FILE")"
printf '%s\n' "$INVALID_BODY"
assert_business_failure "$INVALID_HTTP_CODE" "$INVALID_BODY" "invalid csr format"

echo
echo "== 4) CSR signature verification failure should fail =="
BROKEN_REQUEST_ID="$(request_id "${DEVICE_ID}-broken")"
BROKEN_APPLY_BODY="$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "templateId": sys.argv[2], "deviceId": sys.argv[3], "csr": open(sys.argv[4]).read()}))' "$BROKEN_REQUEST_ID" "$ECU_TEMPLATE_ID" "$DEVICE_ID" "$BROKEN_CSR_PATH")"
BROKEN_HTTP_CODE="$(api_post_capture "${BASE_URL}/ecu-certificates/apply" "$BROKEN_APPLY_BODY" "$BROKEN_BODY_FILE")"
BROKEN_BODY="$(cat "$BROKEN_BODY_FILE")"
printf '%s\n' "$BROKEN_BODY"
assert_business_failure "$BROKEN_HTTP_CODE" "$BROKEN_BODY" "csr signature verification failed"

echo
echo "[PASS] ECU apply invalid CSR verification passed"
