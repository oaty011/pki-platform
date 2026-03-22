ALTER TABLE pki_ecu.certificate_locator
    ADD COLUMN IF NOT EXISTS issuer_id VARCHAR(128),
    ADD COLUMN IF NOT EXISTS routing_version INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ NULL;

UPDATE pki_ecu.certificate_locator
SET issuer_id = COALESCE(issuer_id, 'unknown-issuer')
WHERE issuer_id IS NULL;

ALTER TABLE pki_ecu.certificate_locator
    ALTER COLUMN issuer_id SET NOT NULL;

ALTER TABLE pki_ecu.certificate_locator
    DROP CONSTRAINT IF EXISTS certificate_locator_pkey;

ALTER TABLE pki_ecu.certificate_locator
    ADD CONSTRAINT certificate_locator_pkey PRIMARY KEY (cert_serial, issuer_id);
