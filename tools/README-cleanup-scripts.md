# OpenShift 文件清理脚本

这些脚本用于清理OpenShift安装过程中产生的所有文件，帮助保持工作空间的整洁。

## 脚本说明

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

## 清理的文件类型

### 安装目录
- `work*/` - OpenShift安装工作目录
- `OCP-*/` - OCP项目目录（保留，包含有用脚本）

### 安装状态文件
- `.openshift_install*` - OpenShift安装器状态文件
- `.openshift_install.log` - 安装日志
- `.openshift_install_state.json` - 安装状态

### 集群API文件
- `.clusterapi_output/` - 集群API输出目录
- 包含Machine、AWSMachine、Secret等YAML文件

### 认证和证书
- `auth/` - 认证文件目录
  - `kubeconfig` - 集群访问配置
  - `kubeadmin-password` - 管理员密码
- `tls/` - TLS证书目录

### 元数据和配置
- `metadata.json` - 集群元数据
- `terraform.tfstate*` - Terraform状态文件
- `terraform.platform.auto.tfvars.json` - Terraform自动变量
- `terraform.tfvars.json` - Terraform变量文件

### 日志和临时文件
- `*.log` - 所有日志文件
- `*.tmp` - 临时文件
- `*.bak` - 备份文件
- `*.swp` - 交换文件
- `*~` - 波浪号备份文件

### 安装工件
- `log-bundle-*.tar.gz` - 日志包文件
- `*.pem` - PEM密钥文件

### OpenShift安装器和客户端
- `openshift-install` - OpenShift安装器二进制文件
- `openshift-install-*.tar.gz` - OpenShift安装器包
- `openshift-client-*.tar.gz` - OpenShift客户端包

### 发布和校验文件
- `release.txt` - 发布信息文件
- `sha256sum.txt` - SHA256校验和文件
- `pull-secret.json` - 拉取密钥JSON文件
- `pull-secret.txt` - 拉取密钥文本文件

## 安全特性

### 确认提示
两个脚本都会在删除前要求用户确认：
```
⚠️  This script will delete ALL OpenShift installation files in the workspace.
Are you sure you want to continue? (yes/no):
```

### 预览模式
使用`--dry-run`参数可以预览将要删除的文件，而不实际删除：
```bash
./cleanup-openshift-files.sh --dry-run
```

### 备份功能
带备份的脚本会：
- 创建带时间戳的备份目录
- 在删除前复制所有文件到备份目录
- 显示备份位置和大小
- 提供恢复指令

## 使用场景

### 开发环境清理
```bash
# 快速清理，不保留备份
./cleanup-openshift-files.sh
```

### 生产环境清理
```bash
# 安全清理，保留备份
./cleanup-openshift-files-with-backup.sh
```

### 测试前清理
```bash
# 先预览要删除的文件
./cleanup-openshift-files.sh --dry-run

# 确认无误后执行清理
./cleanup-openshift-files.sh
```

## 恢复文件

### 从备份恢复
如果使用带备份的脚本，可以通过以下方式恢复：
```bash
# 恢复所有文件
cp -r backup-20241201-143022/* ./

# 恢复特定目录
cp -r backup-20241201-143022/OCP-21582 ./
```

### 删除备份
确认文件已正确恢复后，可以删除备份：
```bash
rm -rf backup-20241201-143022
```

## 注意事项

### 保留的文件
脚本会保留以下重要文件：
- `tools/` 目录（工具脚本）
- `generate-metadata/` 目录（元数据生成工具）
- `OCP-*/` 目录（包含有用脚本的OCP项目目录）
- README文件和文档
- 配置模板和样例

### 不可逆操作
- 基础清理脚本的删除操作是不可逆的
- 建议在生产环境使用带备份的脚本
- 删除前请确认不再需要这些文件

### 权限要求
- 脚本需要读取和删除文件的权限
- 某些文件可能需要sudo权限（通常不需要）

## 与AWS资源清理的配合

清理本地文件后，通常还需要清理AWS资源：

```bash
# 检查AWS资源状态
./check-cluster-destroy-status.sh ./work1 us-east-2

# 删除CloudFormation栈
./delete-stacks-by-name.sh <stack-name-pattern>
```

## 故障排除

### 权限错误
如果遇到权限错误：
```bash
# 检查文件权限
ls -la <file-path>

# 修改权限
chmod 644 <file-path>
```

### 文件被占用
如果文件正在被使用：
```bash
# 检查进程
lsof <file-path>

# 终止相关进程
kill <pid>
```

### 备份空间不足
如果备份时空间不足：
```bash
# 检查磁盘空间
df -h

# 清理其他文件或使用基础清理脚本
./cleanup-openshift-files.sh
```
