package com.pki.platform.revocation.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.revocation.dto.request.AppRecoverRequest;
import com.pki.platform.revocation.dto.request.AppRevokeRequest;
import com.pki.platform.revocation.dto.request.EcuRecoverRequest;
import com.pki.platform.revocation.dto.request.EcuRevokeRequest;
import com.pki.platform.revocation.mapper.AppCoreActiveShardMapper;
import com.pki.platform.revocation.mapper.CertificateIssueFactMapper;
import com.pki.platform.revocation.mapper.EcuCoreActiveShardMapper;
import com.pki.platform.revocation.mapper.RevocationCurrentMapper;
import com.pki.platform.revocation.mapper.RevocationOutboxMapper;
import com.pki.platform.revocation.model.CertificateIssueFact;
import com.pki.platform.revocation.model.CoreActiveRecord;
import com.pki.platform.revocation.model.RevocationCurrent;
import com.pki.platform.revocation.model.RevocationOutbox;
import java.time.OffsetDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RevocationCommandService {

    private static final String APP_ORGANIZATION = "DFMC";
    private static final String ECU_ORGANIZATION = "DFMC_ECU";
    private static final String DEFAULT_REASON = "MANUAL";
    private static final String EVENT_REVOKE = "REVOKE";
    private static final String EVENT_RECOVER = "RECOVER";
    private static final String OUTBOX_STATUS_NEW = "NEW";

    private final AppCoreActiveShardMapper appCoreActiveShardMapper;
    private final EcuCoreActiveShardMapper ecuCoreActiveShardMapper;
    private final CertificateIssueFactMapper certificateIssueFactMapper;
    private final RevocationCurrentMapper revocationCurrentMapper;
    private final RevocationOutboxMapper revocationOutboxMapper;
    private final PartitionService partitionService;

    public RevocationCommandService(AppCoreActiveShardMapper appCoreActiveShardMapper,
                                    EcuCoreActiveShardMapper ecuCoreActiveShardMapper,
                                    CertificateIssueFactMapper certificateIssueFactMapper,
                                    RevocationCurrentMapper revocationCurrentMapper,
                                    RevocationOutboxMapper revocationOutboxMapper,
                                    PartitionService partitionService) {
        this.appCoreActiveShardMapper = appCoreActiveShardMapper;
        this.ecuCoreActiveShardMapper = ecuCoreActiveShardMapper;
        this.certificateIssueFactMapper = certificateIssueFactMapper;
        this.revocationCurrentMapper = revocationCurrentMapper;
        this.revocationOutboxMapper = revocationOutboxMapper;
        this.partitionService = partitionService;
    }

    @Transactional
    public CommandResult revokeApp(AppRevokeRequest request) {
        String appId = normalize(request == null ? null : request.getAppId());
        String installId = normalize(request == null ? null : request.getInstallId());
        String subjectId = appId != null ? appId : installId;
        if (subjectId == null) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "appId or installId is required");
        }
        String certSerial = normalize(request == null ? null : request.getCertSerial());
        String issuerId = normalize(request == null ? null : request.getIssuerId());
        validateKey(certSerial, issuerId);
        return revokeBySubject(true, subjectId, APP_ORGANIZATION, certSerial, issuerId);
    }

    @Transactional
    public CommandResult revokeEcu(EcuRevokeRequest request) {
        String subjectId = normalize(request == null ? null : request.getDeviceId());
        if (subjectId == null) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "deviceId is required");
        }
        String certSerial = normalize(request == null ? null : request.getCertSerial());
        String issuerId = normalize(request == null ? null : request.getIssuerId());
        validateKey(certSerial, issuerId);
        return revokeBySubject(false, subjectId, ECU_ORGANIZATION, certSerial, issuerId);
    }

    @Transactional
    public CommandResult recoverApp(AppRecoverRequest request) {
        String appId = normalize(request == null ? null : request.getAppId());
        String installId = normalize(request == null ? null : request.getInstallId());
        String subjectId = appId != null ? appId : installId;
        if (subjectId == null) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "appId or installId is required");
        }
        String certSerial = normalize(request == null ? null : request.getCertSerial());
        String issuerId = normalize(request == null ? null : request.getIssuerId());
        validateKey(certSerial, issuerId);
        return recoverBySubject(true, subjectId, APP_ORGANIZATION, certSerial, issuerId);
    }

    @Transactional
    public CommandResult recoverEcu(EcuRecoverRequest request) {
        String subjectId = normalize(request == null ? null : request.getDeviceId());
        if (subjectId == null) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "deviceId is required");
        }
        String certSerial = normalize(request == null ? null : request.getCertSerial());
        String issuerId = normalize(request == null ? null : request.getIssuerId());
        validateKey(certSerial, issuerId);
        return recoverBySubject(false, subjectId, ECU_ORGANIZATION, certSerial, issuerId);
    }

    private CommandResult revokeBySubject(boolean appDomain,
                                          String subjectId,
                                          String organization,
                                          String certSerial,
                                          String issuerId) {
        CertificateIssueFact issueFact = certificateIssueFactMapper.selectByCertSerialAndIssuerId(certSerial, issuerId);
        if (issueFact != null) {
            validateSubjectOwnership(subjectId, issueFact.getSubjectId());
        }

        int shardId = partitionService.calculateShard(subjectId, organization);
        String tableName = partitionService.resolveCoreActiveTable(shardId);
        CoreActiveRecord activeRecord = appDomain
            ? appCoreActiveShardMapper.selectByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId)
            : ecuCoreActiveShardMapper.selectByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId);
        if (activeRecord == null) {
            throw new BizException(
                ErrorCode.REQUEST_NOT_FOUND,
                "certificate is not in core_active, revoke is not allowed"
            );
        }
        validateSubjectOwnership(subjectId, activeRecord.getSubjectId());

        int deleted = appDomain
            ? appCoreActiveShardMapper.deleteByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId)
            : ecuCoreActiveShardMapper.deleteByCertSerialAndIssuerIdFromShard(tableName, certSerial, issuerId);
        if (deleted == 0) {
            throw new BizException(
                ErrorCode.BUSINESS_ERROR,
                "failed to delete certificate from core_active: certSerial=" + certSerial + ", issuerId=" + issuerId
            );
        }

        OffsetDateTime now = OffsetDateTime.now();
        RevocationCurrent current = new RevocationCurrent();
        current.setCertSerial(certSerial);
        current.setIssuerId(issuerId);
        current.setRevokedAt(now);
        current.setReason(DEFAULT_REASON);
        current.setFirstActivatedAt(activeRecord.getFirstActivatedAt());
        current.setUpdatedAt(now);
        revocationCurrentMapper.insert(current);

        insertOutbox(certSerial, issuerId, EVENT_REVOKE, now);
        return new CommandResult(certSerial, issuerId, "revoked");
    }

    private CommandResult recoverBySubject(boolean appDomain,
                                           String subjectId,
                                           String organization,
                                           String certSerial,
                                           String issuerId) {
        RevocationCurrent revocationCurrent = revocationCurrentMapper.selectByCertSerialAndIssuerId(certSerial, issuerId);
        if (revocationCurrent == null) {
            throw new BizException(
                ErrorCode.REQUEST_NOT_FOUND,
                "certificate is not in revocation_current, recover is not allowed"
            );
        }

        CertificateIssueFact issueFact = certificateIssueFactMapper.selectByCertSerialAndIssuerId(certSerial, issuerId);
        if (issueFact == null) {
            throw new BizException(
                ErrorCode.REQUEST_NOT_FOUND,
                "issue_fact not found, recover is not allowed"
            );
        }
        validateSubjectOwnership(subjectId, issueFact.getSubjectId());
        validateRecoverOrganization(organization, issueFact.getOrganization());

        int shardId = partitionService.calculateShard(subjectId, organization);
        String tableName = partitionService.resolveCoreActiveTable(shardId);
        OffsetDateTime now = OffsetDateTime.now();

        CoreActiveRecord restoredRecord = new CoreActiveRecord();
        restoredRecord.setCertSerial(certSerial);
        restoredRecord.setIssuerId(issuerId);
        restoredRecord.setSubjectId(subjectId);
        restoredRecord.setCurrent(Boolean.FALSE);
        restoredRecord.setNotAfter(issueFact.getNotAfter());
        restoredRecord.setFirstActivatedAt(revocationCurrent.getFirstActivatedAt());
        restoredRecord.setCreatedAt(now);
        restoredRecord.setUpdatedAt(now);

        if (appDomain) {
            appCoreActiveShardMapper.upsertToShard(tableName, restoredRecord);
        } else {
            ecuCoreActiveShardMapper.upsertToShard(tableName, restoredRecord);
        }

        revocationCurrentMapper.deleteByCertSerialAndIssuerId(certSerial, issuerId);
        insertOutbox(certSerial, issuerId, EVENT_RECOVER, now);
        return new CommandResult(certSerial, issuerId, "recovered");
    }

    private void insertOutbox(String certSerial, String issuerId, String eventType, OffsetDateTime now) {
        Long maxVersion = revocationOutboxMapper.selectMaxVersionByCertSerialAndIssuerId(certSerial, issuerId);

        RevocationOutbox outbox = new RevocationOutbox();
        outbox.setCertSerial(certSerial);
        outbox.setIssuerId(issuerId);
        outbox.setEventType(eventType);
        outbox.setStatus(OUTBOX_STATUS_NEW);
        outbox.setVersion(maxVersion == null ? 1L : maxVersion + 1L);
        outbox.setRetryCount(0);
        outbox.setCreatedAt(now);
        outbox.setUpdatedAt(now);
        revocationOutboxMapper.insert(outbox);
    }

    /**
     * Prepares route information from issue_fact as optional route metadata.
     * The active subject-route revoke/recover flow resolves domain and shard from
     * subjectId plus organization, while issue_fact only supplements attributes.
     */
    private IssueFactRouteInfo loadIssueFactRouteInfo(String certSerial, String issuerId) {
        CertificateIssueFact issueFact = certificateIssueFactMapper.selectByCertSerialAndIssuerId(certSerial, issuerId);
        if (issueFact == null) {
            return null;
        }

        Domain domain = resolveDomainByOrganization(issueFact.getOrganization());
        Integer shardId = resolveShardByIssueFact(issueFact);
        return new IssueFactRouteInfo(
            issueFact.getSubjectId(),
            issueFact.getOrganization(),
            issueFact.getNotAfter(),
            domain,
            shardId
        );
    }

    private Domain resolveDomainByOrganization(String organization) {
        if (APP_ORGANIZATION.equals(organization)) {
            return Domain.APP;
        }
        if (ECU_ORGANIZATION.equals(organization)) {
            return Domain.ECU;
        }
        throw new BizException(ErrorCode.BUSINESS_ERROR, "unsupported organization for route resolution: " + organization);
    }

    private Integer resolveShardByIssueFact(CertificateIssueFact issueFact) {
        if (issueFact == null || isBlank(issueFact.getSubjectId()) || isBlank(issueFact.getOrganization())) {
            return null;
        }
        return partitionService.calculateShard(issueFact.getSubjectId(), issueFact.getOrganization());
    }

    private void validateKey(String certSerial, String issuerId) {
        if (isBlank(certSerial) || isBlank(issuerId)) {
            throw new BizException(ErrorCode.INVALID_REQUEST_PARAM, "certSerial and issuerId are required");
        }
    }

    private void validateSubjectOwnership(String requestedSubjectId, String actualSubjectId) {
        if (isBlank(requestedSubjectId) || isBlank(actualSubjectId)
            || !requestedSubjectId.equals(actualSubjectId)) {
            throw new BizException(ErrorCode.BUSINESS_ERROR, "subject does not match certificate owner");
        }
    }

    private void validateRecoverOrganization(String requestedOrganization, String actualOrganization) {
        if (isBlank(requestedOrganization) || isBlank(actualOrganization)
            || !requestedOrganization.equals(actualOrganization)) {
            throw new BizException(
                ErrorCode.BUSINESS_ERROR,
                "recover domain does not match certificate organization"
            );
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private String normalize(String value) {
        return isBlank(value) ? null : value;
    }

    private enum Domain {
        APP,
        ECU
    }

    private static class IssueFactRouteInfo {

        private final String subjectId;
        private final String organization;
        private final OffsetDateTime notAfter;
        private final Domain domain;
        private final Integer shardId;

        private IssueFactRouteInfo(String subjectId,
                                   String organization,
                                   OffsetDateTime notAfter,
                                   Domain domain,
                                   Integer shardId) {
            this.subjectId = subjectId;
            this.organization = organization;
            this.notAfter = notAfter;
            this.domain = domain;
            this.shardId = shardId;
        }

        public String getSubjectId() {
            return subjectId;
        }

        public String getOrganization() {
            return organization;
        }

        public OffsetDateTime getNotAfter() {
            return notAfter;
        }

        public Domain getDomain() {
            return domain;
        }

        public Integer getShardId() {
            return shardId;
        }
    }

    public static class CommandResult {

        private final String certSerial;
        private final String issuerId;
        private final String action;

        public CommandResult(String certSerial, String issuerId, String action) {
            this.certSerial = certSerial;
            this.issuerId = issuerId;
            this.action = action;
        }

        public String getCertSerial() {
            return certSerial;
        }

        public String getIssuerId() {
            return issuerId;
        }

        public String getAction() {
            return action;
        }
    }
}
