# OpenShift on AWS: VPC Provisioning Tools

This repository provides a set of CloudFormation templates and utility scripts to streamline the creation of AWS VPC environments suitable for deploying both **private** and **public** OpenShift clusters.

## Core Concepts

The philosophy is to "first create the network, then install the cluster." You use the provided tools to provision the necessary VPC infrastructure on AWS, and then guide the OpenShift installer to use this pre-existing environment.

- **Private Cluster**: The OpenShift control plane and worker nodes are deployed in private subnets, inaccessible from the public internet. Access is typically managed through a bastion host. The cluster's API and application routes are internal.
- **Public Cluster**: The nodes are deployed in public subnets and are assigned public IP addresses, making the cluster's endpoints directly accessible from the internet.

---

## Quick Start

### 1. Create the VPC

Use the `create-vpc-stack.sh` script to launch a CloudFormation stack. The script is parameterized for flexibility.

**For a Private Cluster:**

This will create a VPC with both public and private subnets, along with NAT gateways for outbound internet access from the private subnets.

```bash
# Usage: ./create-vpc-stack.sh --stack-name <your-stack-name> --template-file <template.yaml>
./create-vpc-stack.sh \
  --stack-name my-private-cluster-vpc \
  --template-file vpc-template-private-cluster.yaml
```

**For a Public Cluster:**

This will create a VPC with only public subnets and an Internet Gateway.

```bash
./create-vpc-stack.sh \
  --stack-name my-public-cluster-vpc \
  --template-file vpc-template-public-cluster.yaml
```

### 2. Get VPC Outputs

Once the CloudFormation stack is `CREATE_COMPLETE`, use the `get-vpc-outputs.sh` script to retrieve the necessary resource IDs.

```bash
# Usage: ./get-vpc-outputs.sh <your-stack-name>
./get-vpc-outputs.sh my-private-cluster-vpc
```

The script's output is intelligent and adapts based on the cluster type:

- **For a private cluster**, it will provide a YAML snippet to be pasted into your `install-config.yaml`.
- **For a public cluster**, it will only display the VPC information, as the OpenShift installer can auto-discover public subnets.

**Example Output (Private Cluster):**
```bash
❯ ./get-vpc-outputs.sh my-private-cluster-vpc
Querying stack 'my-private-cluster-vpc' in region 'us-east-1' for outputs...
----------------------------------------------------------------
VPC Information
----------------------------------------------------------------
VPC ID: vpc-0439f81b789b415f4
Public Subnets: subnet-029dcd0c8f4949a2c,subnet-08b1e2a3f4c5d6e7f
Private Subnets: subnet-02115a41d6cbeb8b8,subnet-0eb73e4781c6dad39

--- For install-config.yaml ---
# Using Private Subnets for Private Cluster installation.
platform:
  aws:
    subnets:
    - subnet-02115a41d6cbeb8b8
    - subnet-0eb73e4781c6dad39
----------------------------------------------------------------
```

### 3. Configure `install-config.yaml`

You must manually edit your `install-config.yaml` to tell the installer to use the specific subnets from your existing VPC.

1.  Generate a base config: `openshift-install create install-config`
2.  Edit the generated `install-config.yaml`:
    -   Copy the entire `platform.aws.subnets` block from the script's output and merge it into the `platform.aws` section of your file.
    -   For **private clusters**, ensure `publish` is set to `Internal`.
    -   For **public clusters**, ensure `publish` is set to `External` (the default).
    -   Ensure `networking.machineNetwork.cidr` matches your VPC's CIDR.

**`install-config.yaml` Example (Private Cluster):**
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
    # --- This is the critical part you add/modify ---
    subnets:
    - subnet-02115a41d6cbeb8b8 # Your first private subnet ID
    - subnet-0eb73e4781c6dad39 # Your second private subnet ID
publish: Internal # Must be Internal for private clusters
pullSecret: '{"auths":...}'
sshKey: ssh-rsa AAAA...
```

### 4. Tag Subnets

**This is a required step for the installer.** The OpenShift installer requires specific tags on the subnets to identify them. Run the `tag-subnets.sh` script.

```bash
# Usage: ./tag-subnets.sh <cluster-name> <vpc-id>
./tag-subnets.sh my-private-cluster vpc-0439f81b789b415f4
```

### 5. (Optional) Create a Bastion Host

For private clusters, a bastion host is essential for accessing the cluster.

```bash
# Usage: ./create-bastion-host.sh <vpc-id> <public-subnet-id> <cluster-name>
./create-bastion-host.sh \
  vpc-0439f81b789b415f4 \
  subnet-029dcd0c8f4949a2c \
  my-private-cluster
```
The bastion host is always deployed in a **public subnet** to be accessible from the internet, providing a secure entry point to your private network.

---

## Utility Scripts

This repository contains helper scripts to manage the CloudFormation stacks.

### `find-stacks-by-name.sh`

Finds all active CloudFormation stacks that contain a specific substring in their name.

**Usage:** `./find-stacks-by-name.sh <substring>`

### `delete-stacks-by-name.sh`

Finds and deletes all stacks containing a specific name, after prompting for confirmation. It sends delete commands in parallel for faster operation.

**Usage:** `./delete-stacks-by-name.sh <substring>`
**Warning:** This is a destructive operation.

### `get-stacks-status.sh`

Checks and displays the current status of all active stacks containing a specific substring.

**Usage:** `./get-stacks-status.sh <substring>`

---

## Examples

```bash
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) 
❯ ../get-vpc-outputs.sh weli3
Querying stack 'weli3' in region 'us-east-1' for outputs...
Error: Failed to describe stack 'weli3'. Please check if the stack exists and you have the correct permissions.
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) [1]
❯ ../get-vpc-outputs.sh weli3-vpc
Querying stack 'weli3-vpc' in region 'us-east-1' for outputs...
----------------------------------------------------------------
VPC Information
----------------------------------------------------------------
VPC ID: vpc-09cfe7770737627a5
Public Subnets: subnet-07d54162fe6545250,subnet-05b5887cee1962f12
Private Subnets: 

--- For install-config.yaml ---
# Using Public Subnets for Public Cluster installation.
platform:
  aws:
    subnets:
    - subnet-07d54162fe6545250
    - subnet-05b5887cee1962f12
----------------------------------------------------------------
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) 
❯ 
```