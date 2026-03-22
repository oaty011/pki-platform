ALTER TABLE pki_issuance.certificate_issue_fact
    ADD COLUMN IF NOT EXISTS organization VARCHAR(128);

CREATE INDEX IF NOT EXISTS idx_certificate_issue_fact_organization
    ON pki_issuance.certificate_issue_fact (organization);
