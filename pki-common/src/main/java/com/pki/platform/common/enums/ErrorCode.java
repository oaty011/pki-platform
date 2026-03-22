package com.pki.platform.common.enums;

public enum ErrorCode {

    SUCCESS("00000", "Success"),
    BAD_REQUEST("40000", "Bad request"),
    INVALID_REQUEST_PARAM("40001", "Invalid request parameter"),
    INVALID_TEMPLATE_ID("40002", "Invalid template id"),
    REQUEST_NOT_FOUND("40400", "Request not found"),
    ISSUE_RECORD_NOT_READY("40900", "Issue record is not ready"),
    CORE_ACTIVE_SYNC_FAILED("40901", "Core active sync failed"),
    BUSINESS_ERROR("50001", "Business error"),
    INTERNAL_SERVER_ERROR("50000", "Internal server error");

    private final String code;
    private final String message;

    ErrorCode(String code, String message) {
        this.code = code;
        this.message = message;
    }

    public String getCode() {
        return code;
    }

    public String getMessage() {
        return message;
    }
}
