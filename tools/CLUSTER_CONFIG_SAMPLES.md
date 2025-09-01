# OpenShift 集群配置样例

本文档提供了 OpenShift 私有集群和公共集群的配置样例。

## 集群类型

### 1. 私有集群 (Private Cluster)

**特点：**
- 所有节点都在私有子网中
- 不需要公共子网
- 通过堡垒主机或 VPN 访问
- 更安全，但需要额外的网络配置

**配置要求：**
- 只需要私有子网
- `publish: Internal`
- 子网需要包含可用区信息

**使用场景：**
- 生产环境
- 需要高安全性的环境
- 有现有网络基础设施的环境

**配置文件：** `install-config.sample.private.yaml`

**VPC 模板：** `vpc-template.yaml`

### 2. 公共集群 (Public Cluster)

**特点：**
- 控制平面节点在私有子网中
- 工作节点可以在公共子网中
- 可以直接从互联网访问
- 部署和配置更简单

**配置要求：**
- 需要公共和私有子网
- `publish: External`
- 所有子网都需要包含可用区信息

**使用场景：**
- 开发和测试环境
- 快速部署和验证
- 不需要严格网络隔离的环境

**配置文件：** `install-config.sample.public.yaml`

**VPC 模板：** `vpc-template.yaml`

## 配置差异对比

| 配置项 | 私有集群 | 公共集群 |
|--------|----------|----------|
| 子网配置 | 仅私有子网 | 公共 + 私有子网 |
| publish | Internal | External |
| 网络访问 | 通过堡垒主机/VPN | 直接互联网访问 |
| 安全性 | 高 | 中等 |
| 部署复杂度 | 中等 | 简单 |

## 使用方法

### 生成配置

使用 `get-vpc-outputs.sh` 脚本生成相应的配置：

```bash
# 私有集群配置
./get-vpc-outputs.sh <stack-name> private

# 公共集群配置
./get-vpc-outputs.sh <stack-name> public

# 自动检测（推荐）
./get-vpc-outputs.sh <stack-name>
```

### 应用标签

使用 `tag-subnets.sh` 脚本为子网应用必要的标签：

```bash
./tag-subnets.sh <stack-name> <cluster-name>
```

## VPC 模板说明

**重要：** 私有集群和公共集群使用不同的 VPC 模板，主要区别在于 `MapPublicIpOnLaunch` 配置。

### 模板选择：

1. **私有集群**：使用 `vpc-template-private-cluster.yaml`
   - 公共子网：`MapPublicIpOnLaunch: "false"`（更安全）
   - 私有子网：`MapPublicIpOnLaunch: "false"`

2. **公共集群**：使用 `vpc-template-public-cluster.yaml`
   - 公共子网：`MapPublicIpOnLaunch: "true"`（支持公网访问）
   - 私有子网：`MapPublicIpOnLaunch: "false"`

### 所有模板都包含：
- **公共子网**：用于 NAT Gateway、Load Balancer、Bastion Host
- **私有子网**：用于 OpenShift 节点部署
- **完整的网络基础设施**：NAT Gateway、路由表、VPC Endpoints

## 注意事项

1. **OpenShift 4.19+ 要求**：所有子网都必须包含可用区信息
2. **子网数量**：建议每个可用区至少有一个公共和一个私有子网
3. **标签要求**：子网必须正确标记以支持 Kubernetes 网络功能
4. **网络规划**：确保子网 CIDR 不重叠且符合 OpenShift 要求
5. **VPC 统一性**：两种集群类型使用相同的 VPC 结构，区别仅在于 `install-config.yaml` 的配置

## 故障排除

### 常见错误

1. **"No public subnet provided"**：公共集群需要公共子网
2. **"Invalid subnet configuration"**：检查子网 ID 和可用区配置
3. **"Missing required tags"**：运行 `tag-subnets.sh` 脚本

### 验证步骤

1. 检查 VPC 输出：`./get-vpc-outputs.sh <stack-name>`
2. 验证子网标签：检查 AWS 控制台中的子网标签
3. 测试网络连通性：确保子网间可以正常通信
