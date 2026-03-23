package com.pki.platform.issuance.service;

import com.pki.platform.issuance.dto.response.MockSignResult;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.springframework.stereotype.Service;

@Service
public class MockSignerService {

    public MockSignResult sign(String subjectId, String templateId) {
        OffsetDateTime notAfter = OffsetDateTime.now().plusDays(90);
        String certSerial = UUID.randomUUID().toString().replace("-", "");
        String issuerId = "mock-issuer-001";
        String signerId = "mock-signer-001";
        String certificatePem = "-----BEGIN CERTIFICATE-----\n"
            + subjectId + ":" + templateId + ":" + certSerial + "\n"
            + "-----END CERTIFICATE-----";
        return new MockSignResult(certSerial, issuerId, signerId, certificatePem, notAfter);
    }
}
