package com.pki.platform.ecudomain.mapper;

import com.pki.platform.ecudomain.model.CoreActiveRecord;
import org.apache.ibatis.annotations.Param;

public interface CoreActiveShardMapper {

    /**
     * core_active holds the primary certificate set only.
     * first_activated_at is write-once and must not be overwritten on upsert.
     */
    int upsertToShard(@Param("tableName") String tableName,
                      @Param("record") CoreActiveRecord record);
}
