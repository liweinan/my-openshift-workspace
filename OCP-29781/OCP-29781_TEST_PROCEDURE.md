# OCP-29781 测试流程 - 正确版本

## 🎯 测试目标
在共享VPC中创建两个OpenShift集群，使用不同的隔离CIDR块，验证网络隔离。

## 📋 测试步骤

### 步骤1: 创建VPC和子网
```bash
# 使用原始模板创建VPC（不包含cluster标签）
aws cloudformation create-stack \
  --stack-name ocp29781-vpc \
  --template-body file://01_vpc_multiCidr.yaml \
  --parameters \
    ParameterKey=VpcCidr2,ParameterValue=10.134.0.0/16 \
    ParameterKey=VpcCidr3,ParameterValue=10.190.0.0/16 \
    ParameterKey=AvailabilityZoneCount,ParameterValue=3

# 等待VPC创建完成
aws cloudformation wait stack-create-complete --stack-name ocp29781-vpc
```

### 步骤2: 获取VPC和子网信息
```bash
# 获取VPC ID
VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ocp29781-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
  --output text)

# 获取子网ID
SUBNETS_CIDR1=$(aws cloudformation describe-stacks \
  --stack-name ocp29781-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetsIdsForCidr`].OutputValue' \
  --output text)

SUBNETS_CIDR2=$(aws cloudformation describe-stacks \
  --stack-name ocp29781-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetsIdsForCidr2`].OutputValue' \
  --output text)

SUBNETS_CIDR3=$(aws cloudformation describe-stacks \
  --stack-name ocp29781-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetsIdsForCidr3`].OutputValue' \
  --output text)

echo "VPC ID: $VPC_ID"
echo "CIDR1 Subnets: $SUBNETS_CIDR1"
echo "CIDR2 Subnets: $SUBNETS_CIDR2" 
echo "CIDR3 Subnets: $SUBNETS_CIDR3"
```

### 步骤3: 为集群1打标签
```bash
# 使用tag-subnets.sh脚本为集群1的子网打标签
# 假设集群1使用CIDR2 (10.134.0.0/16)
CLUSTER1_NAME="cluster1"
CLUSTER1_PRIVATE_SUBNET=$(echo $SUBNETS_CIDR2 | cut -d',' -f1)
CLUSTER1_PUBLIC_SUBNET=$(echo $SUBNETS_CIDR2 | cut -d',' -f2)

# 为集群1的子网打标签
../../tools/tag-subnets.sh ocp29781-vpc $CLUSTER1_NAME
```

### 步骤4: 创建集群1
```bash
# 创建集群1的install-config
cat > install-config-cluster1.yaml << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
compute:
- architecture: arm64
  hyperthreading: Enabled
  name: worker
  platform: 
    aws:
      type: m6g.xlarge
  replicas: 3
controlPlane:
  architecture: arm64
  hyperthreading: Enabled
  name: master
  platform: 
    aws:
      type: m6g.xlarge
  replicas: 3
metadata:
  creationTimestamp: null
  name: $CLUSTER1_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.134.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ap-northeast-1
    vpc:
      subnets:
      - id: $CLUSTER1_PRIVATE_SUBNET
        role: private
      - id: $CLUSTER1_PUBLIC_SUBNET
        role: public
publish: External
pullSecret: 'YOUR_PULL_SECRET_HERE'
sshKey: |
  YOUR_SSH_PUBLIC_KEY_HERE
EOF

# 创建集群1
mkdir -p cluster1-install
cp install-config-cluster1.yaml cluster1-install/install-config.yaml
openshift-install create cluster --dir=cluster1-install
```

### 步骤5: 创建Bastion Host（用于集群1）
```bash
# 使用create-bastion-host.sh脚本在public subnet中创建bastion
../../tools/create-bastion-host.sh $VPC_ID $CLUSTER1_PUBLIC_SUBNET $CLUSTER1_NAME
```

### 步骤6: 验证集群1健康状态
```bash
# 等待集群安装完成
openshift-install wait-for install-complete --dir=cluster1-install

# 验证集群节点
export KUBECONFIG=cluster1-install/auth/kubeconfig
oc get nodes
```

### 步骤7: 为集群2打标签
```bash
# 为集群2的子网打标签
# 假设集群2使用CIDR3 (10.190.0.0/16)
CLUSTER2_NAME="cluster2"
CLUSTER2_PRIVATE_SUBNET=$(echo $SUBNETS_CIDR3 | cut -d',' -f1)
CLUSTER2_PUBLIC_SUBNET=$(echo $SUBNETS_CIDR3 | cut -d',' -f2)

# 为集群2的子网打标签
../../tools/tag-subnets.sh ocp29781-vpc $CLUSTER2_NAME
```

### 步骤8: 创建集群2
```bash
# 创建集群2的install-config
cat > install-config-cluster2.yaml << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
compute:
- architecture: arm64
  hyperthreading: Enabled
  name: worker
  platform: 
    aws:
      type: m6g.xlarge
  replicas: 3
controlPlane:
  architecture: arm64
  hyperthreading: Enabled
  name: master
  platform: 
    aws:
      type: m6g.xlarge
  replicas: 3
metadata:
  creationTimestamp: null
  name: $CLUSTER2_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.190.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ap-northeast-1
    vpc:
      subnets:
      - id: $CLUSTER2_PRIVATE_SUBNET
        role: private
      - id: $CLUSTER2_PUBLIC_SUBNET
        role: public
publish: External
pullSecret: 'YOUR_PULL_SECRET_HERE'
sshKey: |
  YOUR_SSH_PUBLIC_KEY_HERE
EOF

# 创建集群2
mkdir -p cluster2-install
cp install-config-cluster2.yaml cluster2-install/install-config.yaml
openshift-install create cluster --dir=cluster2-install
```

### 步骤9: 创建Bastion Host（用于集群2）
```bash
# 为集群2创建bastion host
../../tools/create-bastion-host.sh $VPC_ID $CLUSTER2_PUBLIC_SUBNET $CLUSTER2_NAME
```

### 步骤10: 验证集群2健康状态
```bash
# 等待集群安装完成
openshift-install wait-for install-complete --dir=cluster2-install

# 验证集群节点
export KUBECONFIG=cluster2-install/auth/kubeconfig
oc get nodes
```

### 步骤11: 验证安全组配置
```bash
# 获取集群1的infraID
CLUSTER1_INFRA_ID=$(cat cluster1-install/metadata.json | jq -r .infraID)

# 获取集群1的所有安全组
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER1_INFRA_ID,Values=owned" \
  | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId' | sort | uniq

# 验证安全组规则是否匹配machine CIDR (10.134.0.0/16)
# 检查master安全组的6443/tcp, 22623/tcp, 22/tcp, icmp端口
# 检查worker安全组的22/tcp, icmp端口
```

### 步骤12: 验证网络隔离
```bash
# 从集群1的bastion host ping集群2的节点
# 应该得到100% packet loss

# 从集群2的bastion host ping集群1的节点  
# 应该得到100% packet loss
```

### 步骤13: 清理资源
```bash
# 销毁集群1
openshift-install destroy cluster --dir=cluster1-install

# 销毁集群2
openshift-install destroy cluster --dir=cluster2-install

# 销毁VPC
aws cloudformation delete-stack --stack-name ocp29781-vpc
```

## 🔧 关键修复点

1. **VPC模板保持原样** - 不包含cluster-specific标签
2. **使用tag-subnets.sh脚本** - 在VPC创建后为子网打标签
3. **使用create-bastion-host.sh脚本** - 在public subnet中创建bastion
4. **正确的install-config格式** - 使用`platform.aws.vpc.subnets`而不是已弃用的`platform.aws.subnets`

## 📊 预期结果

- ✅ VPC和子网创建成功
- ✅ 两个集群在不同CIDR中成功安装
- ✅ 网络隔离验证通过
- ✅ 安全组配置正确
- ✅ Bastion host在public subnet中创建

