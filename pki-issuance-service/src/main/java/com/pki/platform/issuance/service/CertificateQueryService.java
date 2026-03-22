package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.dto.response.CertificateContentResponse;
import com.pki.platform.issuance.dto.response.CertificateStatusResponse;
import com.pki.platform.issuance.mapper.CertificateIssueFactMapper;
import com.pki.platform.issuance.model.CertificateIssueFact;
import org.springframework.stereotype.Service;

@Service
public class CertificateQueryService {

    private final CertificateIssueFactMapper certificateIssueFactMapper;

    public CertificateQueryService(CertificateIssueFactMapper certificateIssueFactMapper) {
        this.certificateIssueFactMapper = certificateIssueFactMapper;
    }

    public CertificateStatusResponse getStatus(String requestId) {
        CertificateIssueFact record = getRequired(requestId);
        return new CertificateStatusResponse(
            record.getRequestId(),
            record.getStatus(),
            record.getCertSerial(),
            record.getIssuerId(),
            record.getSyncStatus()
        );
    }

    public CertificateContentResponse getCertificate(String requestId) {
        CertificateIssueFact record = getRequired(requestId);
        return new CertificateContentResponse(
            record.getRequestId(),
            record.getCertSerial(),
            record.getIssuerId(),
            record.getCertificatePem(),
            null
        );
    }

    private CertificateIssueFact getRequired(String requestId) {
        CertificateIssueFact record = certificateIssueFactMapper.selectByRequestId(requestId);
        if (record == null) {
            throw new BizException(ErrorCode.REQUEST_NOT_FOUND, "requestId not found: " + requestId);
        }
        return record;
    }
}
