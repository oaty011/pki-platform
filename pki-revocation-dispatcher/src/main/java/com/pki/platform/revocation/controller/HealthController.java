package com.pki.platform.revocation.controller;

import com.pki.platform.common.response.ApiResponse;
import com.pki.platform.revocation.service.SystemBootstrapInfoService;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    private final SystemBootstrapInfoService systemBootstrapInfoService;

    public HealthController(SystemBootstrapInfoService systemBootstrapInfoService) {
        this.systemBootstrapInfoService = systemBootstrapInfoService;
    }

    @GetMapping("/health")
    public ApiResponse<Map<String, String>> health() {
        return ApiResponse.success(Map.of("service", "pki-revocation-dispatcher", "status", "UP"));
    }

    @GetMapping("/db-health")
    public ApiResponse<Map<String, Object>> dbHealth() {
        long recordCount = systemBootstrapInfoService.countRecords();
        return ApiResponse.success(Map.of(
            "service", "pki-revocation-dispatcher",
            "status", "UP",
            "recordCount", recordCount
        ));
    }
}
