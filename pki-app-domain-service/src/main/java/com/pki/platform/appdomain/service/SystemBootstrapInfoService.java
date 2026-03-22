package com.pki.platform.appdomain.service;

import com.pki.platform.appdomain.mapper.SystemBootstrapInfoMapper;
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
