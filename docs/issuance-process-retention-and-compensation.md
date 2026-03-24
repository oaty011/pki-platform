# Issuance Process Retention and Compensation

## Overview

`issue_fact` is treated as a short-term process table in `pki-issuance-service`.

The service keeps two supporting background capabilities:
- short-term retention cleanup for old `issue_fact` records
- automatic compensation for `sync-core-active`

## issue_fact retention

- `issue_fact` is retained for 30 days by default
- cleanup runs as a background scheduled task
- cleanup deletes records in batches
- cleanup is configurable and can be enabled or disabled

## sync-core-active compensation

- `sync-core-active` can still be triggered explicitly through the existing API
- the service also provides automatic compensation in the background
- the compensation task scans `issue_fact` records whose `sync_status` is `pending` or `failed`
- retries are executed by reusing the existing `sync-core-active` service logic
- each run only processes a limited batch

## Configuration

The following configuration items are available in `application.yml` and can be overridden by environment variables:

- `pki.issuance.issue-fact-cleanup.enabled`
- `pki.issuance.issue-fact-cleanup.retention-days`
- `pki.issuance.issue-fact-cleanup.batch-size`
- `pki.issuance.issue-fact-cleanup.cron`
- `pki.issuance.sync-core-active-compensation.enabled`
- `pki.issuance.sync-core-active-compensation.batch-size`
- `pki.issuance.sync-core-active-compensation.cron`
