package com.pki.platform.issuance.dto.response;

import java.time.OffsetDateTime;

public class CertificateQueryItemResponse {

    private String certSerial;
    private String issuerId;
    private Boolean isCurrent;
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

    public Boolean getIsCurrent() {
        return isCurrent;
    }

    public void setIsCurrent(Boolean current) {
        isCurrent = current;
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
