# Public Only VPC Template

这个CloudFormation模板专门用于创建只包含公共子网的VPC，满足OCP-80182和OCP-81178测试用例的要求。

## 特性

- ✅ **仅创建公共子网** - 不创建私有子网
- ✅ **无NAT网关** - 不创建NAT网关和相关资源
- ✅ **自动公共IP分配** - 所有子网都设置`MapPublicIpOnLaunch: true`
- ✅ **Internet Gateway** - 提供互联网访问
- ✅ **S3 VPC Endpoint** - 优化S3访问性能
- ✅ **多AZ支持** - 支持1-3个可用区
- ✅ **灵活CIDR配置** - 可自定义VPC和子网CIDR

## 使用方法

### 1. 基本部署

```bash
aws cloudformation create-stack \
  --stack-name openshift-public-vpc \
  --template-body file://vpc-template-public-only.yaml \
  --parameters ParameterKey=AvailabilityZoneCount,ParameterValue=3
```

### 2. 自定义参数部署

```bash
aws cloudformation create-stack \
  --stack-name openshift-public-vpc \
  --template-body file://vpc-template-public-only.yaml \
  --parameters \
    ParameterKey=VpcCidr,ParameterValue=10.0.0.0/16 \
    ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
    ParameterKey=SubnetBits,ParameterValue=12 \
    ParameterKey=AllowedAvailabilityZoneList,ParameterValue="us-east-1a,us-east-1b,us-east-1c"
```

### 3. 获取输出信息

```bash
# 获取VPC ID
aws cloudformation describe-stacks \
  --stack-name openshift-public-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
  --output text

# 获取公共子网ID列表
aws cloudformation describe-stacks \
  --stack-name openshift-public-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text
```

## 参数说明

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| VpcCidr | String | 10.0.0.0/16 | VPC的CIDR块 |
| AvailabilityZoneCount | Number | 3 | 可用区数量 (1-3) |
| SubnetBits | Number | 12 | 每个子网的位数 (/20) |
| AllowedAvailabilityZoneList | CommaDelimitedList | "" | 允许的可用区列表 |

## 输出说明

| 输出名 | 说明 |
|--------|------|
| VpcId | VPC ID |
| PublicSubnetIds | 公共子网ID列表 (逗号分隔) |
| PublicRouteTableId | 公共路由表ID |
| AvailabilityZones | 使用的可用区列表 |
| PublicSubnet1Id | 公共子网1 ID |
| PublicSubnet2Id | 公共子网2 ID (如果存在) |
| PublicSubnet3Id | 公共子网3 ID (如果存在) |

## 与OpenShift集成

### 1. 用于OCP-80182测试

```bash
# 1. 创建VPC
aws cloudformation create-stack \
  --stack-name ocp-80182-vpc \
  --template-body file://vpc-template-public-only.yaml \
  --parameters ParameterKey=AvailabilityZoneCount,ParameterValue=3

# 2. 等待创建完成
aws cloudformation wait stack-create-complete --stack-name ocp-80182-vpc

# 3. 获取子网ID
SUBNET_IDS=$(aws cloudformation describe-stacks \
  --stack-name ocp-80182-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text)

# 4. 设置环境变量
export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true

# 5. 创建install-config.yaml
cat > install-config.yaml << EOF
apiVersion: v1
baseDomain: example.com
metadata:
  name: ocp-80182-test
platform:
  aws:
    region: us-east-1
    subnets:
$(echo $SUBNET_IDS | tr ',' '\n' | sed 's/^/      - /')
pullSecret: '{"auths":{"quay.io":{"auth":"..."}}}'
sshKey: |
  ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...
EOF
```

### 2. 用于OCP-81178测试

```bash
# 1. 创建VPC (与OCP-80182相同)
aws cloudformation create-stack \
  --stack-name ocp-81178-vpc \
  --template-body file://vpc-template-public-only.yaml

# 2. 设置环境变量
export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true

# 3. 运行IPI安装
openshift-install create cluster
```

## 验证

### 1. 验证只有公共子网

```bash
# 检查子网类型
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" \
  --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0],MapPublicIpOnLaunch]' \
  --output table
```

### 2. 验证无NAT网关

```bash
# 检查NAT网关
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=vpc-xxxxxxxxx" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --output table
```

### 3. 验证路由表

```bash
# 检查路由表
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" \
  --query 'RouteTables[*].[RouteTableId,Routes[*].[DestinationCidrBlock,GatewayId]]' \
  --output table
```

## 清理

```bash
# 删除CloudFormation堆栈
aws cloudformation delete-stack --stack-name openshift-public-vpc

# 等待删除完成
aws cloudformation wait stack-delete-complete --stack-name openshift-public-vpc
```

## 注意事项

1. **安全组配置**: 确保安全组允许必要的入站和出站流量
2. **DNS设置**: VPC已启用DNS支持和DNS主机名
3. **子网大小**: 默认每个子网为/20 (4096个IP地址)
4. **成本优化**: 不创建NAT网关可以节省成本
5. **网络性能**: 所有流量都通过Internet Gateway，确保网络延迟可接受

## 与CI模板的区别

| 特性 | 此模板 | CI模板 |
|------|--------|--------|
| 私有子网 | ❌ 不创建 | ✅ 条件创建 |
| NAT网关 | ❌ 不创建 | ✅ 条件创建 |
| 参数复杂度 | 🟢 简单 | 🟡 复杂 |
| 用途 | 🎯 专门用于public-only | 🔄 通用模板 |
| 维护性 | 🟢 易于维护 | 🟡 需要理解条件逻辑 |
