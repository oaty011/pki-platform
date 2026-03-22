package com.pki.platform.revocation.mapper;

import com.pki.platform.revocation.model.RevocationCurrent;
import org.apache.ibatis.annotations.Param;

public interface RevocationCurrentMapper {

    int insert(RevocationCurrent record);

    RevocationCurrent selectByCertSerialAndIssuerId(@Param("certSerial") String certSerial,
                                                    @Param("issuerId") String issuerId);

    int deleteByCertSerialAndIssuerId(@Param("certSerial") String certSerial,
                                      @Param("issuerId") String issuerId);
}
