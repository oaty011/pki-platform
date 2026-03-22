DO $$
DECLARE
    shard_no INTEGER;
    table_name TEXT;
BEGIN
    FOR shard_no IN 0..31 LOOP
        table_name := 'core_active_' || LPAD(shard_no::TEXT, 2, '0');

        EXECUTE FORMAT(
            'CREATE TABLE IF NOT EXISTS pki_ecu.%I ('
            || 'cert_serial VARCHAR(128) NOT NULL,'
            || 'issuer_id VARCHAR(128) NOT NULL,'
            || 'subject_id VARCHAR(128) NOT NULL,'
            || 'status VARCHAR(32) NOT NULL,'
            || 'is_current BOOLEAN NOT NULL,'
            || 'created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,'
            || 'updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,'
            || 'PRIMARY KEY (cert_serial, issuer_id)'
            || ')',
            table_name
        );

        EXECUTE FORMAT(
            'CREATE INDEX IF NOT EXISTS %I ON pki_ecu.%I (subject_id)',
            'idx_' || table_name || '_subject_id',
            table_name
        );

        EXECUTE FORMAT(
            'CREATE INDEX IF NOT EXISTS %I ON pki_ecu.%I (subject_id, is_current)',
            'idx_' || table_name || '_subject_current',
            table_name
        );

        EXECUTE FORMAT(
            'CREATE INDEX IF NOT EXISTS %I ON pki_ecu.%I (updated_at)',
            'idx_' || table_name || '_updated_at',
            table_name
        );
    END LOOP;
END $$;
