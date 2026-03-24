# Core Active Model

Current implementation status note:

- The latest implementation baseline is [issuance-phase1-summary.md](/Users/wuge/Desktop/CodeX/PKI Platform/docs/issuance-phase1-summary.md).
- `is_current` has already been removed from the schema and main logic.
- The default query result is now the latest record in `core_active_xx`, not an `is_current=true` row.

`core_active_xx` only stores certificates that still remain in the primary set.

- The table does not represent `ACTIVE` / `REVOKED` / `EXPIRED` state.
- The table does not represent `hot` / `warm` / `stale` tiers.
- The same `subjectId` may keep multiple certificates in the primary set at the same time.
- The default query now returns the latest record in the primary set for the subject.
- `not_after` is sourced from real issuance results written into `certificate_issue_fact`.
- Manual revoke removes the certificate from `core_active_xx`, writes `revocation_current`, and appends a `REVOKE` event to `revocation_outbox`.
- Manual recover removes the `revocation_current` row, writes the certificate back to `core_active_xx`, and appends a `RECOVER` event to `revocation_outbox`.
- The legacy `POST /certificates/{certSerial}/revoke` and `POST /certificates/{certSerial}/recover` interfaces are deprecated because they depend on locator-based routing.
- The recommended subject-route interfaces are `POST /app-certificates/revoke`, `POST /ecu-certificates/revoke`, `POST /app-certificates/recover`, and `POST /ecu-certificates/recover`.
- The recommended route resolves the target shard from `subjectId + organization` instead of using locator as the primary routing dependency.
- `first_activated_at` is `NULL` until the certificate is actually used for the first time, and once written it must never be updated again.
- Future cleanup decisions should only rely on `updated_at`, `not_after`, and `first_activated_at`.
- Future revoke / expire handling should move certificates out of `core_active_xx` into other collections instead of updating an in-row status.
