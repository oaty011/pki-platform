CREATE SCHEMA IF NOT EXISTS pki_revocation;

CREATE TABLE IF NOT EXISTS pki_revocation.revocation_current (
    cert_serial VARCHAR(128) PRIMARY KEY,
    issuer_id VARCHAR(128) NOT NULL,
    revoked_at TIMESTAMPTZ NOT NULL,
    reason VARCHAR(64) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_revocation_current_updated_at
    ON pki_revocation.revocation_current (updated_at);

CREATE TABLE IF NOT EXISTS pki_revocation.revocation_outbox (
    id BIGSERIAL PRIMARY KEY,
    cert_serial VARCHAR(128) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    status VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_revocation_outbox_status
    ON pki_revocation.revocation_outbox (status);
