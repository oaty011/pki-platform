CREATE SCHEMA IF NOT EXISTS pki_app;

CREATE TABLE IF NOT EXISTS pki_app.certificate_locator (
    cert_serial VARCHAR(128) PRIMARY KEY,
    subject_id VARCHAR(128) NOT NULL,
    shard_id INTEGER NOT NULL,
    storage_type VARCHAR(32) NOT NULL,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_certificate_locator_subject_id
    ON pki_app.certificate_locator (subject_id);

CREATE INDEX IF NOT EXISTS idx_certificate_locator_shard_id
    ON pki_app.certificate_locator (shard_id);
