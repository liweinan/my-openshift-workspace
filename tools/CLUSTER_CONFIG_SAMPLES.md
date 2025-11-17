# OpenShift Cluster Configuration Samples

This document provides configuration examples for OpenShift private and public clusters.

## Cluster Types

### 1. Private Cluster

**Features:**
- All nodes are in private subnets
- No public subnets required
- Access via bastion host or VPN
- More secure but requires additional network configuration

**Configuration Requirements:**
- Only private subnets needed
- `publish: Internal`
- Subnets must contain availability zone information

**Use Cases:**
- Production environments
- Environments requiring high security
- Environments with existing network infrastructure

**Configuration File:** `install-config.sample.private.yaml`

**VPC Template:** `vpc-template.yaml`

### 2. Public Cluster

**Features:**
- Control plane nodes in private subnets
- Worker nodes can be in public subnets
- Direct access from internet
- Simpler deployment and configuration

**Configuration Requirements:**
- Requires both public and private subnets
- `publish: External`
- All subnets must contain availability zone information

**Use Cases:**
- Development and testing environments
- Quick deployment and validation
- Environments without strict network isolation requirements

**Configuration File:** `install-config.sample.public.yaml`

**VPC Template:** `vpc-template.yaml`

## Configuration Comparison

| Configuration Item | Private Cluster | Public Cluster |
|--------------------|-----------------|----------------|
| Subnet Configuration | Only private subnets | Public + private subnets |
| publish | Internal | External |
| Network Access | Via bastion host/VPN | Direct internet access |
| Security | High | Medium |
| Deployment Complexity | Medium | Simple |

## Usage Methods

### Generate Configuration

Use the `get-vpc-outputs.sh` script to generate corresponding configurations:

```bash
# Private cluster configuration
./get-vpc-outputs.sh <stack-name> private

# Public cluster configuration
./get-vpc-outputs.sh <stack-name> public

# Auto-detection (recommended)
./get-vpc-outputs.sh <stack-name>
```

### Apply Labels

Use the `tag-subnets.sh` script to apply necessary labels to subnets:

```bash
./tag-subnets.sh <stack-name> <cluster-name>
```

## VPC Template Description

**Important:** Private and public clusters use different VPC templates, mainly differing in `MapPublicIpOnLaunch` configuration.

### Template Selection:

1. **Private Cluster**: Use `vpc-template-private-cluster.yaml`
   - Public subnets: `MapPublicIpOnLaunch: "false"` (more secure)
   - Private subnets: `MapPublicIpOnLaunch: "false"`

2. **Public Cluster**: Use `vpc-template-public-cluster.yaml`
   - Public subnets: `MapPublicIpOnLaunch: "true"` (supports public access)
   - Private subnets: `MapPublicIpOnLaunch: "false"`

### All templates include:
- **Public subnets**: For NAT Gateway, Load Balancer, Bastion Host
- **Private subnets**: For OpenShift node deployment
- **Complete network infrastructure**: NAT Gateway, route tables, VPC Endpoints

## Notes

1. **OpenShift 4.19+ Requirements**: All subnets must contain availability zone information
2. **Subnet Quantity**: Recommend at least one public and one private subnet per availability zone
3. **Label Requirements**: Subnets must be properly labeled to support Kubernetes network functionality
4. **Network Planning**: Ensure subnet CIDRs do not overlap and meet OpenShift requirements
5. **VPC Consistency**: Both cluster types use the same VPC structure, differences only in `install-config.yaml` configuration

## Troubleshooting

### Common Errors

1. **"No public subnet provided"**: Public clusters require public subnets
2. **"Invalid subnet configuration"**: Check subnet IDs and availability zone configuration
3. **"Missing required tags"**: Run `tag-subnets.sh` script

### Verification Steps

1. Check VPC outputs: `./get-vpc-outputs.sh <stack-name>`
2. Verify subnet labels: Check subnet labels in AWS console
3. Test network connectivity: Ensure subnets can communicate properly