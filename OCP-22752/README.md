# OCP-22752: 分步创建资产然后创建集群

## 测试用例描述
**OCP-22752**: `[ipi-on-aws] Create assets step by step then create cluster without customization`

这个测试用例验证 OpenShift 安装程序能够分步创建各种资产（install-config、manifests、ignition configs），然后成功创建集群，同时确保 SSH 密钥在 ignition 配置文件中正确分布。

## 测试目标
- 验证分步创建 OpenShift 资产的功能
- 确保 ignition 配置文件中 SSH 密钥的正确分布
- 验证集群创建过程中资产匹配消息
- 测试无自定义配置的集群创建

## 前置条件
- Linux 环境
- 已配置 AWS 凭证
- 已安装 `openshift-install` 工具
- 已配置 SSH 密钥对
- 已准备 pull-secret 文件

## 测试步骤

### Step 1: 生成公钥
```bash
# 从私钥生成公钥
ssh-keygen -y -f libra.pem > ~/.ssh/id_rsa.pub
```

### Step 2: 创建 install-config
```bash
# 进入安装程序目录
cd <dir where installer is downloaded>

# 创建 install-config
./openshift-install create install-config --dir test
```

### Step 3: 创建 manifests
```bash
# 创建 manifests
./openshift-install create manifests --dir test
```

### Step 4: 创建 ignition 配置
```bash
# 创建 ignition 配置
./openshift-install create ignition-configs --dir test
```

**期待结果**: bootstrap.ign/worker.ign/master.ign ignition 配置文件创建成功，无警告日志。

### Step 5: 验证 SSH 密钥分布
```bash
# 检查 master.ign - 应该不包含 SSH 密钥
cat test/master.ign | jq '.passwd'
# 期待结果: {}

# 检查 worker.ign - 应该不包含 SSH 密钥
cat test/worker.ign | jq '.passwd'
# 期待结果: {}

# 检查 bootstrap.ign - 应该包含 SSH 密钥
cat test/bootstrap.ign | jq '.passwd'
# 期待结果: 包含 core 用户的 SSH 密钥
```

### Step 6: 创建集群
```bash
# 创建集群
./openshift-install create cluster --dir test
```

**期待结果**: 集群创建成功，安装日志包含 "On-disk <asset.name> matches asset in state file" 消息。

## 自动化脚本

### 1. test-step-by-step-assets.sh
完整的自动化测试脚本，执行所有测试步骤：

```bash
# 基本用法
./test-step-by-step-assets.sh \
  -k ~/.ssh/id_rsa \
  -i ./openshift-install \
  -p pull-secret.json

# 自定义参数
./test-step-by-step-assets.sh \
  -k libra.pem \
  -i ./openshift-install \
  -p pull-secret.json \
  -n my-test-cluster \
  -r us-west-2 \
  -v
```

**参数说明**:
- `-k, --ssh-key`: SSH 私钥路径（必需）
- `-i, --installer`: openshift-install 二进制文件路径（必需）
- `-p, --pull-secret`: pull-secret 文件路径（必需）
- `-n, --name`: 集群名称（默认: step-by-step-test）
- `-r, --region`: AWS 区域（默认: us-east-2）
- `-w, --work-dir`: 工作目录（默认: test-step-by-step）
- `-v, --verbose`: 详细输出
- `--no-cleanup`: 不清理测试环境

### 2. verify-ignition-ssh-keys.sh
专门验证 ignition 配置文件中 SSH 密钥分布的脚本：

```bash
# 验证当前目录的 ignition 文件
./verify-ignition-ssh-keys.sh

# 验证指定目录的 ignition 文件
./verify-ignition-ssh-keys.sh -w /path/to/ignition/files

# 详细输出
./verify-ignition-ssh-keys.sh -v
```

## 验证标准

### 成功标准
1. **资产创建成功**: 所有步骤都能成功执行
2. **SSH 密钥分布正确**:
   - bootstrap.ign 包含 core 用户的 SSH 密钥
   - master.ign 不包含 SSH 密钥
   - worker.ign 不包含 SSH 密钥
3. **无警告日志**: ignition 配置创建过程中无警告
4. **资产匹配消息**: 集群创建日志包含资产匹配消息
5. **集群创建成功**: 集群能够成功创建并访问

### 验证命令
```bash
# 检查 ignition 文件存在
ls -la *.ign

# 验证 SSH 密钥分布
./verify-ignition-ssh-keys.sh

# 检查集群状态
KUBECONFIG=auth/kubeconfig oc get nodes
```

## 故障排除

### 常见问题

#### 1. SSH 密钥生成失败
```bash
# 检查私钥文件
ls -la libra.pem

# 检查私钥权限
chmod 600 libra.pem

# 重新生成公钥
ssh-keygen -y -f libra.pem > ~/.ssh/id_rsa.pub
```

#### 2. Ignition 配置创建失败
```bash
# 检查 install-config.yaml
cat install-config.yaml

# 检查 manifests 目录
ls -la manifests/

# 重新创建 ignition 配置
./openshift-install create ignition-configs --dir .
```

#### 3. SSH 密钥分布不正确
```bash
# 手动验证
cat bootstrap.ign | jq '.passwd.users[] | select(.name == "core") | .sshAuthorizedKeys'
cat master.ign | jq '.passwd'
cat worker.ign | jq '.passwd'
```

#### 4. 集群创建失败
```bash
# 检查安装日志
tail -f .openshift_install.log

# 检查 AWS 资源
aws ec2 describe-instances --filters "Name=tag:Name,Values=<cluster-name>-*"
```

## 清理步骤
```bash
# 销毁集群
./openshift-install destroy cluster --dir test

# 清理工作目录
rm -rf test
```

## 相关测试用例
- **OCP-22317**: 合并的 ignition 配置创建测试
- **OCP-21585**: 合并的集群创建测试
- **OCP-22316**: 合并的资产匹配验证测试
- **CORS-959**: SSH 密钥分布验证

## 注意事项
1. **SSH 密钥分布**: 确保 SSH 密钥只在 bootstrap.ign 中，不在 master.ign 或 worker.ign 中
2. **资产匹配**: 集群创建过程中应该看到资产匹配消息
3. **无警告日志**: ignition 配置创建应该无警告
4. **分步执行**: 严格按照步骤顺序执行，不要跳过任何步骤
5. **环境清理**: 测试完成后及时清理 AWS 资源

## 实际应用价值
这个测试验证的功能对于：
- 理解 OpenShift 安装过程的分步执行
- 验证 ignition 配置的正确性
- 确保 SSH 密钥安全分布
- 测试安装程序的资产管理功能

对于生产环境的部署和故障排除非常重要。
