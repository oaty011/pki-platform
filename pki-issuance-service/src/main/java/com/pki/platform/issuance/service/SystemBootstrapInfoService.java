package com.pki.platform.issuance.service;

import com.pki.platform.issuance.mapper.SystemBootstrapInfoMapper;
import org.springframework.stereotype.Service;

@Service
public class SystemBootstrapInfoService {

    private final SystemBootstrapInfoMapper systemBootstrapInfoMapper;

    public SystemBootstrapInfoService(SystemBootstrapInfoMapper systemBootstrapInfoMapper) {
        this.systemBootstrapInfoMapper = systemBootstrapInfoMapper;
    }

    public long countRecords() {
        return systemBootstrapInfoMapper.countAll();
    }
}
