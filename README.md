# OpenShift Workspace Tools

这个工作空间包含了用于OpenShift集群部署、管理和清理的各种工具脚本。

## 🚀 快速开始

### 集群部署
```bash
# 创建VPC
./tools/create-vpc-stack.sh

# 获取VPC输出
./tools/get-vpc-outputs.sh <stack-name>

# 创建堡垒主机（私有集群）
./tools/create-bastion-host.sh <vpc-id> <subnet-id> <cluster-name>

# 安装集群
openshift-install create cluster --dir ./work1
```

### 集群销毁
```bash
# 标准销毁（有metadata.json）
openshift-install destroy cluster --dir ./work1

# 无metadata.json销毁
./tools/destroy-cluster-without-metadata.sh <cluster-name> <aws-region>

# 验证销毁状态
./tools/check-cluster-destroy-status.sh ./work1 <aws-region>
```

### 清理工作空间
```bash
# 预览清理（推荐先运行）
./tools/cleanup-openshift-files.sh --dry-run

# 基础清理
./tools/cleanup-openshift-files.sh

# 安全清理（带备份）
./tools/cleanup-openshift-files-with-backup.sh
```

### 清理孤立资源
```bash
# 查找集群信息
./tools/find-cluster-info.sh weli-test

# 删除孤立资源（dry-run模式）
./tools/delete-orphaned-cluster-resources.sh weli-test --dry-run

# 实际删除孤立资源
./tools/delete-orphaned-cluster-resources.sh weli-test
```

## 📋 工具分类

### 🔍 集群状态检查工具
- **`check-cluster-destroy-status.sh`** - 完整的集群销毁状态检查，提供详细的检查报告
- **`quick-check-destroy-status.sh`** - 快速检查脚本，提供简洁的状态报告

**功能特点：**
- 智能资源状态分析（区分真正遗留资源 vs 正在删除的资源）
- 减少误报，提供更准确的状态判断
- 彩色输出和更好的用户体验
- 检查AWS资源标签、CloudFormation栈、VPC、Route53记录

### 🧹 清理工具
- **`cleanup-openshift-files.sh`** - 基础清理脚本，直接删除所有OpenShift安装文件
- **`cleanup-openshift-files-with-backup.sh`** - 带备份功能的清理脚本，在删除前先备份文件

**清理的文件类型：**
- 安装目录：`work*/`、`.openshift_install*`、`.clusterapi_output/`
- 认证和证书：`auth/`、`tls/`
- 元数据和配置：`metadata.json`、`terraform.tfstate*`
- 日志和临时文件：`*.log`、`*.tmp`、`*.bak`
- OpenShift安装器：`openshift-install`、`openshift-install-*.tar.gz`
- 发布文件：`release.txt`、`sha256sum.txt`、`pull-secret.json`

### 🔧 集群销毁工具
- **`destroy-cluster-without-metadata.sh`** - 完整的自动化销毁脚本，包含所有步骤
- **`generate-metadata-for-destroy.sh`** - 生成metadata.json文件的脚本

**功能：**
- 自动从AWS获取集群信息
- 生成metadata.json文件
- 验证集群资源存在
- 执行集群销毁
- 验证无遗留资源

### 🗑️ 孤立资源清理工具
- **`delete-orphaned-cluster-resources.sh`** - 删除孤立集群资源的脚本
- **`find-cluster-info.sh`** - 查找集群信息的脚本

**功能：**
- 删除Route53记录
- 删除CloudFormation栈
- 删除S3存储桶
- 删除EC2实例和卷
- 删除负载均衡器
- 支持dry-run模式预览

### 🏗️ VPC和网络管理
- **`create-vpc-stack.sh`** - 创建VPC CloudFormation栈
- **`get-vpc-outputs.sh`** - 获取VPC输出信息
- **`update-vpc-stack.sh`** - 更新VPC栈
- **`tag-subnets.sh`** - 为子网添加标签

### 🖥️ 集群部署工具
- **`create-bastion-host.sh`** - 创建堡垒主机
- **`configure-bastion-security.sh`** - 配置堡垒主机安全组

### ☁️ AWS资源管理
- **`delete-stacks-by-name.sh`** - 按名称删除CloudFormation栈
- **`find-stacks-by-name.sh`** - 查找CloudFormation栈
- **`get-stacks-status.sh`** - 获取栈状态

## 📁 元数据管理工具

### generate-metadata-for-destroy.sh
用于在没有原始 `metadata.json` 文件的情况下，动态生成 `metadata.json` 文件来销毁 OpenShift 集群。

**使用方法：**
```bash
# 使用集群名称（从AWS VPC标签搜索）
./tools/generate-metadata-for-destroy.sh <cluster-name> <aws-region>

# 使用现有metadata.json文件
./tools/generate-metadata-for-destroy.sh /path/to/metadata.json

# 指定输出文件
./tools/generate-metadata-for-destroy.sh <cluster-name> <aws-region> <output-file>
```

**生成的metadata.json格式：**
```json
{
  "clusterName": "my-cluster",
  "clusterID": "12345678-1234-1234-1234-123456789012",
  "infraID": "my-cluster-abc123",
  "aws": {
    "region": "us-east-1",
    "identifier": [
      {"kubernetes.io/cluster/my-cluster-abc123": "owned"},
      {"sigs.k8s.io/cluster-api-provider-aws/cluster/my-cluster-abc123": "owned"}
    ]
  }
}
```

## 🎯 使用场景

### 场景1: 标准集群部署
```bash
# 1. 创建VPC
./tools/create-vpc-stack.sh

# 2. 获取配置
./tools/get-vpc-outputs.sh my-vpc-stack

# 3. 安装集群
openshift-install create cluster --dir ./work1

# 4. 使用集群
export KUBECONFIG=./work1/auth/kubeconfig
oc get nodes
```

### 场景2: 私有集群部署
```bash
# 1. 创建VPC（私有）
./tools/create-vpc-stack.sh

# 2. 创建堡垒主机
./tools/create-bastion-host.sh vpc-xxx subnet-xxx my-cluster

# 3. 在堡垒主机上安装集群
# (复制文件到堡垒主机后执行)
openshift-install create cluster --dir .
```

### 场景3: 集群销毁和清理
```bash
# 1. 销毁集群
openshift-install destroy cluster --dir ./work1

# 2. 验证销毁状态
./tools/check-cluster-destroy-status.sh ./work1 us-east-1

# 3. 清理本地文件
./tools/cleanup-openshift-files.sh

# 4. 清理AWS资源（如有遗留）
./tools/delete-stacks-by-name.sh my-cluster
```

### 场景4: 无metadata.json销毁
```bash
# 1. 生成metadata.json
./tools/generate-metadata-for-destroy.sh my-cluster us-east-1

# 2. 销毁集群
openshift-install destroy cluster --dir .

# 3. 验证销毁
./tools/check-cluster-destroy-status.sh . us-east-1
```

### 场景5: 清理孤立资源
```bash
# 1. 查找集群信息
./tools/find-cluster-info.sh weli-test

# 2. 预览要删除的资源
./tools/delete-orphaned-cluster-resources.sh weli-test --dry-run

# 3. 实际删除孤立资源
./tools/delete-orphaned-cluster-resources.sh weli-test
```

## 📋 配置文件

### 安装配置样例
- `tools/install-config.sample.private.yaml` - 私有集群配置
- `tools/install-config.sample.public.yaml` - 公共集群配置

### VPC模板
- `tools/vpc-template-private-cluster.yaml` - 私有集群VPC模板
- `tools/vpc-template-public-cluster.yaml` - 公共集群VPC模板
- `tools/vpc-template-original.yaml` - 原始VPC模板

## ⚙️ 依赖要求

### 必需工具
- `aws` CLI - AWS命令行工具
- `jq` - JSON处理工具
- `openshift-install` - OpenShift安装工具

### AWS权限
- EC2权限（VPC、实例管理）
- CloudFormation权限（栈管理）
- Resource Groups Tagging API权限（资源标签）
- Route53权限（DNS管理）
- S3权限（存储桶管理）
- ELB权限（负载均衡器管理）

## 🔧 故障排除

### 常见问题
1. **权限错误**: 检查AWS凭证和权限
2. **资源未找到**: 确认AWS区域和资源名称
3. **销毁失败**: 检查资源状态，等待删除完成
4. **清理不完整**: 使用带备份的清理脚本
5. **误报遗留资源**: 检查脚本现在能智能区分真正遗留资源与正在删除的资源，减少误报

### 获取帮助
- 使用`--help`或`--dry-run`参数预览操作
- 检查AWS CloudTrail日志了解详细错误
- 查看各工具的详细使用说明

### 安全特性

#### 确认提示
所有删除脚本都会在删除前要求用户确认：
```
⚠️  This script will delete ALL resources associated with cluster 'cluster-name'
Are you sure you want to continue? (yes/no):
```

#### 预览模式
使用`--dry-run`参数可以预览将要删除的资源，而不实际删除：
```bash
./tools/delete-orphaned-cluster-resources.sh weli-test --dry-run
```

#### 备份功能
带备份的脚本会：
- 创建带时间戳的备份目录
- 在删除前复制所有文件到备份目录
- 显示备份位置和大小
- 提供恢复指令

## 📚 详细文档

### 工具特定文档
- [VPC模板说明](tools/VPC_TEMPLATE_README.md)
- [私有集群部署指南](tools/openshift-private-cluster-deployment-guide.md)
- [集群配置样例](tools/CLUSTER_CONFIG_SAMPLES.md)
- [使用示例](tools/EXAMPLES.md)

### OCP项目文档
- [OCP-21535](OCP-21535/README.md) - RHEL基础设施设置
- [OCP-21984](OCP-21984/README.md) - 集群工作节点配置

## 🤝 贡献

欢迎提交问题和改进建议。请确保：
1. 测试新功能
2. 更新相关文档
3. 遵循现有代码风格
4. 添加适当的错误处理

## 📄 许可证

本项目遵循Apache 2.0许可证。
OpenShift is licensed under the Apache Public License 2.0. The source code for this program is [located on github](https://github.com/openshift/installer).