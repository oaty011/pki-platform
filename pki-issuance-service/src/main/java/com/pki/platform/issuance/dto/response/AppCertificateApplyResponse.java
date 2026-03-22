package com.pki.platform.issuance.dto.response;

public class AppCertificateApplyResponse {

    private String requestId;
    private String status;
    private String appId;
    private String installId;

    public AppCertificateApplyResponse() {
    }

    public AppCertificateApplyResponse(String requestId, String status, String appId, String installId) {
        this.requestId = requestId;
        this.status = status;
        this.appId = appId;
        this.installId = installId;
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

    public String getAppId() {
        return appId;
    }

    public void setAppId(String appId) {
        this.appId = appId;
    }

    public String getInstallId() {
        return installId;
    }

    public void setInstallId(String installId) {
        this.installId = installId;
    }
}
