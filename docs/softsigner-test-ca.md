# Soft Signer 测试证书链说明

状态说明：

- `soft signer` 第一版接入结果请以 [issuance-phase1-summary.md](/Users/wuge/Desktop/CodeX/PKI Platform/docs/issuance-phase1-summary.md) 为准。
- 本文只说明本地测试 CA 材料如何生成与验证，不代表业务默认配置已经自动接入这些材料。

## 用途

本说明文档配套：

- [generate_softsigner_test_ca.sh](/Users/wuge/Desktop/CodeX/PKI Platform/scripts/generate_softsigner_test_ca.sh)

用于本地开发和测试环境生成一套可供 `soft signer` 验证使用的测试证书链材料。

该脚本只用于：

- 本地 `openssl` 证书链校验
- `soft signer` 配置联调
- APP / ECU 主题样例验证

它不会修改任何业务代码，也不会自动接入 `pki-issuance-service` 主流程。

## 生成了哪些文件

脚本默认输出到：

- `.local/test-ca/`

生成文件包括：

- `root-ca.key.pem`
- `root-ca.cert.pem`
- `sub-ca.key.pem`
- `sub-ca.csr.pem`
- `sub-ca.cert.pem`
- `sub-ca.chain.pem`
- `sub-ca.p12`
- `ecu-leaf.key.pem`
- `ecu-leaf.csr.pem`
- `ecu-leaf.cert.pem`
- `ecu-leaf.fullchain.pem`
- `app-leaf.key.pem`
- `app-leaf.csr.pem`
- `app-leaf.cert.pem`
- `app-leaf.fullchain.pem`

以及用于签发扩展的辅助 `.ext` 文件。

## Root / Intermediate / Leaf 分别代表什么

### Root CA

固定主题：

- `CN=DFMC Root CA TEST,O=DFMC_CA,C=CN`

作用：

- 作为测试环境中的根 CA
- 自签名
- 用于签发 Intermediate CA

### Intermediate CA

固定主题：

- `CN=DFMC Sub CA TEST,O=DFMC_CA,C=CN`

作用：

- 由 Root CA 签发
- 作为 `soft signer` 本地验证时的 issuer
- 用于签发 APP / ECU 的 Leaf 样例证书

### Leaf

脚本会生成至少两张样例叶子证书：

- ECU Leaf
- APP Leaf

ECU 主题格式：

- `CN=deviceid,OU=TBOX,O=DFMC ECU,C=CN`
- `CN=deviceid,OU=IVI,O=DFMC ECU,C=CN`
- `CN=deviceid,OU=HAD,O=DFMC ECU,C=CN`
- `CN=deviceid,OU=SGW,O=DFMC ECU,C=CN`
- `CN=deviceid,OU=OBU,O=DFMC ECU,C=CN`

APP 主题格式：

- `CN=installid/appid,OU=Vehicle Controller SDK,O=DFMC,C=CN`

作用：

- 用于校验 leaf 是否被 Intermediate 正确签发
- 用于验证主题与扩展是否符合当前模板规则

## 如何验证证书链

### 验证 Intermediate 是否被 Root 正确签发

执行：

```bash
openssl verify -CAfile .local/test-ca/root-ca.cert.pem .local/test-ca/sub-ca.cert.pem
```

预期：

- 返回 `OK`

### 验证 Leaf 是否被 Intermediate 正确签发

验证 ECU Leaf：

```bash
openssl verify -CAfile .local/test-ca/root-ca.cert.pem -untrusted .local/test-ca/sub-ca.cert.pem .local/test-ca/ecu-leaf.cert.pem
```

验证 APP Leaf：

```bash
openssl verify -CAfile .local/test-ca/root-ca.cert.pem -untrusted .local/test-ca/sub-ca.cert.pem .local/test-ca/app-leaf.cert.pem
```

预期：

- 都返回 `OK`

### 检查主题与扩展

可使用：

```bash
openssl x509 -in .local/test-ca/ecu-leaf.cert.pem -text -noout
openssl x509 -in .local/test-ca/app-leaf.cert.pem -text -noout
```

重点观察：

- Subject
- Issuer
- Basic Constraints
- Key Usage
- Extended Key Usage
- Subject Key Identifier
- Authority Key Identifier

## 如何用于 soft signer 本地验证

### 方式一：PKCS12

脚本会生成：

- `.local/test-ca/sub-ca.p12`

可以把它接到 `soft signer` 配置：

```bash
export PKI_ISSUANCE_SIGNER_SOFT_KEYSTORE_PATH=.local/test-ca/sub-ca.p12
export PKI_ISSUANCE_SIGNER_SOFT_KEYSTORE_PASSWORD=changeit
export PKI_ISSUANCE_SIGNER_SOFT_KEY_ALIAS=softsigner-sub-ca
export PKI_ISSUANCE_SIGNER_SOFT_KEY_PASSWORD=changeit
```

### 方式二：PEM

也可以直接使用：

- `.local/test-ca/sub-ca.cert.pem`
- `.local/test-ca/sub-ca.key.pem`

对应环境变量：

```bash
export PKI_ISSUANCE_SIGNER_SOFT_CERTIFICATE_PATH=.local/test-ca/sub-ca.cert.pem
export PKI_ISSUANCE_SIGNER_SOFT_PRIVATE_KEY_PATH=.local/test-ca/sub-ca.key.pem
export PKI_ISSUANCE_SIGNER_SOFT_SIGNATURE_ALGORITHM=SHA256withRSA
```

## 脚本参数

脚本支持最少量参数与环境变量：

- 第一个位置参数：输出目录
- `ECU_DEVICE_ID`
- `ECU_OU`
- `APP_SUBJECT_ID`
- `P12_PASSWORD`

示例：

```bash
ECU_DEVICE_ID=device-001 ECU_OU=IVI APP_SUBJECT_ID=app-001 ./scripts/generate_softsigner_test_ca.sh
```

## 说明

- 这些证书材料只用于本地开发和测试
- 不应提交到仓库
- 不应直接作为生产 CA 或生产 signer 材料使用
- 不会自动接入 `issuance-service` 主流程
