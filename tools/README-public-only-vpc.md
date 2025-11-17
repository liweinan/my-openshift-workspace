# Public Only VPC Template

This CloudFormation template is specifically designed to create a VPC containing only public subnets, meeting the requirements of OCP-80182 and OCP-81178 test cases.

## Features

- ✅ **Creates only public subnets** - Does not create private subnets
- ✅ **No NAT gateways** - Does not create NAT gateways and related resources
- ✅ **Automatic public IP assignment** - All subnets set `MapPublicIpOnLaunch: true`
- ✅ **Internet Gateway** - Provides internet access
- ✅ **S3 VPC Endpoint** - Optimizes S3 access performance
- ✅ **Multi-AZ support** - Supports 1-3 availability zones
- ✅ **Flexible CIDR configuration** - Customizable VPC and subnet CIDRs

## Usage

### 1. Basic Deployment

```bash
aws cloudformation create-stack \
  --stack-name openshift-public-vpc \
  --template-body file://vpc-template-public-only.yaml \
  --parameters ParameterKey=AvailabilityZoneCount,ParameterValue=3
```

### 2. Custom Parameters Deployment

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

### 3. Get Output Information

```bash
# Get VPC ID
aws cloudformation describe-stacks \
  --stack-name openshift-public-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
  --output text

# Get public subnet ID list
aws cloudformation describe-stacks \
  --stack-name openshift-public-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text
```

## Parameter Description

| Parameter Name | Type | Default Value | Description |
|--------|------|--------|------|
| VpcCidr | String | 10.0.0.0/16 | VPC CIDR block |
| AvailabilityZoneCount | Number | 3 | Number of availability zones (1-3) |
| SubnetBits | Number | 12 | Number of bits per subnet (/20) |
| AllowedAvailabilityZoneList | CommaDelimitedList | "" | List of allowed availability zones |

## Output Description

| Output Name | Description |
|--------|------|
| VpcId | VPC ID |
| PublicSubnetIds | Public subnet ID list (comma-separated) |
| PublicRouteTableId | Public route table ID |
| AvailabilityZones | List of availability zones used |
| PublicSubnet1Id | Public subnet 1 ID |
| PublicSubnet2Id | Public subnet 2 ID (if exists) |
| PublicSubnet3Id | Public subnet 3 ID (if exists) |

## Integration with OpenShift

### 1. For OCP-80182 Testing

```bash
# 1. Create VPC
aws cloudformation create-stack \
  --stack-name ocp-80182-vpc \
  --template-body file://vpc-template-public-only.yaml \
  --parameters ParameterKey=AvailabilityZoneCount,ParameterValue=3

# 2. Wait for creation completion
aws cloudformation wait stack-create-complete --stack-name ocp-80182-vpc

# 3. Get subnet IDs
SUBNET_IDS=$(aws cloudformation describe-stacks \
  --stack-name ocp-80182-vpc \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text)

# 4. Set environment variable
export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true

# 5. Create install-config.yaml
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

### 2. For OCP-81178 Testing

```bash
# 1. Create VPC (same as OCP-80182)
aws cloudformation create-stack \
  --stack-name ocp-81178-vpc \
  --template-body file://vpc-template-public-only.yaml

# 2. Set environment variable
export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true

# 3. Run IPI installation
openshift-install create cluster
```

## Verification

### 1. Verify Only Public Subnets

```bash
# Check subnet types
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" \
  --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0],MapPublicIpOnLaunch]' \
  --output table
```

### 2. Verify No NAT Gateways

```bash
# Check NAT gateways
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=vpc-xxxxxxxxx" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --output table
```

### 3. Verify Route Tables

```bash
# Check route tables
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" \
  --query 'RouteTables[*].[RouteTableId,Routes[*].[DestinationCidrBlock,GatewayId]]' \
  --output table
```

## Cleanup

```bash
# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name openshift-public-vpc

# Wait for deletion completion
aws cloudformation wait stack-delete-complete --stack-name openshift-public-vpc
```

## Notes

1. **Security Group Configuration**: Ensure security groups allow necessary inbound and outbound traffic
2. **DNS Settings**: VPC has DNS support and DNS hostnames enabled
3. **Subnet Size**: Default is /20 per subnet (4096 IP addresses)
4. **Cost Optimization**: Not creating NAT gateways saves costs
5. **Network Performance**: All traffic goes through Internet Gateway, ensure network latency is acceptable

## Differences from CI Template

| Feature | This Template | CI Template |
|------|--------|--------|
| Private Subnets | ❌ Not created | ✅ Conditionally created |
| NAT Gateways | ❌ Not created | ✅ Conditionally created |
| Parameter Complexity | 🟢 Simple | 🟡 Complex |
| Purpose | 🎯 Specifically for public-only | 🔄 General template |
| Maintainability | 🟢 Easy to maintain | 🟡 Requires understanding conditional logic |