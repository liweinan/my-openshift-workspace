# OCP-80182 - Install a cluster in a VPC with only public subnets provided

## Test Case Description

**OCP-80182**: [ipi-on-aws] Install a cluster in a vpc with only public subnets provided

### Test Steps

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

### Expected Result

The installation get completed successfully.

## Test Environment Requirements

- AWS CLI configured
- OpenShift Installer tool
- Sufficient AWS permissions to create VPC, subnets, EC2 instances and other resources

## Quick Start

### 1. Use Pre-created VPC Template

```bash
# Enter test directory
cd /Users/weli/works/oc-swarm/my-openshift-workspace/OCP-80182

# Run test script
./run-ocp-80182-test.sh
```

### 2. Manual Execution Steps

```bash
# 1. Create VPC and public subnets
../tools/create-vpc-stack.sh \
  --stack-name ocp-80182-vpc \
  --template-file ../tools/vpc-template-public-only.yaml \
  --az-count 3

# 2. Get subnet IDs
SUBNET_IDS=$(aws cloudformation describe-stacks \
  --stack-name ocp-80182-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text)

# 3. Set environment variable
export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true

# 4. Create install-config.yaml
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

# 5. Run installation
openshift-install create cluster
```

## Verification Steps

### 1. Verify VPC Configuration

```bash
# Check only public subnets
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$(aws cloudformation describe-stacks --stack-name ocp-80182-vpc --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text)" \
  --query 'Subnets[*].[SubnetId,MapPublicIpOnLaunch]' \
  --output table

# Check no NAT gateways
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$(aws cloudformation describe-stacks --stack-name ocp-80182-vpc --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text)" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --output table
```

### 2. Verify Cluster Installation

```bash
# Check cluster status
export KUBECONFIG=auth/kubeconfig
oc get nodes
oc get clusteroperators
```

## Cleanup Resources

```bash
# Delete OpenShift cluster
openshift-install destroy cluster

# Delete VPC
aws cloudformation delete-stack --stack-name ocp-80182-vpc
aws cloudformation wait stack-delete-complete --stack-name ocp-80182-vpc
```

## Related Files

- `run-ocp-80182-test.sh` - Automated test script
- `verify-vpc-config.sh` - VPC configuration verification script
- `install-config-template.yaml` - install-config.yaml template
- `cleanup.sh` - Cleanup script

## Notes

1. Ensure subnets in VPC template have `MapPublicIpOnLaunch: true` set
2. Do not create private subnets and NAT gateways
3. Ensure all subnets have routes to Internet Gateway
4. Clean up resources promptly after testing to avoid charges