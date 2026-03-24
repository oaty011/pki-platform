# 查询语义重定义说明

状态说明：

- 本文主要记录查询语义重定义的设计讨论过程。
- 当前已落地实现请以 [issuance-phase1-summary.md](/Users/wuge/Desktop/CodeX/PKI Platform/docs/issuance-phase1-summary.md) 为准。
- 当前数据库中的 `is_current` 已下线，接口响应中的 `isCurrent` 也已从 `issuance-service` 下线。

## 1. 背景

当前 PKI Platform 已经形成了相对清晰的证书生命周期主模型：

- `issue_fact`：承载签发事实，是轻量化过程表
- `core_active_xx`：承载当前仍留在主集合中的证书
- `revocation_current`：承载当前已被吊销的证书
- `revocation_outbox`：承载吊销与恢复事件

在当前实现中，证书查询能力仍主要放在 `pki-issuance-service` 内。  
这在系统早期是合理的，因为签发、同步、当前查询最初属于同一条最小闭环。

但随着 `revoke / recover` 已经独立到 `pki-revocation-dispatcher`，以及 `issue_fact` 未来会被 cleanup、`core_active` 已经承担主集合语义，查询语义本身也需要从“签发视角的 current 语义”逐步收口为“生命周期集合视角的默认查询语义”。

因此，现在需要先用文档明确说明：

- 什么是“默认查询”
- 什么是“latest 查询”
- 为什么要弱化甚至去掉 `current`
- 这些变化对现有服务、脚本和后续演进意味着什么

## 2. 当前问题

当前查询语义存在以下现实问题：

### 2.1 `issue_fact` 不适合作为长期查询真源

`issue_fact` 当前已被收口为轻量化过程表，未来还会执行 30 天 cleanup。  
这意味着：

- `issue_fact` 适合承载签发事实和短期过程跟踪
- 不适合作为长期默认查询真源
- 更不适合作为长期“最新证书”语义的唯一依据

一旦过期记录被清理，`issue_fact` 中天然会丢失历史过程数据，无法继续稳定支撑默认查询。

### 2.2 `current` 语义过强，和实际业务含义不完全一致

当前 `core_active_xx` 中保留了 `is_current` 字段。  
它表达的是：

- 当前最后一次成功下证写入主表时，被标记为当前记录

但它并不天然等价于：

- 唯一允许被使用的证书
- 系统唯一默认应返回的证书

特别是在现在的模型下：

- 同一主体可以在主集合中保留多张证书
- `revoke / recover` 只做集合迁移，不自动重算 current
- recover 写回固定 `is_current=false`

这意味着 `current` 更像“一个当前指针”，而不是“唯一默认查询语义”。

### 2.3 `revoke / recover` 已经改变了查询语义基础

在新的生命周期模型中：

- `revoke` 会把证书从 `core_active` 迁出
- `recover` 会把证书迁回 `core_active`
- recover 后证书默认 `is_current=false`

因此，如果系统仍然把 `current` 当成默认查询主语义，会出现以下问题：

- recover 后证书已经重新可用，但默认查询可能看不到它
- 当前业务中的“可用集合”与“current 指针”语义被混为一谈
- 测试人员和开发人员容易误以为 `recover` 会自动恢复 current 身份

### 2.4 当前查询仍留在 issuance-service，职责已经开始漂移

当前 `current/query` 仍在 `pki-issuance-service` 中实现。  
这会带来一个结构性问题：

- issuance-service 理论上已经收口为轻量化下证过程服务
- 但当前查询实际上已经开始依赖 `core_active` 主集合语义
- 生命周期语义越来越重，而签发语义越来越轻

因此，查询服务边界已经出现评审价值，需要在语义上先说清楚，再决定是否迁移。

## 3. 默认查询语义重定义

建议把“默认查询”重新定义为：

### 默认查询 = 当前主体在主集合中的可用证书集合视图

它的核心含义应该是：

- 查询当前主体在 `core_active_xx` 中仍然存在的证书集合
- 默认只关心“仍在主集合中”的证书
- 不默认跨到 `revocation_current`
- 不默认依赖 `issue_fact`

换句话说，默认查询不再等价于“current 查询”，而应该等价于：

- 当前主体的“active set view”

在这个定义下：

- 被 `revoke` 的证书不会出现在默认查询中
- 被 `recover` 写回的证书会重新出现在默认查询中
- 即使它的 `is_current=false`，也仍然属于默认查询返回范围

这样更符合现在的生命周期模型，也更贴近“可用集合”的真实语义。

### 默认查询不应再以 `current` 为唯一结果

建议在评审语义上明确：

- `current` 是一个附加状态标记
- 默认查询返回的是主集合中的记录
- `current` 只作为集合内的一种补充属性

这可以避免把：

- “当前指针”
- “可用集合”
- “默认返回结果”

三种不同概念混成一个概念。

## 4. latest 查询语义重定义

建议把 `latest` 分成两个不同层次：

### 4.1 latest-issued

含义：

- 当前主体最近一次签发成功的证书事实
- 语义来源仍然是 `issue_fact`

但这个语义必须明确说明：

- 它是“最近签发事实”
- 不是“当前可用证书”
- 不是“默认证书”
- 不是“当前主集合中的最新记录”

由于 `issue_fact` 会被 cleanup，`latest-issued` 更适合：

- 短期过程观察
- 人工核对
- 补偿或排查时参考

不适合作为长期稳定查询。

### 4.2 latest-active

含义：

- 当前主体在 `core_active_xx` 中最新的一条主集合记录

这个语义更接近未来默认查询和生命周期视图的需要，因为它基于主集合，而不是基于过程表。

因此，从长期看，建议把 `latest` 查询语义逐步收口为：

- `latest-active` 优先
- `latest-issued` 仅保留为过程辅助视图

这样可以把“最近签发”和“当前仍可用”两个语义分开。

## 5. revoke / recover 对查询的影响

`revoke / recover` 对查询语义的影响非常直接：

### revoke 的影响

- 证书从 `core_active` 迁出
- 因此不应再出现在默认查询中
- 但仍然可能出现在过程事实中

这意味着：

- 默认查询和过程查询将天然分离

### recover 的影响

- 证书重新迁回 `core_active`
- 因此应重新回到默认查询范围
- 但 recover 后默认 `is_current=false`

这意味着：

- recover 后证书重新可见
- 但不意味着自动恢复 current 身份

因此，如果未来去掉对 `current` 的强依赖，查询语义会更加自然：

- 是否可见，看是否在主集合
- 是否被吊销，看是否迁出到吊销集合
- 是否当前，只是附加属性，不决定默认可见性

## 6. 去掉 current 对各服务的影响

### 对 issuance-service 的影响

如果弱化或逐步去掉 `current` 作为默认查询主语义，issuance-service 会更容易收口成：

- 申请
- 签发事实
- 同步
- 轻量短期查询

而不是继续承担越来越重的生命周期查询职责。

### 对 revocation-dispatcher 的影响

对 revocation-dispatcher 来说，影响较小。  
因为它本来就围绕：

- 集合迁移
- 吊销恢复事件

展开，而不是围绕 `current` 语义展开。

### 对 app / ecu domain service 的影响

如果未来查询语义更多基于主集合本身，那么 app / ecu domain 侧的意义会更清晰：

- 它们更像主集合与领域数据的承载侧

这对后续是否继续收口查询边界，会有正向影响。

### 对调用方的影响

如果继续保留 `current` 这个名字但弱化其含义，调用方容易误解。  
因此影响最大的是：

- 调用方接口认知
- 测试语义认知
- 文档表达

这也是为什么应该先用文档说明，再逐步调整实现和接口命名。

## 7. 查询是否应该迁出 issuance-service

从当前项目状态看，这个问题已经值得明确评审。

### 当前仍放在 issuance-service 的原因

目前仍然放在 issuance-service，有现实上的合理性：

- 当前已有实现已经可用
- current/query 逻辑已经存在
- E2E 脚本已基于现状建立

因此短期内不必强行迁移。

### 但从职责边界看，长期不适合一直留在 issuance-service

原因包括：

- issuance-service 已经被定义为轻量化下证过程服务
- 默认查询越来越依赖 `core_active` 主集合
- `revoke / recover` 已不在 issuance-service
- 查询语义已经明显更接近生命周期视图，而不是签发事实视图

因此，中长期更合理的方向是：

- 查询逐步迁出 issuance-service
- 迁向更接近生命周期集合的一侧

但这不需要现在立刻改代码，可以先统一语义，再逐步迁移。

## 8. 对现有测试脚本的影响

如果后续弱化或去掉 `current` 作为默认查询主语义，对现有测试脚本会产生直接影响。

### 影响一：happy path 中“第二次 current query”的解释需要调整

当前 happy path 已经说明：

- recover 写回后 `is_current=false`
- 第二次 current query 返回的是当前主体的 current 证书视图

如果默认查询改成“主集合视图”，脚本和文档就不能再继续把默认查询理解为“current 唯一结果”。

### 影响二：query 返回结构可能需要逐步从 current 导向 active set

当前已经存在：

- 不带 `certSerial` 的聚合查询
- 带 `certSerial` 的 `matchedCertificates`

这实际上已经在向“集合查询”靠近。  
因此现有脚本不是完全推倒重来，而是需要在语义上继续收口：

- 把 `currentActiveCertificate` 的解释弱化
- 把 `matchedCertificates` 的解释强化

### 影响三：cleanup 后不能继续依赖 issue_fact 做长期 latest 解释

如果测试脚本未来还把 `issue_fact` 当作长期 latest 依据，会和 30 天 cleanup 语义冲突。

因此脚本层面也需要跟随语义调整：

- `issue_fact` 更适合做过程验证
- `core_active` 更适合做默认可见性验证

## 9. 推荐实施顺序

建议按以下顺序推进，而不是一次性大改：

### 第一阶段：先在文档中统一语义

- 明确默认查询不等于 current
- 明确 latest-issued 与 latest-active 的区别
- 明确 recover 不自动恢复 current 身份

### 第二阶段：在现有接口中弱化 current 的中心地位

- 保留兼容结构
- 但在文档、测试和返回解释中，把主语义切换为主集合视图

### 第三阶段：逐步把 latest 语义分层

- `latest-issued` 保留为短期过程视图
- `latest-active` 作为长期主查询语义

### 第四阶段：评估查询是否迁出 issuance-service

- 当默认查询彻底以主集合为中心后
- 再决定是否迁到生命周期查询侧

这样可以避免在语义尚未统一时就直接做服务迁移。

## 10. 当前建议

基于当前项目现状，当前建议如下：

- 不要继续强化 `current` 作为默认查询主语义
- 默认查询应逐步重定义为“当前主体在主集合中的可用证书集合视图”
- `latest` 应拆分为 `latest-issued` 与 `latest-active` 两种语义
- 在文档和测试中先统一语义，再决定是否迁移查询服务
- 短期内可以继续保留查询在 issuance-service 中，但应明确这只是过渡状态

结论上，当前最重要的不是马上改代码，而是先把查询语义从“current 唯一视图”收口为“主集合视图 + 过程视图分层”，避免后续继续沿着旧语义扩展。
