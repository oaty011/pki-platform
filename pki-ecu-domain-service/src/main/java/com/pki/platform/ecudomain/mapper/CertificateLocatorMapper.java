package com.pki.platform.ecudomain.mapper;

import com.pki.platform.ecudomain.model.CertificateLocator;
import org.apache.ibatis.annotations.Param;

public interface CertificateLocatorMapper {

    int insert(CertificateLocator record);

    CertificateLocator selectByCertSerialAndIssuerId(@Param("certSerial") String certSerial,
                                                     @Param("issuerId") String issuerId);
}
