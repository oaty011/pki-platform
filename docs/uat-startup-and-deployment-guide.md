# PKI Platform UAT 启动与部署指南

## 1. 系统服务清单

当前 PKI Platform 在 UAT 或本地运行时，主要涉及以下服务组件：

- `pki-issuance-service`
  - 职责：负责证书申请、签发事实管理、`sync-core-active` 同步、当前证书查询，以及 `issue_fact` 清理与 `sync-core-active` 自动补偿。

- `pki-revocation-dispatcher`
  - 职责：负责 APP / ECU 主体视角的证书吊销与恢复，以及 `revocation_current` / `revocation_outbox` 的写入与维护。

- `pki-app-domain-service`
  - 职责：承载 APP 域数据结构与 APP 主表分片能力，主要围绕 `pki_app` schema 运行。

- `pki-ecu-domain-service`
  - 职责：承载 ECU 域数据结构与 ECU 主表分片能力，主要围绕 `pki_ecu` schema 运行。

- PostgreSQL
  - 职责：统一承载 `pki_issuance`、`pki_app`、`pki_ecu`、`pki_revocation` 四类核心 schema 数据。

从当前实现看，业务主链路主要依赖 `pki-issuance-service`、`pki-revocation-dispatcher` 和 PostgreSQL；APP / ECU domain 服务更多承担领域库与数据承载角色。

## 2. 默认端口说明

当前项目默认端口如下：

- `pki-issuance-service`：`18081`
- `pki-app-domain-service`：`18082`
- `pki-ecu-domain-service`：`18083`
- `pki-revocation-dispatcher`：`18084`
- PostgreSQL：默认使用 `5432`

部署时需要重点确认：

- UAT 环境中的端口映射是否与当前默认值一致
- 脚本与人工联调地址是否指向正确服务
- `revoke / recover` 必须访问 `pki-revocation-dispatcher`
- `apply / status / sync-core-active / current query` 访问 `pki-issuance-service`

## 3. 启动方式

当前推荐的启动方式如下：

- 本地环境：
  - 先确保 PostgreSQL 可用
  - 再分别启动 `pki-issuance-service`、`pki-revocation-dispatcher`、`pki-app-domain-service`、`pki-ecu-domain-service`

- UAT 环境：
  - 按服务独立部署
  - 每个服务通过各自配置连接同一套 PostgreSQL

当前系统没有严格的“服务启动顺序依赖”要求：

- 只要 PostgreSQL 可用，各服务可以独立启动
- `pki-issuance-service` 与 `pki-revocation-dispatcher` 之间没有直接启动先后依赖
- APP / ECU domain 服务也不要求先于 issuance 或 revocation 启动

更准确的前提是：

- 数据库必须先可用
- 需要参与联调的目标服务必须已启动
- 对于当前主链路验证，最核心的是先保证 `pki-issuance-service` 和 `pki-revocation-dispatcher` 可用

## 4. 环境变量配置

当前最核心的 PostgreSQL 环境变量包括：

- `PGHOST`
  - 用于指定 PostgreSQL 主机地址。

- `PGPORT`
  - 用于指定 PostgreSQL 端口，默认通常为 `5432`。

- `PGDATABASE`
  - 用于指定目标数据库名称。

- `PGUSER`
  - 用于指定数据库连接用户名。

- `PGPASSWORD`
  - 用于指定数据库连接密码。

在本地执行脚本或进行人工验证时，上述环境变量通常是必需的；如果缺失，验证脚本无法访问数据库，也无法完成 SQL 检查。

对于服务自身，当前各模块在 `application.yml` 中已包含本地默认数据源配置；在 UAT 环境中，建议通过环境变量或部署平台配置统一覆盖数据库连接参数，而不是依赖本地默认值。

## 5. cleanup / compensation 配置

`pki-issuance-service` 当前新增了两类后台任务配置：

### issue_fact cleanup 配置

- `pki.issuance.issue-fact-cleanup.enabled`
  - 控制是否启用 `issue_fact` 清理任务。

- `pki.issuance.issue-fact-cleanup.retention-days`
  - 控制 `issue_fact` 的保留天数，当前默认值为 `30`。

- `pki.issuance.issue-fact-cleanup.batch-size`
  - 控制单次清理任务最多删除多少条过期记录。

- `pki.issuance.issue-fact-cleanup.cron`
  - 控制清理任务的调度周期。

### sync-core-active compensation 配置

- `pki.issuance.sync-core-active-compensation.enabled`
  - 控制是否启用自动补偿任务。

- `pki.issuance.sync-core-active-compensation.batch-size`
  - 控制单次补偿任务最多处理多少条待补偿记录。

- `pki.issuance.sync-core-active-compensation.cron`
  - 控制补偿任务的调度周期。

### 使用建议

- 本地验证时，建议把 cron 调整为更高频率，便于快速观察任务效果。
- UAT 环境中，建议先确认任务开关、批次大小和 cron 是否符合预期，再进行验证。
- 这两类配置都支持通过环境变量覆盖，适合不同环境使用不同策略。

## 6. 本地 vs UAT 差异

说明本地开发环境与 UAT 环境在配置、依赖和运行方式上的主要差异。

## 7. 常见问题排查

### 1. MyBatis XML 解析失败

典型现象：

- 服务启动失败
- 日志中出现 `SAXParseException`
- 报错信息类似“元素内容必须由格式正确的字符数据或标记组成”

当前已知真实问题：

- 在 MyBatis XML 中直接写 `<` 比较符，会导致 XML 解析失败。

排查方向：

- 检查 mapper XML 中是否直接写了 `<`、`<=`、`<>` 等比较符
- 必要时改为 XML 合法写法，如 `&lt;`，或使用 CDATA

### 2. 数据表不存在

典型现象：

- 服务启动后接口报错
- SQL 执行时报表不存在或列不存在

当前已知真实风险：

- 新增后台任务、revocation 表结构、主表字段或历史变更，如果数据库没有完成对应 migration，就会在运行时失败。

排查方向：

- 确认目标数据库是否已执行最新 Flyway migration
- 确认 `pki_issuance`、`pki_app`、`pki_ecu`、`pki_revocation` schema 是否都已存在
- 确认新增字段和表结构是否与当前代码一致

### 3. REVOCATION_BASE_URL 配置错误

典型现象：

- happy path 或 mismatch 脚本在 revoke / recover 阶段失败
- 返回类似 `No static resource app-certificates/revoke`

当前已知真实问题：

- `revoke / recover` 不属于 `pki-issuance-service`
- 如果脚本把请求发到 issuance 端口，就会请求到错误服务

排查方向：

- 确认 `REVOCATION_BASE_URL` 是否指向 `pki-revocation-dispatcher`
- 当前实际默认端口应为 `18084`
- 确认脚本中的 issuance 与 revocation 地址是否已区分

### 4. 端口占用

典型现象：

- 服务无法启动
- 启动日志提示端口已被占用

当前需要重点检查的端口：

- `18081`：`pki-issuance-service`
- `18082`：`pki-app-domain-service`
- `18083`：`pki-ecu-domain-service`
- `18084`：`pki-revocation-dispatcher`
- `5432`：PostgreSQL

排查方向：

- 确认目标端口是否已被其他本地进程占用
- 确认脚本访问地址与实际启动端口是否一致
- 如果端口调整过，需同步检查环境变量和部署配置

## 8. 健康检查方法

说明如何确认服务、数据库和关键后台任务处于可用状态。

## 9. 总结

说明文档使用范围、部署注意事项以及上线前的最终确认重点。

## 10. 服务职责说明

### pki-issuance-service

`pki-issuance-service` 是当前系统中的轻量化下证过程服务，主要负责以下能力：

- 受理 APP / ECU 的证书申请请求
- 生成并维护 `issue_fact` 签发事实记录
- 提供按 `requestId` 的状态查询与证书查询能力
- 提供 `sync-core-active` 手工同步入口
- 提供 APP / ECU 的当前证书查询能力
- 承担 `issue_fact` 清理任务与 `sync-core-active` 自动补偿任务

在当前架构里，它是签发事实与当前查询的主要入口服务。

### pki-revocation-dispatcher

`pki-revocation-dispatcher` 负责证书生命周期中的吊销与恢复动作，主要包括：

- 提供 APP / ECU 主体视角的 `revoke` 接口
- 提供 APP / ECU 主体视角的 `recover` 接口
- 将被吊销证书写入 `revocation_current`
- 将吊销与恢复事件写入 `revocation_outbox`
- 负责证书从 `core_active_xx` 迁出和迁回

在当前架构里，所有 `revoke / recover` 相关请求都应访问这个服务，而不是访问 issuance-service。

### pki-app-domain-service / pki-ecu-domain-service

这两个 domain 服务当前主要承担领域表与 schema 承载职责：

- `pki-app-domain-service` 对应 `pki_app`
- `pki-ecu-domain-service` 对应 `pki_ecu`

它们的主要作用是：

- 承载 APP / ECU 主表分片结构
- 维护各自 schema 的数据库迁移
- 提供领域模型边界

在当前主链路里，它们不是 E2E 脚本直接调用的核心入口，但建议在完整环境中一并启动，以保持各模块部署形态与 UAT 一致。

## 11. 启动步骤

以下步骤适用于本地联调和 UAT 验证准备。

### 第一步：启动 PostgreSQL

先确认 PostgreSQL 已启动，并且目标数据库可连接。

需要确认：

- PostgreSQL 默认端口为 `5432`
- 数据库连接参数与服务配置一致
- 目标数据库中可访问以下 schema：
  - `pki_issuance`
  - `pki_revocation`
  - `pki_app`
  - `pki_ecu`

如果数据库未启动或连接参数错误，后续所有服务都会启动失败或运行时报错。

### 第二步：启动 pki-issuance-service

启动 `pki-issuance-service`，确认其监听端口为：

- `18081`

该服务启动后，建议优先确认：

- `/health`
- `/db-health`

以及 `application.yml` 中的 cleanup / compensation 配置是否符合当前验证需要。

### 第三步：启动 pki-revocation-dispatcher

启动 `pki-revocation-dispatcher`，确认其监听端口为：

- `18084`

该服务启动后，后续 `revoke / recover` 请求都应指向该端口。

如果该服务未启动，即使 issuance 正常工作，E2E 中的吊销和恢复阶段也会失败。

### 第四步：启动 pki-app-domain-service

启动 `pki-app-domain-service`，确认其监听端口为：

- `18082`

该服务当前不是 E2E 脚本的主要调用目标，但建议作为完整环境的一部分启动。

### 第五步：启动 pki-ecu-domain-service

启动 `pki-ecu-domain-service`，确认其监听端口为：

- `18083`

同样建议在完整环境中一并启动，以保持环境一致性。

### 第六步：设置环境变量

执行验证脚本前，至少需要设置以下环境变量：

```bash
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=<your_database>
export PGUSER=<your_user>
export PGPASSWORD=<your_password>
export BASE_URL=http://localhost:18081
export REVOCATION_BASE_URL=http://localhost:18084
```

如果要运行 APP / ECU 脚本，也可以按需补充：

```bash
export APP_TEMPLATE_ID=app-template-demo
export ECU_TEMPLATE_ID=ecu-template-demo
```

### 启动顺序说明

启动顺序在“首次拉起环境”时建议按以下顺序进行：

1. PostgreSQL
2. pki-issuance-service
3. pki-revocation-dispatcher
4. pki-app-domain-service
5. pki-ecu-domain-service

需要特别说明的是：

- 这个顺序主要用于首次启动和排错阶段，便于快速定位问题
- 在运行期，各服务之间没有强依赖的启动顺序要求
- 只要数据库可用、目标服务已启动，其他服务可以独立重启或单独运行

## 12. 启动后验证

服务启动完成后，建议按以下方式验证。

### 1. 健康检查

先检查 issuance-service：

```bash
curl http://localhost:18081/health
curl http://localhost:18081/db-health
```

如果 revocation-dispatcher 也暴露了健康检查接口，同样建议验证其可用性；如果没有统一健康接口，至少需要确认服务端口已监听且启动日志正常。

### 2. 执行 E2E 总控脚本

在项目根目录执行：

```bash
./scripts/run_all_e2e.sh
```

执行前应确保：

- `BASE_URL=http://localhost:18081`
- `REVOCATION_BASE_URL=http://localhost:18084`
- PostgreSQL 环境变量已设置

### 3. 当前 E2E 覆盖内容

`run_all_e2e.sh` 会依次执行：

- `scripts/verify_app_e2e_happy_path.sh`
- `scripts/verify_ecu_e2e_happy_path.sh`
- `scripts/verify_app_subject_mismatch.sh`
- `scripts/verify_ecu_subject_mismatch.sh`

这些脚本会覆盖：

- APP happy path
- ECU happy path
- APP subject mismatch
- ECU subject mismatch

### 4. 成功判断标准

可以按以下标准判断当前系统是否启动成功并可用于联调：

- `pki-issuance-service` 健康检查通过
- `pki-issuance-service` 数据库健康检查通过
- `run_all_e2e.sh` 全部执行完成
- 最终输出：

```text
[PASS] all E2E checks passed
```

如果上述条件都满足，说明当前环境已经具备继续联调和验证的基础能力。
