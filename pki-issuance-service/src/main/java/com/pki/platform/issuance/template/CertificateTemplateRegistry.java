package com.pki.platform.issuance.template;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.config.IssuanceTemplateProperties;
import java.util.LinkedHashMap;
import java.util.Map;

public class CertificateTemplateRegistry {

    private final Map<String, CertificateTemplate> templates;

    public CertificateTemplateRegistry(IssuanceTemplateProperties properties) {
        this.templates = buildTemplates(properties);
    }

    public CertificateTemplate getRequired(String templateId) {
        CertificateTemplate template = templates.get(templateId);
        if (template == null) {
            throw new BizException(ErrorCode.INVALID_TEMPLATE_ID, "unsupported templateId: " + templateId);
        }
        return template;
    }

    private Map<String, CertificateTemplate> buildTemplates(IssuanceTemplateProperties properties) {
        Map<String, CertificateTemplate> registry = new LinkedHashMap<>();
        for (IssuanceTemplateProperties.TemplateDefinition template : properties.getTemplates()) {
            CertificateTemplate previous = registry.put(
                template.getTemplateId(),
                new CertificateTemplate(
                    template.getTemplateId(),
                    template.getCertificateType(),
                    template.getSubjectCnSource(),
                    template.getSubjectOu(),
                    template.getSubjectO(),
                    template.getSubjectC(),
                    template.getOrganization(),
                    template.getValidityDays(),
                    template.getKeyAlgorithm(),
                    template.isDigitalSignature(),
                    template.isKeyEncipherment(),
                    template.isClientAuth(),
                    template.getProviderType(),
                    template.getSignerType(),
                    template.getIssuerBinding()
                )
            );
            if (previous != null) {
                throw new IllegalStateException("duplicate templateId in issuance-templates.yml: "
                    + template.getTemplateId());
            }
        }
        return Map.copyOf(registry);
    }
}
