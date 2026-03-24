package com.pki.platform.issuance.mapper;

import com.pki.platform.issuance.model.CertificateIssueFact;
import java.time.OffsetDateTime;
import java.util.List;
import org.apache.ibatis.annotations.Param;

public interface CertificateIssueFactMapper {

    int insert(CertificateIssueFact record);

    CertificateIssueFact selectById(Long id);

    CertificateIssueFact selectByRequestId(String requestId);

    int countBySubjectIdAndOrganization(@Param("subjectId") String subjectId,
                                        @Param("organization") String organization);

    CertificateIssueFact selectLatestBySubjectIdAndOrganization(@Param("subjectId") String subjectId,
                                                                @Param("organization") String organization);

    List<CertificateIssueFact> selectBySubjectIdAndOrganizationAndCertSerial(@Param("subjectId") String subjectId,
                                                                              @Param("organization") String organization,
                                                                              @Param("certSerial") String certSerial);

    CertificateIssueFact selectByRequestIdAndStatus(@Param("requestId") String requestId,
                                                    @Param("status") String status,
                                                    @Param("syncStatus") String syncStatus);

    List<String> selectRequestIdsForSyncCompensation(@Param("status") String status,
                                                     @Param("pendingStatus") String pendingStatus,
                                                     @Param("failedStatus") String failedStatus,
                                                     @Param("limit") int limit);

    int deleteExpiredIssueFacts(@Param("cutoff") OffsetDateTime cutoff,
                                @Param("batchSize") int batchSize);

    int updateSyncStatusByRequestId(@Param("requestId") String requestId,
                                    @Param("syncStatus") String syncStatus,
                                    @Param("updatedAt") OffsetDateTime updatedAt);
}
