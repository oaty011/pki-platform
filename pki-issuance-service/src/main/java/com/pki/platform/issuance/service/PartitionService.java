package com.pki.platform.issuance.service;

import org.springframework.stereotype.Service;

@Service
public class PartitionService {

    public int calculateShard(String subjectId, String organization) {
        String partitionKey = subjectId + ":" + organization;
        return Math.floorMod(partitionKey.hashCode(), 32);
    }

    public String resolveCoreActiveTable(int shardId) {
        return String.format("core_active_%02d", shardId);
    }
}
