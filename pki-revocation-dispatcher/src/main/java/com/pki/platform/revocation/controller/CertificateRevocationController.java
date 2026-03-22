package com.pki.platform.revocation.controller;

import com.pki.platform.common.response.ApiResponse;
import com.pki.platform.revocation.dto.request.AppRecoverRequest;
import com.pki.platform.revocation.dto.request.AppRevokeRequest;
import com.pki.platform.revocation.dto.request.EcuRecoverRequest;
import com.pki.platform.revocation.dto.request.EcuRevokeRequest;
import com.pki.platform.revocation.service.RevocationCommandService;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class CertificateRevocationController {

    private final RevocationCommandService revocationCommandService;

    public CertificateRevocationController(RevocationCommandService revocationCommandService) {
        this.revocationCommandService = revocationCommandService;
    }

    @PostMapping("/app-certificates/revoke")
    public ApiResponse<Map<String, String>> revokeApp(@RequestBody AppRevokeRequest request) {
        RevocationCommandService.CommandResult result = revocationCommandService.revokeApp(request);
        return ApiResponse.success(Map.of(
            "certSerial", result.getCertSerial(),
            "issuerId", result.getIssuerId(),
            "action", result.getAction()
        ));
    }

    @PostMapping("/ecu-certificates/revoke")
    public ApiResponse<Map<String, String>> revokeEcu(@RequestBody EcuRevokeRequest request) {
        RevocationCommandService.CommandResult result = revocationCommandService.revokeEcu(request);
        return ApiResponse.success(Map.of(
            "certSerial", result.getCertSerial(),
            "issuerId", result.getIssuerId(),
            "action", result.getAction()
        ));
    }

    @PostMapping("/app-certificates/recover")
    public ApiResponse<Map<String, String>> recoverApp(@RequestBody AppRecoverRequest request) {
        RevocationCommandService.CommandResult result = revocationCommandService.recoverApp(request);
        return ApiResponse.success(Map.of(
            "certSerial", result.getCertSerial(),
            "issuerId", result.getIssuerId(),
            "action", result.getAction()
        ));
    }

    @PostMapping("/ecu-certificates/recover")
    public ApiResponse<Map<String, String>> recoverEcu(@RequestBody EcuRecoverRequest request) {
        RevocationCommandService.CommandResult result = revocationCommandService.recoverEcu(request);
        return ApiResponse.success(Map.of(
            "certSerial", result.getCertSerial(),
            "issuerId", result.getIssuerId(),
            "action", result.getAction()
        ));
    }
}
