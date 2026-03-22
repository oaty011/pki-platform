CREATE SCHEMA IF NOT EXISTS pki_issuance;

CREATE TABLE IF NOT EXISTS pki_issuance.certificate_issue_fact (
    id BIGSERIAL PRIMARY KEY,
    request_id VARCHAR(128) NOT NULL,
    subject_id VARCHAR(128) NOT NULL,
    issuer_id VARCHAR(128) NOT NULL,
    cert_serial VARCHAR(128),
    certificate_pem TEXT,
    status VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_certificate_issue_fact_request_id
    ON pki_issuance.certificate_issue_fact (request_id);

CREATE INDEX IF NOT EXISTS idx_certificate_issue_fact_subject_id
    ON pki_issuance.certificate_issue_fact (subject_id);
