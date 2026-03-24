package com.pki.platform.ecudomain.model;

import java.time.OffsetDateTime;

public class CoreActiveRecord {

    private String certSerial;
    private String issuerId;
    private String subjectId;
    /**
     * core_active only stores certificates that still remain in the primary set.
     * Revoked or expired certificates will later leave this set by table migration,
     * not by changing an in-row status field.
     */
    private OffsetDateTime notAfter;
    /**
     * Written once on first real activation and then never updated again.
     */
    private OffsetDateTime firstActivatedAt;
    private OffsetDateTime createdAt;
    private OffsetDateTime updatedAt;

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

    public String getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(String subjectId) {
        this.subjectId = subjectId;
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

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(OffsetDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(OffsetDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
