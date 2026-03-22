# Minimal Verification Guide

This guide verifies the current minimal issuance closure without changing Java code or database schema.

## Files

- `scripts/verify_minimal_flow.sh`: curl-based verification script
- `scripts/verify_queries.sql`: SQL checks for issue_fact and core_active

## Preconditions

1. `pki-issuance-service` is running on `http://localhost:18081` unless `BASE_URL` is overridden.
2. PostgreSQL is reachable and the schema migrations have already been applied.
3. `curl` and `psql` are available locally.

## Scenario 1: apply idempotency

Steps:
1. Run the first APP apply call.
2. Run the second APP apply call with the same `requestId`.
3. Query `/certificates/{requestId}`.
4. Run the issue_fact SQL checks.

Commands:
- `./scripts/verify_minimal_flow.sh`
- `psql "$DATABASE_URL" -v request_id_app='app-req-001' -v request_id_app_2='app-req-002' -v request_id_ecu='ecu-req-001' -v app_subject_id='app-demo-001' -v ecu_subject_id='ecu-demo-001' -f scripts/verify_queries.sql`

Expected result:
- The two APP apply responses return the same `requestId`.
- The status remains `ISSUED`.
- `pki_issuance.certificate_issue_fact` has exactly one row for that `requestId`.
- The cert content queried by `GET /certificates/{requestId}/certificate` is stable.

## Scenario 2: sync-core-active idempotency

Steps:
1. Call `POST /certificates/sync-core-active/{requestId}` the first time.
2. Call it again with the same `requestId`.
3. Run issue_fact and core_active SQL checks.

Expected result:
- First call returns `action=executed`.
- Second call returns `action=already_done`.
- `core_active_xx` remains unique by `(cert_serial, issuer_id)`.
- No duplicate rows are introduced by repeated sync.

## Scenario 3: same subject, new certificate overrides old current

Steps:
1. Issue APP certificate #1 for a fixed `appId`.
2. Sync core_active for APP certificate #1.
3. Issue APP certificate #2 with a different `requestId` but the same `appId`.
4. Sync core_active for APP certificate #2.
5. Call `GET /app-certificates/current/{subjectId}`.
6. Query the resolved `pki_app.core_active_xx` table.

Expected result:
- `GET /app-certificates/current/{subjectId}` returns the second certificate.
- In the shard table there are two rows for the same `subjectId`.
- Old row: `is_current = false`.
- New row: `is_current = true`.

## Scenario 4: FAILED retry

No new failure injection is added in this step. Use a manual failure and retry flow:

Steps:
1. Trigger `POST /certificates/sync-core-active/{requestId}` while intentionally breaking DB write success for core_active, for example by temporarily revoking DB write permission or using an invalid target environment.
2. Confirm `issue_fact.sync_status = failed` in `pki_issuance.certificate_issue_fact`.
3. Restore the DB condition.
4. Trigger `POST /certificates/sync-core-active/{requestId}` again.
5. Re-check `issue_fact` and the relevant `core_active_xx` table.

Expected result:
- The failed attempt leaves `sync_status = failed`.
- The retry is allowed.
- A successful retry moves `sync_status` to `done`.
- Core_active remains upsert-based and does not create duplicate primary-key rows.

## Shard table lookup note

The SQL file uses `core_active_xx` as a placeholder.

Current shard rule in the project:
- `partitionKey = subjectId + ":" + organization`
- `shard = floorMod(hash(partitionKey), 32)`
- table name = `core_active_%02d`

For manual verification, resolve the exact shard from the running service behavior or logs. `PartitionService` remains the single source of truth.
