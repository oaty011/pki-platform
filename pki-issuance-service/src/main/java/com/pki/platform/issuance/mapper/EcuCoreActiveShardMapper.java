package com.pki.platform.issuance.mapper;

import com.pki.platform.issuance.model.CoreActiveRecord;
import org.apache.ibatis.annotations.Param;

public interface EcuCoreActiveShardMapper {

    /**
     * core_active holds the primary certificate set only.
     * first_activated_at is write-once and must not be overwritten on upsert.
     */
    int upsertToShard(@Param("tableName") String tableName,
                      @Param("record") CoreActiveRecord record);

    CoreActiveRecord selectCurrentBySubjectIdFromShard(@Param("tableName") String tableName,
                                                       @Param("subjectId") String subjectId);

    CoreActiveRecord selectByCertSerialFromShard(@Param("tableName") String tableName,
                                                 @Param("certSerial") String certSerial);

    int markCurrentFalseBySubjectIdInShard(@Param("tableName") String tableName,
                                           @Param("subjectId") String subjectId,
                                           @Param("updatedAt") java.time.OffsetDateTime updatedAt);
}
