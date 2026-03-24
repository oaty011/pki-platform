package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.dto.request.AppCertificateApplyRequest;
import com.pki.platform.issuance.dto.request.EcuCertificateApplyRequest;
import com.pki.platform.issuance.dto.response.AppCertificateApplyResponse;
import com.pki.platform.issuance.dto.response.EcuCertificateApplyResponse;
import com.pki.platform.issuance.enums.CertificateIssueStatus;
import com.pki.platform.issuance.enums.IssueSyncStatus;
import com.pki.platform.issuance.mapper.CertificateIssueFactMapper;
import com.pki.platform.issuance.model.CertificateIssueFact;
import com.pki.platform.issuance.service.issuance.CertificateIssuanceCommand;
import com.pki.platform.issuance.service.issuance.CertificateIssuanceProvider;
import com.pki.platform.issuance.service.issuance.CertificateIssuanceResult;
import com.pki.platform.issuance.template.CertificateTemplate;
import com.pki.platform.issuance.template.CertificateTemplateRegistry;
import com.pki.platform.issuance.template.CertificateType;
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
    private final CertificateIssuanceProvider certificateIssuanceProvider;
    private final CertificateTemplateRegistry certificateTemplateRegistry;
    private final InstallIdGenerator installIdGenerator;

    public CertificateApplicationService(CertificateIssueFactMapper certificateIssueFactMapper,
                                         CertificateIssuanceProvider certificateIssuanceProvider,
                                         CertificateTemplateRegistry certificateTemplateRegistry,
                                         InstallIdGenerator installIdGenerator) {
        this.certificateIssueFactMapper = certificateIssueFactMapper;
        this.certificateIssuanceProvider = certificateIssuanceProvider;
        this.certificateTemplateRegistry = certificateTemplateRegistry;
        this.installIdGenerator = installIdGenerator;
    }

    @Transactional
    public AppCertificateApplyResponse applyAppCertificate(AppCertificateApplyRequest request) {
        validateBase(request == null ? null : request.getRequestId(), request == null ? null : request.getTemplateId());
        CertificateTemplate template = certificateTemplateRegistry.getRequired(request.getTemplateId());
        ensureTemplateType(template, CertificateType.APP);

        String appId = normalize(request.getAppId());
        String installId = appId == null ? installIdGenerator.generate() : null;
        String subjectId = appId != null ? appId : installId;
        CertificateIssueFact issueFact = issue(request.getRequestId(), template, subjectId, request.getCsr());
        return new AppCertificateApplyResponse(issueFact.getRequestId(), issueFact.getStatus(), appId, installId);
    }

    @Transactional
    public EcuCertificateApplyResponse applyEcuCertificate(EcuCertificateApplyRequest request) {
        validateBase(request == null ? null : request.getRequestId(), request == null ? null : request.getTemplateId());
        if (request == null || isBlank(request.getDeviceId())) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "deviceId is required");
        }
        CertificateTemplate template = certificateTemplateRegistry.getRequired(request.getTemplateId());
        ensureTemplateType(template, CertificateType.ECU);

        CertificateIssueFact issueFact = issue(request.getRequestId(), template, request.getDeviceId(), request.getCsr());
        return new EcuCertificateApplyResponse(issueFact.getRequestId(), issueFact.getStatus(), request.getDeviceId());
    }

    private CertificateIssueFact issue(String requestId, CertificateTemplate template, String subjectId, String csrPem) {
        CertificateIssueFact existing = certificateIssueFactMapper.selectByRequestId(requestId);
        if (existing != null) {
            log.info("apply idempotent hit existing requestId={}", requestId);
            return existing;
        }

        CertificateIssuanceCommand command = buildCommand(requestId, template, subjectId, csrPem);
        CertificateIssuanceResult signResult = certificateIssuanceProvider.issue(command);
        OffsetDateTime now = OffsetDateTime.now();

        CertificateIssueFact record = new CertificateIssueFact();
        record.setRequestId(requestId);
        record.setTemplateId(template.getTemplateId());
        record.setSubjectId(subjectId);
        record.setOrganization(template.getOrganization());
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

    private CertificateIssuanceCommand buildCommand(String requestId,
                                                    CertificateTemplate template,
                                                    String subjectId,
                                                    String csrPem) {
        CertificateIssuanceCommand command = new CertificateIssuanceCommand();
        command.setRequestId(requestId);
        command.setTemplateId(template.getTemplateId());
        command.setSubjectId(subjectId);
        command.setCertificateType(template.getCertificateType());
        command.setSubjectCnSource(template.getSubjectCnSource());
        command.setOrganization(template.getOrganization());
        command.setSubjectOu(template.getSubjectOu());
        command.setSubjectO(template.getSubjectO());
        command.setSubjectC(template.getSubjectC());
        command.setSubjectDn(buildSubjectDn(template, subjectId));
        command.setCsrPem(normalize(csrPem));
        command.setValidityDays(template.getValidityDays());
        command.setKeyAlgorithm(template.getKeyAlgorithm());
        command.setDigitalSignature(template.isDigitalSignature());
        command.setKeyEncipherment(template.isKeyEncipherment());
        command.setClientAuth(template.isClientAuth());
        command.setProviderType(template.getProviderType());
        command.setSignerType(template.getSignerType());
        command.setIssuerBinding(template.getIssuerBinding());
        command.setNotBefore(OffsetDateTime.now());
        command.setNotAfter(OffsetDateTime.now().plusDays(template.getValidityDays()));
        return command;
    }

    private String buildSubjectDn(CertificateTemplate template, String subjectId) {
        return "CN=" + subjectId
            + ",OU=" + template.getSubjectOu()
            + ",O=" + template.getSubjectO()
            + ",C=" + template.getSubjectC();
    }

    private void ensureTemplateType(CertificateTemplate template, CertificateType expectedType) {
        if (template.getCertificateType() != expectedType) {
            throw new BizException(
                ErrorCode.INVALID_TEMPLATE_ID,
                "templateId does not match certificate type: " + template.getTemplateId()
            );
        }
    }

    private String buildSubjectDn(String templateId, String subjectId) {
        if (templateId != null && templateId.startsWith("app-")) {
            return "CN=" + subjectId + ",OU=Vehicle Controller SDK,O=DFMC,C=CN";
        }
        if (templateId != null && templateId.startsWith("ecu-")) {
            return "CN=" + subjectId + ",OU=" + templateId + ",O=DFMC ECU,C=CN";
        }
        return "CN=" + subjectId + ",O=DFMC,C=CN";
    }

    private void validateBase(String requestId, String templateId) {
        if (isBlank(requestId) || isBlank(templateId)) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "requestId and templateId are required");
        }
    }

    private String normalize(String value) {
        return isBlank(value) ? null : value;
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
