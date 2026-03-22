package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.dto.request.AppCertificateApplyRequest;
import com.pki.platform.issuance.dto.request.EcuCertificateApplyRequest;
import com.pki.platform.issuance.dto.response.AppCertificateApplyResponse;
import com.pki.platform.issuance.dto.response.EcuCertificateApplyResponse;
import com.pki.platform.issuance.dto.response.MockSignResult;
import com.pki.platform.issuance.enums.CertificateIssueStatus;
import com.pki.platform.issuance.enums.IssueSyncStatus;
import com.pki.platform.issuance.mapper.CertificateIssueFactMapper;
import com.pki.platform.issuance.model.CertificateIssueFact;
import java.time.OffsetDateTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CertificateApplicationService {

    private static final Logger log = LoggerFactory.getLogger(CertificateApplicationService.class);

    private final CertificateIssueFactMapper certificateIssueFactMapper;
    private final MockSignerService mockSignerService;
    private final InstallIdGenerator installIdGenerator;
    private final OrganizationResolver organizationResolver;

    public CertificateApplicationService(CertificateIssueFactMapper certificateIssueFactMapper,
                                         MockSignerService mockSignerService,
                                         InstallIdGenerator installIdGenerator,
                                         OrganizationResolver organizationResolver) {
        this.certificateIssueFactMapper = certificateIssueFactMapper;
        this.mockSignerService = mockSignerService;
        this.installIdGenerator = installIdGenerator;
        this.organizationResolver = organizationResolver;
    }

    @Transactional
    public AppCertificateApplyResponse applyAppCertificate(AppCertificateApplyRequest request) {
        validateBase(request == null ? null : request.getRequestId(), request == null ? null : request.getTemplateId());
        ensureTemplatePrefix(request.getTemplateId(), "app-");

        String appId = normalize(request.getAppId());
        String installId = appId == null ? installIdGenerator.generate() : null;
        String subjectId = appId != null ? appId : installId;
        CertificateIssueFact issueFact = issue(request.getRequestId(), request.getTemplateId(), subjectId);
        return new AppCertificateApplyResponse(issueFact.getRequestId(), issueFact.getStatus(), appId, installId);
    }

    @Transactional
    public EcuCertificateApplyResponse applyEcuCertificate(EcuCertificateApplyRequest request) {
        validateBase(request == null ? null : request.getRequestId(), request == null ? null : request.getTemplateId());
        if (request == null || isBlank(request.getDeviceId())) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "deviceId is required");
        }
        ensureTemplatePrefix(request.getTemplateId(), "ecu-");

        CertificateIssueFact issueFact = issue(request.getRequestId(), request.getTemplateId(), request.getDeviceId());
        return new EcuCertificateApplyResponse(issueFact.getRequestId(), issueFact.getStatus(), request.getDeviceId());
    }

    private CertificateIssueFact issue(String requestId, String templateId, String subjectId) {
        CertificateIssueFact existing = certificateIssueFactMapper.selectByRequestId(requestId);
        if (existing != null) {
            log.info("apply idempotent hit existing requestId={}", requestId);
            return existing;
        }

        MockSignResult signResult = mockSignerService.sign(subjectId, templateId);
        OffsetDateTime now = OffsetDateTime.now();
        String organization = organizationResolver.resolveByTemplateId(templateId);

        CertificateIssueFact record = new CertificateIssueFact();
        record.setRequestId(requestId);
        record.setTemplateId(templateId);
        record.setSubjectId(subjectId);
        record.setOrganization(organization);
        record.setIssuerId(signResult.getIssuerId());
        record.setSignerId(signResult.getSignerId());
        record.setCertSerial(signResult.getCertSerial());
        record.setCertificatePem(signResult.getCertificatePem());
        record.setNotAfter(signResult.getNotAfter());
        record.setStatus(CertificateIssueStatus.ISSUED.getValue());
        record.setSyncStatus(IssueSyncStatus.PENDING.getValue());
        record.setCreatedAt(now);
        record.setUpdatedAt(now);
        try {
            certificateIssueFactMapper.insert(record);
            log.info("apply new record created requestId={}", requestId);
            return record;
        } catch (DataIntegrityViolationException ex) {
            CertificateIssueFact conflictRecord = certificateIssueFactMapper.selectByRequestId(requestId);
            if (conflictRecord != null) {
                log.info("apply idempotent hit after unique conflict requestId={}", requestId);
                return conflictRecord;
            }
            throw new BizException(ErrorCode.BUSINESS_ERROR,
                "failed to persist certificate request after unique conflict, requestId=" + requestId);
        }
    }

    private void validateBase(String requestId, String templateId) {
        if (isBlank(requestId) || isBlank(templateId)) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "requestId and templateId are required");
        }
    }

    private void ensureTemplatePrefix(String templateId, String prefix) {
        if (templateId == null || !templateId.startsWith(prefix)) {
            throw new BizException(ErrorCode.INVALID_TEMPLATE_ID, "templateId must start with " + prefix);
        }
    }

    private String normalize(String value) {
        return isBlank(value) ? null : value;
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
