# OCP-29781 CI失败分析报告 - 正确版本

## 🔍 问题概述

基于CI日志分析，OCP-29781多CIDR测试失败的主要原因是VPC子网标签配置不正确。

**CI Job**: `aws-ipi-multi-cidr-arm-f14`  
**失败时间**: 2025-09-09T14:40:36Z  
**失败原因**: 子网标签缺失导致OpenShift安装器拒绝使用这些子网

## 🚨 核心错误

```
level=error msg=failed to fetch Metadata: failed to load asset "Install Config": failed to create install config: platform.aws.vpc.subnets: Forbidden: additional subnets [subnet-0139fe13fff4eeff0 subnet-08dc7ce7f6967dc2d subnet-09bafffa992546fdf subnet-0a917eee79a1949ec] without tag prefix kubernetes.io/cluster/ are found in vpc vpc-00a6f792a4739069f of provided subnets. Please add a tag kubernetes.io/cluster/unmanaged to those subnets to exclude them from cluster installation or explicitly assign roles in the install-config to provided subnets
```

## 📋 问题详细分析

### 1. VPC创建成功
- ✅ CloudFormation堆栈创建成功
- ✅ 堆栈ID: `arn:aws:cloudformation:ap-northeast-1:301721915996:stack/ci-op-4tl7yiy2-34190-vpc/7c5ae3e0-8d8a-11f0-8468-0a37c9653281`

### 2. 子网标签问题
- ❌ VPC中存在未标记的子网
- ❌ 缺少Kubernetes必需的标签
- ❌ 子网角色未明确指定

### 3. 配置格式问题
- ⚠️ 使用了已弃用的配置格式
- ⚠️ `platform.aws.subnets` → `platform.aws.vpc.subnets`

## 🛠️ 正确的修复方案

### 1. VPC模板保持原样
**重要**: VPC模板不应该包含cluster-specific标签，因为创建VPC时还不知道cluster name。

### 2. 使用tag-subnets.sh脚本
**解决方案**: 在VPC创建后，使用`tag-subnets.sh`脚本为子网打标签。

```bash
# 为集群1的子网打标签
../../tools/tag-subnets.sh ocp29781-vpc cluster1

# 为集群2的子网打标签  
../../tools/tag-subnets.sh ocp29781-vpc cluster2
```

### 3. Install Config修复

**问题**: 使用已弃用的配置格式
**解决**: 使用新的VPC子网配置格式

```yaml
# 修复前
platform:
  aws:
    region: ap-northeast-1
    subnets: ['subnet-0001294fd6a01e6b2', 'subnet-0c1434250038d5185']

# 修复后
platform:
  aws:
    region: ap-northeast-1
    vpc:
      subnets:
      - id: subnet-0fd59c515317ccb4b
        role: private
      - id: subnet-0f2233e736be9697a
        role: public
```

### 4. 使用create-bastion-host.sh脚本
**确认**: `create-bastion-host.sh`脚本确实在public subnet中创建bastion host，符合测试要求。

## 🔧 正确的测试流程

### 1. 创建VPC（使用原始模板）
```bash
aws cloudformation create-stack \
  --stack-name ocp29781-vpc \
  --template-body file://01_vpc_multiCidr.yaml \
  --parameters \
    ParameterKey=VpcCidr2,ParameterValue=10.134.0.0/16 \
    ParameterKey=VpcCidr3,ParameterValue=10.190.0.0/16
```

### 2. 为子网打标签
```bash
# 使用tag-subnets.sh脚本
../../tools/tag-subnets.sh ocp29781-vpc cluster1
../../tools/tag-subnets.sh ocp29781-vpc cluster2
```

### 3. 创建集群
使用正确的install-config格式创建两个集群。

### 4. 创建Bastion Host
```bash
# 使用create-bastion-host.sh脚本
../../tools/create-bastion-host.sh $VPC_ID $PUBLIC_SUBNET_ID $CLUSTER_NAME
```

## 🎯 预期结果

修复后，测试应该能够：
1. ✅ 成功创建VPC和子网
2. ✅ 使用tag-subnets.sh脚本为子网打标签
3. ✅ 成功创建集群1（使用10.134.0.0/16 CIDR）
4. ✅ 成功创建集群2（使用10.190.0.0/16 CIDR）
5. ✅ 在public subnet中创建bastion host
6. ✅ 验证网络隔离
7. ✅ 验证安全组配置

## 📊 关键修复点

1. **VPC模板保持原样** - 不包含cluster-specific标签
2. **使用tag-subnets.sh脚本** - 在VPC创建后为子网打标签
3. **使用create-bastion-host.sh脚本** - 在public subnet中创建bastion
4. **正确的install-config格式** - 使用`platform.aws.vpc.subnets`

## 🔗 相关链接

- [CI Job日志](https://storage.googleapis.com/qe-private-deck/logs/periodic-ci-openshift-verification-tests-main-installation-nightly-4.20-aws-ipi-multi-cidr-arm-f14/1965423507990908928/build-log.txt)
- [OpenShift VPC配置文档](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-vpc.html)
- [AWS子网标签要求](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-vpc.html#installation-aws-vpc-tags_installing-aws-vpc)
