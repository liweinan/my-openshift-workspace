# OpenShift on AWS: VPC Provisioning Tools

This repository provides a set of CloudFormation templates and utility scripts to streamline the creation of AWS VPC environments suitable for deploying OpenShift clusters.

## Core Concepts

The philosophy is to "first create the network, then install the cluster." You use the provided tools to provision the necessary VPC infrastructure on AWS, and then guide the OpenShift installer to use this pre-existing environment.

### The Golden Rule: Always Use Private Subnets

A critical requirement for the OpenShift installer is that it **must** deploy the cluster nodes (both control plane and workers) into **private subnets**. This is true for both **private** and **public** cluster installations.

-   **Private Cluster (`publish: Internal`)**: The installer places nodes in private subnets. The API endpoints and application routes are accessible only within the VPC.
-   **Public Cluster (`publish: External`)**: The installer still places nodes in private subnets for security. It then automatically uses the corresponding **public subnets** in the same Availability Zones to create public-facing Load Balancers for the API and application routes.

Therefore, you should **always** use a VPC that has both public and private subnets.

---

## Quick Start

### 1. Create the VPC

Use the `create-vpc-stack.sh` script with the `vpc-template-private-cluster.yaml` template. This creates the required topology with public subnets, private subnets, and NAT gateways.

```bash
# This is the recommended command for ALL cluster types.
./create-vpc-stack.sh \
  --stack-name my-openshift-vpc \
  --template-file vpc-template-private-cluster.yaml
```

### 2. Get VPC Outputs

Once the CloudFormation stack is `CREATE_COMPLETE`, use the `get-vpc-outputs.sh` script to retrieve the resource IDs in the correct format for `install-config.yaml`.

```bash
# Usage: ./get-vpc-outputs.sh <your-stack-name>
./get-vpc-outputs.sh my-openshift-vpc
```

The script will automatically extract the **private subnet IDs** and format them correctly.

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

--- For install-config.yaml ---
# Using Private Subnets. This is required for both Private and Public cluster installations.
platform:
  aws:
    vpc:
      vpcID: vpc-0439f81b789b415f4
      subnets:
      - subnet-02115a41d6cbeb8b8
      - subnet-0eb73e4781c6dad39
----------------------------------------------------------------
```

### 3. Configure `install-config.yaml`

You must manually edit your `install-config.yaml` to use the existing VPC.

1.  Generate a base config: `openshift-install create install-config`
2.  Edit the generated `install-config.yaml`:
    -   Remove the entire default `platform.aws` section.
    -   Paste the complete `platform:` block from the script's output into your file.
    -   Set `publish` to `Internal` for a private cluster or `External` for a public cluster.
    -   Ensure `networking.machineNetwork.cidr` matches your VPC's CIDR.

**`install-config.yaml` Example:**
```yaml
apiVersion: v1
baseDomain: your.base.domain.com
metadata:
  name: my-cluster
networking:
  machineNetwork:
  - cidr: 10.0.0.0/16 # Must match your VPC CIDR
# --- Paste the entire platform block from the script output here ---
platform:
  aws:
    vpc:
      vpcID: vpc-0439f81b789b415f4
      subnets:
      - subnet-02115a41d6cbeb8b8
      - subnet-0eb73e4781c6dad39
publish: External # Or "Internal" for a private cluster
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
