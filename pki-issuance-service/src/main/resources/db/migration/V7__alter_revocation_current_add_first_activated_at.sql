ALTER TABLE pki_revocation.revocation_current
    ADD COLUMN IF NOT EXISTS first_activated_at TIMESTAMPTZ NULL;
