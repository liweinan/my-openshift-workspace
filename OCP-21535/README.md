# RHEL Infrastructure Deployment

这个项目使用AWS CloudFormation自动化部署RHEL 8.10基础设施，包括VPC、安全组、子网和EC2实例。

## 项目结构

```
OCP-21535/
├── deploy-cloudformation.sh      # 主要部署脚本
├── ssh-connect.sh               # SSH连接脚本
├── rhel-infrastructure.yaml     # CloudFormation模板
├── cleanup-cloudformation.sh    # 清理脚本
├── create-key.sh               # 密钥对创建脚本
├── create-security-group.sh    # 安全组创建脚本
├── run-instance.sh             # 实例运行脚本
├── register-rhel.sh            # RHEL注册脚本
├── quick-rhel-setup.sh         # 快速RHEL设置脚本
├── check-username.sh           # 用户名检查脚本
├── simple-cleanup.sh           # 简单清理脚本
└── README.md                   # 项目文档
```

## 功能特性

- **自动化部署**: 一键部署完整的RHEL基础设施
- **密钥对管理**: 自动处理密钥对的创建、删除和更新
- **网络配置**: 自动创建VPC、子网、路由表和互联网网关
- **安全组**: 预配置SSH、HTTP、HTTPS和ICMP访问规则
- **实例配置**: 使用最新的RHEL 8.10 AMI
- **错误处理**: 完善的错误处理和回滚机制

## 系统要求

- AWS CLI已安装并配置
- 适当的AWS权限（EC2、CloudFormation、VPC等）
- Bash shell环境

## 快速开始

### 1. 部署基础设施

```bash
./deploy-cloudformation.sh
```

这个脚本会：
- 验证CloudFormation模板
- 清理现有的密钥对和堆栈
- 创建新的密钥对
- 部署CloudFormation堆栈
- 提供连接信息

### 2. 连接到RHEL实例

```bash
# 使用SSH连接脚本
./ssh-connect.sh

# 或直接使用SSH命令
ssh -i weli-rhel-key.pem ec2-user@<PUBLIC_IP>
```

### 3. 清理资源

```bash
# 删除CloudFormation堆栈
./cleanup-cloudformation.sh

# 或使用简单清理脚本
./simple-cleanup.sh
```

## 配置参数

### CloudFormation参数

| 参数 | 默认值 | 描述 |
|------|--------|------|
| KeyPairName | weli-rhel-key | EC2密钥对名称 |
| InstanceType | m5.xlarge | EC2实例类型 |
| RHELImageId | ami-07cf28d58cb5c8f73 | RHEL 8.10 AMI ID |
| VpcCidr | 10.0.0.0/16 | VPC CIDR块 |
| SubnetCidr | 10.0.1.0/24 | 子网 CIDR块 |

### 支持的实例类型

- t3.micro, t3.small, t3.medium, t3.large
- m5.large, m5.xlarge, m5.2xlarge
- c5.large, c5.xlarge

## 网络架构

```
Internet Gateway
       |
   Route Table
       |
   Public Subnet (10.0.1.0/24)
       |
   EC2 Instance (RHEL 8.10)
       |
   Security Group
   ├── SSH (22) - 0.0.0.0/0
   ├── HTTP (80) - 0.0.0.0/0
   ├── HTTPS (443) - 0.0.0.0/0
   └── ICMP - 0.0.0.0/0
```

## 安全组规则

| 类型 | 协议 | 端口 | 源 | 描述 |
|------|------|------|-----|------|
| SSH | TCP | 22 | 0.0.0.0/0 | SSH访问 |
| HTTP | TCP | 80 | 0.0.0.0/0 | HTTP访问 |
| HTTPS | TCP | 443 | 0.0.0.0/0 | HTTPS访问 |
| ICMP | ICMP | -1 | 0.0.0.0/0 | Ping测试 |

## 故障排除

### 常见问题

1. **密钥对冲突**
   - 脚本会自动处理密钥对的删除和重新创建
   - 如果仍有问题，手动删除AWS中的密钥对

2. **SSH连接失败**
   - 检查安全组是否允许SSH访问
   - 确认实例状态为"running"
   - 验证密钥文件权限 (chmod 400)

3. **堆栈创建失败**
   - 检查AWS权限
   - 查看CloudFormation事件日志
   - 确认AMI ID在目标区域可用

### 日志查看

```bash
# 查看CloudFormation事件
aws cloudformation describe-stack-events --stack-name weli-rhel-stack --region us-east-1

# 查看实例系统日志
aws ec2 get-console-output --instance-id <INSTANCE_ID> --region us-east-1
```

## 脚本说明

### deploy-cloudformation.sh
主要部署脚本，包含完整的部署流程：
- 模板验证
- 密钥对管理
- 堆栈创建/更新
- 输出信息显示

### ssh-connect.sh
SSH连接脚本，自动获取实例IP并建立连接。

### cleanup-cloudformation.sh
清理脚本，删除CloudFormation堆栈和相关资源。

## 版本信息

- **RHEL版本**: 8.10 (Ootpa)
- **AMI ID**: ami-07cf28d58cb5c8f73
- **默认实例类型**: m5.xlarge
- **默认用户**: ec2-user

## 注意事项

1. 部署前确保AWS CLI已正确配置
2. 实例启动后需要几分钟时间完成初始化
3. 密钥文件 `weli-rhel-key.pem` 需要保持安全，不要提交到版本控制
4. 生产环境建议使用更严格的网络访问控制

## 许可证

本项目遵循MIT许可证。
