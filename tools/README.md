# OpenShift Tools Collection

这个目录包含了用于OpenShift集群部署、管理和清理的各种工具脚本。

## 工具分类

### 🚀 集群部署工具
- **VPC管理**: 创建、配置和管理AWS VPC
- **集群安装**: OpenShift集群安装配置和部署
- **堡垒主机**: 私有集群的堡垒主机配置

### 🔍 集群状态检查工具
- **销毁状态检查**: 验证集群销毁后无遗留资源
- **快速状态检查**: 快速检查集群销毁状态

### 🧹 清理工具
- **文件清理**: 清理OpenShift安装产生的文件
- **安全清理**: 带备份的文件清理

### 🔧 集群销毁工具
- **无metadata销毁**: 在没有原始metadata.json时销毁集群
- **元数据生成**: 生成集群销毁用的元数据文件

## 快速开始

### 集群部署
```bash
# 创建VPC
./create-vpc-stack.sh

# 获取VPC输出
./get-vpc-outputs.sh <stack-name>

# 创建堡垒主机（私有集群）
./create-bastion-host.sh <vpc-id> <subnet-id> <cluster-name>
```

### 集群销毁
```bash
# 标准销毁（有metadata.json）
openshift-install destroy cluster --dir ./work1

# 无metadata.json销毁
./destroy-cluster-without-metadata.sh <cluster-name> <aws-region>

# 验证销毁状态
./check-cluster-destroy-status.sh ./work1 <aws-region>
```

### 清理工作空间
```bash
# 预览清理（推荐先运行）
./cleanup-openshift-files.sh --dry-run

# 基础清理
./cleanup-openshift-files.sh

# 安全清理（带备份）
./cleanup-openshift-files-with-backup.sh
```

## 详细文档

- [完整工具指南](README-TOOLS.md) - 所有工具的详细使用说明
- [VPC模板说明](VPC_TEMPLATE_README.md)
- [私有集群部署指南](openshift-private-cluster-deployment-guide.md)
- [集群配置样例](CLUSTER_CONFIG_SAMPLES.md)
- [使用示例](EXAMPLES.md)

## 工具列表

### VPC和网络管理
| 脚本 | 功能 |
|------|------|
| `create-vpc-stack.sh` | 创建VPC CloudFormation栈 |
| `get-vpc-outputs.sh` | 获取VPC输出信息 |
| `update-vpc-stack.sh` | 更新VPC栈 |
| `tag-subnets.sh` | 为子网添加标签 |

### 集群部署
| 脚本 | 功能 |
|------|------|
| `create-bastion-host.sh` | 创建堡垒主机 |
| `configure-bastion-security.sh` | 配置堡垒主机安全组 |

### 集群状态检查
| 脚本 | 功能 |
|------|------|
| `check-cluster-destroy-status.sh` | 完整销毁状态检查 |
| `quick-check-destroy-status.sh` | 快速状态检查 |

### 集群销毁
| 脚本 | 功能 |
|------|------|
| `destroy-cluster-without-metadata.sh` | 无metadata销毁 |
| `generate-metadata-for-destroy.sh` | 生成销毁用metadata |

### 清理工具
| 脚本 | 功能 |
|------|------|
| `cleanup-openshift-files.sh` | 基础文件清理 |
| `cleanup-openshift-files-with-backup.sh` | 安全文件清理 |

### AWS资源管理
| 脚本 | 功能 |
|------|------|
| `delete-stacks-by-name.sh` | 按名称删除CloudFormation栈 |
| `find-stacks-by-name.sh` | 查找CloudFormation栈 |
| `get-stacks-status.sh` | 获取栈状态 |

## 配置文件

### 安装配置样例
- `install-config.sample.private.yaml` - 私有集群配置
- `install-config.sample.public.yaml` - 公共集群配置

### VPC模板
- `vpc-template-private-cluster.yaml` - 私有集群VPC模板
- `vpc-template-public-cluster.yaml` - 公共集群VPC模板
- `vpc-template-original.yaml` - 原始VPC模板

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

## 许可证

OpenShift is licensed under the Apache Public License 2.0. The source code for this
program is [located on github](https://github.com/openshift/installer).
