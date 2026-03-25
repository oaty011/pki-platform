#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-controller-sdk}"
TEST_CSR_DIR="${TEST_CSR_DIR:-.local/test-csr}"
CONCURRENCY_LEVELS="${CONCURRENCY_LEVELS:-10 50 100 200 500}"
REQUEST_ID_PREFIX="${REQUEST_ID_PREFIX:-issue-concurrency}"
APP_ID_PREFIX="${APP_ID_PREFIX:-issue-concurrency-app}"
CURL_TIMEOUT_SECONDS="${CURL_TIMEOUT_SECONDS:-}"

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing required command: $1" >&2
    exit 1
  }
}

fail() {
  echo "[FAIL] $*" >&2
  exit 1
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

now_ms() {
  python3 -c 'import time; print(time.time_ns() // 1000000)'
}

curl_common_args() {
  if [[ -n "$CURL_TIMEOUT_SECONDS" ]]; then
    printf -- "--max-time %s" "$CURL_TIMEOUT_SECONDS"
  fi
}

worker_apply() {
  local encoded="$1"
  local decoded
  decoded="$(python3 -c 'import base64,sys; print(base64.b64decode(sys.argv[1]).decode("utf-8"))' "$encoded")"

  local request_id app_id csr
  request_id="$(printf '%s' "$decoded" | python3 -c 'import json,sys; print(json.load(sys.stdin)["requestId"])')"
  app_id="$(printf '%s' "$decoded" | python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])')"
  csr="$(printf '%s' "$decoded" | python3 -c 'import json,sys; print(json.load(sys.stdin)["csr"])')"

  local body
  body="$(python3 -c 'import json,sys; print(json.dumps({"requestId": sys.argv[1], "templateId": sys.argv[2], "appId": sys.argv[3], "csr": sys.argv[4]}))' \
    "$request_id" "$APP_TEMPLATE_ID" "$app_id" "$csr")"

  local body_file http_code start_ms end_ms latency_ms
  body_file="$(mktemp)"
  start_ms="$(now_ms)"
  http_code="$(sh -c "curl -sS $(curl_common_args) -o '$body_file' -w '%{http_code}' -X POST '$BASE_URL/app-certificates/apply' -H 'Content-Type: application/json' -d @- <<'EOF'
$body
EOF")" || http_code="000"
  end_ms="$(now_ms)"
  latency_ms="$((end_ms - start_ms))"

  local response success status response_request_id record_success
  response="$(cat "$body_file" 2>/dev/null || true)"
  rm -f "$body_file"

  success="$(printf '%s' "$response" | json_get "success" 2>/dev/null || true)"
  status="$(printf '%s' "$response" | json_get "data.status" 2>/dev/null || true)"
  response_request_id="$(printf '%s' "$response" | json_get "data.requestId" 2>/dev/null || true)"

  if [[ "$http_code" == "200" && "$success" == "true" && "$status" == "ISSUED" && -n "$response_request_id" ]]; then
    record_success="true"
  else
    record_success="false"
  fi

  python3 -c '
import json
import sys

print(json.dumps({
    "phase": "apply",
    "requestId": sys.argv[1],
    "appId": sys.argv[2],
    "httpCode": sys.argv[3],
    "success": sys.argv[4] == "true",
    "latencyMs": int(sys.argv[5]),
    "response": sys.stdin.read()
}, ensure_ascii=False))
' "$request_id" "$app_id" "$http_code" "$record_success" "$latency_ms" <<<"$response"
}

worker_fetch() {
  local encoded="$1"
  local decoded request_id
  decoded="$(python3 -c 'import base64,sys; print(base64.b64decode(sys.argv[1]).decode("utf-8"))' "$encoded")"
  request_id="$(printf '%s' "$decoded" | python3 -c 'import json,sys; print(json.load(sys.stdin)["requestId"])')"

  local body_file http_code start_ms end_ms latency_ms
  body_file="$(mktemp)"
  start_ms="$(now_ms)"
  http_code="$(sh -c "curl -sS $(curl_common_args) -o '$body_file' -w '%{http_code}' '$BASE_URL/certificates/$request_id/certificate'")" || http_code="000"
  end_ms="$(now_ms)"
  latency_ms="$((end_ms - start_ms))"

  local response success cert_serial issuer_id certificate_pem record_success
  response="$(cat "$body_file" 2>/dev/null || true)"
  rm -f "$body_file"

  success="$(printf '%s' "$response" | json_get "success" 2>/dev/null || true)"
  cert_serial="$(printf '%s' "$response" | json_get "data.certSerial" 2>/dev/null || true)"
  issuer_id="$(printf '%s' "$response" | json_get "data.issuerId" 2>/dev/null || true)"
  certificate_pem="$(printf '%s' "$response" | json_get "data.certificatePem" 2>/dev/null || true)"

  if [[ "$http_code" == "200" && "$success" == "true" && -n "$cert_serial" && -n "$issuer_id" && -n "$certificate_pem" ]]; then
    record_success="true"
  else
    record_success="false"
  fi

  python3 -c '
import json
import sys

print(json.dumps({
    "phase": "certificate",
    "requestId": sys.argv[1],
    "httpCode": sys.argv[2],
    "success": sys.argv[3] == "true",
    "latencyMs": int(sys.argv[4]),
    "response": sys.stdin.read()
}, ensure_ascii=False))
' "$request_id" "$http_code" "$record_success" "$latency_ms" <<<"$response"
}

summarize_phase() {
  local label="$1"
  local result_file="$2"
  python3 - "$label" "$result_file" <<'PY'
import json
import math
import statistics
import sys

label = sys.argv[1]
path = sys.argv[2]
records = []
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            records.append(json.loads(line))

latencies = sorted(r["latencyMs"] for r in records)
total = len(records)
success = sum(1 for r in records if r["success"])
failed = total - success

def percentile(values, ratio):
    if not values:
        return 0
    index = int(ratio * len(values))
    if index >= len(values):
        index = len(values) - 1
    return values[index]

avg = round(sum(latencies) / total, 2) if total else 0
p95 = percentile(latencies, 0.95)
p99 = percentile(latencies, 0.99)

http_non_200 = any(str(r.get("httpCode", "")) != "200" for r in records)
success_false = any(not r.get("success", False) for r in records)
cert_serial_empty = False
certificate_pem_empty = False
for r in records:
    response = r.get("response", "")
    try:
        payload = json.loads(response) if response else {}
    except Exception:
        payload = {}
    data = payload.get("data") if isinstance(payload, dict) else {}
    if label == "Certificate Phase":
        if not (isinstance(data, dict) and data.get("certSerial")):
            cert_serial_empty = True
        if not (isinstance(data, dict) and data.get("certificatePem")):
            certificate_pem_empty = True

print(f"{label}:")
print(f"- total={total}")
print(f"- success={success}")
print(f"- failed={failed}")
print(f"- avg latency(ms)={avg}")
print(f"- p95 latency(ms)={p95}")
print(f"- p99 latency(ms)={p99}")
print(f"- http_non_200={'true' if http_non_200 else 'false'}")
print(f"- success_false={'true' if success_false else 'false'}")
print(f"- cert_serial_empty={'true' if cert_serial_empty else 'false'}")
print(f"- certificate_pem_empty={'true' if certificate_pem_empty else 'false'}")
PY
}

emit_successful_apply_inputs() {
  local result_file="$1"
  python3 - "$result_file" <<'PY'
import base64
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        record = json.loads(line)
        if not record.get("success"):
            continue
        payload = {"requestId": record["requestId"]}
        print(base64.b64encode(json.dumps(payload).encode("utf-8")).decode("ascii"))
PY
}

prepare_inputs_for_level() {
  local concurrency="$1"
  local level_dir="${TEST_CSR_DIR}/concurrency-${concurrency}"
  local jsonl_path="${TEST_CSR_DIR}/concurrency-${concurrency}.jsonl"
  mkdir -p "$level_dir"
  : > "$jsonl_path"

  local i request_id app_id key_path csr_path
  for ((i = 1; i <= concurrency; i++)); do
    app_id="${APP_ID_PREFIX}-${concurrency}-$(printf '%04d' "$i")"
    request_id="${APP_TEMPLATE_ID}:${app_id}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')"
    request_id_file_safe="${request_id//:/_}"
    key_path="${level_dir}/${request_id_file_safe}.key.pem"
    csr_path="${level_dir}/${request_id_file_safe}.csr.pem"

    openssl genrsa -out "$key_path" 2048 >/dev/null 2>&1 || fail "failed to generate private key for ${request_id}"
    openssl req -new -sha256 \
      -key "$key_path" \
      -subj "/CN=${app_id}/OU=concurrency-test/O=DFMC/C=CN" \
      -out "$csr_path" >/dev/null 2>&1 || fail "failed to generate CSR for ${request_id}"

    python3 -c '
import json
import sys
print(json.dumps({
    "requestId": sys.argv[1],
    "appId": sys.argv[2],
    "csr": open(sys.argv[3], "r", encoding="utf-8").read()
}, ensure_ascii=False))
' "$request_id" "$app_id" "$csr_path" >> "$jsonl_path"
  done

  printf '%s\n' "$jsonl_path"
}

run_level() {
  local concurrency="$1"
  local prep_jsonl apply_input_file apply_result_file fetch_input_file fetch_result_file
  local level_dir="${TEST_CSR_DIR}/concurrency-${concurrency}"
  local wall_start wall_end wall_ms

  >&2 echo
  >&2 echo "== CONCURRENCY ${concurrency} =="
  >&2 echo
  >&2 echo "== Preparation Phase =="
  prep_jsonl="$(prepare_inputs_for_level "$concurrency")"
  >&2 echo "prepared_jsonl=${prep_jsonl}"
  >&2 echo "prepared_count=${concurrency}"

  apply_input_file="${level_dir}/apply-inputs.txt"
  apply_result_file="${level_dir}/apply-results.jsonl"
  fetch_input_file="${level_dir}/fetch-inputs.txt"
  fetch_result_file="${level_dir}/fetch-results.jsonl"
  : > "$apply_input_file"
  : > "$apply_result_file"
  : > "$fetch_input_file"
  : > "$fetch_result_file"

  wall_start="$(now_ms)"

  >&2 echo
  >&2 echo "== Apply Phase =="
  python3 - "$prep_jsonl" <<'PY' > "$apply_input_file"
import base64
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            print(base64.b64encode(line.encode("utf-8")).decode("ascii"))
PY
  xargs -P "$concurrency" -n 1 "$SCRIPT_PATH" __apply_worker < "$apply_input_file" > "$apply_result_file"

  summarize_phase "Apply Phase" "$apply_result_file" >&2

  emit_successful_apply_inputs "$apply_result_file" > "$fetch_input_file"
  local successful_apply_count
  successful_apply_count="$(wc -l < "$fetch_input_file" | tr -d ' ')"

  >&2 echo
  >&2 echo "== Certificate Fetch Phase =="
  if [[ "$successful_apply_count" -gt 0 ]]; then
    xargs -P "$concurrency" -n 1 "$SCRIPT_PATH" __fetch_worker < "$fetch_input_file" > "$fetch_result_file"
  fi
  summarize_phase "Certificate Phase" "$fetch_result_file" >&2

  wall_end="$(now_ms)"
  wall_ms="$((wall_end - wall_start))"

  local apply_http_non_200 apply_success_false fetch_http_non_200 fetch_success_false fetch_cert_empty fetch_pem_empty level_ok
  apply_http_non_200="$(python3 - "$apply_result_file" <<'PY'
import json,sys
print("true" if any(json.loads(line).get("httpCode") != "200" for line in open(sys.argv[1], encoding="utf-8") if line.strip()) else "false")
PY
)"
  apply_success_false="$(python3 - "$apply_result_file" <<'PY'
import json,sys
print("true" if any(not json.loads(line).get("success") for line in open(sys.argv[1], encoding="utf-8") if line.strip()) else "false")
PY
)"
  fetch_http_non_200="$(python3 - "$fetch_result_file" <<'PY'
import json,sys
print("true" if any(json.loads(line).get("httpCode") != "200" for line in open(sys.argv[1], encoding="utf-8") if line.strip()) else "false")
PY
)"
  fetch_success_false="$(python3 - "$fetch_result_file" <<'PY'
import json,sys
print("true" if any(not json.loads(line).get("success") for line in open(sys.argv[1], encoding="utf-8") if line.strip()) else "false")
PY
)"
  fetch_cert_empty="$(python3 - "$fetch_result_file" <<'PY'
import json,sys
flag = False
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        payload = json.loads(json.loads(line).get("response") or "{}")
    except Exception:
        flag = True
        break
    data = payload.get("data") or {}
    if not data.get("certSerial"):
        flag = True
        break
print("true" if flag else "false")
PY
)"
  fetch_pem_empty="$(python3 - "$fetch_result_file" <<'PY'
import json,sys
flag = False
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        payload = json.loads(json.loads(line).get("response") or "{}")
    except Exception:
        flag = True
        break
    data = payload.get("data") or {}
    if not data.get("certificatePem"):
        flag = True
        break
print("true" if flag else "false")
PY
)"

  >&2 echo
  >&2 echo "Overall:"
  >&2 echo "- total wall time=${wall_ms}ms"
  >&2 echo "- http_non_200=$([[ "$apply_http_non_200" == "true" || "$fetch_http_non_200" == "true" ]] && echo true || echo false)"
  >&2 echo "- success_false=$([[ "$apply_success_false" == "true" || "$fetch_success_false" == "true" ]] && echo true || echo false)"
  >&2 echo "- certSerial_empty=${fetch_cert_empty}"
  >&2 echo "- certificatePem_empty=${fetch_pem_empty}"

  level_ok="true"
  if [[ "$apply_success_false" == "true" || "$apply_http_non_200" == "true" || "$fetch_success_false" == "true" || "$fetch_http_non_200" == "true" || "$fetch_cert_empty" == "true" || "$fetch_pem_empty" == "true" ]]; then
    level_ok="false"
  fi
  printf '%s\n' "$level_ok"
}

if [[ "${1:-}" == "__apply_worker" ]]; then
  shift
  worker_apply "$1"
  exit 0
fi

if [[ "${1:-}" == "__fetch_worker" ]]; then
  shift
  worker_fetch "$1"
  exit 0
fi

require_cmd curl
require_cmd python3
require_cmd openssl
require_cmd xargs

mkdir -p "$TEST_CSR_DIR"

cat <<MSG
BASE_URL=${BASE_URL}
APP_TEMPLATE_ID=${APP_TEMPLATE_ID}
TEST_CSR_DIR=${TEST_CSR_DIR}
CONCURRENCY_LEVELS=${CONCURRENCY_LEVELS}
REQUEST_ID_PREFIX=${REQUEST_ID_PREFIX}
APP_ID_PREFIX=${APP_ID_PREFIX}
CURL_TIMEOUT_SECONDS=${CURL_TIMEOUT_SECONDS:-<default>}
MSG

failed_levels=()
for concurrency in $CONCURRENCY_LEVELS; do
  level_result="$(run_level "$concurrency")"
  level_result="${level_result##*$'\n'}"
  if [[ "$level_result" != "true" ]]; then
    failed_levels+=("$concurrency")
  fi
done

echo
if [[ "${#failed_levels[@]}" -eq 0 ]]; then
  echo "[PASS] issue high concurrency verification passed"
else
  echo "[FAIL] issue high concurrency verification found failures"
  echo "failed_levels=${failed_levels[*]}"
  exit 1
fi
