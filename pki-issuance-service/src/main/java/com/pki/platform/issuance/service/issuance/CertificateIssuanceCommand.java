package com.pki.platform.issuance.service.issuance;

import com.pki.platform.issuance.template.CertificateType;
import com.pki.platform.issuance.template.SubjectCnSource;
import java.time.OffsetDateTime;

public class CertificateIssuanceCommand {

    private String requestId;
    private String templateId;
    private String subjectId;
    private CertificateType certificateType;
    private SubjectCnSource subjectCnSource;
    private String organization;
    private String subjectDn;
    private String subjectOu;
    private String subjectO;
    private String subjectC;
    private String csrPem;
    private int validityDays;
    private String keyAlgorithm;
    private boolean digitalSignature;
    private boolean keyEncipherment;
    private boolean clientAuth;
    private String providerType;
    private String signerType;
    private String issuerBinding;
    private OffsetDateTime notBefore;
    private OffsetDateTime notAfter;

    public String getRequestId() {
        return requestId;
    }

    public void setRequestId(String requestId) {
        this.requestId = requestId;
    }

    public String getTemplateId() {
        return templateId;
    }

    public void setTemplateId(String templateId) {
        this.templateId = templateId;
    }

    public String getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(String subjectId) {
        this.subjectId = subjectId;
    }

    public CertificateType getCertificateType() {
        return certificateType;
    }

    public void setCertificateType(CertificateType certificateType) {
        this.certificateType = certificateType;
    }

    public SubjectCnSource getSubjectCnSource() {
        return subjectCnSource;
    }

    public void setSubjectCnSource(SubjectCnSource subjectCnSource) {
        this.subjectCnSource = subjectCnSource;
    }

    public String getOrganization() {
        return organization;
    }

    public void setOrganization(String organization) {
        this.organization = organization;
    }

    public String getSubjectDn() {
        return subjectDn;
    }

    public void setSubjectDn(String subjectDn) {
        this.subjectDn = subjectDn;
    }

    public String getSubjectOu() {
        return subjectOu;
    }

    public void setSubjectOu(String subjectOu) {
        this.subjectOu = subjectOu;
    }

    public String getSubjectO() {
        return subjectO;
    }

    public void setSubjectO(String subjectO) {
        this.subjectO = subjectO;
    }

    public String getSubjectC() {
        return subjectC;
    }

    public void setSubjectC(String subjectC) {
        this.subjectC = subjectC;
    }

    public String getCsrPem() {
        return csrPem;
    }

    public void setCsrPem(String csrPem) {
        this.csrPem = csrPem;
    }

    public int getValidityDays() {
        return validityDays;
    }

    public void setValidityDays(int validityDays) {
        this.validityDays = validityDays;
    }

    public String getKeyAlgorithm() {
        return keyAlgorithm;
    }

    public void setKeyAlgorithm(String keyAlgorithm) {
        this.keyAlgorithm = keyAlgorithm;
    }

    public boolean isDigitalSignature() {
        return digitalSignature;
    }

    public void setDigitalSignature(boolean digitalSignature) {
        this.digitalSignature = digitalSignature;
    }

    public boolean isKeyEncipherment() {
        return keyEncipherment;
    }

    public void setKeyEncipherment(boolean keyEncipherment) {
        this.keyEncipherment = keyEncipherment;
    }

    public boolean isClientAuth() {
        return clientAuth;
    }

    public void setClientAuth(boolean clientAuth) {
        this.clientAuth = clientAuth;
    }

    public String getProviderType() {
        return providerType;
    }

    public void setProviderType(String providerType) {
        this.providerType = providerType;
    }

    public String getSignerType() {
        return signerType;
    }

    public void setSignerType(String signerType) {
        this.signerType = signerType;
    }

    public String getIssuerBinding() {
        return issuerBinding;
    }

    public void setIssuerBinding(String issuerBinding) {
        this.issuerBinding = issuerBinding;
    }

    public OffsetDateTime getNotBefore() {
        return notBefore;
    }

    public void setNotBefore(OffsetDateTime notBefore) {
        this.notBefore = notBefore;
    }

    public OffsetDateTime getNotAfter() {
        return notAfter;
    }

    public void setNotAfter(OffsetDateTime notAfter) {
        this.notAfter = notAfter;
    }
}
