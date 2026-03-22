ALTER TABLE pki_revocation.revocation_current
    DROP CONSTRAINT IF EXISTS revocation_current_pkey;

ALTER TABLE pki_revocation.revocation_current
    ADD CONSTRAINT revocation_current_pkey PRIMARY KEY (cert_serial, issuer_id);
