# VPC Template Design Documentation

## Overview

This project uses three different VPC templates to support different OpenShift cluster deployment requirements:
- **`vpc-template-original.yaml`** - General VPC template supporting multiple configuration options
- **`vpc-template-private-cluster.yaml`** - Private cluster dedicated VPC template
- **`vpc-template-public-cluster.yaml`** - Public cluster dedicated VPC template

## Why Three Templates?

### Key Difference: MapPublicIpOnLaunch Configuration

This configuration determines whether instances in subnets automatically get public IP addresses, which has important implications for different cluster types:

#### 1. Private Cluster Template (`vpc-template-private-cluster.yaml`)
```yaml
# Public subnets - do not auto-assign public IPs (more secure)
PublicSubnet:
  Properties:
    MapPublicIpOnLaunch: "false"  # Key: false

# Private subnets - do not auto-assign public IPs
PrivateSubnet:
  Properties:
    MapPublicIpOnLaunch: "false"  # Key: false
```

**Characteristics:**
- More secure network configuration
- Public subnets only used for NAT Gateway, Load Balancer
- All nodes are in private subnets
- Access through bastion host or VPN

#### 2. Public Cluster Template (`vpc-template-public-cluster.yaml`)
```yaml
# Public subnets - auto-assign public IPs
PublicSubnet:
  Properties:
    MapPublicIpOnLaunch: "true"   # Key: true

# Private subnets - do not auto-assign public IPs
PrivateSubnet:
  Properties:
    MapPublicIpOnLaunch: "false"  # Key: false
```

**Characteristics:**
- Instances in public subnets can be directly accessed from internet
- Supports public Load Balancer
- Simpler deployment and configuration
- Suitable for development and testing environments

#### 3. General Template (`vpc-template-original.yaml`)
```yaml
# Supports dynamic configuration
PublicSubnet:
  Properties:
    MapPublicIpOnLaunch:
      !If [
        "DoOnlyPublicSubnets",
        "true",    # If only creating public subnets
        "false"    # If creating mixed subnets
      ]
```

**Characteristics:**
- Most flexible configuration options
- Supports multiple deployment scenarios
- Includes additional features (DHCP options, resource sharing, etc.)

## Template Selection Guide

### Choose Private Cluster Template (`vpc-template-private-cluster.yaml`) when:
- Need high-security production environment
- Have existing network infrastructure
- Access cluster through bastion host or VPN
- Don't need instances in public subnets to directly access internet

### Choose Public Cluster Template (`vpc-template-public-cluster.yaml`) when:
- Development and testing environments
- Need quick deployment and validation
- Need public Load Balancer
- Instances in public subnets need direct internet access

### Choose General Template (`vpc-template-original.yaml`) when:
- Need special network configuration
- Need DHCP option sets
- Need resource sharing features
- Need more complex conditional logic

## Network Architecture Comparison

| Feature | Private Cluster | Public Cluster | General Template |
|------|----------|----------|----------|
| Public Subnet MapPublicIpOnLaunch | false | true | Configurable |
| Private Subnet MapPublicIpOnLaunch | false | false | false |
| Security Level | High | Medium | Configurable |
| Deployment Complexity | Medium | Simple | Complex |
| Flexibility | Medium | Medium | High |

## Usage

### Create Private Cluster VPC
```bash
./create-vpc-stack.sh -s my-private-vpc -t vpc-template-private-cluster.yaml
```

### Create Public Cluster VPC
```bash
./create-vpc-stack.sh -s my-public-vpc -t vpc-template-public-cluster.yaml
```

### Create General VPC
```bash
./create-vpc-stack.sh -s my-general-vpc -t vpc-template-original.yaml
```

## Summary

The existence of three VPC templates is to meet different security requirements and deployment scenarios:

1. **Private Cluster Template**: Provides highest security, suitable for production environments
2. **Public Cluster Template**: Provides simple deployment, suitable for development and testing
3. **General Template**: Provides maximum flexibility, suitable for special requirements

Which template to choose depends on your specific needs, security requirements, and deployment environment.