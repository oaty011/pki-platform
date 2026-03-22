package com.pki.platform.appdomain.mapper;

import com.pki.platform.appdomain.model.CertificateLocator;
import org.apache.ibatis.annotations.Param;

public interface CertificateLocatorMapper {

    int insert(CertificateLocator record);

    CertificateLocator selectByCertSerialAndIssuerId(@Param("certSerial") String certSerial,
                                                     @Param("issuerId") String issuerId);
}
