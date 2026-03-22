DO $$
DECLARE
    shard_no INTEGER;
    table_name TEXT;
BEGIN
    FOR shard_no IN 0..31 LOOP
        table_name := 'core_active_' || LPAD(shard_no::TEXT, 2, '0');

        EXECUTE FORMAT(
            'ALTER TABLE pki_ecu.%I '
            || 'ADD COLUMN IF NOT EXISTS not_after TIMESTAMPTZ NULL, '
            || 'ADD COLUMN IF NOT EXISTS first_activated_at TIMESTAMPTZ NULL',
            table_name
        );

        EXECUTE FORMAT(
            'ALTER TABLE pki_ecu.%I '
            || 'DROP COLUMN IF EXISTS status',
            table_name
        );

        EXECUTE FORMAT(
            'CREATE INDEX IF NOT EXISTS %I ON pki_ecu.%I (not_after)',
            'idx_' || table_name || '_not_after',
            table_name
        );
    END LOOP;
END $$;
