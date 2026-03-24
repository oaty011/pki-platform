DO $$
DECLARE
    shard_no INTEGER;
    table_name TEXT;
    index_name TEXT;
BEGIN
    FOR shard_no IN 0..31 LOOP
        table_name := 'core_active_' || LPAD(shard_no::TEXT, 2, '0');
        index_name := 'idx_' || table_name || '_subject_current';

        EXECUTE FORMAT('DROP INDEX IF EXISTS pki_ecu.%I', index_name);
        EXECUTE FORMAT('ALTER TABLE pki_ecu.%I DROP COLUMN IF EXISTS is_current', table_name);
    END LOOP;
END $$;
