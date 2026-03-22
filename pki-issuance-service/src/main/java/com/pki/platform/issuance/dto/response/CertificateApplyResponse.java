package com.pki.platform.issuance.dto.response;

public class CertificateApplyResponse {

    private String requestId;
    private String status;

    public CertificateApplyResponse() {
    }

    public CertificateApplyResponse(String requestId, String status) {
        this.requestId = requestId;
        this.status = status;
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
}
