package com.pki.platform.issuance.enums;

public enum IssueSyncStatus {

    PENDING("pending"),
    DONE("done"),
    FAILED("failed");

    private final String value;

    IssueSyncStatus(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
