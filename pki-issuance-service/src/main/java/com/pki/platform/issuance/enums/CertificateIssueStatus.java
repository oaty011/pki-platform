package com.pki.platform.issuance.enums;

public enum CertificateIssueStatus {

    ISSUED("ISSUED");

    private final String value;

    CertificateIssueStatus(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
