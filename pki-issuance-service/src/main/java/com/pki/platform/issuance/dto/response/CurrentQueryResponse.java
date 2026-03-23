package com.pki.platform.issuance.dto.response;

import java.util.List;

public class CurrentQueryResponse {

    private String subjectId;
    private String organization;
    private Integer shardId;
    private Integer issuedCount;
    private CertificateQueryItemResponse latestIssuedCertificate;
    private CertificateQueryItemResponse currentActiveCertificate;
    private List<CertificateQueryItemResponse> matchedCertificates;

    public String getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(String subjectId) {
        this.subjectId = subjectId;
    }

    public String getOrganization() {
        return organization;
    }

    public void setOrganization(String organization) {
        this.organization = organization;
    }

    public Integer getShardId() {
        return shardId;
    }

    public void setShardId(Integer shardId) {
        this.shardId = shardId;
    }

    public Integer getIssuedCount() {
        return issuedCount;
    }

    public void setIssuedCount(Integer issuedCount) {
        this.issuedCount = issuedCount;
    }

    public CertificateQueryItemResponse getLatestIssuedCertificate() {
        return latestIssuedCertificate;
    }

    public void setLatestIssuedCertificate(CertificateQueryItemResponse latestIssuedCertificate) {
        this.latestIssuedCertificate = latestIssuedCertificate;
    }

    public CertificateQueryItemResponse getCurrentActiveCertificate() {
        return currentActiveCertificate;
    }

    public void setCurrentActiveCertificate(CertificateQueryItemResponse currentActiveCertificate) {
        this.currentActiveCertificate = currentActiveCertificate;
    }

    public List<CertificateQueryItemResponse> getMatchedCertificates() {
        return matchedCertificates;
    }

    public void setMatchedCertificates(List<CertificateQueryItemResponse> matchedCertificates) {
        this.matchedCertificates = matchedCertificates;
    }
}
