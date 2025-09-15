# OpenShift Tools 完整指南

这个目录包含了用于OpenShift集群部署、管理和清理的各种工具脚本。

## 目录

- [集群销毁工具](#集群销毁工具)
- [文件清理工具](#文件清理工具)
- [VPC和网络管理](#vpc和网络管理)
- [集群部署工具](#集群部署工具)
- [AWS资源管理](#aws资源管理)
- [配置文件](#配置文件)
- [依赖要求](#依赖要求)
- [故障排除](#故障排除)

---

## 集群销毁工具

### 1. 标准销毁状态检查

#### check-cluster-destroy-status.sh
完整的集群销毁状态检查脚本，提供详细的检查报告。

**功能：**
- 从metadata.json提取集群信息（clusterName, clusterID, infraID）
- 检查AWS资源标签
- 验证CloudFormation栈状态
- 检查VPC状态
- 检查Route53记录
- 提供详细的资源状态信息

**使用方法：**
```bash
# 使用默认区域（us-east-1）
./check-cluster-destroy-status.sh ./work1

# 指定AWS区域
./check-cluster-destroy-status.sh ./work1 us-east-2
```

#### quick-check-destroy-status.sh
快速检查脚本，提供简洁的状态报告。

**功能：**
- 快速检查集群标签资源
- 检查CloudFormation栈
- 提供简洁的输出

**使用方法：**
```bash
# 使用默认区域
./quick-check-destroy-status.sh ./work1

# 指定AWS区域
./quick-check-destroy-status.sh ./work1 us-east-2
```

### 2. 无metadata.json销毁

#### destroy-cluster-without-metadata.sh
完整的自动化销毁脚本，包含所有步骤。

**功能：**
- 自动从AWS获取集群信息
- 生成metadata.json文件
- 验证集群资源存在
- 执行集群销毁
- 验证无遗留资源

**使用方法：**
```bash
# 基本用法
./destroy-cluster-without-metadata.sh <cluster-name> <aws-region>

# 指定输出目录
./destroy-cluster-without-metadata.sh <cluster-name> <aws-region> <output-directory>

# 示例
./destroy-cluster-without-metadata.sh qe-jialiu3 us-east-2
./destroy-cluster-without-metadata.sh my-cluster us-west-2 ./destroy-work
```

#### generate-metadata-for-destroy.sh
仅生成metadata.json文件的脚本。

**功能：**
- 从AWS获取集群信息
- 生成metadata.json文件
- 提供使用说明

**使用方法：**
```bash
# 基本用法
./generate-metadata-for-destroy.sh <cluster-name> <aws-region>

# 指定输出文件
./generate-metadata-for-destroy.sh <cluster-name> <aws-region> <output-file>

# 使用现有metadata.json
./generate-metadata-for-destroy.sh /path/to/metadata.json

# 示例
./generate-metadata-for-destroy.sh qe-jialiu3 us-east-2
./generate-metadata-for-destroy.sh my-cluster us-west-2 ./cleanup/metadata.json
```

### 销毁工具使用场景

#### 场景1: 标准销毁流程
```bash
# 1. 销毁集群
openshift-install destroy cluster --dir ./work1

# 2. 验证销毁状态
./check-cluster-destroy-status.sh ./work1 us-east-2

# 3. 快速检查
./quick-check-destroy-status.sh ./work1 us-east-2
```

#### 场景2: 无metadata.json销毁
```bash
# 1. 生成metadata.json
./generate-metadata-for-destroy.sh my-cluster us-east-2

# 2. 销毁集群
openshift-install destroy cluster --dir .

# 3. 验证销毁
./check-cluster-destroy-status.sh . us-east-2
```

#### 场景3: 完全自动化销毁
```bash
# 一键完成所有步骤
./destroy-cluster-without-metadata.sh my-cluster us-east-2
```

---

## 文件清理工具

### 1. cleanup-openshift-files.sh
基础清理脚本，直接删除所有OpenShift安装文件。

**功能：**
- 删除所有work*/目录
- 删除.openshift_install*文件
- 删除.clusterapi_output/目录
- 删除auth/目录
- 删除tls/目录
- 删除metadata.json文件
- 删除terraform文件
- 删除日志文件
- 删除临时文件
- 删除OpenShift安装器和客户端包
- 删除发布和校验文件
- 保留OCP项目目录（包含有用脚本）

**使用方法：**
```bash
# 预览模式（不实际删除）
./cleanup-openshift-files.sh --dry-run

# 实际清理
./cleanup-openshift-files.sh
```

### 2. cleanup-openshift-files-with-backup.sh
带备份功能的清理脚本，在删除前先备份文件。

**功能：**
- 与基础脚本相同的清理功能
- 在删除前自动备份所有文件
- 提供恢复选项
- 显示备份大小和位置

**使用方法：**
```bash
# 预览模式（不实际删除）
./cleanup-openshift-files-with-backup.sh --dry-run

# 实际清理（带备份）
./cleanup-openshift-files-with-backup.sh
```

### 清理的文件类型

#### 安装目录
- `work*/` - OpenShift安装工作目录
- `OCP-*/` - OCP项目目录（保留，包含有用脚本）

#### 安装状态文件
- `.openshift_install*` - OpenShift安装器状态文件
- `.openshift_install.log` - 安装日志
- `.openshift_install_state.json` - 安装状态

#### 集群API文件
- `.clusterapi_output/` - 集群API输出目录
- 包含Machine、AWSMachine、Secret等YAML文件

#### 认证和证书
- `auth/` - 认证文件目录
  - `kubeconfig` - 集群访问配置
  - `kubeadmin-password` - 管理员密码
- `tls/` - TLS证书目录

#### 元数据和配置
- `metadata.json` - 集群元数据
- `terraform.tfstate*` - Terraform状态文件
- `terraform.platform.auto.tfvars.json` - Terraform自动变量
- `terraform.tfvars.json` - Terraform变量文件

#### 日志和临时文件
- `*.log` - 所有日志文件
- `*.tmp` - 临时文件
- `*.bak` - 备份文件
- `*.swp` - 交换文件
- `*~` - 波浪号备份文件

#### 安装工件
- `log-bundle-*.tar.gz` - 日志包文件
- `*.pem` - PEM密钥文件

#### OpenShift安装器和客户端
- `openshift-install` - OpenShift安装器二进制文件
- `openshift-install-*.tar.gz` - OpenShift安装器包
- `openshift-client-*.tar.gz` - OpenShift客户端包

#### 发布和校验文件
- `release.txt` - 发布信息文件
- `sha256sum.txt` - SHA256校验和文件
- `pull-secret.json` - 拉取密钥JSON文件
- `pull-secret.txt` - 拉取密钥文本文件

### 清理工具使用场景

#### 场景1: 开发环境清理
```bash
# 快速清理，不保留备份
./cleanup-openshift-files.sh
```

#### 场景2: 生产环境清理
```bash
# 安全清理，保留备份
./cleanup-openshift-files-with-backup.sh
```

#### 场景3: 测试前清理
```bash
# 先预览要删除的文件
./cleanup-openshift-files.sh --dry-run

# 确认无误后执行清理
./cleanup-openshift-files.sh
```

---

## VPC和网络管理

### 1. create-vpc-stack.sh
创建VPC CloudFormation栈

### 2. get-vpc-outputs.sh
获取VPC输出信息

### 3. update-vpc-stack.sh
更新VPC栈

### 4. tag-subnets.sh
为子网添加标签

---

## 集群部署工具

### 1. create-bastion-host.sh
创建堡垒主机

### 2. configure-bastion-security.sh
配置堡垒主机安全组

---

## AWS资源管理

### 1. delete-stacks-by-name.sh
按名称删除CloudFormation栈

### 2. find-stacks-by-name.sh
查找CloudFormation栈

### 3. get-stacks-status.sh
获取栈状态

---

## 配置文件

### 安装配置样例
- `install-config.sample.private.yaml` - 私有集群配置
- `install-config.sample.public.yaml` - 公共集群配置

### VPC模板
- `vpc-template-private-cluster.yaml` - 私有集群VPC模板
- `vpc-template-public-cluster.yaml` - 公共集群VPC模板
- `vpc-template-original.yaml` - 原始VPC模板

---

## 依赖要求

### 必需工具
- `aws` CLI - AWS命令行工具
- `jq` - JSON处理工具
- `openshift-install` - OpenShift安装工具

### AWS权限
- EC2权限（VPC、实例管理）
- CloudFormation权限（栈管理）
- Resource Groups Tagging API权限（资源标签）
- Route53权限（DNS管理）

---

## 故障排除

### 常见问题
1. **权限错误**: 检查AWS凭证和权限
2. **资源未找到**: 确认AWS区域和资源名称
3. **销毁失败**: 检查资源状态，等待删除完成
4. **清理不完整**: 使用带备份的清理脚本

### 获取帮助
- 查看各工具的详细README文档
- 使用`--help`或`--dry-run`参数预览操作
- 检查AWS CloudTrail日志了解详细错误

### 安全特性

#### 确认提示
所有脚本都会在删除前要求用户确认：
```
⚠️  This script will delete ALL OpenShift installation files in the workspace.
Are you sure you want to continue? (yes/no):
```

#### 预览模式
使用`--dry-run`参数可以预览将要删除的文件，而不实际删除：
```bash
./cleanup-openshift-files.sh --dry-run
```

#### 备份功能
带备份的脚本会：
- 创建带时间戳的备份目录
- 在删除前复制所有文件到备份目录
- 显示备份位置和大小
- 提供恢复指令

### 恢复文件

#### 从备份恢复
如果使用带备份的脚本，可以通过以下方式恢复：
```bash
# 恢复所有文件
cp -r backup-20241201-143022/* ./

# 恢复特定目录
cp -r backup-20241201-143022/OCP-21582 ./
```

#### 删除备份
确认文件已正确恢复后，可以删除备份：
```bash
rm -rf backup-20241201-143022
```

### 注意事项

#### 保留的文件
脚本会保留以下重要文件：
- `tools/` 目录（工具脚本）
- `generate-metadata/` 目录（元数据生成工具）
- `OCP-*/` 目录（包含有用脚本的OCP项目目录）
- README文件和文档
- 配置模板和样例

#### 不可逆操作
- 基础清理脚本的删除操作是不可逆的
- 建议在生产环境使用带备份的脚本
- 删除前请确认不再需要这些文件

#### 权限要求
- 脚本需要读取和删除文件的权限
- 某些文件可能需要sudo权限（通常不需要）

### 与AWS资源清理的配合

清理本地文件后，通常还需要清理AWS资源：

```bash
# 检查AWS资源状态
./check-cluster-destroy-status.sh ./work1 us-east-2

# 删除CloudFormation栈
./delete-stacks-by-name.sh <stack-name-pattern>
```

---

## 许可证

OpenShift is licensed under the Apache Public License 2.0. The source code for this
program is [located on github](https://github.com/openshift/installer).
