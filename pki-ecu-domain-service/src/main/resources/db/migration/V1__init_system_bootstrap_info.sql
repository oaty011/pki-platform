CREATE SCHEMA IF NOT EXISTS pki_ecu;

CREATE TABLE IF NOT EXISTS pki_ecu.system_bootstrap_info (
    id BIGSERIAL PRIMARY KEY,
    service_name VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_system_bootstrap_info_service_name
    ON pki_ecu.system_bootstrap_info (service_name);

CREATE INDEX IF NOT EXISTS idx_system_bootstrap_info_created_at
    ON pki_ecu.system_bootstrap_info (created_at);

INSERT INTO pki_ecu.system_bootstrap_info (service_name)
SELECT 'pki-ecu-domain-service'
WHERE NOT EXISTS (
    SELECT 1 FROM pki_ecu.system_bootstrap_info WHERE service_name = 'pki-ecu-domain-service'
);
