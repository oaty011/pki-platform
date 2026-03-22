package com.pki.platform.issuance.dto.response;

public class EcuCertificateApplyResponse {

    private String requestId;
    private String status;
    private String deviceId;

    public EcuCertificateApplyResponse() {
    }

    public EcuCertificateApplyResponse(String requestId, String status, String deviceId) {
        this.requestId = requestId;
        this.status = status;
        this.deviceId = deviceId;
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

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }
}
