# Issuance Background Jobs Verification

## Scope

This document describes the minimum verification approach for the two background jobs added to `pki-issuance-service`:

- issue_fact cleanup
- sync-core-active compensation

## Configuration

### issue_fact cleanup

Relevant configuration items:

- `pki.issuance.issue-fact-cleanup.enabled`
- `pki.issuance.issue-fact-cleanup.retention-days`
- `pki.issuance.issue-fact-cleanup.batch-size`
- `pki.issuance.issue-fact-cleanup.cron`

Recommended verification setup:

- enable the job
- set `retention-days=30`
- use a small `batch-size` such as `1`
- use a frequent cron during verification

### sync-core-active compensation

Relevant configuration items:

- `pki.issuance.sync-core-active-compensation.enabled`
- `pki.issuance.sync-core-active-compensation.batch-size`
- `pki.issuance.sync-core-active-compensation.cron`

Recommended verification setup:

- enable the job
- use a small but non-zero `batch-size`
- use a frequent cron during verification

## Scripts

### verify_issue_fact_cleanup.sh

This script verifies that:

- expired `issue_fact` rows older than the retention period are eligible for deletion
- cleanup runs in batches
- fresh `issue_fact` rows are not deleted

### verify_sync_core_active_compensation.sh

This script verifies that:

- an `ISSUED` record with `sync_status=pending` can be compensated automatically
- compensation writes the certificate into the resolved `core_active_xx` shard
- compensation changes `sync_status` from `pending` or `failed` to `done`

## Execution prerequisites

Before running the scripts:

- start `pki-issuance-service`
- ensure PostgreSQL is reachable
- ensure Flyway migration has already been applied
- ensure the background job configuration is enabled
- ensure the cron expressions are frequent enough for the chosen verification window

## Logs to observe

When verifying cleanup, observe logs similar to:

- `issue_fact cleanup deleted ...`

When verifying compensation, observe logs similar to:

- `sync-core-active compensation processed ...`
- `sync-core-active compensation failed ...`
- `sync-core-active executed ...`

## Database fields to observe

### For issue_fact cleanup

Observe:

- `certificate_issue_fact.request_id`
- `certificate_issue_fact.created_at`
- `certificate_issue_fact.updated_at`

### For sync-core-active compensation

Observe:

- `certificate_issue_fact.request_id`
- `certificate_issue_fact.status`
- `certificate_issue_fact.sync_status`
- `certificate_issue_fact.cert_serial`
- `certificate_issue_fact.issuer_id`
- `certificate_issue_fact.subject_id`
- `certificate_issue_fact.organization`
- `core_active_xx.cert_serial`
- `core_active_xx.issuer_id`
- `core_active_xx.subject_id`
- `core_active_xx.is_current`
- `core_active_xx.not_after`

## Expected results

### issue_fact cleanup

- records older than the configured retention period are deleted
- deletion respects the configured batch size
- fresh records remain

### sync-core-active compensation

- a newly issued record starts with `sync_status=pending` when no manual sync is executed
- the compensation job later changes `sync_status` to `done`
- the certificate is written into the expected `core_active_xx` shard
- no manual `/certificates/sync-core-active/{requestId}` call is needed for this verification
