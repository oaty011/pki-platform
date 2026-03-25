package com.pki.platform.issuance.service;

import com.pki.platform.issuance.dto.response.MockSignResult;
import org.springframework.stereotype.Service;

@Service
public class MockSignerService {

    public MockSignResult sign(String subjectId, String templateId) {
        throw new UnsupportedOperationException("MockSignerService is no longer used by the template-driven issuance flow");
    }
}
