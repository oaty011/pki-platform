package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.dto.response.CurrentCertificateResponse;
import com.pki.platform.issuance.mapper.AppCoreActiveShardMapper;
import com.pki.platform.issuance.mapper.EcuCoreActiveShardMapper;
import com.pki.platform.issuance.model.CoreActiveRecord;
import org.springframework.stereotype.Service;

@Service
public class CertificateCurrentQueryService {

    private final AppCoreActiveShardMapper appCoreActiveShardMapper;
    private final EcuCoreActiveShardMapper ecuCoreActiveShardMapper;
    private final OrganizationResolver organizationResolver;
    private final PartitionService partitionService;

    public CertificateCurrentQueryService(AppCoreActiveShardMapper appCoreActiveShardMapper,
                                          EcuCoreActiveShardMapper ecuCoreActiveShardMapper,
                                          OrganizationResolver organizationResolver,
                                          PartitionService partitionService) {
        this.appCoreActiveShardMapper = appCoreActiveShardMapper;
        this.ecuCoreActiveShardMapper = ecuCoreActiveShardMapper;
        this.organizationResolver = organizationResolver;
        this.partitionService = partitionService;
    }

    public CurrentCertificateResponse getCurrentAppCertificate(String subjectId) {
        return toResponse(loadApp(subjectId));
    }

    public CurrentCertificateResponse getCurrentEcuCertificate(String subjectId) {
        return toResponse(loadEcu(subjectId));
    }

    private CoreActiveRecord loadApp(String subjectId) {
        int shardId = partitionService.calculateShard(subjectId, organizationResolver.getAppOrganization());
        String tableName = partitionService.resolveCoreActiveTable(shardId);
        CoreActiveRecord record = appCoreActiveShardMapper.selectCurrentBySubjectIdFromShard(tableName, subjectId);
        if (record == null) {
            throw new BizException(ErrorCode.REQUEST_NOT_FOUND, "current app certificate not found for subjectId=" + subjectId);
        }
        return record;
    }

    private CoreActiveRecord loadEcu(String subjectId) {
        int shardId = partitionService.calculateShard(subjectId, organizationResolver.getEcuOrganization());
        String tableName = partitionService.resolveCoreActiveTable(shardId);
        CoreActiveRecord record = ecuCoreActiveShardMapper.selectCurrentBySubjectIdFromShard(tableName, subjectId);
        if (record == null) {
            throw new BizException(ErrorCode.REQUEST_NOT_FOUND, "current ecu certificate not found for subjectId=" + subjectId);
        }
        return record;
    }

    private CurrentCertificateResponse toResponse(CoreActiveRecord record) {
        return new CurrentCertificateResponse(
            record.getSubjectId(),
            record.getCertSerial(),
            record.getIssuerId(),
            record.getCurrent(),
            record.getNotAfter(),
            record.getFirstActivatedAt()
        );
    }
}
