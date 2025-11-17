# OCP-25784 - [ipi-on-aws] Create private clusters with no public endpoints and access from internet

## Overview

OCP-25784 test case validates the ability to create private OpenShift clusters on AWS, ensuring clusters have no public endpoints and can only be accessed from instances within the VPC.

## Test Objectives

- Validate creation of private OpenShift clusters
- Ensure cluster endpoints are not accessible from the internet
- Verify cluster access functionality through VPC-internal bastion hosts
- Test complete cluster lifecycle management

## File Structure

```
OCP-25784/
├── README.md                           # This document
├── OCP-25784_TEST_PROCEDURE.md        # Detailed test steps
├── run-ocp25784-test.sh               # Automated test script
└── install-config-template.yaml       # Installation config template (generated at runtime)
```

## Quick Start

### 1. Run Automated Test Script

```bash
# Use default configuration
./run-ocp25784-test.sh

# Use custom configuration
./run-ocp25784-test.sh --cluster-name my-private-cluster --region us-west-2

# Enable proxy settings
./run-ocp25784-test.sh --proxy

# Skip cleanup (keep resources for manual testing)
./run-ocp25784-test.sh --skip-cleanup
```

### 2. Manual Test Steps

Refer to the `OCP-25784_TEST_PROCEDURE.md` file for detailed steps.

**Important**: Before starting installation, ensure the following files are transferred to the bastion host:
- `~/.openshift/pull-secret` - OpenShift pull secret
- `~/.aws/` - AWS credentials directory
- `oc` and `openshift-install` tools

## Configuration Options

### Command Line Parameters

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `-v, --vpc-stack-name` | VPC CloudFormation stack name | `weli-vpc-priv` |
| `-c, --cluster-name` | OpenShift cluster name | `weli-priv-test` |
| `-r, --region` | AWS region | `us-east-1` |
| `-b, --bastion-name` | Bastion host name | `weli-test` |
| `-d, --vpc-cidr` | VPC CIDR block | `10.0.0.0/16` |
| `-p, --proxy` | Enable proxy settings | `false` |
| `-s, --skip-cleanup` | Skip cleanup | `false` |

### Environment Variables

| Variable Name | Description |
|---------------|-------------|
| `VPC_STACK_NAME` | VPC stack name |
| `CLUSTER_NAME` | Cluster name |
| `AWS_REGION` | AWS region |
| `BASTION_NAME` | Bastion host name |
| `VPC_CIDR` | VPC CIDR block |

## Test Flow

1. **Infrastructure Preparation**
   - Create VPC and subnets
   - Create bastion host
   - Tag subnets

2. **Tool Preparation**
   - Download OpenShift CLI tools
   - Transfer tools to bastion host

3. **Cluster Installation**
   - Create install-config.yaml
   - Execute IPI installation
   - Verify installation results

4. **Functionality Verification**
   - Verify VPC internal access
   - Verify VPC external access is blocked
   - Test cluster functionality

5. **Resource Cleanup**
   - Destroy cluster
   - Clean up infrastructure

## Key Configuration

### install-config.yaml Key Settings

```yaml
publish: Internal  # Key: Set to Internal to create private cluster
platform:
  aws:
    vpc:
      subnets:
        - id: <private-subnet-1>  # Use private subnets
        - id: <private-subnet-2>
```

### Network Configuration

- **VPC CIDR**: 10.0.0.0/16
- **Cluster Network**: 10.128.0.0/14
- **Service Network**: 172.30.0.0/16
- **Network Type**: OVNKubernetes

## Verification Points

### Success Criteria

- [ ] VPC and bastion host created successfully
- [ ] Subnets correctly tagged with Kubernetes labels
- [ ] Private cluster installation successful
- [ ] All nodes and operators status normal
- [ ] VPC internal cluster console access possible
- [ ] VPC external cluster endpoints blocked
- [ ] Cluster resources successfully cleaned up

### Network Isolation Verification

```bash
# VPC internal access (should succeed)
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com

# VPC external access (should fail)
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com
```

## Troubleshooting

### Common Issues

1. **Subnet Tagging Issues**
   ```bash
   # Check subnet tags
   aws ec2 describe-subnets --subnet-ids <subnet-id>
   ```

2. **Network Connection Issues**
   ```bash
   # Check security group configuration
   aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"
   ```

3. **DNS Resolution Issues**
   ```bash
   # Check Route53 private zones
   aws route53 list-hosted-zones
   ```

### Debug Commands

```bash
# Check cluster status
oc get nodes
oc get clusteroperators

# Check network configuration
oc get network.config/cluster -o yaml

# Check routes
oc get routes -A
```

## Required Tools

- AWS CLI
- OpenShift CLI (oc)
- OpenShift Installer (openshift-install)
- jq (JSON processing)
- curl (network testing)

## Notes

1. **Credential Transfer**: Must transfer pull-secret and AWS credentials to bastion host
2. **Proxy Settings**: HTTP proxy may be required in enterprise network environments
3. **Resource Cleanup**: Always clean up AWS resources after testing to avoid charges
4. **Permission Requirements**: Need sufficient AWS permissions to create and manage resources
5. **Network Configuration**: Ensure VPC configuration complies with enterprise network policies

## Related Documentation

- [OpenShift IPI Installation Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-private.html)
- [AWS VPC Configuration Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [OpenShift Network Configuration](https://docs.openshift.com/container-platform/latest/networking/understanding-networking.html)