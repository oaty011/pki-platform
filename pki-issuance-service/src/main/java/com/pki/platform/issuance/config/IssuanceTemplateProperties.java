package com.pki.platform.issuance.config;

import com.pki.platform.issuance.template.CertificateType;
import com.pki.platform.issuance.template.SubjectCnSource;
import java.util.ArrayList;
import java.util.List;

public class IssuanceTemplateProperties {

    private List<TemplateDefinition> templates = new ArrayList<>();

    public List<TemplateDefinition> getTemplates() {
        return templates;
    }

    public void setTemplates(List<TemplateDefinition> templates) {
        this.templates = templates;
    }

    public void validate() {
        if (templates == null || templates.isEmpty()) {
            throw new IllegalStateException("issuance-templates.yml must define at least one template");
        }
        for (TemplateDefinition template : templates) {
            validateTemplate(template);
        }
    }

    private void validateTemplate(TemplateDefinition template) {
        requireNotBlank(template.getTemplateId(), "templateId", "<unknown>");
        requireNonNull(template.getCertificateType(), "certificateType", template.getTemplateId());
        requireNonNull(template.getSubjectCnSource(), "subjectCnSource", template.getTemplateId());
        requireNotBlank(template.getSubjectOu(), "subjectOu", template.getTemplateId());
        requireNotBlank(template.getSubjectO(), "subjectO", template.getTemplateId());
        requireNotBlank(template.getSubjectC(), "subjectC", template.getTemplateId());
        requireNotBlank(template.getOrganization(), "organization", template.getTemplateId());
        if (template.getValidityDays() <= 0) {
            throw new IllegalStateException("issuance template [" + template.getTemplateId()
                + "] validityDays must be greater than 0");
        }
        requireNotBlank(template.getKeyAlgorithm(), "keyAlgorithm", template.getTemplateId());
        requireNotBlank(template.getProviderType(), "providerType", template.getTemplateId());
        requireNotBlank(template.getSignerType(), "signerType", template.getTemplateId());
        requireNotBlank(template.getIssuerBinding(), "issuerBinding", template.getTemplateId());
    }

    private void requireNonNull(Object value, String field, String templateId) {
        if (value == null) {
            throw new IllegalStateException("issuance template [" + templateId + "] missing required field: " + field);
        }
    }

    private void requireNotBlank(String value, String field, String templateId) {
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("issuance template [" + templateId + "] missing required field: " + field);
        }
    }

    public static class TemplateDefinition {

        private String templateId;
        private CertificateType certificateType;
        private SubjectCnSource subjectCnSource;
        private String subjectOu;
        private String subjectO;
        private String subjectC;
        private String organization;
        private int validityDays;
        private String keyAlgorithm;
        private boolean digitalSignature;
        private boolean keyEncipherment;
        private boolean clientAuth;
        private String providerType;
        private String signerType;
        private String issuerBinding;

        public String getTemplateId() {
            return templateId;
        }

        public void setTemplateId(String templateId) {
            this.templateId = templateId;
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

        public String getOrganization() {
            return organization;
        }

        public void setOrganization(String organization) {
            this.organization = organization;
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
    }
}
