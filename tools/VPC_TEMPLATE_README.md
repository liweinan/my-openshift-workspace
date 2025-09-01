# VPC 模板设计说明

## 概述

本项目使用三个不同的 VPC 模板来支持不同的 OpenShift 集群部署需求：
- **`vpc-template-original.yaml`** - 通用 VPC 模板，支持多种配置选项
- **`vpc-template-private-cluster.yaml`** - 私有集群专用 VPC 模板
- **`vpc-template-public-cluster.yaml`** - 公共集群专用 VPC 模板

## 为什么需要三个模板？

### 关键差异：MapPublicIpOnLaunch 配置

这个配置决定了子网中的实例是否自动分配公网 IP 地址，对于不同的集群类型有重要影响：

#### 1. 私有集群模板 (`vpc-template-private-cluster.yaml`)
```yaml
# 公共子网 - 不自动分配公网IP（更安全）
PublicSubnet:
  Properties:
    MapPublicIpOnLaunch: "false"  # 关键：false

# 私有子网 - 不自动分配公网IP
PrivateSubnet:
  Properties:
    MapPublicIpOnLaunch: "false"  # 关键：false
```

**特点：**
- 更安全的网络配置
- 公共子网仅用于 NAT Gateway、Load Balancer
- 所有节点都在私有子网中
- 通过堡垒主机或 VPN 访问

#### 2. 公共集群模板 (`vpc-template-public-cluster.yaml`)
```yaml
# 公共子网 - 自动分配公网IP
PublicSubnet:
  Properties:
    MapPublicIpOnLaunch: "true"   # 关键：true

# 私有子网 - 不自动分配公网IP
PrivateSubnet:
  Properties:
    MapPublicIpOnLaunch: "false"  # 关键：false
```

**特点：**
- 公共子网中的实例可以直接从互联网访问
- 支持公共 Load Balancer
- 部署和配置更简单
- 适合开发和测试环境

#### 3. 通用模板 (`vpc-template-original.yaml`)
```yaml
# 支持动态配置
PublicSubnet:
  Properties:
    MapPublicIpOnLaunch:
      !If [
        "DoOnlyPublicSubnets",
        "true",    # 如果只创建公共子网
        "false"    # 如果创建混合子网
      ]
```

**特点：**
- 最灵活的配置选项
- 支持多种部署场景
- 包含额外的功能（DHCP 选项、资源分享等）

## 模板选择指南

### 选择私有集群模板 (`vpc-template-private-cluster.yaml`) 当：
- 需要高安全性的生产环境
- 有现有的网络基础设施
- 通过堡垒主机或 VPN 访问集群
- 不需要公共子网中的实例直接访问互联网

### 选择公共集群模板 (`vpc-template-public-cluster.yaml`) 当：
- 开发和测试环境
- 需要快速部署和验证
- 需要公共 Load Balancer
- 公共子网中的实例需要直接互联网访问

### 选择通用模板 (`vpc-template-original.yaml`) 当：
- 需要特殊的网络配置
- 需要 DHCP 选项集
- 需要资源分享功能
- 需要更复杂的条件逻辑

## 网络架构对比

| 特性 | 私有集群 | 公共集群 | 通用模板 |
|------|----------|----------|----------|
| 公共子网 MapPublicIpOnLaunch | false | true | 可配置 |
| 私有子网 MapPublicIpOnLaunch | false | false | false |
| 安全性 | 高 | 中等 | 可配置 |
| 部署复杂度 | 中等 | 简单 | 复杂 |
| 灵活性 | 中等 | 中等 | 高 |

## 使用方法

### 创建私有集群 VPC
```bash
./create-vpc-stack.sh -s my-private-vpc -t vpc-template-private-cluster.yaml
```

### 创建公共集群 VPC
```bash
./create-vpc-stack.sh -s my-public-vpc -t vpc-template-public-cluster.yaml
```

### 创建通用 VPC
```bash
./create-vpc-stack.sh -s my-general-vpc -t vpc-template-original.yaml
```

## 总结

三个 VPC 模板的存在是为了满足不同的安全需求和部署场景：

1. **私有集群模板**：提供最高安全性，适合生产环境
2. **公共集群模板**：提供简单部署，适合开发测试
3. **通用模板**：提供最大灵活性，适合特殊需求

选择哪个模板取决于你的具体需求、安全要求和部署环境。
