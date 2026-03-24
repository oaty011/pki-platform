package com.pki.platform.issuance.dto.response;

import java.time.OffsetDateTime;

public class CertificateQueryItemResponse {

    private String certSerial;
    private String issuerId;
    private OffsetDateTime notAfter;
    private OffsetDateTime firstActivatedAt;

    public String getCertSerial() {
        return certSerial;
    }

    public void setCertSerial(String certSerial) {
        this.certSerial = certSerial;
    }

    public String getIssuerId() {
        return issuerId;
    }

    public void setIssuerId(String issuerId) {
        this.issuerId = issuerId;
    }

    public OffsetDateTime getNotAfter() {
        return notAfter;
    }

    public void setNotAfter(OffsetDateTime notAfter) {
        this.notAfter = notAfter;
    }

    public OffsetDateTime getFirstActivatedAt() {
        return firstActivatedAt;
    }

    public void setFirstActivatedAt(OffsetDateTime firstActivatedAt) {
        this.firstActivatedAt = firstActivatedAt;
    }
}
