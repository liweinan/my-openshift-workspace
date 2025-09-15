# OpenShift Workspace Tools

这个工作空间包含了用于OpenShift集群部署、管理和清理的各种工具脚本。

## 工具分类

### 🚀 集群部署工具
- **VPC管理**: 创建、配置和管理AWS VPC
- **集群安装**: OpenShift集群安装配置和部署
- **堡垒主机**: 私有集群的堡垒主机配置

### 🔍 集群状态检查工具
- **销毁状态检查**: 验证集群销毁后无遗留资源
- **快速状态检查**: 快速检查集群销毁状态
- **资源验证**: 验证AWS资源标签和状态

### 🧹 清理工具
- **文件清理**: 清理OpenShift安装产生的文件
- **安全清理**: 带备份的文件清理
- **AWS资源清理**: 清理CloudFormation栈和AWS资源

### 🔧 元数据管理工具
- **元数据生成**: 生成集群元数据文件
- **无metadata销毁**: 在没有原始metadata.json时销毁集群
- **元数据验证**: 验证和修复元数据文件

## 快速开始

### 1. 集群部署
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

### 2. 集群销毁
```bash
# 标准销毁（有metadata.json）
openshift-install destroy cluster --dir ./work1

# 无metadata.json销毁
./tools/destroy-cluster-without-metadata.sh <cluster-name> <aws-region>

# 验证销毁状态
./tools/check-cluster-destroy-status.sh ./work1 <aws-region>
```

### 3. 清理工作空间
```bash
# 预览清理（推荐先运行）
./tools/cleanup-openshift-files.sh --dry-run

# 基础清理
./tools/cleanup-openshift-files.sh

# 安全清理（带备份）
./tools/cleanup-openshift-files-with-backup.sh
```

## 详细文档

### 集群部署
- [VPC模板说明](tools/VPC_TEMPLATE_README.md)
- [私有集群部署指南](tools/openshift-private-cluster-deployment-guide.md)
- [集群配置样例](tools/CLUSTER_CONFIG_SAMPLES.md)
- [使用示例](tools/EXAMPLES.md)

### 集群管理
- [集群销毁状态检查](tools/README-cluster-destroy-check.md)
- [无metadata销毁指南](tools/README-destroy-without-metadata.md)
- [元数据生成工具](generate-metadata/README-metadata-generator.md)

### 清理工具
- [文件清理脚本](tools/README-cleanup-scripts.md)

## 工具列表

### VPC和网络管理
| 脚本 | 功能 | 文档 |
|------|------|------|
| `create-vpc-stack.sh` | 创建VPC CloudFormation栈 | [VPC模板说明](tools/VPC_TEMPLATE_README.md) |
| `get-vpc-outputs.sh` | 获取VPC输出信息 | [使用示例](tools/EXAMPLES.md) |
| `update-vpc-stack.sh` | 更新VPC栈 | [VPC模板说明](tools/VPC_TEMPLATE_README.md) |
| `tag-subnets.sh` | 为子网添加标签 | [使用示例](tools/EXAMPLES.md) |

### 集群部署
| 脚本 | 功能 | 文档 |
|------|------|------|
| `create-bastion-host.sh` | 创建堡垒主机 | [私有集群指南](tools/openshift-private-cluster-deployment-guide.md) |
| `configure-bastion-security.sh` | 配置堡垒主机安全组 | [私有集群指南](tools/openshift-private-cluster-deployment-guide.md) |

### 集群状态检查
| 脚本 | 功能 | 文档 |
|------|------|------|
| `check-cluster-destroy-status.sh` | 完整销毁状态检查 | [销毁状态检查](tools/README-cluster-destroy-check.md) |
| `quick-check-destroy-status.sh` | 快速状态检查 | [销毁状态检查](tools/README-cluster-destroy-check.md) |

### 集群销毁
| 脚本 | 功能 | 文档 |
|------|------|------|
| `destroy-cluster-without-metadata.sh` | 无metadata销毁 | [无metadata销毁](tools/README-destroy-without-metadata.md) |
| `generate-metadata-for-destroy.sh` | 生成销毁用metadata | [无metadata销毁](tools/README-destroy-without-metadata.md) |

### 清理工具
| 脚本 | 功能 | 文档 |
|------|------|------|
| `cleanup-openshift-files.sh` | 基础文件清理 | [清理脚本](tools/README-cleanup-scripts.md) |
| `cleanup-openshift-files-with-backup.sh` | 安全文件清理 | [清理脚本](tools/README-cleanup-scripts.md) |

### AWS资源管理
| 脚本 | 功能 | 文档 |
|------|------|------|
| `delete-stacks-by-name.sh` | 按名称删除CloudFormation栈 | [使用示例](tools/EXAMPLES.md) |
| `find-stacks-by-name.sh` | 查找CloudFormation栈 | [使用示例](tools/EXAMPLES.md) |
| `get-stacks-status.sh` | 获取栈状态 | [使用示例](tools/EXAMPLES.md) |

### 元数据管理
| 脚本 | 功能 | 文档 |
|------|------|------|
| `generate-metadata-for-destroy.sh` | 生成销毁用元数据 | [元数据生成](generate-metadata/README-metadata-generator.md) |
| `quick-generate-metadata.sh` | 快速元数据生成 | [元数据生成](generate-metadata/README-metadata-generator.md) |

## 配置文件

### 安装配置样例
- `install-config.sample.private.yaml` - 私有集群配置
- `install-config.sample.public.yaml` - 公共集群配置

### VPC模板
- `vpc-template-private-cluster.yaml` - 私有集群VPC模板
- `vpc-template-public-cluster.yaml` - 公共集群VPC模板
- `vpc-template-original.yaml` - 原始VPC模板

## 使用场景

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

## 贡献

欢迎提交问题和改进建议。请确保：
1. 测试新功能
2. 更新相关文档
3. 遵循现有代码风格
4. 添加适当的错误处理

## 许可证

本项目遵循Apache 2.0许可证。
