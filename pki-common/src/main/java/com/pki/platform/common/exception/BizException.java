package com.pki.platform.common.exception;

import com.pki.platform.common.enums.ErrorCode;

public class BizException extends RuntimeException {

    private final String code;

    public BizException(String message) {
        this(ErrorCode.BUSINESS_ERROR, message);
    }

    public BizException(ErrorCode errorCode) {
        this(errorCode, errorCode.getMessage());
    }

    public BizException(ErrorCode errorCode, String message) {
        super(message);
        this.code = errorCode.getCode();
    }

    public String getCode() {
        return code;
    }
}
