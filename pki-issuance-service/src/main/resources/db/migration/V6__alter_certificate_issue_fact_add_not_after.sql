ALTER TABLE pki_issuance.certificate_issue_fact
    ADD COLUMN IF NOT EXISTS not_after TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS idx_certificate_issue_fact_not_after
    ON pki_issuance.certificate_issue_fact (not_after);
