ALTER TABLE pki_issuance.certificate_issue_fact
    ADD COLUMN IF NOT EXISTS signer_id VARCHAR(128),
    ADD COLUMN IF NOT EXISTS sync_status VARCHAR(32) NOT NULL DEFAULT 'pending';

CREATE INDEX IF NOT EXISTS idx_certificate_issue_fact_sync_status
    ON pki_issuance.certificate_issue_fact (sync_status);
