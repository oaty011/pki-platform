package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import org.springframework.stereotype.Service;

@Service
public class OrganizationResolver {

    public String resolveByTemplateId(String templateId) {
        if (templateId != null && templateId.startsWith("app-")) {
            return getAppOrganization();
        }
        if (templateId != null && templateId.startsWith("ecu-")) {
            return getEcuOrganization();
        }
        throw new BizException(ErrorCode.INVALID_TEMPLATE_ID, "unsupported templateId: " + templateId);
    }

    public String getAppOrganization() {
        return "DFMC";
    }

    public String getEcuOrganization() {
        return "DFMC_ECU";
    }
}
