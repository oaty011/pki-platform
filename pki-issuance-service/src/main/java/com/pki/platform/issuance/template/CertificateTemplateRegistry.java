package com.pki.platform.issuance.template;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import java.util.Map;
import org.springframework.stereotype.Component;

@Component
public class CertificateTemplateRegistry {

    private final Map<String, CertificateTemplate> templates = Map.ofEntries(
        Map.entry("ecu-tbox", ecuTemplate("ecu-tbox", "TBOX")),
        Map.entry("ecu-ivi", ecuTemplate("ecu-ivi", "IVI")),
        Map.entry("ecu-had", ecuTemplate("ecu-had", "HAD")),
        Map.entry("ecu-sgw", ecuTemplate("ecu-sgw", "SGW")),
        Map.entry("ecu-obu", ecuTemplate("ecu-obu", "OBU")),
        Map.entry("app-controller-sdk", appTemplate("app-controller-sdk")),
        // Compatibility aliases for existing callers and scripts.
        Map.entry("app-template-demo", appTemplate("app-template-demo")),
        Map.entry("ecu-template-demo", ecuTemplate("ecu-template-demo", "DEMO"))
    );

    public CertificateTemplate getRequired(String templateId) {
        CertificateTemplate template = templates.get(templateId);
        if (template == null) {
            throw new BizException(ErrorCode.INVALID_TEMPLATE_ID, "unsupported templateId: " + templateId);
        }
        return template;
    }

    private static CertificateTemplate ecuTemplate(String templateId, String subjectOu) {
        return new CertificateTemplate(
            templateId,
            CertificateType.ECU,
            SubjectCnSource.DEVICE_ID,
            subjectOu,
            "DFMC ECU",
            "CN",
            "DFMC_ECU",
            90,
            "RSA",
            true,
            true,
            true,
            "local-x509",
            "soft",
            "default-local-issuer"
        );
    }

    private static CertificateTemplate appTemplate(String templateId) {
        return new CertificateTemplate(
            templateId,
            CertificateType.APP,
            SubjectCnSource.APP_ID_OR_INSTALL_ID,
            "Vehicle Controller SDK",
            "DFMC",
            "CN",
            "DFMC",
            90,
            "RSA",
            true,
            true,
            true,
            "local-x509",
            "soft",
            "default-local-issuer"
        );
    }
}
