package com.pki.platform.issuance.service.issuance;

public interface CertificateIssuanceProvider {

    CertificateIssuanceResult issue(CertificateIssuanceCommand command);
}
