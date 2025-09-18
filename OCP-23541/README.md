# OCP-23541 - [ipi-on-aws] [Hyperthreading] Create cluster with hyperthreading disabled on worker and master nodes

## 测试概述

这个测试用例验证在AWS上创建OpenShift集群时禁用超线程功能的能力。测试确保：

1. 集群安装时正确配置超线程禁用
2. 所有节点（master和worker）的超线程都被禁用
3. MachineConfigPool正确应用超线程禁用配置
4. 节点CPU信息显示超线程已禁用

## 测试步骤

### 步骤1: 创建install-config.yaml并禁用超线程
创建安装配置文件，在install-config.yaml中禁用超线程：
```yaml
compute:
- hyperthreading: Disabled
  name: worker
  platform:
    aws:
      type: m6i.xlarge
  replicas: 3
controlPlane:
  hyperthreading: Disabled
  name: master
  platform:
    aws:
      type: m6i.xlarge
  replicas: 3
```

### 步骤2: 安装集群
使用修改后的install-config.yaml安装集群：
```bash
./openshift-install create cluster --dir test
```

**预期结果：** 集群创建成功

### 步骤3: 验证超线程禁用状态
检查所有节点的超线程状态：
```bash
# 检查节点状态
oc get nodes

# 验证每个节点的CPU信息
oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo
```

**预期结果：**
- `siblings` 值等于 `cpu cores` 值
- 例如：`siblings: 4` 和 `cpu cores: 4` 表示超线程已禁用

### 步骤4: 验证MachineConfigPool
检查MachineConfigPool状态和配置：
```bash
oc get machineconfigpools
oc describe machineconfigpools
```

**预期结果：**
- MachineConfigPool状态为Updated
- 配置中包含 `99-master-disable-hyperthreading` 和 `99-worker-disable-hyperthreading`

## 自动化脚本

### setup-ocp-23541-test.sh

这个脚本自动化了测试的完整流程：

#### 功能
- 生成带有超线程禁用配置的install-config.yaml
- 自动安装OpenShift集群
- 验证所有节点的超线程禁用状态
- 检查MachineConfigPool配置
- 提供详细的测试结果报告

#### 使用方法
```bash
# 基本用法（使用默认参数）
./setup-ocp-23541-test.sh

# 自定义参数
./setup-ocp-23541-test.sh \
  --region us-west-2 \
  --cluster-name my-hyperthreading-test \
  --instance-type m5.2xlarge \
  --worker-count 3 \
  --master-count 3

# 仅生成配置文件（跳过安装）
./setup-ocp-23541-test.sh --skip-install
```

#### 参数说明
- `-r, --region`: AWS区域（默认：us-east-2）
- `-n, --cluster-name`: 集群名称（默认：hyperthreading-test）
- `-i, --instance-type`: 实例类型（默认：m6i.xlarge）
- `-w, --worker-count`: 工作节点数量（默认：3）
- `-m, --master-count`: 主节点数量（默认：3）
- `-d, --dir`: 安装目录（默认：test）
- `--skip-install`: 跳过集群安装，仅生成配置文件
- `-h, --help`: 显示帮助信息

### verify-hyperthreading.sh

这个脚本用于验证现有集群的超线程禁用状态：

#### 功能
- 验证所有节点或指定节点的超线程状态
- 检查MachineConfigPool配置
- 提供详细的CPU信息分析
- 生成验证报告

#### 使用方法
```bash
# 验证所有节点
./verify-hyperthreading.sh --kubeconfig /path/to/kubeconfig

# 验证特定节点
./verify-hyperthreading.sh --kubeconfig /path/to/kubeconfig --node ip-10-0-130-76.us-east-2.compute.internal

# 显示详细CPU信息
./verify-hyperthreading.sh --kubeconfig /path/to/kubeconfig --detailed
```

#### 参数说明
- `-k, --kubeconfig <path>`: Kubeconfig文件路径（必需）
- `-n, --node <node-name>`: 指定单个节点进行验证（可选）
- `-d, --detailed`: 显示详细的CPU信息（可选）
- `-h, --help`: 显示帮助信息

## 手动执行步骤

### 1. 准备环境
```bash
# 确保已安装必要工具
aws --version
openshift-install version
oc version

# 设置AWS凭证
aws configure

# 准备pull-secret.json文件
cp pull-secret.json OCP-23541/
```

### 2. 运行自动化脚本
```bash
cd OCP-23541
./setup-ocp-23541-test.sh --region us-east-2
```

### 3. 手动验证（可选）
```bash
# 设置kubeconfig
export KUBECONFIG=test/auth/kubeconfig

# 检查节点状态
oc get nodes

# 验证超线程状态
./verify-hyperthreading.sh --kubeconfig test/auth/kubeconfig --detailed
```

### 4. 清理资源
```bash
# 销毁集群
openshift-install destroy cluster --dir test
```

## 验证要点

### 超线程禁用验证
在节点上执行以下命令验证超线程状态：
```bash
oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo | grep -E "(siblings|cpu cores)"
```

**正确结果示例：**
```
siblings    : 4
cpu cores   : 4
```
- `siblings` = `cpu cores` 表示超线程已禁用

**错误结果示例：**
```
siblings    : 8
cpu cores   : 4
```
- `siblings` > `cpu cores` 表示超线程未禁用

### MachineConfigPool验证
```bash
oc get machineconfigpools -o wide
oc describe machineconfigpools master
oc describe machineconfigpools worker
```

**预期结果：**
- 状态为 `Updated`
- 配置名称包含超线程禁用配置
- 所有节点都已更新

### CPU信息分析
```bash
# 获取详细CPU信息
oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo

# 分析逻辑CPU和物理CPU
oc debug node/<node-name> -- chroot /host nproc
oc debug node/<node-name> -- chroot /host lscpu
```

## 故障排除

### 常见问题

1. **超线程未禁用**
   - 检查install-config.yaml中的hyperthreading配置
   - 验证MachineConfigPool状态
   - 确认节点已完全重启

2. **集群安装失败**
   - 检查AWS权限和配额
   - 验证实例类型是否支持
   - 查看openshift-install日志

3. **验证脚本失败**
   - 确认kubeconfig文件有效
   - 检查节点是否就绪
   - 验证debug pod权限

4. **MachineConfigPool未更新**
   - 等待配置应用完成
   - 检查节点状态
   - 查看MachineConfigOperator日志

### 调试命令
```bash
# 检查集群状态
oc get nodes -o wide
oc get machineconfigpools
oc get machineconfigs

# 查看配置详情
oc describe machineconfigpool master
oc describe machineconfigpool worker

# 检查节点事件
oc describe node <node-name>

# 查看MachineConfigOperator日志
oc logs -n openshift-machine-config-operator deployment/machine-config-operator
```

## 依赖要求

### 必需工具
- `aws` CLI - AWS命令行工具
- `openshift-install` - OpenShift安装工具
- `oc` - OpenShift客户端工具
- `jq` - JSON处理工具

### AWS权限
- EC2权限（实例管理）
- IAM权限（角色和策略管理）
- VPC权限（网络管理）
- Route53权限（DNS管理）

### 文件要求
- `pull-secret.json` - Red Hat拉取密钥
- SSH公钥（~/.ssh/id_rsa.pub）

## 相关文档

- [OpenShift IPI安装文档](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-installer.html)
- [OpenShift Machine Config Operator文档](https://docs.openshift.com/container-platform/latest/post_installation_configuration/machine-configuration-tasks.html)
- [AWS EC2实例类型文档](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
- [OCP-23541 JIRA](https://issues.redhat.com/browse/OCP-23541)

## 注意事项

1. **实例类型选择**：禁用超线程后，建议使用更大的实例类型以确保足够的CPU性能
2. **安装时间**：超线程禁用可能需要额外的配置时间，请耐心等待
3. **性能影响**：禁用超线程可能会影响某些工作负载的性能
4. **成本考虑**：使用更大的实例类型会增加AWS成本

## 测试结果示例

### 成功的验证输出
```
[INFO] 验证节点: ip-10-0-130-76.us-east-2.compute.internal
[INFO] 节点角色: worker
[INFO] CPU信息分析:
  - 逻辑CPU数量: 4
  - 物理CPU数量: 1
  - 每个物理CPU的siblings: 4
  - 每个物理CPU的cores: 4
[SUCCESS] ✅ 超线程已禁用 (siblings == cpu_cores)
```

### MachineConfigPool状态
```
NAME     CONFIG                                   UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-abc123                    True      False      False      3              3                   3                     0                      15m
worker   rendered-worker-def456                    True      False      False      3              3                   3                     0                      15m
```
