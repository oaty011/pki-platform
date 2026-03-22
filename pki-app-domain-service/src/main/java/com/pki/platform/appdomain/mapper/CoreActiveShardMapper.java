package com.pki.platform.appdomain.mapper;

import com.pki.platform.appdomain.model.CoreActiveRecord;
import org.apache.ibatis.annotations.Param;

public interface CoreActiveShardMapper {

    /**
     * core_active holds the primary certificate set only.
     * first_activated_at is write-once and must not be overwritten on upsert.
     */
    int upsertToShard(@Param("tableName") String tableName,
                      @Param("record") CoreActiveRecord record);

    CoreActiveRecord selectCurrentBySubjectIdFromShard(@Param("tableName") String tableName,
                                                       @Param("subjectId") String subjectId);

    int markCurrentFalseBySubjectIdInShard(@Param("tableName") String tableName,
                                           @Param("subjectId") String subjectId,
                                           @Param("updatedAt") java.time.OffsetDateTime updatedAt);
}
