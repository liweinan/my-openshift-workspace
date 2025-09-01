# OpenShift on AWS: VPC Provisioning Tools

This repository provides a set of CloudFormation templates and utility scripts to streamline the creation of AWS VPC environments suitable for deploying OpenShift clusters.

## Core Concepts

The philosophy is to "first create the network, then install the cluster." You use the provided tools to provision the necessary VPC infrastructure on AWS, and then guide the OpenShift installer to use this pre-existing environment.

### VPC Templates for Different Cluster Types

We provide three VPC templates to support different deployment scenarios:

1. **`vpc-template-private-cluster.yaml`** - For private clusters (recommended for production)
   - Public subnets: `MapPublicIpOnLaunch: "false"` (more secure)
   - Private subnets: `MapPublicIpOnLaunch: "false"`
   - Includes NAT Gateways for private subnet internet access

2. **`vpc-template-public-cluster.yaml`** - For public clusters (suitable for dev/test)
   - Public subnets: `MapPublicIpOnLaunch: "true"` (supports public access)
   - Private subnets: `MapPublicIpOnLaunch: "false"`
   - Includes NAT Gateways for private subnet internet access

3. **`vpc-template-original.yaml`** - Generic template with advanced options
   - Configurable public IP assignment
   - Additional features like DHCP options and resource sharing

### The Golden Rule: Always Use Private Subnets for Nodes

A critical requirement for the OpenShift installer is that it **must** deploy the cluster nodes (both control plane and workers) into **private subnets**. This is true for both **private** and **public** cluster installations.

-   **Private Cluster (`publish: Internal`)**: The installer places nodes in private subnets. The API endpoints and application routes are accessible only within the VPC.
-   **Public Cluster (`publish: External`)**: The installer still places nodes in private subnets for security. It then automatically uses the corresponding **public subnets** in the same Availability Zones to create public-facing Load Balancers for the API and application routes.

Therefore, you should **always** use a VPC that has both public and private subnets.

---

## Quick Start

### 1. Create the VPC

Choose the appropriate VPC template based on your cluster type:

```bash
# For Private Clusters (Production - Recommended)
./create-vpc-stack.sh \
  --stack-name my-private-vpc \
  --template-file vpc-template-private-cluster.yaml

# For Public Clusters (Dev/Test)
./create-vpc-stack.sh \
  --stack-name my-public-vpc \
  --template-file vpc-template-public-cluster.yaml

# For Generic/Advanced Use Cases
./create-vpc-stack.sh \
  --stack-name my-general-vpc \
  --template-file vpc-template-original.yaml
```

### 2. Get VPC Outputs

Once the CloudFormation stack is `CREATE_COMPLETE`, use the `get-vpc-outputs.sh` script to retrieve the resource IDs in the correct format for `install-config.yaml`.

```bash
# Usage: ./get-vpc-outputs.sh <your-stack-name>
./get-vpc-outputs.sh my-openshift-vpc
```

The script will output configurations for **both** private and public clusters, allowing you to choose the appropriate one.

**Example Output:**
```bash
❯ ./get-vpc-outputs.sh my-openshift-vpc
Querying stack 'my-openshift-vpc' in region 'us-east-1' for outputs...
----------------------------------------------------------------
VPC Information
----------------------------------------------------------------
VPC ID: vpc-0439f81b789b415f4
Public Subnets: subnet-029dcd0c8f4949a2c,subnet-08b1e2a3f4c5d6e7f
Private Subnets: subnet-02115a41d6cbeb8b8,subnet-0eb73e4781c6dad39

==================================================================
PRIVATE CLUSTER CONFIGURATION
==================================================================
# Use this configuration for private clusters (publish: Internal)
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
      - id: subnet-02115a41d6cbeb8b8
        zone: us-east-1a
      - id: subnet-0eb73e4781c6dad39
        zone: us-east-1b

publish: Internal

==================================================================
PUBLIC CLUSTER CONFIGURATION
==================================================================
# Use this configuration for public clusters (publish: External)
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
      # Public subnets for each availability zone
      - id: subnet-029dcd0c8f4949a2c
        zone: us-east-1a
      - id: subnet-08b1e2a3f4c5d6e7f
        zone: us-east-1b
      # Private subnets for each availability zone
      - id: subnet-02115a41d6cbeb8b8
        zone: us-east-1a
      - id: subnet-0eb73e4781c6dad39
        zone: us-east-1b

publish: External
```

### 3. Configure `install-config.yaml`

You must manually edit your `install-config.yaml` to use the existing VPC.

1.  Generate a base config: `openshift-install create install-config`
2.  Edit the generated `install-config.yaml`:
    -   Remove the entire default `platform.aws` section.
    -   Paste the appropriate `platform:` block from the script's output into your file.
    -   Set `publish` to `Internal` for a private cluster or `External` for a public cluster.
    -   Ensure `networking.machineNetwork.cidr` matches your VPC's CIDR.

**Private Cluster `install-config.yaml` Example:**
```yaml
apiVersion: v1
baseDomain: your.base.domain.com
metadata:
  name: my-private-cluster
networking:
  machineNetwork:
  - cidr: 10.0.0.0/16 # Must match your VPC CIDR
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
      - id: subnet-02115a41d6cbeb8b8
        zone: us-east-1a
      - id: subnet-0eb73e4781c6dad39
        zone: us-east-1b
publish: Internal
pullSecret: '{"auths":...}'
sshKey: ssh-rsa AAAA...
```

**Public Cluster `install-config.yaml` Example:**
```yaml
apiVersion: v1
baseDomain: your.base.domain.com
metadata:
  name: my-public-cluster
networking:
  machineNetwork:
  - cidr: 10.0.0.0/16 # Must match your VPC CIDR
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
      # Public subnets for each availability zone
      - id: subnet-029dcd0c8f4949a2c
        zone: us-east-1a
      - id: subnet-08b1e2a3f4c5d6e7f
        zone: us-east-1b
      # Private subnets for each availability zone
      - id: subnet-02115a41d6cbeb8b8
        zone: us-east-1a
      - id: subnet-0eb73e4781c6dad39
        zone: us-east-1b
publish: External
pullSecret: '{"auths":...}'
sshKey: ssh-rsa AAAA...
```

### 4. Tag Subnets

**This is a critical, mandatory step.** The OpenShift installer relies on specific tags to discover and correctly use the public and private subnets. The `tag-subnets.sh` script automates this process.

It will add the following tags:
-   **All Subnets**: `kubernetes.io/cluster/<cluster-name> = shared`
-   **Public Subnets**: `kubernetes.io/role/elb = 1`
-   **Private Subnets**: `kubernetes.io/role/internal-elb = 1`

```bash
# Usage: ./tag-subnets.sh <stack-name> <cluster-name>
./tag-subnets.sh my-openshift-vpc my-cluster
```

### 5. (Optional) Create a Bastion Host

For private clusters, a bastion host is essential for access.

```bash
# Usage: ./create-bastion-host.sh <vpc-id> <public-subnet-id> <cluster-name>
./create-bastion-host.sh \
  vpc-0439f81b789b415f4 \
  subnet-029dcd0c8f4949a2c \
  my-cluster
```

---

## Utility Scripts

This repository contains helper scripts to manage the CloudFormation stacks.

### `find-stacks-by-name.sh`

Finds all active CloudFormation stacks that contain a specific substring in their name.

**Usage:** `./find-stacks-by-name.sh <substring>`

### `delete-stacks-by-name.sh`

Finds and deletes all stacks containing a specific name, after prompting for confirmation.

**Usage:** `./delete-stacks-by-name.sh <substring>`
**Warning:** This is a destructive operation.

### `get-stacks-status.sh`

Checks and displays the current status of all active stacks containing a specific substring.

**Usage:** `./get-stacks-status.sh <substring>`
