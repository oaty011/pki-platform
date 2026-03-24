# 1. 背景与问题

`is_current` 字段最初用于在 `core_active_xx` 中标记某个主体当前的一张证书，并围绕该字段构建：

- 下证后将新证书置为 `is_current = true`
- 将旧证书批量改为 `is_current = false`
- 查询时优先按 `is_current = true` 取当前证书

随着 PKI Platform 生命周期模型演进，这个字段已经不再适合作为核心语义来源，主要问题如下：

- 状态冗余：`core_active_xx` 本身已经表达“仍在主集合中的可用证书”，再额外维护 `is_current` 会形成第二套状态。
- 语义冲突：`revoke / recover` 是按主集合迁移表达生命周期，而不是按行内状态切换表达；recover 后证书重新进入主集合，但不自动恢复 `current`，导致“可用集合”和“current 指针”长期冲突。
- 维护成本：写路径需要额外维护“清旧 current / 设新 current”，查询、脚本、DTO、mapper、schema、索引都要同时兼容这个字段。
- 一致性风险：并发 `sync-core-active` 时，`is_current` 语义天然引入双 current 风险和额外校验成本。

# 2. 目标

最终目标是彻底移除 `is_current`。

系统统一后的查询语义如下：

- `currentActiveCertificate = core_active` 主集合中的最新记录
- `latestIssuedCertificate = issue_fact` 中最近一次签发成功记录

这意味着：

- 默认查询不再依赖 `is_current = true`
- 主集合负责表达“当前仍可用的证书集合”
- 过程事实负责表达“最近签发事实”

# 3. 分阶段改造过程

## 阶段1：去写路径依赖

做了什么：

- `sync-core-active` 不再主动维护 `setCurrent(true)`
- 不再执行按 subject 清旧 current 的写前更新
- `recover` 写回时不再主动设置 `setCurrent(false)`

达到什么效果：

- 写路径业务语义已经不再依赖 `is_current`
- `is_current` 从“业务驱动字段”降级为“兼容列”

## 阶段2：去 issuance 读路径依赖

做了什么：

- `issuance-service` 默认查询不再按 `is_current = true` 取值
- 旧 `GET /app-certificates/current/{subjectId}`、`GET /ecu-certificates/current/{subjectId}` 的内部实现收口为 “latest active / 主集合最新记录”
- `POST /app-certificates/current/query`、`POST /ecu-certificates/current/query` 的默认主选结果统一为 `core_active` 最新记录
- mapper 方法命名从 `selectCurrent...` 收口为 `selectLatestActive...`

达到什么效果：

- 读路径主语义彻底脱离 `is_current`
- 默认查询与主集合语义统一

## 阶段3：去脚本断言依赖

做了什么：

- happy path、并发验证、最小幂等验证、SQL 验证等脚本逐步把主断言从 `is_current=true/false` 切到：
  - latest active
  - 主集合记录存在
  - recover 后重新进入 active 集合
  - 默认查询返回主集合最新记录

达到什么效果：

- 验证体系不再把 `is_current` 当作核心正确性判断
- 脚本与新查询语义保持一致

## 阶段4：去主服务模型/映射依赖

做了什么：

- `issuance-service` 的 `CoreActiveRecord` 删除 `current` 属性
- `revocation-dispatcher` 的 `CoreActiveRecord` 删除 `current` 属性
- 两个主服务的 mapper `resultMap` 不再映射 `is_current -> current`
- 读取 SQL 不再 `SELECT is_current`

达到什么效果：

- 主服务运行路径已经不再读取或映射 `is_current`
- `is_current` 不再进入主服务模型层

## 阶段5：domain / migration 收口

做了什么：

- `pki-app-domain-service` 与 `pki-ecu-domain-service` 的 `CoreActiveRecord` 删除 `current` 属性
- domain mapper / xml 不再映射 `is_current`
- domain 模块中未被使用的旧 current 方法与 SQL 一并删除

达到什么效果：

- domain 模块代码层也不再保留 `is_current` 语义
- 剩余阻塞点只剩 schema 与最终 SQL 去列

## 阶段6：最终 SQL 去列 + drop column

做了什么：

- `issuance-service` 与 `revocation-dispatcher` 的 `upsertToShard` SQL 彻底去掉 `is_current`
- domain 模块 `upsertToShard` SQL 彻底去掉 `is_current`
- 新增 forward migration：
  - `pki-app-domain-service` 的 `V6__drop_core_active_is_current.sql`
  - `pki-ecu-domain-service` 的 `V6__drop_core_active_is_current.sql`
- migration 删除：
  - `is_current` 列
  - `(subject_id, is_current)` 索引

达到什么效果：

- 运行路径中不再写入 `is_current`
- schema 中不再保留 `is_current`
- `is_current` 完成最终下线

# 4. 本次变更内容（最终状态）

本次变更完成后，系统达到以下最终状态：

- 已删除 `is_current` 列
- 已删除 `(subject_id, is_current)` 相关索引
- `issuance-service` 不再写、读、映射 `is_current`
- `revocation-dispatcher` 不再写、读、映射 `is_current`
- `app / ecu domain` 模块不再写、读、映射 `is_current`
- 核心 SQL、mapper、model、脚本已不再依赖该字段

系统不再维护“current 指针字段”，而是统一基于主集合与时间顺序表达默认查询语义。

# 5. 当前系统语义

## 默认查询（不带 certSerial）语义

默认查询语义为：

- 先按 `subjectId + organization` 命中 shard
- 再从对应 `core_active_xx` 中按 `created_at DESC, updated_at DESC` 取最新一条

默认查询返回的是：

- 当前主体在主集合中的最新记录

它不再依赖：

- `is_current = true`

## latestIssuedCertificate 语义

`latestIssuedCertificate` 的语义为：

- 当前主体在 `issue_fact` 中最近一次签发成功记录

它只看：

- `issue_fact`

它不看：

- `core_active`

## core_active 与 issue_fact 的职责划分

- `core_active_xx`：表达当前仍留在主集合中的可用证书集合
- `issue_fact`：表达签发过程与签发事实

两者职责已经明确分层：

- 默认查询看 `core_active`
- 最近签发视图看 `issue_fact`

# 6. 兼容性影响

## 是否影响接口

不影响接口路径。

现有接口路径保持不变，包括：

- `GET /app-certificates/current/{subjectId}`
- `GET /ecu-certificates/current/{subjectId}`
- `POST /app-certificates/current/query`
- `POST /ecu-certificates/current/query`

## DTO 字段保留情况

当前仍保留以下兼容字段名：

- `currentActiveCertificate`
- `isCurrent`

其中：

- `currentActiveCertificate` 字段名保留用于兼容既有调用方
- `isCurrent` 已不再承载主业务语义

## 是否需要客户端调整

不需要客户端因本次变更调整接口路径或调用方式。

但客户端如仍把 `isCurrent` 视为核心业务语义，需要同步改为：

- 以 `currentActiveCertificate` 表达默认主选结果
- 以 `latestIssuedCertificate` 表达最近签发结果

# 7. 数据库变更

本次新增 migration：

- `pki-app-domain-service/src/main/resources/db/migration/V6__drop_core_active_is_current.sql`
- `pki-ecu-domain-service/src/main/resources/db/migration/V6__drop_core_active_is_current.sql`

删除内容包括：

- `is_current` 列
- `(subject_id, is_current)` 索引

影响范围：

- `pki_app.core_active_00 ~ core_active_31`
- `pki_ecu.core_active_00 ~ core_active_31`

# 8. 验证方式

## SQL 验证（无 is_current）

确认列已删除：

```sql
SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE table_schema IN ('pki_app', 'pki_ecu')
  AND table_name LIKE 'core_active_%'
  AND column_name = 'is_current';
```

预期结果：

- 0 行

确认索引已删除：

```sql
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname IN ('pki_app', 'pki_ecu')
  AND tablename LIKE 'core_active_%'
  AND indexdef ILIKE '%is_current%';
```

预期结果：

- 0 行

## E2E 验证点

执行现有脚本：

- `scripts/run_all_e2e.sh`

重点确认：

- apply / sync-core-active / revoke / recover 仍正常
- 默认查询仍返回 latest active
- recover 后记录重新进入 active 集合

## 默认查询行为验证

重点确认：

- 不带 `certSerial` 的默认查询返回 `core_active` 最新记录
- `latestIssuedCertificate` 仍来自 `issue_fact`
- 两者语义清晰分离

# 9. 风险与回滚

## 如果 migration 未执行的风险

如果代码已升级，但数据库未执行删除列 migration，会出现以下问题：

- 代码层已不再写 `is_current`
- 但老 schema 仍保留 `NOT NULL` 列定义
- 主表写入将失败

因此本次变更必须保证：

- 代码变更与 migration 同步落地

## 回滚方案

本次变更不支持简单的代码层局部回滚。

如果需要回滚，必须整体回退：

- 主服务 mapper SQL
- domain mapper SQL
- schema migration

也就是说，回滚必须以“代码 + 数据库结构”一体回退执行。

# 10. 结论

`is_current` 已彻底下线。

系统当前语义已经统一为：

- 默认查询基于 `core_active` 最新记录
- 最近签发视图基于 `issue_fact` 最新记录
- 不再依赖额外的 `is_current` 状态字段表达主业务语义

本次变更完成后，查询、写入、脚本验证、domain 映射和 schema 设计均已完成统一收口。
