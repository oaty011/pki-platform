# Issuance 第一版阶段成果说明

## 1. 阶段背景

第一版的目标是把 `pki-issuance-service` 从“最小 mock 下证闭环”推进到“可本地验证的真实软签发闭环”，同时保持当前主流程边界稳定，不扩展到 KMS、第三方 CA、OCSP、CRL 或独立 lifecycle service。

本阶段同时处理了两个历史问题：

- `current / is_current` 语义过重，与当前主集合模型不一致
- 证书签发仍然依赖 mock 结果，无法形成真实 X.509 证书下证链路

因此第一版做了两条主线收口：

- 查询与主集合语义收口
- 模板驱动 + `CertificateIssuanceProvider` + `SoftSigner` 的最小真实签发骨架接入

### 为什么要做 current/is_current 收口

原因有三点：

- `core_active_xx` 本身已经表达“当前仍在主集合中的证书”，再维护 `is_current` 会形成第二套状态
- `revoke / recover` 已经改为集合迁移模型，默认查询更适合表达“主集合最新记录”，而不是“唯一 current 记录”
- 并发与兼容逻辑会因为 `is_current` 变得更复杂，且字段本身已经不再承载真实业务含义

### 为什么要引入模板驱动 + CertificateIssuanceProvider + SoftSigner

原因有三点：

- 签发参数不应继续靠 `templateId` 字符串和硬编码方法直接拼接
- 证书主题、有效期、KeyUsage、provider/signer 选择都需要先收口到模板对象
- 真实签发链路需要把“证书组装”和“底层签名”解耦，形成最小可扩展骨架

## 2. 第一版已完成能力

当前已完成的能力包括：

- `is_current` 已从数据库和主逻辑下线
- 默认查询主语义已收口为：`core_active` 主集合最新记录
- `latestIssuedCertificate` 语义已收口为：`issue_fact` 最近签发记录
- 模板驱动证书主题
- CSR 只承担公钥提取与自签名校验职责
- 真实 `SoftSigner` 已可完成第一版 X.509 签发
- `GET /certificates/{requestId}/certificate` 可返回证书内容
- `sync-core-active` 可将签发结果推进到 `core_active_xx`
- `refresh-status` 可刷新 `core_active.updated_at`
- `isCurrent` 已从当前 `issuance-service` 响应中下线

## 3. 当前接口清单

### POST /app-certificates/apply

语义：

- 接收 APP 下证请求
- 根据模板和主体信息生成真实签发命令
- 产出 `issue_fact`

### POST /ecu-certificates/apply

语义：

- 接收 ECU 下证请求
- 根据模板和主体信息生成真实签发命令
- 产出 `issue_fact`

### GET /certificates/{requestId}

语义：

- 查询某次申请的签发状态
- 返回 `requestId / status / certSerial / issuerId / syncStatus`

### GET /certificates/{requestId}/certificate

语义：

- 返回该次申请对应的证书内容
- 当前主要返回 `certificatePem`

### POST /certificates/sync-core-active/{requestId}

语义：

- 将已签发的 `issue_fact` 同步进入对应 shard 的 `core_active_xx`

### POST /app-certificates/current/query

语义：

- 查询 APP 主体当前证书视图
- 不带 `certSerial` 时返回：
  - `issuedCount`
  - `latestIssuedCertificate`
  - `currentActiveCertificate`
- 带 `certSerial` 时返回：
  - `matchedCertificates`

### POST /ecu-certificates/current/query

语义：

- 查询 ECU 主体当前证书视图
- 语义与 APP 版本一致，只是主体和 organization 不同

### POST /certificates/refresh-status

语义：

- 表示某张证书刚刚被正常使用
- 通过 `subjectId + organization -> shard`
- 在对应 `core_active_xx` 中按 `certSerial + issuerId` 精确定位
- 刷新该行的 `updated_at`

## 4. 当前模板模型说明

当前引入了最小模板对象 `CertificateTemplate`，至少包含：

- `templateId`
- `certificateType`
- `subjectCnSource`
- `subjectOu`
- `subjectO`
- `subjectC`
- `organization`
- `validityDays`
- `keyAlgorithm`
- `digitalSignature`
- `keyEncipherment`
- `clientAuth`
- `providerType`
- `signerType`
- `issuerBinding`

### templateId 的作用

- `templateId` 现在只作为模板查找 key
- 不再直接承担 OU、算法、provider、signer 等业务语义

### subject 如何由模板生成

当前最终证书主题由模板生成：

- APP：
  - `CN=appId/installId,OU=Vehicle Controller SDK,O=DFMC,C=CN`
- ECU：
  - `CN=deviceId,OU=<template-defined-ou>,O=DFMC ECU,C=CN`

CSR 中的 subject DN 不再作为最终证书主题来源。

### APP / ECU 当前默认模板语义

当前内存模板注册表至少包含：

- `ecu-tbox`
- `ecu-ivi`
- `ecu-had`
- `ecu-sgw`
- `ecu-obu`
- `app-controller-sdk`

同时保留了当前验证链路兼容模板：

- `app-template-demo`
- `ecu-template-demo`

### providerType / signerType / issuerBinding 当前状态

当前这些字段已经进入模板模型，但仍属于第一版内存模板字段：

- `providerType`
- `signerType`
- `issuerBinding`

它们已经成为未来扩展点，但当前只落地：

- `providerType = local-x509`
- `signerType = soft`

## 5. 当前生命周期字段语义

### created_at

- 表示该记录首次进入 `core_active_xx` 的时间

### updated_at

- 当前作为主集合记录的“最近活跃刷新时间”
- `refresh-status` 第一版直接刷新该字段

### first_activated_at

- 当前仍为保留字段
- 第一版还没有把真实“首次活跃”语义接入
- 因此当前 `first_activated_at = null` 是预期现象，不是 bug

## 6. 当前验证脚本清单

### scripts/generate_softsigner_test_ca.sh

用途：

- 生成本地测试 Root / Intermediate / Leaf 证书链
- 用于 `soft signer` 本地验证

### scripts/verify_softsigner_issue_app.sh

用途：

- 验证 APP 真实 soft signer 下证闭环
- 包括 apply、status、certificate 下载、openssl 证书检查和链校验

### scripts/verify_softsigner_issue_ecu.sh

用途：

- 验证 ECU 真实 soft signer 下证闭环
- 包括 ECU 模板主题检查和链校验

### scripts/verify_refresh_status.sh

用途：

- 验证 `refresh-status` 会刷新 `core_active.updated_at`

### scripts/verify_refresh_status_negative.sh

用途：

- 验证 `refresh-status` 的失败场景
- 包括：
  - subject mismatch
  - cert 不在 core_active
  - issuerId 错误

## 7. 当前未完成项 / 下一阶段候选项

当前仍未完成的内容包括：

- KMS signer 未实现
- 第三方 CA / Private CA provider 未实现
- 模板数据库化未实现
- 模板管理接口未实现
- `firstActivatedAt` 语义未接入
- 新验证脚本尚未接入 `run_all_e2e.sh`
- API 命名仍有兼容残留：
  - `currentActiveCertificate`
  - 旧 `GET /app-certificates/current/{subjectId}`
  - 旧 `GET /ecu-certificates/current/{subjectId}`

当前第一版的重点是：

- 主流程真实可运行
- 查询与主集合语义收口
- 模板与 signer/provider 骨架可扩展

而不是一次性完成所有后续扩展项。
