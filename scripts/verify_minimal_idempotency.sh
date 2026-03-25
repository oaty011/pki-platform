#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
SUBJECT_ID="${SUBJECT_ID:-app-demo-001}"
TEMPLATE_ID="${TEMPLATE_ID:-app-template-basic}"
DB_NAME="${DB_NAME:-pki_platform}"
DB_USER="${DB_USER:-postgres}"
REQUEST_ID_1="${REQUEST_ID_1:-${TEMPLATE_ID}:${SUBJECT_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')}"
REQUEST_ID_2="${REQUEST_ID_2:-${TEMPLATE_ID}:${SUBJECT_ID}:$(python3 -c 'from datetime import datetime; print(datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3])'):$(python3 -c 'import random,string; chars=string.ascii_lowercase+string.digits; print("".join(random.choice(chars) for _ in range(6)))')}"

cat <<MSG
[1] Same requestId repeated apply
curl -s -X POST "$BASE_URL/app-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d '{"requestId":"'$REQUEST_ID_1'","templateId":"'$TEMPLATE_ID'","appId":"'$SUBJECT_ID'"}'

curl -s -X POST "$BASE_URL/app-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d '{"requestId":"'$REQUEST_ID_1'","templateId":"'$TEMPLATE_ID'","appId":"'$SUBJECT_ID'"}'
Expected: same requestId/status returned; issue_fact only one row for requestId=$REQUEST_ID_1.

[2] Same requestId repeated sync-core-active
curl -s -X POST "$BASE_URL/certificates/sync-core-active/$REQUEST_ID_1"
curl -s -X POST "$BASE_URL/certificates/sync-core-active/$REQUEST_ID_1"
Expected: both succeed; default query returns the latest active certificate for subjectId=$SUBJECT_ID.

[3] Same subjectId with different requestId issued twice
curl -s -X POST "$BASE_URL/app-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d '{"requestId":"'$REQUEST_ID_2'","templateId":"'$TEMPLATE_ID'","appId":"'$SUBJECT_ID'"}'

curl -s -X POST "$BASE_URL/certificates/sync-core-active/$REQUEST_ID_2"
Expected: newest certificate becomes the default latest active result for subjectId=$SUBJECT_ID.

[4] Optional SQL checks
psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT request_id, COUNT(*)
FROM pki_issuance.certificate_issue_fact
WHERE request_id IN ('$REQUEST_ID_1', '$REQUEST_ID_2')
GROUP BY request_id;

-- Replace core_active_xx with the shard table resolved by PartitionService for subjectId=$SUBJECT_ID.
SELECT cert_serial, issuer_id, subject_id, updated_at
FROM pki_app.core_active_xx
WHERE subject_id = '$SUBJECT_ID'
ORDER BY updated_at DESC;
SQL

Expected SQL results:
- issue_fact: each requestId count = 1
- core_active shard table: rows remain stable for subjectId=$SUBJECT_ID, and default query should return the latest active record
MSG
