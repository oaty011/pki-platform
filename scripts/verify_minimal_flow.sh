#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
APP_ID="${APP_ID:-app-demo-001}"
DEVICE_ID="${DEVICE_ID:-ecu-demo-001}"
APP_TEMPLATE_ID="${APP_TEMPLATE_ID:-app-template-demo}"
ECU_TEMPLATE_ID="${ECU_TEMPLATE_ID:-ecu-template-demo}"
REQUEST_ID_APP="${REQUEST_ID_APP:-${APP_TEMPLATE_ID}:${APP_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')}"
REQUEST_ID_APP_2="${REQUEST_ID_APP_2:-${APP_TEMPLATE_ID}:${APP_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')}"
REQUEST_ID_ECU="${REQUEST_ID_ECU:-${ECU_TEMPLATE_ID}:${DEVICE_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')}"

cat <<MSG
Base URL: ${BASE_URL}
APP requestId #1: ${REQUEST_ID_APP}
APP requestId #2: ${REQUEST_ID_APP_2}
ECU requestId: ${REQUEST_ID_ECU}
APP subjectId(appId): ${APP_ID}
ECU subjectId(deviceId): ${DEVICE_ID}
MSG

echo
 echo '== 1) APP apply idempotency: first call =='
curl -sS -X POST "${BASE_URL}/app-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d "{\"requestId\":\"${REQUEST_ID_APP}\",\"templateId\":\"${APP_TEMPLATE_ID}\",\"appId\":\"${APP_ID}\"}"
echo

echo '== 2) APP apply idempotency: second call with same requestId =='
curl -sS -X POST "${BASE_URL}/app-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d "{\"requestId\":\"${REQUEST_ID_APP}\",\"templateId\":\"${APP_TEMPLATE_ID}\",\"appId\":\"${APP_ID}\"}"
echo

echo '== 3) Query APP certificate status by requestId =='
curl -sS "${BASE_URL}/certificates/${REQUEST_ID_APP}"
echo

echo '== 4) Query APP certificate PEM by requestId =='
curl -sS "${BASE_URL}/certificates/${REQUEST_ID_APP}/certificate"
echo

echo '== 5) sync-core-active first call =='
curl -sS -X POST "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID_APP}"
echo

echo '== 6) sync-core-active second call with same requestId =='
curl -sS -X POST "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID_APP}"
echo

echo '== 7) APP current certificate by subjectId =='
curl -sS "${BASE_URL}/app-certificates/current/${APP_ID}"
echo

echo '== 8) Same subject second certificate issuance =='
curl -sS -X POST "${BASE_URL}/app-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d "{\"requestId\":\"${REQUEST_ID_APP_2}\",\"templateId\":\"${APP_TEMPLATE_ID}\",\"appId\":\"${APP_ID}\"}"
echo

echo '== 9) sync-core-active for second APP certificate =='
curl -sS -X POST "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID_APP_2}"
echo

echo '== 10) APP current certificate after second issuance =='
curl -sS "${BASE_URL}/app-certificates/current/${APP_ID}"
echo

echo '== 11) ECU apply =='
curl -sS -X POST "${BASE_URL}/ecu-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d "{\"requestId\":\"${REQUEST_ID_ECU}\",\"templateId\":\"${ECU_TEMPLATE_ID}\",\"deviceId\":\"${DEVICE_ID}\"}"
echo

echo '== 12) ECU sync-core-active =='
curl -sS -X POST "${BASE_URL}/certificates/sync-core-active/${REQUEST_ID_ECU}"
echo

echo '== 13) ECU current certificate by subjectId =='
curl -sS "${BASE_URL}/ecu-certificates/current/${DEVICE_ID}"
echo
