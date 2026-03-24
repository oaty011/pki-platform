package com.pki.platform.issuance.controller;

import com.pki.platform.common.response.ApiResponse;
import com.pki.platform.issuance.dto.request.AppCurrentQueryRequest;
import com.pki.platform.issuance.dto.request.AppCertificateApplyRequest;
import com.pki.platform.issuance.dto.request.CertificateRefreshStatusRequest;
import com.pki.platform.issuance.dto.request.EcuCurrentQueryRequest;
import com.pki.platform.issuance.dto.request.EcuCertificateApplyRequest;
import com.pki.platform.issuance.dto.response.AppCertificateApplyResponse;
import com.pki.platform.issuance.dto.response.CertificateContentResponse;
import com.pki.platform.issuance.dto.response.CertificateRefreshStatusResponse;
import com.pki.platform.issuance.dto.response.CertificateStatusResponse;
import com.pki.platform.issuance.dto.response.CurrentCertificateResponse;
import com.pki.platform.issuance.dto.response.CurrentQueryResponse;
import com.pki.platform.issuance.dto.response.EcuCertificateApplyResponse;
import com.pki.platform.issuance.service.CertificateApplicationService;
import com.pki.platform.issuance.service.CertificateCurrentQueryFacadeService;
import com.pki.platform.issuance.service.CertificateCurrentQueryService;
import com.pki.platform.issuance.service.CertificateQueryService;
import com.pki.platform.issuance.service.CertificateRefreshStatusService;
import com.pki.platform.issuance.service.CoreActiveSyncService;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class CertificateController {

    private final CertificateApplicationService certificateApplicationService;
    private final CertificateQueryService certificateQueryService;
    private final CertificateCurrentQueryService certificateCurrentQueryService;
    private final CertificateCurrentQueryFacadeService certificateCurrentQueryFacadeService;
    private final CoreActiveSyncService coreActiveSyncService;
    private final CertificateRefreshStatusService certificateRefreshStatusService;

    public CertificateController(CertificateApplicationService certificateApplicationService,
                                 CertificateQueryService certificateQueryService,
                                 CertificateCurrentQueryService certificateCurrentQueryService,
                                 CertificateCurrentQueryFacadeService certificateCurrentQueryFacadeService,
                                 CoreActiveSyncService coreActiveSyncService,
                                 CertificateRefreshStatusService certificateRefreshStatusService) {
        this.certificateApplicationService = certificateApplicationService;
        this.certificateQueryService = certificateQueryService;
        this.certificateCurrentQueryService = certificateCurrentQueryService;
        this.certificateCurrentQueryFacadeService = certificateCurrentQueryFacadeService;
        this.coreActiveSyncService = coreActiveSyncService;
        this.certificateRefreshStatusService = certificateRefreshStatusService;
    }

    @PostMapping("/app-certificates/apply")
    public ApiResponse<AppCertificateApplyResponse> applyApp(@RequestBody AppCertificateApplyRequest request) {
        return ApiResponse.success(certificateApplicationService.applyAppCertificate(request));
    }

    @PostMapping("/ecu-certificates/apply")
    public ApiResponse<EcuCertificateApplyResponse> applyEcu(@RequestBody EcuCertificateApplyRequest request) {
        return ApiResponse.success(certificateApplicationService.applyEcuCertificate(request));
    }

    @GetMapping("/app-certificates/current/{subjectId}")
    public ApiResponse<CurrentCertificateResponse> getCurrentApp(@PathVariable("subjectId") String subjectId) {
        return ApiResponse.success(certificateCurrentQueryService.getCurrentAppCertificate(subjectId));
    }

    @GetMapping("/ecu-certificates/current/{subjectId}")
    public ApiResponse<CurrentCertificateResponse> getCurrentEcu(@PathVariable("subjectId") String subjectId) {
        return ApiResponse.success(certificateCurrentQueryService.getCurrentEcuCertificate(subjectId));
    }

    @PostMapping("/app-certificates/current/query")
    public ApiResponse<CurrentQueryResponse> queryCurrentApp(@RequestBody AppCurrentQueryRequest request) {
        return ApiResponse.success(certificateCurrentQueryFacadeService.queryAppCurrent(request));
    }

    @PostMapping("/ecu-certificates/current/query")
    public ApiResponse<CurrentQueryResponse> queryCurrentEcu(@RequestBody EcuCurrentQueryRequest request) {
        return ApiResponse.success(certificateCurrentQueryFacadeService.queryEcuCurrent(request));
    }

    @GetMapping("/certificates/{requestId}")
    public ApiResponse<CertificateStatusResponse> getStatus(@PathVariable("requestId") String requestId) {
        return ApiResponse.success(certificateQueryService.getStatus(requestId));
    }

    @GetMapping("/certificates/{requestId}/certificate")
    public ApiResponse<CertificateContentResponse> getCertificate(@PathVariable("requestId") String requestId) {
        return ApiResponse.success(certificateQueryService.getCertificate(requestId));
    }

    @PostMapping("/certificates/sync-core-active/{requestId}")
    public ApiResponse<Map<String, String>> syncCoreActive(@PathVariable("requestId") String requestId) {
        CoreActiveSyncService.SyncCoreActiveResult result = coreActiveSyncService.syncCoreActive(requestId);
        return ApiResponse.success(Map.of(
            "requestId", result.getRequestId(),
            "syncStatus", result.getSyncStatus(),
            "action", result.getAction()
        ));
    }

    @PostMapping("/certificates/refresh-status")
    public ApiResponse<CertificateRefreshStatusResponse> refreshStatus(@RequestBody CertificateRefreshStatusRequest request) {
        return ApiResponse.success(certificateRefreshStatusService.refresh(request));
    }
}
