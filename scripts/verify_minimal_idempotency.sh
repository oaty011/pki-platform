#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:18081}"
REQUEST_ID_1="${REQUEST_ID_1:-app-idem-001}"
REQUEST_ID_2="${REQUEST_ID_2:-app-idem-002}"
SUBJECT_ID="${SUBJECT_ID:-app-demo-001}"
TEMPLATE_ID="${TEMPLATE_ID:-app-template-basic}"
DB_NAME="${DB_NAME:-pki_platform}"
DB_USER="${DB_USER:-postgres}"

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
Expected: both succeed; core_active has only one current row for subjectId=$SUBJECT_ID.

[3] Same subjectId with different requestId issued twice
curl -s -X POST "$BASE_URL/app-certificates/apply" \
  -H 'Content-Type: application/json' \
  -d '{"requestId":"'$REQUEST_ID_2'","templateId":"'$TEMPLATE_ID'","appId":"'$SUBJECT_ID'"}'

curl -s -X POST "$BASE_URL/certificates/sync-core-active/$REQUEST_ID_2"
Expected: newest certificate becomes current; old core_active row switches to is_current=false.

[4] Optional SQL checks
psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT request_id, COUNT(*)
FROM pki_issuance.certificate_issue_fact
WHERE request_id IN ('$REQUEST_ID_1', '$REQUEST_ID_2')
GROUP BY request_id;

-- Replace core_active_xx with the shard table resolved by PartitionService for subjectId=$SUBJECT_ID.
SELECT cert_serial, issuer_id, subject_id, is_current, updated_at
FROM pki_app.core_active_xx
WHERE subject_id = '$SUBJECT_ID'
ORDER BY updated_at DESC;
SQL

Expected SQL results:
- issue_fact: each requestId count = 1
- core_active shard table: only one row with is_current=true for subjectId=$SUBJECT_ID
MSG
