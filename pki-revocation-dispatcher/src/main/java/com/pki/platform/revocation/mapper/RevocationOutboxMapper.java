package com.pki.platform.revocation.mapper;

import com.pki.platform.revocation.model.RevocationOutbox;
import org.apache.ibatis.annotations.Param;

public interface RevocationOutboxMapper {

    int insert(RevocationOutbox record);

    Long selectMaxVersionByCertSerialAndIssuerId(@Param("certSerial") String certSerial,
                                                 @Param("issuerId") String issuerId);
}
