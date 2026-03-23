# PKI Platform 方案说明 / PKI Platform Overview

## 中文版

## 1. 项目背景与目标 / Background and Objectives

PKI Platform 面向车端与应用侧证书管理场景，目标是为 APP 与 ECU 提供统一、可演进的证书生命周期管理能力。平台需要解决证书申请、下发、主集合管理、吊销、恢复以及当前证书查询等核心问题，同时保证主体边界清晰、状态表达稳定、后续扩展路径明确。

平台当前聚焦两类业务对象：
- APP 证书
- ECU 证书

平台的生命周期管理目标包括：
- 提供统一的签发事实承载能力
- 提供按主体路由的主表管理能力
- 提供显式的吊销与恢复能力
- 提供面向主体的当前证书查询能力
- 为后续治理、清理与分发能力预留稳定边界

## 2. 系统整体架构 / System Architecture

当前系统由以下模块构成：

- `pki-issuance-service`：负责证书申请、签发事实管理、主表同步与当前查询能力。
- `pki-revocation-dispatcher`：负责吊销、恢复与吊销事件记录。
- `pki-app-domain-service`：承载 APP 域主表与域内数据模型。
- `pki-ecu-domain-service`：承载 ECU 域主表与域内数据模型。
- `scripts`：提供最小自动化验证与回归执行入口。
- `docs`：提供方案说明、验证说明与场景化验证文档。

整体架构上，签发、主表管理、当前查询、吊销恢复分别收口到相对清晰的职责边界中，形成以主体路由为核心的主业务路径。

## 3. 核心数据模型 / Core Data Model

平台当前围绕以下核心数据对象组织：

- `issue_fact`：承载每一次证书申请与签发结果的事实记录，是签发侧的稳定来源。
- `core_active_xx`：承载仍留在主表中的证书集合，是当前主集合与当前证书视图的核心数据来源。
- `revocation_current`：承载当前已被吊销、尚处于吊销集合中的证书记录。
- `revocation_outbox`：承载吊销与恢复事件的出站记录，为后续分发与治理提供边界。

这四类数据对象分别承担签发事实、主集合状态、吊销集合状态和事件记录的职责，避免将所有生命周期语义混杂在单一表中。

## 4. 主体路由模型 / Subject Routing Model

平台当前采用统一的主体路由模型：

- `subjectId + organization -> shard`

其中：
- APP 场景以 `appId` 或 `installId` 作为主体标识
- ECU 场景以 `deviceId` 作为主体标识

在此基础上，系统根据主体与组织信息计算目标分片，并将查询、吊销、恢复等动作直接路由到对应的主表分片。

当前不再将 locator 作为主业务路径中的核心路由依赖，主要原因包括：
- 路由直接绑定主体语义，降低中间索引耦合
- 路由规则更稳定，便于对外解释与长期维护
- 主体查询、吊销、恢复可以共享一致的路径模型
- 有助于减少“事实来源”和“路由来源”混杂带来的不一致风险

## 5. 证书生命周期流程 / Certificate Lifecycle

平台当前支持的主生命周期流程包括：

- `apply`：接收 APP 或 ECU 的证书申请，并形成签发事实记录。
- `sync-core-active`：将已完成签发的事实记录同步到对应主体所在分片的主表集合中。
- `current/query`：面向主体提供当前证书查询能力，支持聚合视图与按证书号过滤的列表视图。
- `revoke`：将目标证书从主表集合迁出，并写入吊销集合与事件记录。
- `recover`：将目标证书从吊销集合恢复回主表集合，并写入恢复事件记录。

整体上，主表集合负责表达“仍留在主表中的证书”，吊销与恢复通过集合迁移表达，而不是通过在主表中直接切换生命周期状态表达。

## 6. current/query 查询语义 / Query Semantics

`current/query` 当前有两种明确语义：

第一种是不带 `certSerial` 的聚合查询：
- 返回当前主体的基础路由信息
- 返回签发数量视图
- 返回最近一次签发证书视图
- 返回当前主集合中的 current 证书视图

第二种是带 `certSerial` 的匹配列表查询：
- 先根据 `subjectId + organization` 定位分片
- 只在该主体命中的分片范围内查询
- 返回当前主体下所有匹配该 `certSerial` 的证书列表
- 不再将结果伪装成唯一单证书视图

该查询模型明确保证：
- 不跨 subject 返回结果
- 不跨 shard 扫描结果
- 仅在当前主体路径内做必要回落

这使得未来在同一主体下存在多个不同 issuer 的同号证书时，查询语义仍然清晰可用。

## 7. 安全控制机制 / Security Controls

平台当前已经建立最小必要的安全控制机制：

- `subject mismatch` 校验：主体视角的吊销与恢复请求必须与证书真实所属主体一致。
- `recover domain` 校验：恢复请求必须与证书事实记录中的组织域一致。
- 跨主体防护：请求主体不能操作其他主体的证书。
- 跨域防护：APP 与 ECU 入口不能错误恢复到不属于本域的主表集合。

这些控制机制共同保证：
- 主体边界不被绕过
- 恢复路径不会跨域写回
- 主体路由模型具备最基本的安全闭环

## 8. 当前验证体系 / Validation Coverage

当前验证体系由脚本验证与文档验证两部分构成：

- `scripts`：提供 APP 与 ECU 的 happy path、主体不匹配失败路径以及总控回归入口。
- `docs`：提供场景化验证文档，覆盖主链路、失败路径与关键语义说明。

当前已覆盖的重点场景包括：
- APP happy path
- ECU happy path
- APP subject mismatch
- ECU subject mismatch
- 带 `certSerial` 的多记录匹配列表语义
- 同 shard 下非当前主体记录排除
- recover 的 organization/domain mismatch 场景

这套验证体系已经能够支撑当前阶段的联调与回归验证。

## 9. 当前系统边界与风险点 / Known Limitations

当前仍存在以下已知边界与风险点：

- 并发情况下可能出现双 current 风险
- outbox version 存在并发竞争风险
- revoke / recover 当前不是严格幂等语义
- locator 相关历史残留仍存在于部分模块和数据表中
- organization 当前仍采用固定值硬编码

## 10. 当前阶段结论 / Current Status

当前系统处于：

**可联调 / 预发布候选阶段（Ready for Integration / Pre-release Candidate）**

系统已经具备可对接、可验证、可说明的主链路能力，但仍保留少量并发与历史收口类风险，后续可在不改变当前主模型的前提下继续治理。

---

## English Version

## 1. 项目背景与目标 / Background and Objectives

PKI Platform is designed for certificate management across vehicle-side and application-side scenarios. Its goal is to provide a unified and evolvable lifecycle management capability for both APP and ECU certificates. The platform addresses the core problems of certificate application, issuance, primary-set management, revocation, recovery, and current-certificate query, while maintaining clear subject boundaries, stable state semantics, and a clear path for future evolution.

The platform currently focuses on two business domains:
- APP certificates
- ECU certificates

Its lifecycle management objectives are:
- to provide a stable source of issuance facts
- to provide subject-routed primary-set management
- to provide explicit revocation and recovery capabilities
- to provide subject-oriented current certificate query capabilities
- to reserve clear boundaries for future governance, cleanup, and dispatch capabilities

## 2. 系统整体架构 / System Architecture

The system currently consists of the following modules:

- `pki-issuance-service`: handles certificate application, issuance fact management, synchronization to the primary set, and current query capabilities.
- `pki-revocation-dispatcher`: handles revocation, recovery, and revocation event recording.
- `pki-app-domain-service`: carries the APP domain primary tables and domain data model.
- `pki-ecu-domain-service`: carries the ECU domain primary tables and domain data model.
- `scripts`: provides minimal automated verification and regression execution entry points.
- `docs`: provides architecture overviews, verification notes, and scenario-based validation documents.

At the architectural level, issuance, primary-set management, current query, and revocation/recovery are now converging toward relatively clear responsibility boundaries, forming a business path centered on subject routing.

## 3. 核心数据模型 / Core Data Model

The platform is currently organized around the following core data objects:

- `issue_fact`: stores the fact record for each certificate application and issuance result, serving as the stable source on the issuance side.
- `core_active_xx`: stores the certificate set that remains in the primary tables, serving as the core source for the primary-set view and the current certificate view.
- `revocation_current`: stores certificates that are currently revoked and still reside in the revocation set.
- `revocation_outbox`: stores outgoing revocation and recovery events, providing a boundary for future dispatch and governance.

These four data objects separate issuance facts, primary-set state, revocation-set state, and event recording, instead of mixing all lifecycle semantics into a single table.

## 4. 主体路由模型 / Subject Routing Model

The platform currently uses a unified subject routing model:

- `subjectId + organization -> shard`

Specifically:
- in the APP domain, `appId` or `installId` is used as the subject identifier
- in the ECU domain, `deviceId` is used as the subject identifier

Based on this model, the system computes the target shard from the subject and organization, and routes queries, revocation, and recovery directly to the corresponding primary-table shard.

Locator is no longer treated as the primary routing dependency in the main business path. The main reasons are:
- routing is bound directly to subject semantics, reducing intermediate index coupling
- the routing rule is more stable and easier to explain and maintain
- subject query, revocation, and recovery can share one consistent routing model
- it helps reduce inconsistency risks caused by mixing the “fact source” and the “routing source”

## 5. 证书生命周期流程 / Certificate Lifecycle

The platform currently supports the following primary lifecycle flows:

- `apply`: accepts APP or ECU certificate requests and creates issuance fact records.
- `sync-core-active`: synchronizes successfully issued records into the primary-set shard for the corresponding subject.
- `current/query`: provides subject-oriented current certificate query capability, supporting both aggregate view and certSerial-filtered list view.
- `revoke`: moves the target certificate out of the primary set and writes it into the revocation set and event log.
- `recover`: restores the target certificate from the revocation set back into the primary set and writes a recovery event record.

Overall, the primary set represents certificates that still remain in the primary tables, while revocation and recovery are expressed through set migration rather than by toggling lifecycle status inside the primary table.

## 6. current/query 查询语义 / Query Semantics

`current/query` currently has two explicit semantics:

The first is aggregate query without `certSerial`:
- returns basic routing information for the current subject
- returns issuance count view
- returns the latest issued certificate view
- returns the current certificate view from the active primary set

The second is matched-list query with `certSerial`:
- first resolves the shard from `subjectId + organization`
- only queries within the shard resolved for that subject
- returns all certificates under the current subject that match the given `certSerial`
- no longer pretends the result is a unique single-certificate view

This query model explicitly guarantees:
- no cross-subject results
- no cross-shard scan
- fallback remains limited to the current subject path only

This keeps the semantics clear even when multiple certificates with the same serial number exist under the same subject but with different issuers.

## 7. 安全控制机制 / Security Controls

The platform currently has the following minimum required security controls:

- `subject mismatch` validation: subject-oriented revoke and recover requests must match the actual certificate owner.
- `recover domain` validation: recovery requests must match the organization domain recorded in the certificate fact.
- cross-subject protection: one subject cannot operate on another subject’s certificate.
- cross-domain protection: APP and ECU entry points cannot restore certificates into the wrong domain’s primary set.

Together, these controls ensure:
- subject boundaries cannot be bypassed
- recovery cannot write back across domains
- the subject routing model has a minimum viable security closure

## 8. 当前验证体系 / Validation Coverage

The current validation system consists of scripted verification and documented verification:

- `scripts`: provides APP and ECU happy paths, subject mismatch failure paths, and a top-level regression entry point.
- `docs`: provides scenario-based verification documents covering the main flow, failure paths, and key semantic expectations.

The currently covered scenarios include:
- APP happy path
- ECU happy path
- APP subject mismatch
- ECU subject mismatch
- multi-record matched list semantics with `certSerial`
- exclusion of foreign-subject records in the same shard
- recover organization/domain mismatch scenario

This validation system is already sufficient to support the current stage of integration and regression verification.

## 9. 当前系统边界与风险点 / Known Limitations

The system still has the following known boundaries and risks:

- concurrent execution may still lead to double-current risk
- outbox version generation still has concurrency contention risk
- revoke / recover are not strictly idempotent at the moment
- locator-related historical residue still exists in some modules and tables
- organization values are still hardcoded

## 10. 当前阶段结论 / Current Status

The system is currently in:

**可联调 / 预发布候选阶段（Ready for Integration / Pre-release Candidate）**

The platform already provides a main flow that is explainable, integratable, and verifiable, while still retaining a limited number of concurrency and historical-cleanup risks that can be addressed without changing the current primary model.
