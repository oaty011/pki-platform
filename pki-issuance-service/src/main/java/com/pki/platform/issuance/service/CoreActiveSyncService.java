package com.pki.platform.issuance.service;

import com.pki.platform.common.enums.ErrorCode;
import com.pki.platform.common.exception.BizException;
import com.pki.platform.issuance.enums.CertificateIssueStatus;
import com.pki.platform.issuance.enums.IssueSyncStatus;
import com.pki.platform.issuance.mapper.AppCoreActiveShardMapper;
import com.pki.platform.issuance.mapper.CertificateIssueFactMapper;
import com.pki.platform.issuance.mapper.EcuCoreActiveShardMapper;
import com.pki.platform.issuance.model.CertificateIssueFact;
import com.pki.platform.issuance.model.CoreActiveRecord;
import java.time.OffsetDateTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CoreActiveSyncService {

    private static final Logger log = LoggerFactory.getLogger(CoreActiveSyncService.class);

    private final CertificateIssueFactMapper certificateIssueFactMapper;
    private final AppCoreActiveShardMapper appCoreActiveShardMapper;
    private final EcuCoreActiveShardMapper ecuCoreActiveShardMapper;
    private final DomainRoutingService domainRoutingService;
    private final PartitionService partitionService;

    public CoreActiveSyncService(CertificateIssueFactMapper certificateIssueFactMapper,
                                 AppCoreActiveShardMapper appCoreActiveShardMapper,
                                 EcuCoreActiveShardMapper ecuCoreActiveShardMapper,
                                 DomainRoutingService domainRoutingService,
                                 PartitionService partitionService) {
        this.certificateIssueFactMapper = certificateIssueFactMapper;
        this.appCoreActiveShardMapper = appCoreActiveShardMapper;
        this.ecuCoreActiveShardMapper = ecuCoreActiveShardMapper;
        this.domainRoutingService = domainRoutingService;
        this.partitionService = partitionService;
    }

    @Transactional(noRollbackFor = BizException.class)
    public SyncCoreActiveResult syncCoreActive(String requestId) {
        CertificateIssueFact issueFact = certificateIssueFactMapper.selectByRequestId(requestId);
        if (issueFact == null) {
            throw new BizException(ErrorCode.REQUEST_NOT_FOUND, "requestId not found: " + requestId);
        }
        if (!CertificateIssueStatus.ISSUED.getValue().equalsIgnoreCase(issueFact.getStatus())) {
            throw new BizException(ErrorCode.ISSUE_RECORD_NOT_READY, "issue record is not ready for core_active sync");
        }

        String syncStatus = issueFact.getSyncStatus();
        if (IssueSyncStatus.DONE.getValue().equalsIgnoreCase(syncStatus)) {
            log.info("sync-core-active skipped because already done requestId={}", requestId);
            return SyncCoreActiveResult.alreadyDone(requestId);
        }
        if (!IssueSyncStatus.PENDING.getValue().equalsIgnoreCase(syncStatus)
            && !IssueSyncStatus.FAILED.getValue().equalsIgnoreCase(syncStatus)) {
            throw new BizException(ErrorCode.ISSUE_RECORD_NOT_READY, "unsupported sync status: " + syncStatus);
        }

        OffsetDateTime now = OffsetDateTime.now();
        int shardId = partitionService.calculateShard(issueFact.getSubjectId(), issueFact.getOrganization());
        String tableName = partitionService.resolveCoreActiveTable(shardId);

        CoreActiveRecord coreActiveRecord = new CoreActiveRecord();
        coreActiveRecord.setCertSerial(issueFact.getCertSerial());
        coreActiveRecord.setIssuerId(issueFact.getIssuerId());
        coreActiveRecord.setSubjectId(issueFact.getSubjectId());
        coreActiveRecord.setCurrent(Boolean.TRUE);
        coreActiveRecord.setNotAfter(issueFact.getNotAfter());
        // first_activated_at stays null until a later real activation flow writes it.
        coreActiveRecord.setFirstActivatedAt(null);
        coreActiveRecord.setCreatedAt(now);
        coreActiveRecord.setUpdatedAt(now);

        String phase = "template-routing";
        try {
            DomainRoutingService.DomainTarget target = domainRoutingService.resolveByTemplateId(issueFact.getTemplateId());
            if (target == DomainRoutingService.DomainTarget.APP) {
                phase = "core-active-mark-old-false";
                appCoreActiveShardMapper.markCurrentFalseBySubjectIdInShard(tableName, issueFact.getSubjectId(), now);
                phase = "core-active-upsert";
                appCoreActiveShardMapper.upsertToShard(tableName, coreActiveRecord);
            } else {
                phase = "core-active-mark-old-false";
                ecuCoreActiveShardMapper.markCurrentFalseBySubjectIdInShard(tableName, issueFact.getSubjectId(), now);
                phase = "core-active-upsert";
                ecuCoreActiveShardMapper.upsertToShard(tableName, coreActiveRecord);
            }
            phase = "sync-status-update";
            certificateIssueFactMapper.updateSyncStatusByRequestId(requestId, IssueSyncStatus.DONE.getValue(), now);
            log.info("sync-core-active executed requestId={} shardId={} tableName={}", requestId, shardId, tableName);
            return SyncCoreActiveResult.executed(requestId);
        } catch (Exception ex) {
            log.warn("sync-core-active failed requestId={} phase={} error={}", requestId, phase, ex.getMessage());
            certificateIssueFactMapper.updateSyncStatusByRequestId(requestId, IssueSyncStatus.FAILED.getValue(), OffsetDateTime.now());
            throw new BizException(ErrorCode.CORE_ACTIVE_SYNC_FAILED, "failed to sync core_active for requestId=" + requestId);
        }
    }

    public static class SyncCoreActiveResult {

        private final String requestId;
        private final String syncStatus;
        private final String action;

        private SyncCoreActiveResult(String requestId, String syncStatus, String action) {
            this.requestId = requestId;
            this.syncStatus = syncStatus;
            this.action = action;
        }

        public static SyncCoreActiveResult executed(String requestId) {
            return new SyncCoreActiveResult(requestId, IssueSyncStatus.DONE.getValue(), "executed");
        }

        public static SyncCoreActiveResult alreadyDone(String requestId) {
            return new SyncCoreActiveResult(requestId, IssueSyncStatus.DONE.getValue(), "already_done");
        }

        public String getRequestId() {
            return requestId;
        }

        public String getSyncStatus() {
            return syncStatus;
        }

        public String getAction() {
            return action;
        }
    }
}
