# OCP-29781 CI Failure Analysis Report - Corrected Version

## 🔍 Problem Overview

Based on CI log analysis, the main reason for OCP-29781 multi-CIDR test failure was incorrect VPC subnet tag configuration.

**CI Job**: `aws-ipi-multi-cidr-arm-f14`  
**Failure Time**: 2025-09-09T14:40:36Z  
**Failure Reason**: Missing subnet tags caused OpenShift installer to reject using these subnets

## 🚨 Core Error

```
level=error msg=failed to fetch Metadata: failed to load asset "Install Config": failed to create install config: platform.aws.vpc.subnets: Forbidden: additional subnets [subnet-0139fe13fff4eeff0 subnet-08dc7ce7f6967dc2d subnet-09bafffa992546fdf subnet-0a917eee79a1949ec] without tag prefix kubernetes.io/cluster/ are found in vpc vpc-00a6f792a4739069f of provided subnets. Please add a tag kubernetes.io/cluster/unmanaged to those subnets to exclude them from cluster installation or explicitly assign roles in the install-config to provided subnets
```

## 📋 Detailed Problem Analysis

### 1. VPC Creation Successful
- ✅ CloudFormation stack created successfully
- ✅ Stack ID: `arn:aws:cloudformation:ap-northeast-1:301721915996:stack/ci-op-4tl7yiy2-34190-vpc/7c5ae3e0-8d8a-11f0-8468-0a37c9653281`

### 2. Subnet Tag Issues
- ❌ Unlabeled subnets exist in VPC
- ❌ Missing required Kubernetes labels
- ❌ Subnet roles not explicitly specified

### 3. Configuration Format Issues
- ⚠️ Using deprecated configuration format
- ⚠️ `platform.aws.subnets` → `platform.aws.vpc.subnets`

## 🛠️ Correct Fix Solution

### 1. Keep VPC Template Unchanged
**Important**: VPC template should not contain cluster-specific labels because the cluster name is unknown when creating the VPC.

### 2. Use tag-subnets.sh Script
**Solution**: After VPC creation, use the `tag-subnets.sh` script to tag subnets.

```bash
# Tag subnets for cluster1
../../tools/tag-subnets.sh ocp29781-vpc cluster1

# Tag subnets for cluster2  
../../tools/tag-subnets.sh ocp29781-vpc cluster2
```

### 3. Install Config Fix

**Problem**: Using deprecated configuration format
**Solution**: Use the new VPC subnet configuration format

```yaml
# Before fix
platform:
  aws:
    region: ap-northeast-1
    subnets: ['subnet-0001294fd6a01e6b2', 'subnet-0c1434250038d5185']

# After fix
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

### 4. Use create-bastion-host.sh Script
**Confirmed**: The `create-bastion-host.sh` script indeed creates the bastion host in the public subnet, meeting test requirements.

## 🔧 Correct Test Flow

### 1. Create VPC (Using Original Template)
```bash
aws cloudformation create-stack \
  --stack-name ocp29781-vpc \
  --template-body file://01_vpc_multiCidr.yaml \
  --parameters \
    ParameterKey=VpcCidr2,ParameterValue=10.134.0.0/16 \
    ParameterKey=VpcCidr3,ParameterValue=10.190.0.0/16
```

### 2. Tag Subnets
```bash
# Use tag-subnets.sh script
../../tools/tag-subnets.sh ocp29781-vpc cluster1
../../tools/tag-subnets.sh ocp29781-vpc cluster2
```

### 3. Create Clusters
Create two clusters using the correct install-config format.

### 4. Create Bastion Host
```bash
# Use create-bastion-host.sh script
../../tools/create-bastion-host.sh $VPC_ID $PUBLIC_SUBNET_ID $CLUSTER_NAME
```

## 🎯 Expected Results

After the fix, the test should be able to:
1. ✅ Successfully create VPC and subnets
2. ✅ Use tag-subnets.sh script to tag subnets
3. ✅ Successfully create cluster1 (using 10.134.0.0/16 CIDR)
4. ✅ Successfully create cluster2 (using 10.190.0.0/16 CIDR)
5. ✅ Create bastion host in public subnet
6. ✅ Verify network isolation
7. ✅ Verify security group configuration

## 📊 Key Fix Points

1. **Keep VPC Template Unchanged** - Do not include cluster-specific labels
2. **Use tag-subnets.sh Script** - Tag subnets after VPC creation
3. **Use create-bastion-host.sh Script** - Create bastion in public subnet
4. **Correct install-config Format** - Use `platform.aws.vpc.subnets`

## 🔗 Related Links

- [CI Job Log](https://storage.googleapis.com/qe-private-deck/logs/periodic-ci-openshift-verification-tests-main-installation-nightly-4.20-aws-ipi-multi-cidr-arm-f14/1965423507990908928/build-log.txt)
- [OpenShift VPC Configuration Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-vpc.html)
- [AWS Subnet Tag Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-vpc.html#installation-aws-vpc-tags_installing-aws-vpc)