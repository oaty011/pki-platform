package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import org.springframework.stereotype.Service;

@Service
public class DomainRoutingService {

    public DomainTarget resolveByTemplateId(String templateId) {
        if (templateId != null && templateId.startsWith("app-")) {
            return DomainTarget.APP;
        }
        if (templateId != null && templateId.startsWith("ecu-")) {
            return DomainTarget.ECU;
        }
        throw new BizException(ErrorCode.INVALID_TEMPLATE_ID, "unsupported templateId: " + templateId);
    }

    public enum DomainTarget {
        APP,
        ECU
    }
}
