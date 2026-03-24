package com.pki.platform.issuance.dto.response;

public class CertificateRefreshStatusResponse {

    private final String certSerial;
    private final String issuerId;
    private final String subjectId;
    private final String organization;
    private final boolean refreshed;

    public CertificateRefreshStatusResponse(String certSerial,
                                            String issuerId,
                                            String subjectId,
                                            String organization,
                                            boolean refreshed) {
        this.certSerial = certSerial;
        this.issuerId = issuerId;
        this.subjectId = subjectId;
        this.organization = organization;
        this.refreshed = refreshed;
    }

    public String getCertSerial() {
        return certSerial;
    }

    public String getIssuerId() {
        return issuerId;
    }

    public String getSubjectId() {
        return subjectId;
    }

    public String getOrganization() {
        return organization;
    }

    public boolean isRefreshed() {
        return refreshed;
    }
}
