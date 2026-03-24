package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.dto.request.CertificateRefreshStatusRequest;
import com.pki.platform.issuance.dto.response.CertificateRefreshStatusResponse;
import com.pki.platform.issuance.mapper.AppCoreActiveShardMapper;
import com.pki.platform.issuance.mapper.EcuCoreActiveShardMapper;
import com.pki.platform.issuance.model.CoreActiveRecord;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CertificateRefreshStatusService {

    private final AppCoreActiveShardMapper appCoreActiveShardMapper;
    private final EcuCoreActiveShardMapper ecuCoreActiveShardMapper;
    private final PartitionService partitionService;
    private final OrganizationResolver organizationResolver;

    public CertificateRefreshStatusService(AppCoreActiveShardMapper appCoreActiveShardMapper,
                                           EcuCoreActiveShardMapper ecuCoreActiveShardMapper,
                                           PartitionService partitionService,
                                           OrganizationResolver organizationResolver) {
        this.appCoreActiveShardMapper = appCoreActiveShardMapper;
        this.ecuCoreActiveShardMapper = ecuCoreActiveShardMapper;
        this.partitionService = partitionService;
        this.organizationResolver = organizationResolver;
    }

    @Transactional
    public CertificateRefreshStatusResponse refresh(CertificateRefreshStatusRequest request) {
        validate(request);

        String subjectId = request.getSubjectId().trim();
        String organization = request.getOrganization().trim();
        String certSerial = request.getCertSerial().trim();
        String issuerId = request.getIssuerId().trim();

        int shardId = partitionService.calculateShard(subjectId, organization);
        String tableName = partitionService.resolveCoreActiveTable(shardId);

        CoreActiveRecord record = isAppOrganization(organization)
            ? appCoreActiveShardMapper.selectByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId)
            : ecuCoreActiveShardMapper.selectByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId);

        if (record == null) {
            throw new BizException(
                ErrorCode.REQUEST_NOT_FOUND,
                "certificate is not in core_active, refresh-status is not allowed"
            );
        }
        if (!subjectId.equals(record.getSubjectId())) {
            throw new BizException(ErrorCode.BUSINESS_ERROR, "subject does not match certificate owner");
        }

        int updated = isAppOrganization(organization)
            ? appCoreActiveShardMapper.refreshUpdatedAtByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId)
            : ecuCoreActiveShardMapper.refreshUpdatedAtByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId);

        if (updated != 1) {
            throw new BizException(ErrorCode.BUSINESS_ERROR, "failed to refresh certificate status");
        }

        return new CertificateRefreshStatusResponse(certSerial, issuerId, subjectId, organization, true);
    }

    private void validate(CertificateRefreshStatusRequest request) {
        if (request == null
            || isBlank(request.getSubjectId())
            || isBlank(request.getOrganization())
            || isBlank(request.getCertSerial())
            || isBlank(request.getIssuerId())) {
            throw new BizException(
                ErrorCode.INVALID_REQUEST_PARAM,
                "subjectId, organization, certSerial and issuerId are required"
            );
        }
        String organization = request.getOrganization().trim();
        if (!isAppOrganization(organization) && !isEcuOrganization(organization)) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "unsupported organization: " + organization);
        }
    }

    private boolean isAppOrganization(String organization) {
        return organizationResolver.getAppOrganization().equals(organization);
    }

    private boolean isEcuOrganization(String organization) {
        return organizationResolver.getEcuOrganization().equals(organization);
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
