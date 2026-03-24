package com.pki.platform.issuance.service;

import com.pki.platform.issuance.mapper.CertificateIssueFactMapper;
import java.time.OffsetDateTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class IssueFactCleanupScheduler {

    private static final Logger log = LoggerFactory.getLogger(IssueFactCleanupScheduler.class);

    private final CertificateIssueFactMapper certificateIssueFactMapper;

    @Value("${pki.issuance.issue-fact-cleanup.enabled:true}")
    private boolean enabled;

    @Value("${pki.issuance.issue-fact-cleanup.retention-days:30}")
    private int retentionDays;

    @Value("${pki.issuance.issue-fact-cleanup.batch-size:500}")
    private int batchSize;

    public IssueFactCleanupScheduler(CertificateIssueFactMapper certificateIssueFactMapper) {
        this.certificateIssueFactMapper = certificateIssueFactMapper;
    }

    @Scheduled(cron = "${pki.issuance.issue-fact-cleanup.cron:0 0 3 * * *}")
    public void cleanupExpiredIssueFacts() {
        if (!enabled) {
            return;
        }

        OffsetDateTime cutoff = OffsetDateTime.now().minusDays(retentionDays);
        int deleted = certificateIssueFactMapper.deleteExpiredIssueFacts(cutoff, batchSize);
        if (deleted > 0) {
            log.info("issue_fact cleanup deleted {} rows older than {} days", deleted, retentionDays);
        }
    }
}
