#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
APP_ID="${APP_ID:-softsigner-app-$(date +%s)}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-controller-sdk}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-softsigner-app}"
TEST_CA_DIR="${TEST_CA_DIR:-.local/test-ca}"
TEST_CSR_DIR="${TEST_CSR_DIR:-.local/test-csr}"

REQUEST_ID="${APP_TEMPLATE_ID}:${APP_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')"
REQUEST_ID_FILE_SAFE="${REQUEST_ID//:/_}"
CSR_KEY_PATH="${TEST_CSR_DIR}/${REQUEST_ID_FILE_SAFE}.key.pem"
CSR_PATH="${TEST_CSR_DIR}/${REQUEST_ID_FILE_SAFE}.csr.pem"
ISSUED_CERT_PATH="${TEST_CSR_DIR}/${REQUEST_ID_FILE_SAFE}.issued.cert.pem"
ROOT_CA_PATH="${TEST_CA_DIR}/root-ca.cert.pem"
SUB_CA_PATH="${TEST_CA_DIR}/sub-ca.cert.pem"

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
require_cmd openssl

[[ -f "$ROOT_CA_PATH" && -f "$SUB_CA_PATH" ]] || fail "test CA materials not found, please run scripts/generate_softsigner_test_ca.sh first"

mkdir -p "$TEST_CSR_DIR"

cat <<MSG
BASE_URL=${BASE_URL}
APP_ID=${APP_ID}
APP_TEMPLATE_ID=${APP_TEMPLATE_ID}
REQUEST_ID=${REQUEST_ID}
TEST_CA_DIR=${TEST_CA_DIR}
TEST_CSR_DIR=${TEST_CSR_DIR}
MSG

echo
echo "== 1) Generate temporary APP key and CSR =="
openssl genrsa -out "$CSR_KEY_PATH" 2048 >/dev/null 2>&1 || fail "failed to generate APP private key"
openssl req -new -sha256 \
  -key "$CSR_KEY_PATH" \
  -subj "/CN=${APP_ID}/OU=ignored-by-platform/O=ignored/C=CN" \
  -out "$CSR_PATH" >/dev/null 2>&1 || fail "failed to generate APP CSR"
CSR_CONTENT="$(cat "$CSR_PATH")"
assert_non_empty "$CSR_CONTENT" "CSR content is empty"

echo
echo "== 2) APP apply with real CSR =="
APPLY_BODY="$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "templateId": sys.argv[2], "appId": sys.argv[3], "csr": open(sys.argv[4]).read()}))' "$REQUEST_ID" "$APP_TEMPLATE_ID" "$APP_ID" "$CSR_PATH")"
APPLY_RESPONSE="$(api_post "${BASE_URL}/app-certificates/apply" "$APPLY_BODY")"
printf '%s\n' "$APPLY_RESPONSE"
assert_api_success "$APPLY_RESPONSE" "APP apply"
assert_equals "$REQUEST_ID" "$(printf '%s' "$APPLY_RESPONSE" | json_get "data.requestId")" "apply requestId mismatch"
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
echo "== 4) Query issued certificate content =="
CERT_RESPONSE="$(api_get "${BASE_URL}/certificates/${REQUEST_ID}/certificate")"
printf '%s\n' "$CERT_RESPONSE"
assert_api_success "$CERT_RESPONSE" "certificate query"
CERT_CONTENT_SERIAL="$(printf '%s' "$CERT_RESPONSE" | json_get "data.certSerial")"
CERT_CONTENT_ISSUER="$(printf '%s' "$CERT_RESPONSE" | json_get "data.issuerId")"
CERT_PEM="$(printf '%s' "$CERT_RESPONSE" | json_get "data.certificatePem")"
assert_equals "$CERT_SERIAL" "$CERT_CONTENT_SERIAL" "certificate content certSerial mismatch"
assert_equals "$ISSUER_ID" "$CERT_CONTENT_ISSUER" "certificate content issuerId mismatch"
assert_non_empty "$CERT_PEM" "certificatePem is empty"
printf '%s\n' "$CERT_PEM" > "$ISSUED_CERT_PATH"

echo
echo "== 4.1) Assert response does not depend on isCurrent =="
assert_json_path_empty "$CERT_RESPONSE" "data.isCurrent" "certificate content should not expose isCurrent"

echo
echo "== 5) Inspect issued certificate with openssl =="
ISSUER_TEXT="$(openssl x509 -in "$ISSUED_CERT_PATH" -noout -issuer)"
SUBJECT_TEXT="$(openssl x509 -in "$ISSUED_CERT_PATH" -noout -subject)"
BC_TEXT="$(openssl x509 -in "$ISSUED_CERT_PATH" -text -noout | grep -A1 'Basic Constraints' || true)"
printf '%s\n' "$ISSUER_TEXT"
printf '%s\n' "$SUBJECT_TEXT"
printf '%s\n' "$BC_TEXT"

[[ "$ISSUER_TEXT" == *"DFMC Sub CA TEST"* ]] || fail "issuer does not contain DFMC Sub CA TEST"
[[ "$SUBJECT_TEXT" == *"$APP_ID"* ]] || fail "subject does not contain appId"
[[ "$SUBJECT_TEXT" == *"Vehicle Controller SDK"* ]] || fail "subject does not contain Vehicle Controller SDK"
[[ "$BC_TEXT" == *"CA:FALSE"* ]] || fail "issued certificate is not a leaf certificate"

echo
echo "== 6) Verify certificate chain =="
VERIFY_OUTPUT="$(openssl verify -CAfile "$ROOT_CA_PATH" -untrusted "$SUB_CA_PATH" "$ISSUED_CERT_PATH" 2>&1)" || fail "openssl verify failed: ${VERIFY_OUTPUT}"
printf '%s\n' "$VERIFY_OUTPUT"
[[ "$VERIFY_OUTPUT" == *": OK" ]] || fail "certificate chain verification did not return OK"

echo
echo "[PASS] soft signer APP issuance verified"
echo "requestId=${REQUEST_ID}"
echo "certSerial=${CERT_SERIAL}"
echo "issuerId=${ISSUER_ID}"
echo "issuedCertPath=${ISSUED_CERT_PATH}"
