package com.pki.platform.issuance.service;

import java.util.UUID;
import org.springframework.stereotype.Service;

@Service
public class InstallIdGenerator {

    public String generate() {
        return "install-" + UUID.randomUUID().toString().replace("-", "");
    }
}
