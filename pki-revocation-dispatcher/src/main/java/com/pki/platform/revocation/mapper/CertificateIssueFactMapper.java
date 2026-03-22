package com.pki.platform.revocation.mapper;

import com.pki.platform.revocation.model.CertificateIssueFact;
import org.apache.ibatis.annotations.Param;

public interface CertificateIssueFactMapper {

    CertificateIssueFact selectByCertSerialAndIssuerId(@Param("certSerial") String certSerial,
                                                       @Param("issuerId") String issuerId);
}
