# OCP-29781 Test Procedure - Corrected Version

## 🎯 Test Objective
Create two OpenShift clusters in a shared VPC using different isolated CIDR blocks and verify network isolation.

## 📋 Test Steps

### Step 1: Create VPC and Subnets
```bash
# Create VPC using original template (without cluster labels)
aws cloudformation create-stack \
  --stack-name ocp29781-vpc \
  --template-body file://01_vpc_multiCidr.yaml \
  --parameters \
    ParameterKey=VpcCidr2,ParameterValue=10.134.0.0/16 \
    ParameterKey=VpcCidr3,ParameterValue=10.190.0.0/16 \
    ParameterKey=AvailabilityZoneCount,ParameterValue=3

# Wait for VPC creation to complete
aws cloudformation wait stack-create-complete --stack-name ocp29781-vpc
```

### Step 2: Get VPC and Subnet Information
```bash
# Get VPC ID
VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ocp29781-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
  --output text)

# Get subnet IDs
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

### Step 3: Tag Subnets for Cluster1
```bash
# Use tag-subnets.sh script to tag subnets for cluster1
# Assume cluster1 uses CIDR2 (10.134.0.0/16)
CLUSTER1_NAME="cluster1"
CLUSTER1_PRIVATE_SUBNET=$(echo $SUBNETS_CIDR2 | cut -d',' -f1)
CLUSTER1_PUBLIC_SUBNET=$(echo $SUBNETS_CIDR2 | cut -d',' -f2)

# Tag subnets for cluster1
../../tools/tag-subnets.sh ocp29781-vpc $CLUSTER1_NAME
```

### Step 4: Create Cluster1
```bash
# Create install-config for cluster1
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

# Create cluster1
mkdir -p cluster1-install
cp install-config-cluster1.yaml cluster1-install/install-config.yaml
openshift-install create cluster --dir=cluster1-install
```

### Step 5: Create Bastion Host (for Cluster1)
```bash
# Use create-bastion-host.sh script to create bastion in public subnet
../../tools/create-bastion-host.sh $VPC_ID $CLUSTER1_PUBLIC_SUBNET $CLUSTER1_NAME
```

### Step 6: Verify Cluster1 Health Status
```bash
# Wait for cluster installation to complete
openshift-install wait-for install-complete --dir=cluster1-install

# Verify cluster nodes
export KUBECONFIG=cluster1-install/auth/kubeconfig
oc get nodes
```

### Step 7: Tag Subnets for Cluster2
```bash
# Tag subnets for cluster2
# Assume cluster2 uses CIDR3 (10.190.0.0/16)
CLUSTER2_NAME="cluster2"
CLUSTER2_PRIVATE_SUBNET=$(echo $SUBNETS_CIDR3 | cut -d',' -f1)
CLUSTER2_PUBLIC_SUBNET=$(echo $SUBNETS_CIDR3 | cut -d',' -f2)

# Tag subnets for cluster2
../../tools/tag-subnets.sh ocp29781-vpc $CLUSTER2_NAME
```

### Step 8: Create Cluster2
```bash
# Create install-config for cluster2
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

# Create cluster2
mkdir -p cluster2-install
cp install-config-cluster2.yaml cluster2-install/install-config.yaml
openshift-install create cluster --dir=cluster2-install
```

### Step 9: Create Bastion Host (for Cluster2)
```bash
# Create bastion host for cluster2
../../tools/create-bastion-host.sh $VPC_ID $CLUSTER2_PUBLIC_SUBNET $CLUSTER2_NAME
```

### Step 10: Verify Cluster2 Health Status
```bash
# Wait for cluster installation to complete
openshift-install wait-for install-complete --dir=cluster2-install

# Verify cluster nodes
export KUBECONFIG=cluster2-install/auth/kubeconfig
oc get nodes
```

### Step 11: Verify Security Group Configuration
```bash
# Get cluster1 infraID
CLUSTER1_INFRA_ID=$(cat cluster1-install/metadata.json | jq -r .infraID)

# Get all security groups for cluster1
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER1_INFRA_ID,Values=owned" \
  | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId' | sort | uniq

# Verify security group rules match machine CIDR (10.134.0.0/16)
# Check master security group ports 6443/tcp, 22623/tcp, 22/tcp, icmp
# Check worker security group ports 22/tcp, icmp
```

### Step 12: Verify Network Isolation
```bash
# Ping cluster2 nodes from cluster1's bastion host
# Should get 100% packet loss

# Ping cluster1 nodes from cluster2's bastion host  
# Should get 100% packet loss
```

### Step 13: Cleanup Resources
```bash
# Destroy cluster1
openshift-install destroy cluster --dir=cluster1-install

# Destroy cluster2
openshift-install destroy cluster --dir=cluster2-install

# Destroy VPC
aws cloudformation delete-stack --stack-name ocp29781-vpc
```

## 🔧 Key Fix Points

1. **Keep VPC Template Unchanged** - Do not include cluster-specific labels
2. **Use tag-subnets.sh Script** - Tag subnets after VPC creation
3. **Use create-bastion-host.sh Script** - Create bastion in public subnet
4. **Correct install-config Format** - Use `platform.aws.vpc.subnets` instead of deprecated `platform.aws.subnets`

## 📊 Expected Results

- ✅ VPC and subnets created successfully
- ✅ Two clusters successfully installed in different CIDRs
- ✅ Network isolation verification passed
- ✅ Security group configuration correct
- ✅ Bastion host created in public subnet