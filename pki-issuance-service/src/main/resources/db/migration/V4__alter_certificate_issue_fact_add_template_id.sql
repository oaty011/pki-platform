ALTER TABLE pki_issuance.certificate_issue_fact
    ADD COLUMN IF NOT EXISTS template_id VARCHAR(128);

CREATE INDEX IF NOT EXISTS idx_certificate_issue_fact_template_id
    ON pki_issuance.certificate_issue_fact (template_id);
