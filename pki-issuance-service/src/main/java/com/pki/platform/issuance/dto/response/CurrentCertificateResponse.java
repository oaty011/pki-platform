package com.pki.platform.issuance.dto.response;

import java.time.OffsetDateTime;

public class CurrentCertificateResponse {

    private String subjectId;
    private String certSerial;
    private String issuerId;
    private Boolean isCurrent;
    private OffsetDateTime notAfter;
    private OffsetDateTime firstActivatedAt;

    public CurrentCertificateResponse() {
    }

    public CurrentCertificateResponse(String subjectId,
                                      String certSerial,
                                      String issuerId,
                                      Boolean isCurrent,
                                      OffsetDateTime notAfter,
                                      OffsetDateTime firstActivatedAt) {
        this.subjectId = subjectId;
        this.certSerial = certSerial;
        this.issuerId = issuerId;
        this.isCurrent = isCurrent;
        this.notAfter = notAfter;
        this.firstActivatedAt = firstActivatedAt;
    }

    public String getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(String subjectId) {
        this.subjectId = subjectId;
    }

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
