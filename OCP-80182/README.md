# OCP-80182 - Install a cluster in a VPC with only public subnets provided

## 测试用例描述

**OCP-80182**: [ipi-on-aws] Install a cluster in a vpc with only public subnets provided

### 测试步骤

1. **Step 1**: Create a VPC with only public subnets created, no private subnets, NAT and related resources, also enable the VPC option of allowing instances to associate with public IP automatically.

2. **Step 2**: Export `OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=True` ENV var

3. **Step 3**: Prepare install-config.yaml, only provide public subnets, something like:
   ```yaml
   platform:
     aws:
       region: ap-northeast-1
       subnets:
         - 'subnet-097d0a644ac6e0a80'
         - 'subnet-0da57a7c788688448'
         - 'subnet-0b5515fc2d1bd482a'
   ```

4. **Step 4**: Run installer to create the cluster.

### 预期结果

The installation get completed successfully.

## 测试环境要求

- AWS CLI 配置完成
- OpenShift Installer 工具
- 足够的AWS权限创建VPC、子网、EC2实例等资源

## 快速开始

### 1. 使用预创建的VPC模板

```bash
# 进入测试目录
cd /Users/weli/works/oc-swarm/my-openshift-workspace/OCP-80182

# 运行测试脚本
./run-ocp-80182-test.sh
```

### 2. 手动执行步骤

```bash
# 1. 创建VPC和公共子网
../tools/create-vpc-stack.sh \
  --stack-name ocp-80182-vpc \
  --template-file ../tools/vpc-template-public-only.yaml \
  --az-count 3

# 2. 获取子网ID
SUBNET_IDS=$(aws cloudformation describe-stacks \
  --stack-name ocp-80182-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text)

# 3. 设置环境变量
export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true

# 4. 创建install-config.yaml
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

# 5. 运行安装
openshift-install create cluster
```

## 验证步骤

### 1. 验证VPC配置

```bash
# 检查只有公共子网
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$(aws cloudformation describe-stacks --stack-name ocp-80182-vpc --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text)" \
  --query 'Subnets[*].[SubnetId,MapPublicIpOnLaunch]' \
  --output table

# 检查无NAT网关
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$(aws cloudformation describe-stacks --stack-name ocp-80182-vpc --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text)" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --output table
```

### 2. 验证集群安装

```bash
# 检查集群状态
export KUBECONFIG=auth/kubeconfig
oc get nodes
oc get clusteroperators
```

## 清理资源

```bash
# 删除OpenShift集群
openshift-install destroy cluster

# 删除VPC
aws cloudformation delete-stack --stack-name ocp-80182-vpc
aws cloudformation wait stack-delete-complete --stack-name ocp-80182-vpc
```

## 相关文件

- `run-ocp-80182-test.sh` - 自动化测试脚本
- `verify-vpc-config.sh` - VPC配置验证脚本
- `install-config-template.yaml` - install-config.yaml模板
- `cleanup.sh` - 清理脚本

## 注意事项

1. 确保VPC模板中的子网都设置了`MapPublicIpOnLaunch: true`
2. 不要创建私有子网和NAT网关
3. 确保所有子网都有到Internet Gateway的路由
4. 测试完成后及时清理资源以避免费用
