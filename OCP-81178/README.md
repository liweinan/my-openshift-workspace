# OCP-81178: Public Only Subnets Verification Script

This directory contains a script to verify that an OpenShift cluster is deployed with public-only subnets configuration, as required by OCP-81178 test case.

## Overview

The script `check-public-only-subnets.sh` validates that a cluster meets the following requirements:
1. All subnets in the cluster VPC are public type
2. No NAT Gateway is created
3. No NAT instances are created
4. All default routes go to Internet Gateway (not NAT devices)

## Prerequisites

Before running the script, ensure you have the following tools installed:

- `aws` CLI configured with appropriate credentials
- `jq` for JSON processing
- Access to the AWS region where the cluster is deployed

## Usage

```bash
./check-public-only-subnets.sh <cluster-name> [aws-region]
```

### Parameters

- `cluster-name`: The name of your OpenShift cluster (required)
- `aws-region`: AWS region where the cluster is deployed (optional, defaults to `us-east-1`)

### Examples

```bash
# Check cluster in default region (us-east-1)
./check-public-only-subnets.sh my-cluster

# Check cluster in specific region
./check-public-only-subnets.sh my-cluster us-west-2

# Check the weli-public cluster
./check-public-only-subnets.sh weli-public us-east-1
```

## What the Script Checks

### 1. Subnet Verification
- Lists all subnets in the cluster VPC
- Verifies that `MapPublicIpOnLaunch` is `true` for all subnets
- Reports subnet details including availability zone and CIDR block

### 2. NAT Gateway Check
- Searches for any NAT Gateways in the cluster VPC
- Should return empty results for public-only deployment

### 3. NAT Instance Check
- Searches for any NAT instances in the cluster VPC
- Should return empty results for public-only deployment

### 4. Route Table Analysis
- Examines all route tables in the VPC
- Verifies that default routes (0.0.0.0/0) go to Internet Gateway
- Ensures no routes point to NAT devices

### 5. Internet Gateway Verification
- Confirms Internet Gateway exists and is attached to the VPC
- Verifies the Internet Gateway is in "available" state

## Output

The script provides colored output with the following status indicators:

- 🔵 **[INFO]**: Informational messages
- 🟢 **[SUCCESS]**: Successful verification steps
- 🟡 **[WARNING]**: Warning messages
- 🔴 **[ERROR]**: Error conditions or failed verifications

### Example Output

```
[INFO] Starting OCP-81178 Public Only Subnets verification
[INFO] Cluster: weli-public
[INFO] Region: us-east-1

[SUCCESS] Found VPC: vpc-02804902ea7c5adf6

[INFO] Checking subnets in VPC: vpc-02804902ea7c5adf6
[INFO] Found 5 subnets in the VPC
[SUCCESS] Subnet subnet-0e000f59e880de148 (weli-public-gmx9w-subnet-public-us-east-1a) in us-east-1a is PUBLIC
[SUCCESS] Subnet subnet-056624e0f8125631b (weli-public-gmx9w-subnet-public-us-east-1b) in us-east-1b is PUBLIC
[SUCCESS] Subnet subnet-0b2c2c09a25a35da7 (weli-public-gmx9w-subnet-public-us-east-1c) in us-east-1c is PUBLIC
[SUCCESS] Subnet subnet-0a50e78a43c9b05cf (weli-public-gmx9w-subnet-public-us-east-1d) in us-east-1d is PUBLIC
[SUCCESS] Subnet subnet-06cc66c21f5004a58 (weli-public-gmx9w-subnet-public-us-east-1f) in us-east-1f is PUBLIC
[INFO] Subnet Summary: 5 public, 0 private
[SUCCESS] All subnets are public - public-only configuration confirmed

[INFO] Checking for NAT Gateways in VPC: vpc-02804902ea7c5adf6
[SUCCESS] No NAT Gateways found - public-only configuration confirmed

[INFO] Checking for NAT instances in VPC: vpc-02804902ea7c5adf6
[SUCCESS] No NAT instances found - public-only configuration confirmed

[INFO] Checking route tables in VPC: vpc-02804902ea7c5adf6
[SUCCESS] Route table rtb-07b0c351f6ec2d31c routes to Internet Gateway: igw-0e9f36cb2fbbc1b11
[SUCCESS] Route table rtb-03f4cf37366607da3 routes to Internet Gateway: igw-0e9f36cb2fbbc1b11
[SUCCESS] Route table rtb-00b5196e324119068 routes to Internet Gateway: igw-0e9f36cb2fbbc1b11
[SUCCESS] Route table rtb-080d0e43cf42c84a5 routes to Internet Gateway: igw-0e9f36cb2fbbc1b11
[SUCCESS] Route table rtb-0a1bd5abd4627b2ae routes to Internet Gateway: igw-0e9f36cb2fbbc1b11
[INFO] Route Summary: 5 routes to IGW, 0 routes to NAT
[SUCCESS] All default routes go to Internet Gateway - public-only confirmed

[INFO] Checking Internet Gateway for VPC: vpc-02804902ea7c5adf6
[SUCCESS] Internet Gateway igw-0e9f36cb2fbbc1b11 is available

[SUCCESS] 🎉 OCP-81178 verification PASSED!
[SUCCESS] Cluster 'weli-public' is correctly deployed with public-only subnets
```

## Exit Codes

- `0`: All verifications passed - cluster meets public-only requirements
- `1`: One or more verifications failed - cluster does not meet requirements

## Troubleshooting

### Common Issues

1. **VPC not found**
   - Ensure the cluster name is correct
   - Verify the cluster is deployed and running
   - Check that you're using the correct AWS region

2. **Permission denied**
   - Ensure your AWS credentials have sufficient permissions
   - Required permissions: `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeNatGateways`, `ec2:DescribeInstances`, `ec2:DescribeRouteTables`, `ec2:DescribeInternetGateways`

3. **Missing tools**
   - Install `aws` CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
   - Install `jq`: https://stedolan.github.io/jq/download/

### AWS Permissions Required

The script requires the following AWS IAM permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeNatGateways",
                "ec2:DescribeInstances",
                "ec2:DescribeRouteTables",
                "ec2:DescribeInternetGateways"
            ],
            "Resource": "*"
        }
    ]
}
```

## Related Documentation

- [OCP-81178 Test Case](https://issues.redhat.com/browse/OCP-81178)
- [OpenShift IPI Installation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-customizations.html)
- [AWS VPC and Subnets](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html)

## Environment Variable

To deploy a cluster with public-only subnets, set the following environment variable before running `openshift-install`:

```bash
export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=True
```

**Note**: This configuration is not officially supported and should only be used for testing purposes.