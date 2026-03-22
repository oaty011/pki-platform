-- Replace the placeholders before running in psql.
-- Example:
--   psql "$DATABASE_URL" -v request_id_app='app-req-001' -v request_id_app_2='app-req-002' -v request_id_ecu='ecu-req-001' -v app_subject_id='app-demo-001' -v ecu_subject_id='ecu-demo-001'
--
-- Shard rule reference for manual verification:
--   partitionKey = subjectId || ':' || organization
--   shard = floorMod(hash(partitionKey), 32)
-- In the running service, PartitionService is the single source of truth.
-- If you need the exact shard table, compute it from the Java service or logs.

\echo '1) issue_fact uniqueness / apply idempotency'
SELECT request_id, subject_id, organization, cert_serial, status, sync_status, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE request_id IN (:'request_id_app', :'request_id_app_2', :'request_id_ecu')
ORDER BY created_at;

SELECT request_id, COUNT(*) AS row_count
FROM pki_issuance.certificate_issue_fact
WHERE request_id IN (:'request_id_app', :'request_id_app_2', :'request_id_ecu')
GROUP BY request_id
ORDER BY request_id;

\echo '2) core_active current switch validation'
-- Replace core_active_xx with the shard table resolved by PartitionService/logs.
SELECT cert_serial, issuer_id, subject_id, is_current, created_at, updated_at
FROM pki_app.core_active_xx
WHERE subject_id = :'app_subject_id'
ORDER BY updated_at;

SELECT cert_serial, issuer_id, subject_id, is_current, created_at, updated_at
FROM pki_ecu.core_active_xx
WHERE subject_id = :'ecu_subject_id'
ORDER BY updated_at;
