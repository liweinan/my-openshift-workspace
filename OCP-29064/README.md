# OCP-29064: IPI 安装程序与无效 KMS 密钥配置

## 测试用例描述
**OCP-29064**: `[ipi-on-aws] IPI Installer with KMS configuration [invalid key]`

这个测试用例验证 OpenShift 安装程序能够正确处理无效的 KMS 密钥配置。通过在 KMS 密钥区域与集群区域不匹配的情况下尝试创建集群，验证安装程序能够正确识别并报告错误。

## 测试目标
- 验证 KMS 密钥区域与集群区域不匹配时的错误处理
- 确保安装程序能够正确识别无效的 KMS 配置
- 验证错误消息的准确性和有用性
- 测试集群销毁功能在失败场景下的工作状态

## 前置条件
- Linux 环境
- 已配置 AWS 凭证
- 已安装 `openshift-install` 工具
- 已配置 SSH 密钥对
- 已准备 pull-secret 文件
- 已安装 `jq` 和 `yq` 工具

## 测试步骤

### Step 1: 获取用户 ARN
```bash
# 获取当前用户的 ARN
aws sts get-caller-identity --output json | jq -r .Arn
# 输出示例: arn:aws:iam::301721915996:user/yunjiang
```

### Step 2: 创建 KMS 密钥
```bash
# 在 us-east-2 区域创建 KMS 密钥
aws kms create-key \
  --region us-east-2 \
  --description "testing" \
  --output json \
  --policy '{
    "Id": "key-consolepolicy-3",
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::301721915996:user/yunjiang"
        },
        "Action": "kms:*",
        "Resource": "*"
      }
    ]
  }'
```

**期待结果**: KMS 密钥创建成功，记录 KeyId 和 ARN。

### Step 3: 创建 install-config
```bash
# 创建 install-config.yaml
openshift-install create install-config --dir demo1
```

### Step 4: 修改配置文件，添加无效 KMS 密钥
```yaml
# 在 install-config.yaml 中添加 KMS 配置
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      rootVolume:
        kmsKeyARN: arn:aws:kms:us-east-2:301721915996:key/4f5265b4-16f7-4d85-9a09-7209ab0c8456
  replicas: 3
platform:
  aws:
    region: ap-northeast-1  # 注意：KMS 密钥在 us-east-2，但集群在 ap-northeast-1
```

**关键点**: KMS 密钥创建在 `us-east-2` 区域，但集群配置在 `ap-northeast-1` 区域，这会导致区域不匹配错误。

### Step 5: 尝试创建集群（应该失败）
```bash
# 尝试创建集群
openshift-install create cluster --dir demo1
```

**期待结果**: 集群创建失败，出现类似以下错误：
```
Error: Error waiting for instance (i-xxx) to become ready: Failed to reach target state. Reason: Client.InternalError: Client error on launch
```

### Step 6: 销毁集群
```bash
# 销毁集群（清理）
openshift-install destroy cluster --dir demo1
```

**期待结果**: 集群销毁成功。

## 自动化脚本

### 1. test-invalid-kms-key.sh
完整的自动化测试脚本，执行所有测试步骤：

```bash
# 基本用法
./test-invalid-kms-key.sh

# 自定义参数
./test-invalid-kms-key.sh \
  -k us-west-2 \
  -c us-east-1 \
  -n my-invalid-kms-test \
  -v
```

**参数说明**:
- `-w, --work-dir`: 工作目录（默认: demo1）
- `-n, --name`: 集群名称（默认: invalid-kms-test）
- `-k, --kms-region`: KMS 密钥区域（默认: us-east-2）
- `-c, --cluster-region`: 集群区域（默认: ap-northeast-1）
- `-d, --description`: KMS 密钥描述
- `-v, --verbose`: 详细输出
- `--no-cleanup`: 不清理测试环境

### 2. verify-kms-config.sh
专门验证 KMS 配置的脚本：

```bash
# 验证当前目录的 install-config.yaml
./verify-kms-config.sh

# 验证指定目录的配置
./verify-kms-config.sh -w /path/to/install/config

# 详细输出
./verify-kms-config.sh -v
```

## 验证标准

### 成功标准
1. **KMS 密钥创建成功**: 在指定区域成功创建 KMS 密钥
2. **配置修改正确**: install-config.yaml 正确包含 KMS 密钥 ARN
3. **区域不匹配**: KMS 密钥区域与集群区域不匹配
4. **集群创建失败**: 由于无效 KMS 配置导致集群创建失败
5. **错误消息准确**: 错误消息包含 "Client.InternalError" 或类似内容
6. **清理成功**: 能够成功销毁集群和清理资源

### 验证命令
```bash
# 检查 KMS 密钥
aws kms describe-key --region us-east-2 --key-id <key-id>

# 验证 install-config.yaml
./verify-kms-config.sh

# 检查集群状态
aws ec2 describe-instances --filters "Name=tag:Name,Values=<cluster-name>-*"
```

## 故障排除

### 常见问题

#### 1. KMS 密钥创建失败
```bash
# 检查 AWS 凭证
aws sts get-caller-identity

# 检查权限
aws iam get-user

# 检查区域可用性
aws kms list-keys --region us-east-2
```

#### 2. 集群创建意外成功
```bash
# 检查区域配置
yq eval '.platform.aws.region' install-config.yaml
yq eval '.controlPlane.platform.aws.rootVolume.kmsKeyARN' install-config.yaml

# 验证 KMS 密钥区域
aws kms describe-key --region us-east-2 --key-id <key-id>
```

#### 3. 错误消息不明确
```bash
# 检查详细日志
openshift-install create cluster --dir demo1 --log-level debug

# 检查 Terraform 日志
tail -f .openshift_install.log
```

#### 4. 清理失败
```bash
# 手动清理 KMS 密钥
aws kms schedule-key-deletion --region us-east-2 --key-id <key-id> --pending-window-in-days 7

# 手动清理 EC2 资源
aws ec2 describe-instances --filters "Name=tag:Name,Values=<cluster-name>-*"
```

## 清理步骤
```bash
# 销毁集群
openshift-install destroy cluster --dir demo1

# 清理 KMS 密钥
aws kms schedule-key-deletion \
  --region us-east-2 \
  --key-id <key-id> \
  --pending-window-in-days 7

# 清理工作目录
rm -rf demo1
```

## 相关测试用例
- **OCP-29060**: IPI 安装程序与 KMS 配置 [master]
- **OCP-29063**: IPI 安装程序与 KMS 配置 [worker]
- **OCP-29074**: AWS 手动模式配置 CCO

## 注意事项
1. **区域不匹配**: 确保 KMS 密钥区域与集群区域不同
2. **权限配置**: 确保 KMS 密钥策略包含正确的用户权限
3. **错误预期**: 这个测试期望集群创建失败
4. **清理重要**: 及时清理 KMS 密钥以避免费用
5. **日志分析**: 仔细分析错误日志以验证错误类型

## 实际应用价值
这个测试验证的功能对于：
- 理解 KMS 密钥区域限制
- 验证错误处理机制
- 确保配置验证的准确性
- 测试故障场景下的清理功能

对于生产环境的配置验证和错误处理非常重要。
