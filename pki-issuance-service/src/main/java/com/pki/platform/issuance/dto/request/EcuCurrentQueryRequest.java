package com.pki.platform.issuance.dto.request;

public class EcuCurrentQueryRequest {

    private String deviceId;
    private String certSerial;

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }

    public String getCertSerial() {
        return certSerial;
    }

    public void setCertSerial(String certSerial) {
        this.certSerial = certSerial;
    }
}
