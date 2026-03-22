# New Subject-Route Verification

## Scope

### Deprecated legacy certSerial revoke/recover routes

- `POST /certificates/{certSerial}/revoke` is deprecated.
- `POST /certificates/{certSerial}/recover` is deprecated.
- These legacy interfaces depend on locator-based routing.
- The recommended interfaces are:
  - `POST /app-certificates/revoke`
  - `POST /ecu-certificates/revoke`
  - `POST /app-certificates/recover`
  - `POST /ecu-certificates/recover`
- The new subject-route path uses `subjectId + organization -> shard -> core_active_xx` as the primary routing rule.

### APP current query

### ECU current query

### APP revoke

### ECU revoke

### APP recover

### ECU recover

## APP Current Query Scenarios

### Query current aggregate by appId

### Query current aggregate by installId

### Query single certificate by appId and certSerial

### Query single certificate by installId and certSerial

## ECU Current Query Scenarios

### Query current aggregate by deviceId

### Query single certificate by deviceId and certSerial

## APP Revoke Scenarios

### Revoke active certificate by appId

#### Preconditions

- The same certificate still exists in the resolved `pki_app.core_active_xx` shard table.
- The certificate has a valid `certSerial` and `issuerId`.
- The request uses `appId` as the subject identifier.

#### API Call

- `POST /app-certificates/revoke`

Request body:

```json
{
  "appId": "app-demo-001",
  "installId": "",
  "certSerial": "ABC123",
  "issuerId": "ca-01"
}
```

#### Steps

1. Confirm the certificate is still present in the APP `core_active_xx` shard table resolved from `appId + DFMC`.
2. Call `POST /app-certificates/revoke` with `appId`, `certSerial`, and `issuerId`.
3. Re-check the same APP `core_active_xx` shard table.
4. Re-check `pki_revocation.revocation_current`.
5. Re-check `pki_revocation.revocation_outbox`.

#### SQL Checks

Resolve shard from the same application rule:

```text
partitionKey = appId + ":" + organization
organization = DFMC
shard = floorMod(hash(partitionKey), 32)
tableName = core_active_%02d
```

Check APP core_active shard before and after revoke:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_app.core_active_xx
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_current:

```sql
SELECT cert_serial, issuer_id, revoked_at, reason, first_activated_at, updated_at
FROM pki_revocation.revocation_current
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_outbox:

```sql
SELECT cert_serial, issuer_id, event_type, status, version, retry_count, created_at, updated_at
FROM pki_revocation.revocation_outbox
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY version;
```

#### Expected Result

- The request succeeds for the given `appId`, `certSerial`, and `issuerId`.
- The target certificate is no longer present in the resolved `pki_app.core_active_xx` table.
- A new row exists in `pki_revocation.revocation_current`.
- The new `revocation_current` row has:
  - matching `cert_serial`
  - matching `issuer_id`
  - `reason = MANUAL`
  - non-null `revoked_at`
- A new row exists in `pki_revocation.revocation_outbox`.
- The new `revocation_outbox` row has:
  - `event_type = REVOKE`
  - `status = NEW`
  - `retry_count = 0`
- The scenario is considered passed only if the certificate was removed from `core_active_xx` and both revocation tables were updated.

### Revoke active certificate by installId

### Revoke fails when certificate is not in core_active

## ECU Revoke Scenarios

### Revoke active certificate by deviceId

#### Preconditions

- The same certificate still exists in the resolved `pki_ecu.core_active_xx` shard table.
- The certificate has a valid `certSerial` and `issuerId`.
- The request uses `deviceId` as the subject identifier.
- The ECU organization is fixed to `DFMC_ECU`.

#### API Call

- `POST /ecu-certificates/revoke`

Request body:

```json
{
  "deviceId": "device123",
  "certSerial": "ABC123",
  "issuerId": "ca-01"
}
```

#### Steps

1. Confirm the certificate is still present in the ECU `core_active_xx` shard table resolved from `deviceId + DFMC_ECU`.
2. Resolve shard using `subjectId = deviceId` and `organization = DFMC_ECU`.
3. Call `POST /ecu-certificates/revoke` with `deviceId`, `certSerial`, and `issuerId`.
4. Re-check the same ECU `core_active_xx` shard table.
5. Re-check `pki_revocation.revocation_current`.
6. Re-check `pki_revocation.revocation_outbox`.

#### SQL Checks

Resolve shard from the same application rule:

```text
partitionKey = deviceId + ":" + organization
organization = DFMC_ECU
shard = floorMod(hash(partitionKey), 32)
tableName = core_active_%02d
```

Check ECU core_active shard before and after revoke:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_ecu.core_active_xx
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_current:

```sql
SELECT cert_serial, issuer_id, revoked_at, reason, first_activated_at, updated_at
FROM pki_revocation.revocation_current
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_outbox:

```sql
SELECT cert_serial, issuer_id, event_type, status, version, retry_count, created_at, updated_at
FROM pki_revocation.revocation_outbox
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY version;
```

#### Expected Result

- The request succeeds for the given `deviceId`, `certSerial`, and `issuerId`.
- The routing path uses `subjectId = deviceId` and `organization = DFMC_ECU` to resolve the target ECU shard.
- The target certificate is no longer present in the resolved `pki_ecu.core_active_xx` table.
- A new row exists in `pki_revocation.revocation_current`.
- The new `revocation_current` row has:
  - matching `cert_serial`
  - matching `issuer_id`
  - `reason = MANUAL`
  - non-null `revoked_at`
- A new row exists in `pki_revocation.revocation_outbox`.
- The new `revocation_outbox` row has:
  - `event_type = REVOKE`
  - `status = NEW`
  - `retry_count = 0`
- The scenario is considered passed only if the certificate moved from `pki_ecu.core_active_xx` to `pki_revocation.revocation_current` and a `REVOKE` outbox event was created.

### Revoke fails when certificate is not in core_active

## APP Recover Scenarios

### Recover revoked certificate by appId

#### Preconditions

- A target APP certificate already exists in `pki_revocation.revocation_current`.
- The same certificate no longer exists in the resolved `pki_app.core_active_xx` shard table.
- A matching `pki_issuance.certificate_issue_fact` row exists for the same `certSerial` and `issuerId`.
- The `issue_fact` row contains a non-null `not_after`.
- The request uses `appId` as the subject identifier.

#### API Call

- `POST /app-certificates/recover`

Request body:

```json
{
  "appId": "app-demo-001",
  "installId": "",
  "certSerial": "ABC123",
  "issuerId": "ca-01"
}
```

#### Steps

1. Confirm the certificate currently exists in `pki_revocation.revocation_current`.
2. Confirm the certificate is absent from the resolved `pki_app.core_active_xx` shard table.
3. Confirm a matching `pki_issuance.certificate_issue_fact` row exists and has the expected `not_after`.
4. Call `POST /app-certificates/recover` with `appId`, `certSerial`, and `issuerId`.
5. Re-check the same APP `core_active_xx` shard table.
6. Re-check `pki_revocation.revocation_current`.
7. Re-check `pki_revocation.revocation_outbox`.
8. Compare the recovered `core_active_xx.not_after` with `issue_fact.not_after`.

#### SQL Checks

Resolve shard from the same application rule:

```text
partitionKey = appId + ":" + organization
organization = DFMC
shard = floorMod(hash(partitionKey), 32)
tableName = core_active_%02d
```

Check issue_fact source:

```sql
SELECT cert_serial, issuer_id, subject_id, organization, not_after, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY created_at DESC;
```

Check revocation_current before and after recover:

```sql
SELECT cert_serial, issuer_id, revoked_at, reason, first_activated_at, updated_at
FROM pki_revocation.revocation_current
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check APP core_active shard after recover:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_app.core_active_xx
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_outbox:

```sql
SELECT cert_serial, issuer_id, event_type, status, version, retry_count, created_at, updated_at
FROM pki_revocation.revocation_outbox
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY version;
```

#### Expected Result

- The request succeeds for the given `appId`, `certSerial`, and `issuerId`.
- The target certificate is written back into the resolved `pki_app.core_active_xx` table.
- The recovered `core_active_xx` row has:
  - matching `cert_serial`
  - matching `issuer_id`
  - matching `subject_id`
  - `is_current = false`
  - non-null `not_after`
- The recovered `core_active_xx.not_after` matches the `not_after` value from `pki_issuance.certificate_issue_fact`.
- The corresponding row is removed from `pki_revocation.revocation_current`.
- A new row exists in `pki_revocation.revocation_outbox`.
- The new `revocation_outbox` row has:
  - `event_type = RECOVER`
  - `status = NEW`
  - `retry_count = 0`
- The scenario is considered passed only if the certificate moved from `revocation_current` back to `core_active_xx` and `not_after` was restored correctly.

### Recover revoked certificate by installId

### Recover fails when revocation_current record is missing

### Recover fails when issue_fact record is missing

## ECU Recover Scenarios

### Recover revoked certificate by deviceId

#### Preconditions

- A target ECU certificate already exists in `pki_revocation.revocation_current`.
- The same certificate no longer exists in the resolved `pki_ecu.core_active_xx` shard table.
- A matching `pki_issuance.certificate_issue_fact` row exists for the same `certSerial` and `issuerId`.
- The `issue_fact` row contains a non-null `not_after`.
- The request uses `deviceId` as the subject identifier.
- The ECU organization is fixed to `DFMC_ECU`.

#### API Call

- `POST /ecu-certificates/recover`

Request body:

```json
{
  "deviceId": "device123",
  "certSerial": "ABC123",
  "issuerId": "ca-01"
}
```

#### Steps

1. Confirm the certificate currently exists in `pki_revocation.revocation_current`.
2. Confirm the certificate is absent from the resolved `pki_ecu.core_active_xx` shard table.
3. Confirm a matching `pki_issuance.certificate_issue_fact` row exists and has the expected `not_after`.
4. Resolve shard using `subjectId = deviceId` and `organization = DFMC_ECU`.
5. Call `POST /ecu-certificates/recover` with `deviceId`, `certSerial`, and `issuerId`.
6. Re-check the same ECU `core_active_xx` shard table.
7. Re-check `pki_revocation.revocation_current`.
8. Re-check `pki_revocation.revocation_outbox`.
9. Compare the recovered `core_active_xx.not_after` with `issue_fact.not_after`.

#### SQL Checks

Resolve shard from the same application rule:

```text
partitionKey = deviceId + ":" + organization
organization = DFMC_ECU
shard = floorMod(hash(partitionKey), 32)
tableName = core_active_%02d
```

Check issue_fact source:

```sql
SELECT cert_serial, issuer_id, subject_id, organization, not_after, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY created_at DESC;
```

Check revocation_current before and after recover:

```sql
SELECT cert_serial, issuer_id, revoked_at, reason, first_activated_at, updated_at
FROM pki_revocation.revocation_current
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check ECU core_active shard after recover:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_ecu.core_active_xx
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_outbox:

```sql
SELECT cert_serial, issuer_id, event_type, status, version, retry_count, created_at, updated_at
FROM pki_revocation.revocation_outbox
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY version;
```

#### Expected Result

- The request succeeds for the given `deviceId`, `certSerial`, and `issuerId`.
- The routing path uses `subjectId = deviceId` and `organization = DFMC_ECU` to resolve the target ECU shard.
- The target certificate is written back into the resolved `pki_ecu.core_active_xx` table.
- The recovered `core_active_xx` row has:
  - matching `cert_serial`
  - matching `issuer_id`
  - matching `subject_id`
  - `is_current = false`
  - non-null `not_after`
- The recovered `core_active_xx.not_after` matches the `not_after` value from `pki_issuance.certificate_issue_fact`.
- The corresponding row is removed from `pki_revocation.revocation_current`.
- A new row exists in `pki_revocation.revocation_outbox`.
- The new `revocation_outbox` row has:
  - `event_type = RECOVER`
  - `status = NEW`
  - `retry_count = 0`
- The scenario is considered passed only if the certificate moved from `pki_revocation.revocation_current` back to `pki_ecu.core_active_xx`, `not_after` was restored correctly, and a `RECOVER` outbox event was created.

### Recover fails when revocation_current record is missing

### Recover fails when issue_fact record is missing

## Routing Consistency Scenarios

### APP uses subjectId plus organization to resolve shard

### ECU uses subjectId plus organization to resolve shard

### Current query and revoke use the same subject-route path

### Current query and recover use the same subject-route path

The unified subject-route statement for these scenarios is:

- `current/query`, `revoke`, and `recover` all use `subjectId + organization -> shard -> core_active_xx` as the primary routing path.
- `locator` is not a required precondition and is not a required verification target for the new subject-route scenarios.
- `issue_fact` is only a required verification point when recover needs to verify that `not_after` was written back correctly.

## APP E2E happy path

### Preconditions

- An APP subject identifier is prepared and uses `appId = app-demo-001`.
- A new `requestId` is prepared for the apply call.
- The APP template uses an `app-` prefix and routes to APP domain.
- The APP organization is fixed to `DFMC`.
- The environment already has `pki_issuance`, `pki_app`, and `pki_revocation` schemas available.

### API Calls

- `POST /app-certificates/apply`
- `POST /certificates/sync-core-active/{requestId}`
- `POST /app-certificates/current/query`
- `POST /app-certificates/revoke`
- `POST /app-certificates/recover`
- `POST /app-certificates/current/query`

### Steps

1. Call `POST /app-certificates/apply` with a new `requestId`, `templateId`, and `appId`.
2. Query the apply result by `requestId` and confirm the certificate has been issued with a stable `certSerial` and `issuerId`.
3. Call `POST /certificates/sync-core-active/{requestId}`.
4. Call `POST /app-certificates/current/query` with `appId` and empty `certSerial`.
5. Confirm the current query returns the current active certificate for the same APP subject.
6. Call `POST /app-certificates/revoke` with the same `appId`, `certSerial`, and `issuerId`.
7. Confirm the certificate is removed from the resolved `pki_app.core_active_xx` shard and inserted into `pki_revocation.revocation_current`.
8. Call `POST /app-certificates/recover` with the same `appId`, `certSerial`, and `issuerId`.
9. Confirm the certificate is written back to the resolved `pki_app.core_active_xx` shard with `is_current = false`.
10. Call `POST /app-certificates/current/query` again with the same `appId` and empty `certSerial`.
11. Confirm the current query still returns a consistent APP subject view after revoke and recover.

### SQL Checks

Resolve shard from the APP subject-route rule:

```text
partitionKey = appId + ":" + organization
organization = DFMC
shard = floorMod(hash(partitionKey), 32)
tableName = core_active_%02d
```

Check issue_fact after apply:

```sql
SELECT request_id, cert_serial, issuer_id, subject_id, organization, status, sync_status, not_after, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE request_id = 'app-e2e-001';
```

Use the actual `certSerial` and `issuerId` returned by apply in the SQL checks below. Do not treat `ABC123` and `ca-01` as fixed business values.

Check APP core_active shard after sync:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_app.core_active_xx
WHERE subject_id = 'app-demo-001'
ORDER BY updated_at DESC;
```

Check revocation_current after revoke and after recover:

```sql
SELECT cert_serial, issuer_id, revoked_at, reason, first_activated_at, updated_at
FROM pki_revocation.revocation_current
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_outbox after revoke and recover:

```sql
SELECT cert_serial, issuer_id, event_type, status, version, retry_count, created_at, updated_at
FROM pki_revocation.revocation_outbox
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY version;
```

Check issue_fact source used by recover:

```sql
SELECT cert_serial, issuer_id, subject_id, organization, not_after, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY created_at DESC;
```

Check APP core_active shard directly after recover:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_app.core_active_xx
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

### Expected Result

- The APP apply call succeeds and returns an issued certificate with non-null `certSerial` and `issuerId`.
- The sync-core-active call succeeds and writes the certificate into the resolved `pki_app.core_active_xx` shard.
- The first APP current query returns:
  - matching `subjectId`
  - `organization = DFMC`
  - the resolved `shardId`
  - a non-null `currentActiveCertificate`
- The APP revoke call succeeds and removes the certificate from `pki_app.core_active_xx`.
- The APP revoke call also writes:
  - one row to `pki_revocation.revocation_current`
  - one `REVOKE` event to `pki_revocation.revocation_outbox`
- The APP recover call succeeds and writes the certificate back into `pki_app.core_active_xx`.
- The recovered row has:
  - matching `cert_serial`
  - matching `issuer_id`
  - matching `subject_id`
  - `is_current = false`
  - non-null `not_after`
- The recovered `not_after` matches the value stored in `pki_issuance.certificate_issue_fact`.
- The APP recover call removes the row from `pki_revocation.revocation_current`.
- The APP recover call appends one `RECOVER` event to `pki_revocation.revocation_outbox`.
- The second APP current query succeeds and returns the subject's current certificate view.
- The recover-writeback certificate remains `is_current = false` unless another separate current-switch action makes it current again.
- The scenario verifies the full apply -> sync-core-active -> current query -> revoke -> recover -> current query chain without implying that recover automatically restores current ownership.

## ECU E2E happy path

### Preconditions

- An ECU subject identifier is prepared and uses `deviceId = device123`.
- A new `requestId` is prepared for the apply call.
- The ECU template uses an `ecu-` prefix and routes to ECU domain.
- The ECU organization is fixed to `DFMC_ECU`.
- The environment already has `pki_issuance`, `pki_ecu`, and `pki_revocation` schemas available.

### API Calls

- `POST /ecu-certificates/apply`
- `POST /certificates/sync-core-active/{requestId}`
- `POST /ecu-certificates/current/query`
- `POST /ecu-certificates/revoke`
- `POST /ecu-certificates/recover`
- `POST /ecu-certificates/current/query`

### Steps

1. Call `POST /ecu-certificates/apply` with a new `requestId`, `templateId`, and `deviceId`.
2. Query the apply result by `requestId` and confirm the certificate has been issued with a stable `certSerial` and `issuerId`.
3. Call `POST /certificates/sync-core-active/{requestId}`.
4. Call `POST /ecu-certificates/current/query` with `deviceId` and empty `certSerial`.
5. Confirm the current query returns the current active certificate for the same ECU subject.
6. Call `POST /ecu-certificates/revoke` with the same `deviceId`, `certSerial`, and `issuerId`.
7. Confirm the certificate is removed from the resolved `pki_ecu.core_active_xx` shard and inserted into `pki_revocation.revocation_current`.
8. Call `POST /ecu-certificates/recover` with the same `deviceId`, `certSerial`, and `issuerId`.
9. Confirm the certificate is written back to the resolved `pki_ecu.core_active_xx` shard with `is_current = false`.
10. Call `POST /ecu-certificates/current/query` again with the same `deviceId` and empty `certSerial`.
11. Confirm the current query returns the ECU subject's current certificate view after revoke and recover, without implying that the recovered certificate automatically becomes current again.

### SQL Checks

Resolve shard from the ECU subject-route rule:

```text
partitionKey = deviceId + ":" + organization
organization = DFMC_ECU
shard = floorMod(hash(partitionKey), 32)
tableName = core_active_%02d
```

Check issue_fact after apply:

```sql
SELECT request_id, cert_serial, issuer_id, subject_id, organization, status, sync_status, not_after, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE request_id = 'ecu-e2e-001';
```

Use the actual `certSerial` and `issuerId` returned by apply in the SQL checks below. Do not treat `ABC123` and `ca-01` as fixed business values.

Check ECU core_active shard after sync:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_ecu.core_active_xx
WHERE subject_id = 'device123'
ORDER BY updated_at DESC;
```

Check revocation_current after revoke and after recover:

```sql
SELECT cert_serial, issuer_id, revoked_at, reason, first_activated_at, updated_at
FROM pki_revocation.revocation_current
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_outbox after revoke and recover:

```sql
SELECT cert_serial, issuer_id, event_type, status, version, retry_count, created_at, updated_at
FROM pki_revocation.revocation_outbox
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY version;
```

Check issue_fact source used by recover:

```sql
SELECT cert_serial, issuer_id, subject_id, organization, not_after, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY created_at DESC;
```

Check ECU core_active shard directly after recover:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_ecu.core_active_xx
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

### Expected Result

- The ECU apply call succeeds and returns an issued certificate with non-null `certSerial` and `issuerId`.
- The sync-core-active call succeeds and writes the certificate into the resolved `pki_ecu.core_active_xx` shard.
- The first ECU current query returns:
  - matching `subjectId`
  - `organization = DFMC_ECU`
  - the resolved `shardId`
  - a non-null `currentActiveCertificate`
- The ECU revoke call succeeds and removes the certificate from `pki_ecu.core_active_xx`.
- The ECU revoke call also writes:
  - one row to `pki_revocation.revocation_current`
  - one `REVOKE` event to `pki_revocation.revocation_outbox`
- The ECU recover call succeeds and writes the certificate back into `pki_ecu.core_active_xx`.
- The recovered row has:
  - matching `cert_serial`
  - matching `issuer_id`
  - matching `subject_id`
  - `is_current = false`
  - non-null `not_after`
- The recovered `not_after` matches the value stored in `pki_issuance.certificate_issue_fact`.
- The ECU recover call removes the row from `pki_revocation.revocation_current`.
- The ECU recover call appends one `RECOVER` event to `pki_revocation.revocation_outbox`.
- The second ECU current query succeeds and returns the subject's current certificate view.
- The recover-writeback certificate remains `is_current = false` unless another separate current-switch action makes it current again.
- The scenario verifies the full apply -> sync-core-active -> current query -> revoke -> recover -> current query chain without implying that recover automatically restores current ownership.

## APP subject mismatch failure path

### Preconditions

- A target APP certificate already exists for a real subject, for example `subjectId = app-owner-001`.
- The certificate has a valid `certSerial` and `issuerId`.
- For revoke mismatch verification, the certificate is still present in the resolved `pki_app.core_active_xx` shard table for the real subject.
- For recover mismatch verification, the certificate has already been moved into `pki_revocation.revocation_current`.
- A different APP request subject is prepared, for example `appId = app-other-999` or `installId = app-other-999`.
- The mismatch subject is not equal to the certificate owner's real `subjectId`.

### API Calls

- `POST /app-certificates/revoke`
- `POST /app-certificates/recover`

### Steps

1. Prepare a certificate whose real owner subject is known from prior apply and sync-core-active steps.
2. Confirm the real owner `subjectId` from `pki_issuance.certificate_issue_fact`.
3. Prepare a revoke request using a different `appId` or `installId` than the real owner subject.
4. Call `POST /app-certificates/revoke` with the mismatched subject and the real certificate's `certSerial` and `issuerId`.
5. Confirm the request fails with `subject does not match certificate owner`.
6. If recover mismatch is also being verified, first ensure the same certificate is already in `pki_revocation.revocation_current`.
7. Call `POST /app-certificates/recover` with the same mismatched subject and the real certificate's `certSerial` and `issuerId`.
8. Confirm the request fails with `subject does not match certificate owner`.

### SQL Checks

Use the actual `certSerial` and `issuerId` returned by apply. Do not treat example values as fixed business values.

Check the real owner from issue_fact:

```sql
SELECT cert_serial, issuer_id, subject_id, organization, not_after, created_at, updated_at
FROM pki_issuance.certificate_issue_fact
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY created_at DESC;
```

Check APP core_active ownership for revoke mismatch verification:

```sql
SELECT cert_serial, issuer_id, subject_id, is_current, not_after, first_activated_at, created_at, updated_at
FROM pki_app.core_active_xx
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_current for recover mismatch verification:

```sql
SELECT cert_serial, issuer_id, revoked_at, reason, first_activated_at, updated_at
FROM pki_revocation.revocation_current
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01';
```

Check revocation_outbox remains unchanged:

```sql
SELECT cert_serial, issuer_id, event_type, status, version, retry_count, created_at, updated_at
FROM pki_revocation.revocation_outbox
WHERE cert_serial = 'ABC123'
  AND issuer_id = 'ca-01'
ORDER BY version;
```

### Expected Result

- The APP revoke request with mismatched `appId` or `installId` fails with:
  - `subject does not match certificate owner`
- The APP recover request with mismatched `appId` or `installId` fails with:
  - `subject does not match certificate owner`
- Revoke mismatch does not delete the certificate from `pki_app.core_active_xx`.
- Recover mismatch does not write any new row back into `pki_app.core_active_xx`.
- Recover mismatch does not delete the existing row from `pki_revocation.revocation_current`.
- Neither mismatch request appends a new outbox event.
