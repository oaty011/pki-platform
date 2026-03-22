package com.pki.platform.revocation.mapper;

import com.pki.platform.revocation.model.CoreActiveRecord;
import org.apache.ibatis.annotations.Param;

public interface AppCoreActiveShardMapper {

    CoreActiveRecord selectByCertSerialAndIssuerIdFromShard(@Param("tableName") String tableName,
                                                            @Param("certSerial") String certSerial,
                                                            @Param("issuerId") String issuerId);

    int deleteByCertSerialAndIssuerIdFromShard(@Param("tableName") String tableName,
                                               @Param("certSerial") String certSerial,
                                               @Param("issuerId") String issuerId);

    int upsertToShard(@Param("tableName") String tableName,
                      @Param("record") CoreActiveRecord record);
}
