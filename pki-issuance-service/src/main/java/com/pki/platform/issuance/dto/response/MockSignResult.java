package com.pki.platform.issuance.dto.response;

import java.time.OffsetDateTime;

public class MockSignResult {

    private final String certSerial;
    private final String issuerId;
    private final String signerId;
    private final String certificatePem;
    private final OffsetDateTime notAfter;

    public MockSignResult(String certSerial,
                          String issuerId,
                          String signerId,
                          String certificatePem,
                          OffsetDateTime notAfter) {
        this.certSerial = certSerial;
        this.issuerId = issuerId;
        this.signerId = signerId;
        this.certificatePem = certificatePem;
        this.notAfter = notAfter;
    }

    public String getCertSerial() {
        return certSerial;
    }

    public String getIssuerId() {
        return issuerId;
    }

    public String getSignerId() {
        return signerId;
    }

    public String getCertificatePem() {
        return certificatePem;
    }

    public OffsetDateTime getNotAfter() {
        return notAfter;
    }
}
