package com.pki.platform.issuance.dto.response;

public class CertificateStatusResponse {

    private String requestId;
    private String status;
    private String certSerial;
    private String issuerId;
    private String syncStatus;

    public CertificateStatusResponse() {
    }

    public CertificateStatusResponse(String requestId, String status, String certSerial, String issuerId, String syncStatus) {
        this.requestId = requestId;
        this.status = status;
        this.certSerial = certSerial;
        this.issuerId = issuerId;
        this.syncStatus = syncStatus;
    }

    public String getRequestId() {
        return requestId;
    }

    public void setRequestId(String requestId) {
        this.requestId = requestId;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
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

    public String getSyncStatus() {
        return syncStatus;
    }

    public void setSyncStatus(String syncStatus) {
        this.syncStatus = syncStatus;
    }
}
