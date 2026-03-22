package com.pki.platform.issuance.dto.response;

public class CertificateContentResponse {

    private String requestId;
    private String certSerial;
    private String issuerId;
    private String certificatePem;
    private String chainPem;

    public CertificateContentResponse() {
    }

    public CertificateContentResponse(String requestId, String certSerial, String issuerId, String certificatePem, String chainPem) {
        this.requestId = requestId;
        this.certSerial = certSerial;
        this.issuerId = issuerId;
        this.certificatePem = certificatePem;
        this.chainPem = chainPem;
    }

    public String getRequestId() {
        return requestId;
    }

    public void setRequestId(String requestId) {
        this.requestId = requestId;
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

    public String getCertificatePem() {
        return certificatePem;
    }

    public void setCertificatePem(String certificatePem) {
        this.certificatePem = certificatePem;
    }

    public String getChainPem() {
        return chainPem;
    }

    public void setChainPem(String chainPem) {
        this.chainPem = chainPem;
    }
}
