package com.pki.platform.issuance.service;

import com.pki.platform.issuance.enums.CertificateIssueStatus;
import com.pki.platform.issuance.enums.IssueSyncStatus;
import com.pki.platform.issuance.mapper.CertificateIssueFactMapper;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class CoreActiveSyncCompensationScheduler {

    private static final Logger log = LoggerFactory.getLogger(CoreActiveSyncCompensationScheduler.class);

    private final CertificateIssueFactMapper certificateIssueFactMapper;
    private final CoreActiveSyncService coreActiveSyncService;

    @Value("${pki.issuance.sync-core-active-compensation.enabled:true}")
    private boolean enabled;

    @Value("${pki.issuance.sync-core-active-compensation.batch-size:100}")
    private int batchSize;

    public CoreActiveSyncCompensationScheduler(CertificateIssueFactMapper certificateIssueFactMapper,
                                               CoreActiveSyncService coreActiveSyncService) {
        this.certificateIssueFactMapper = certificateIssueFactMapper;
        this.coreActiveSyncService = coreActiveSyncService;
    }

    @Scheduled(cron = "${pki.issuance.sync-core-active-compensation.cron:0 */5 * * * *}")
    public void compensateSyncCoreActive() {
        if (!enabled) {
            return;
        }

        List<String> requestIds = certificateIssueFactMapper.selectRequestIdsForSyncCompensation(
            CertificateIssueStatus.ISSUED.getValue(),
            IssueSyncStatus.PENDING.getValue(),
            IssueSyncStatus.FAILED.getValue(),
            batchSize
        );

        for (String requestId : requestIds) {
            try {
                coreActiveSyncService.syncCoreActive(requestId);
            } catch (Exception ex) {
                log.warn("sync-core-active compensation failed requestId={} error={}", requestId, ex.getMessage());
            }
        }

        if (!requestIds.isEmpty()) {
            log.info("sync-core-active compensation processed {} requestIds", requestIds.size());
        }
    }
}
