# Concurrency Verification Guide

## 1. 目的

本说明文档用于指导如何执行最小并发与一致性验证。

这些脚本的目标是验证当前已知高风险点是否可以在最小并发条件下复现。

需要特别说明：

- 这些脚本属于“最小一致性验证”
- 它们不是性能压测平台
- 它们不用于评估吞吐量、延迟或极限并发能力

## 2. 执行前提

执行前需要确保：

- `pki-issuance-service` 已启动
- `pki-revocation-dispatcher` 已启动
- PostgreSQL 已启动并可连接
- 相关 schema 和表已完成迁移

执行脚本时需要提供以下环境变量：

- `BASE_URL`
- `REVOCATION_BASE_URL`
- `PGHOST`
- `PGPORT`
- `PGDATABASE`
- `PGUSER`
- `PGPASSWORD`

## 3. 脚本清单与验证目标

### 3.1 verify_apply_idempotency_concurrency.sh

验证目标：

- 对同一个 `requestId` 并发调用 `apply`
- 检查最终是否只生成一条 `issue_fact`
- 检查是否出现重复签发事实

### 3.2 verify_sync_core_active_concurrency.sh

验证目标：

- 对同一个 `requestId` 并发调用 `/certificates/sync-core-active/{requestId}`
- 检查最终 `sync_status` 是否为 `done`
- 检查同一 subject 在目标 `core_active_xx` 中是否出现多个 `is_current=true`

### 3.3 verify_revoke_idempotency_concurrency.sh

验证目标：

- 对同一张证书并发调用 `revoke`
- 检查主集合是否正确迁出
- 检查 `revocation_current` 与 `revocation_outbox` 是否出现明显重复脏数据

### 3.4 verify_recover_idempotency_concurrency.sh

验证目标：

- 对同一张证书并发调用 `recover`
- 检查证书是否最终回到正确状态
- 检查是否出现重复写回 `core_active`

## 4. 推荐执行顺序

建议按以下顺序执行：

1. `./scripts/verify_apply_idempotency_concurrency.sh`
2. `./scripts/verify_sync_core_active_concurrency.sh`
3. `./scripts/verify_revoke_idempotency_concurrency.sh`
4. `./scripts/verify_recover_idempotency_concurrency.sh`

这个顺序更容易从签发事实、同步、吊销、恢复逐步观察一致性问题。

## 5. 需要观察的表和字段

### apply 并发

观察：

- `pki_issuance.certificate_issue_fact.request_id`
- `pki_issuance.certificate_issue_fact.cert_serial`
- `pki_issuance.certificate_issue_fact.status`

### sync-core-active 并发

观察：

- `pki_issuance.certificate_issue_fact.sync_status`
- `pki_app.core_active_xx.subject_id`
- `pki_app.core_active_xx.is_current`
- `pki_app.core_active_xx.cert_serial`
- `pki_app.core_active_xx.issuer_id`

### revoke 并发

观察：

- `pki_app.core_active_xx.cert_serial`
- `pki_app.core_active_xx.issuer_id`
- `pki_revocation.revocation_current.cert_serial`
- `pki_revocation.revocation_current.issuer_id`
- `pki_revocation.revocation_outbox.event_type`
- `pki_revocation.revocation_outbox.version`

### recover 并发

观察：

- `pki_app.core_active_xx.cert_serial`
- `pki_app.core_active_xx.issuer_id`
- `pki_app.core_active_xx.is_current`
- `pki_revocation.revocation_current.cert_serial`
- `pki_revocation.revocation_outbox.event_type`
- `pki_revocation.revocation_outbox.version`

## 6. 如何判断是否存在一致性问题

如果出现以下情况，应视为存在一致性问题：

- 同一个 `requestId` 产生多条 `issue_fact`
- 同一 subject 在同一分片中出现多条 `is_current=true`
- 并发 revoke 后主表中仍残留目标证书
- 并发 revoke 后 `revocation_current` 中出现重复记录
- 并发 revoke 后 `REVOKE` outbox 出现重复事件
- 并发 recover 后 `core_active` 中出现重复写回
- 并发 recover 后 `revocation_current` 未清空
- 并发 recover 后 `RECOVER` outbox 出现重复事件

## 7. 结果判断

每个脚本都会输出自己的阶段日志，并在最后输出：

- `[PASS] ...`
  - 说明该次最小并发验证未发现脚本定义范围内的一致性问题

- `[FAIL] ...`
  - 说明该次最小并发验证发现了可复现的一致性异常或状态异常

建议将脚本输出与数据库实际结果一起保留，作为并发验证记录。
