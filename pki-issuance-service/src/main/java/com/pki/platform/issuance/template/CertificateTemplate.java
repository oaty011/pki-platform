package com.pki.platform.issuance.template;

public class CertificateTemplate {

    private final String templateId;
    private final CertificateType certificateType;
    private final SubjectCnSource subjectCnSource;
    private final String subjectOu;
    private final String subjectO;
    private final String subjectC;
    private final String organization;
    private final int validityDays;
    private final String keyAlgorithm;
    private final boolean digitalSignature;
    private final boolean keyEncipherment;
    private final boolean clientAuth;
    private final String providerType;
    private final String signerType;
    private final String issuerBinding;

    public CertificateTemplate(String templateId,
                               CertificateType certificateType,
                               SubjectCnSource subjectCnSource,
                               String subjectOu,
                               String subjectO,
                               String subjectC,
                               String organization,
                               int validityDays,
                               String keyAlgorithm,
                               boolean digitalSignature,
                               boolean keyEncipherment,
                               boolean clientAuth,
                               String providerType,
                               String signerType,
                               String issuerBinding) {
        this.templateId = templateId;
        this.certificateType = certificateType;
        this.subjectCnSource = subjectCnSource;
        this.subjectOu = subjectOu;
        this.subjectO = subjectO;
        this.subjectC = subjectC;
        this.organization = organization;
        this.validityDays = validityDays;
        this.keyAlgorithm = keyAlgorithm;
        this.digitalSignature = digitalSignature;
        this.keyEncipherment = keyEncipherment;
        this.clientAuth = clientAuth;
        this.providerType = providerType;
        this.signerType = signerType;
        this.issuerBinding = issuerBinding;
    }

    public String getTemplateId() {
        return templateId;
    }

    public CertificateType getCertificateType() {
        return certificateType;
    }

    public SubjectCnSource getSubjectCnSource() {
        return subjectCnSource;
    }

    public String getSubjectOu() {
        return subjectOu;
    }

    public String getSubjectO() {
        return subjectO;
    }

    public String getSubjectC() {
        return subjectC;
    }

    public String getOrganization() {
        return organization;
    }

    public int getValidityDays() {
        return validityDays;
    }

    public String getKeyAlgorithm() {
        return keyAlgorithm;
    }

    public boolean isDigitalSignature() {
        return digitalSignature;
    }

    public boolean isKeyEncipherment() {
        return keyEncipherment;
    }

    public boolean isClientAuth() {
        return clientAuth;
    }

    public String getProviderType() {
        return providerType;
    }

    public String getSignerType() {
        return signerType;
    }

    public String getIssuerBinding() {
        return issuerBinding;
    }
}
