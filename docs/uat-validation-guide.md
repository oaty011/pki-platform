# 1. 验证目标

本手册用于指导测试人员在 UAT 环境验证 PKI Platform 的证书全生命周期能力是否正常可用。

# 2. 使用前提

本手册默认测试环境已由开发或运维人员完成部署，所有服务处于可用状态。

# 3. 验证流程总览

UAT 验证建议按以下顺序执行：

- APP happy path
- ECU happy path
- subject mismatch
- cleanup 验证
- compensation 验证

# 4. APP 证书流程验证（happy path）

## 4.1 执行脚本

在项目根目录执行：

```bash
./scripts/verify_app_e2e_happy_path.sh
```

## 4.2 关键输出看哪里

重点关注以下输出阶段：

- `== 1) APP apply ==`
- `== 3) Sync core_active ==`
- `== 6) APP revoke ==`
- `== 8) APP recover ==`
- 最后一行 PASS 输出

## 4.3 成功标准

满足以下条件即视为 APP happy path 通过：

- 脚本执行过程中没有中断
- 没有出现 `[FAIL]`
- 最终输出包含：

```text
[PASS] APP E2E happy path verified
```

# 5. ECU 证书流程验证（happy path）

## 5.1 执行脚本

在项目根目录执行：

```bash
./scripts/verify_ecu_e2e_happy_path.sh
```

## 5.2 关键输出看哪里

重点关注以下输出阶段：

- `== 1) ECU apply ==`
- `== 3) Sync core_active ==`
- `== 6) ECU revoke ==`
- `== 8) ECU recover ==`
- 最后一行 PASS 输出

## 5.3 成功标准

满足以下条件即视为 ECU happy path 通过：

- 脚本执行过程中没有中断
- 没有出现 `[FAIL]`
- 最终输出包含：

```text
[PASS] ECU E2E happy path verified
```

# 6. subject mismatch 验证

这是错误场景验证，用于确认系统会拒绝“主体与证书真实 owner 不一致”的操作。

## 6.1 APP subject mismatch

执行脚本：

```bash
./scripts/verify_app_subject_mismatch.sh
```

成功标准：

- 脚本执行完成
- revoke mismatch 与 recover mismatch 都被拒绝
- 返回错误语义包含：

```text
subject does not match certificate owner
```

- 最终输出包含：

```text
[PASS] APP subject mismatch failure path verified
```

## 6.2 ECU subject mismatch

执行脚本：

```bash
./scripts/verify_ecu_subject_mismatch.sh
```

成功标准：

- 脚本执行完成
- revoke mismatch 与 recover mismatch 都被拒绝
- 返回错误语义包含：

```text
subject does not match certificate owner
```

- 最终输出包含：

```text
[PASS] ECU subject mismatch failure path verified
```

# 7. issue_fact 清理任务验证

## 7.1 执行脚本

在项目根目录执行：

```bash
./scripts/verify_issue_fact_cleanup.sh
```

## 7.2 预期现象

执行该脚本后，应看到以下现象：

- 脚本构造 2 条超过 retention-days 的旧数据
- 脚本构造 1 条未过期的新数据
- cleanup 任务不会一次性无上限删除
- 当 `batch-size` 设置较小值时，旧数据会分批删除
- 新数据不会被误删

## 7.3 数据库验证点

重点观察：

- `pki_issuance.certificate_issue_fact.created_at`

成功标准：

- 旧数据被删除
- 新数据保留
- 最终输出包含：

```text
[PASS] issue_fact cleanup verification passed
```

# 8. sync-core-active 补偿验证

## 8.1 执行脚本

在项目根目录执行：

```bash
./scripts/verify_sync_core_active_compensation.sh
```

## 8.2 验证重点

该验证必须满足以下条件：

- 不调用手工接口 `/certificates/sync-core-active/{requestId}`
- 通过后台 compensation 任务完成同步
- 初始 `sync_status` 为 `pending`
- 补偿完成后 `sync_status` 变为 `done`
- 对应 `core_active_xx` 中出现该证书数据

## 8.3 成功标准

满足以下条件即视为 compensation 验证通过：

- 脚本执行完成
- 输出中能观察到 `pending -> done`
- 能观察到目标 `core_active_xx` 中出现记录
- 最终输出包含：

```text
[PASS] sync-core-active compensation verification passed
```

# 9. 成功标准（最终判断）

只有当以下全部成立，UAT通过：

- 所有脚本执行完成
- 输出包含：
  `[PASS] all E2E checks passed`
- cleanup 验证通过
- compensation 验证通过

建议执行顺序如下：

```bash
./scripts/run_all_e2e.sh
./scripts/verify_issue_fact_cleanup.sh
./scripts/verify_sync_core_active_compensation.sh
```

# 10. 常见失败与排查

## 10.1 REVOCATION_BASE_URL 错误

### 现象

- `revoke / recover` 阶段失败
- 返回类似：

```text
No static resource app-certificates/revoke
```

### 原因

- 脚本把 `revoke / recover` 请求发到了错误服务
- `REVOCATION_BASE_URL` 没有指向 `pki-revocation-dispatcher`

### 如何解决

- 确认当前测试环境中的 `REVOCATION_BASE_URL` 已正确指向 `pki-revocation-dispatcher`
- 当前默认地址应为 `http://localhost:18084`
- 如仍失败，确认 `pki-revocation-dispatcher` 服务已启动且可访问

## 10.2 XML `<` 未转义

### 现象

- 服务启动失败
- 日志中出现 `SAXParseException`
- 提示 XML 内容不合法

### 原因

- MyBatis XML 中直接写了 `<` 比较符
- XML 解析器把它当成非法标记起始符

### 如何解决

- 检查报错的 mapper XML
- 把 `<` 改为 `&lt;` 或使用合法 XML 写法

## 10.3 PostgreSQL 连接失败

### 现象

- 脚本执行失败
- `psql` 报连接错误
- 服务启动后数据库健康检查失败

### 原因

- PostgreSQL 未启动
- 环境变量配置错误
- 用户名、密码、数据库名不正确

### 如何解决

- 确认当前测试环境中的 PostgreSQL 连接参数已正确配置
- 确认 PostgreSQL 服务已启动且数据库可访问
- 如仍失败，请联系环境提供方或开发人员核对数据库连接信息

## 10.4 服务未启动

### 现象

- `curl` 无响应
- 脚本调用接口时报连接失败

### 原因

- issuance-service 或 revocation-dispatcher 未启动

### 如何解决

- 先检查 `pki-issuance-service`
- 再检查 `pki-revocation-dispatcher`
- 使用健康检查确认服务存活

## 10.5 端口冲突

### 现象

- 服务启动时报端口占用
- 启动后脚本请求命中错误进程

### 原因

- 当前默认端口已被其他程序占用

### 如何解决

- 重点检查：
  - `18081`
  - `18082`
  - `18083`
  - `18084`
  - `5432`
- 确认目标端口对应的是正确服务
- 如果端口被调整，需同步修改环境变量
