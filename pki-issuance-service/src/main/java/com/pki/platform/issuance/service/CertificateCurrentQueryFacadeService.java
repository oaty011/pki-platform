package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.dto.request.AppCurrentQueryRequest;
import com.pki.platform.issuance.dto.request.EcuCurrentQueryRequest;
import com.pki.platform.issuance.dto.response.CertificateQueryItemResponse;
import com.pki.platform.issuance.dto.response.CurrentQueryResponse;
import com.pki.platform.issuance.mapper.AppCoreActiveShardMapper;
import com.pki.platform.issuance.mapper.CertificateIssueFactMapper;
import com.pki.platform.issuance.mapper.EcuCoreActiveShardMapper;
import com.pki.platform.issuance.model.CertificateIssueFact;
import com.pki.platform.issuance.model.CoreActiveRecord;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;

@Service
public class CertificateCurrentQueryFacadeService {

    private final OrganizationResolver organizationResolver;
    private final PartitionService partitionService;
    private final CertificateIssueFactMapper certificateIssueFactMapper;
    private final AppCoreActiveShardMapper appCoreActiveShardMapper;
    private final EcuCoreActiveShardMapper ecuCoreActiveShardMapper;

    public CertificateCurrentQueryFacadeService(OrganizationResolver organizationResolver,
                                                PartitionService partitionService,
                                                CertificateIssueFactMapper certificateIssueFactMapper,
                                                AppCoreActiveShardMapper appCoreActiveShardMapper,
                                                EcuCoreActiveShardMapper ecuCoreActiveShardMapper) {
        this.organizationResolver = organizationResolver;
        this.partitionService = partitionService;
        this.certificateIssueFactMapper = certificateIssueFactMapper;
        this.appCoreActiveShardMapper = appCoreActiveShardMapper;
        this.ecuCoreActiveShardMapper = ecuCoreActiveShardMapper;
    }

    public CurrentQueryResponse queryAppCurrent(AppCurrentQueryRequest request) {
        String appId = normalize(request == null ? null : request.getAppId());
        String installId = normalize(request == null ? null : request.getInstallId());
        String subjectId = appId != null ? appId : installId;
        if (subjectId == null) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "appId or installId is required");
        }

        String organization = organizationResolver.getAppOrganization();
        int shardId = partitionService.calculateShard(subjectId, organization);
        return buildResponse(subjectId, organization, shardId, normalize(request == null ? null : request.getCertSerial()), true);
    }

    public CurrentQueryResponse queryEcuCurrent(EcuCurrentQueryRequest request) {
        String subjectId = normalize(request == null ? null : request.getDeviceId());
        if (subjectId == null) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "deviceId is required");
        }

        String organization = organizationResolver.getEcuOrganization();
        int shardId = partitionService.calculateShard(subjectId, organization);
        return buildResponse(subjectId, organization, shardId, normalize(request == null ? null : request.getCertSerial()), false);
    }

    private CurrentQueryResponse buildResponse(String subjectId,
                                               String organization,
                                               int shardId,
                                               String certSerial,
                                               boolean appDomain) {
        CurrentQueryResponse response = new CurrentQueryResponse();
        response.setSubjectId(subjectId);
        response.setOrganization(organization);
        response.setShardId(shardId);
        String tableName = partitionService.resolveCoreActiveTable(shardId);

        if (certSerial == null) {
            response.setIssuedCount(certificateIssueFactMapper.countBySubjectIdAndOrganization(subjectId, organization));
            response.setLatestIssuedCertificate(toIssueFactItem(
                certificateIssueFactMapper.selectLatestBySubjectIdAndOrganization(subjectId, organization)
            ));
            response.setCurrentActiveCertificate(toCoreActiveItem(
                appDomain
                    ? appCoreActiveShardMapper.selectCurrentBySubjectIdFromShard(tableName, subjectId)
                    : ecuCoreActiveShardMapper.selectCurrentBySubjectIdFromShard(tableName, subjectId)
            ));
            return response;
        }

        List<CoreActiveRecord> coreActiveRecords = appDomain
            ? appCoreActiveShardMapper.selectByCertSerialFromShard(tableName, certSerial)
            : ecuCoreActiveShardMapper.selectByCertSerialFromShard(tableName, certSerial);
        if (coreActiveRecords != null && !coreActiveRecords.isEmpty()) {
            List<CertificateQueryItemResponse> matchedCoreActive = toCoreActiveItems(coreActiveRecords, subjectId);
            if (!matchedCoreActive.isEmpty()) {
                response.setMatchedCertificates(matchedCoreActive);
                return response;
            }
        }

        response.setMatchedCertificates(toIssueFactItems(
            certificateIssueFactMapper.selectBySubjectIdAndOrganizationAndCertSerial(subjectId, organization, certSerial)
        ));
        return response;
    }

    private CertificateQueryItemResponse toIssueFactItem(CertificateIssueFact record) {
        if (record == null) {
            return null;
        }
        CertificateQueryItemResponse item = new CertificateQueryItemResponse();
        item.setCertSerial(record.getCertSerial());
        item.setIssuerId(record.getIssuerId());
        item.setNotAfter(record.getNotAfter());
        item.setFirstActivatedAt(null);
        item.setIsCurrent(null);
        return item;
    }

    private CertificateQueryItemResponse toCoreActiveItem(CoreActiveRecord record) {
        if (record == null) {
            return null;
        }
        CertificateQueryItemResponse item = new CertificateQueryItemResponse();
        item.setCertSerial(record.getCertSerial());
        item.setIssuerId(record.getIssuerId());
        item.setNotAfter(record.getNotAfter());
        item.setFirstActivatedAt(record.getFirstActivatedAt());
        item.setIsCurrent(record.getCurrent());
        return item;
    }

    private List<CertificateQueryItemResponse> toIssueFactItems(List<CertificateIssueFact> records) {
        if (records == null || records.isEmpty()) {
            return Collections.emptyList();
        }
        return records.stream()
            .map(this::toIssueFactItem)
            .collect(Collectors.toList());
    }

    private List<CertificateQueryItemResponse> toCoreActiveItems(List<CoreActiveRecord> records, String subjectId) {
        if (records == null || records.isEmpty()) {
            return Collections.emptyList();
        }
        return records.stream()
            .filter(record -> subjectId.equals(record.getSubjectId()))
            .map(this::toCoreActiveItem)
            .collect(Collectors.toList());
    }

    private String normalize(String value) {
        return value == null || value.isBlank() ? null : value;
    }
}
