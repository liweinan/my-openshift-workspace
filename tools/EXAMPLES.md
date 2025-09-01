## Examples

```bash
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) 
❯ ../create-vpc-stack.sh --help
Usage: ../create-vpc-stack.sh [options]./create-vpc-stack.sh  (command)
Options:
  -p, --profile <profile>      AWS CLI profile to use. Leave empty to use the default profile.
  -r, --region <region>        The AWS region where the stack will be created. (Default: us-east-1)
  -s, --stack-name <name>      The name of the CloudFormation stack. (Default: my-private-cluster-vpc)
  -c, --vpc-cidr <cidr>        The CIDR block for the VPC. (Default: 10.0.0.0/16)
  -a, --az-count <count>       The number of Availability Zones to use (1, 2, or 3). (Default: 2)
  -t, --template-file <file>   The path to the CloudFormation template file. (Default: vpc-template-private-cluster.yaml)
  -h, --help                   Show this help message.
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) [1]
❯ ../create-vpc-stack.sh -s weli4-vpc -t ../vpc-template-private-cluster.yaml 
Executing command:.yaml  …template-private-cluster.yaml  …template-public-cluster.yaml
aws cloudformation deploy   --region us-east-1   --stack-name weli4-vpc   --template-file ../vpc-template-private-cluster.yaml   --parameter-overrides     VpcCidr=10.0.0.0/16     AvailabilityZoneCount=2   --capabilities CAPABILITY_IAM


Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - weli4-vpc
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) 
❯ 
```

```bash
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) 
❯ ../get-stacks-status.sh weli3
Searching for CloudFormation stacks containing 'weli3' in region us-east-1...
Current status of matching stacks:
- weli3-vpc: CREATE_COMPLETE

Note: AWS API status can be eventually consistent. If a stack was just deleted, it might take a moment to appear here or disappear from the list.
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
```

```bash
❯ ../delete-stacks-by-name.sh weli3-vpc
Searching for CloudFormation stacks containing 'weli3-vpc' in region us-east-1...
The following stacks will be DELETED:
weli3-vpc

Are you sure you want to delete these stacks? (yes/no) y
Issuing delete command for stack: weli3-vpc
All delete commands have been sent.
```

```bash
❯ ../openshift-install create cluster --dir . --log-level debug
...
ERROR failed to fetch Metadata: failed to load asset "Install Config": failed to create install config: [platform.aws.vpc.subnets: Forbidden: additional subnets [subnet-05fe9ef5ce90ae9eb subnet-0ef53cd147f09d5d1] without tag prefix kubernetes.io/cluster/ are found in vpc vpc-0b04e4f6baadcc1fd of provided subnets. Please add a tag kubernetes.io/cluster/unmanaged to those subnets to exclude them from cluster installation or explicitly assign roles in the install-config to provided subnets, platform.aws.vpc.subnets: Invalid value: []aws.Subnet{aws.Subnet{ID:"subnet-0870351b311b13372", Roles:[]aws.SubnetRole(nil)}, aws.Subnet{ID:"subnet-0866bbb6b23bbc53f", Roles:[]aws.SubnetRole(nil)}}: No public subnet provided for zones [us-east-1a us-east-1b]] 
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) [3]
❯ ../tag-subnets.sh --help
Usage: ../tag-subnets.sh <stack-name> <cluster-name>
Please provide the CloudFormation stack name and the desired OpenShift cluster name.
weli@tower ~/works/oc-swarm/my-openshift-workspace/tools/work (main) [1]
❯ ../tag-subnets.sh weli4-vpc weli4a-clus
Querying stack 'weli4-vpc' in region 'us-east-1' for subnet outputs...
Tagging subnets for cluster 'weli4a-clus'...
Tagging subnet: subnet-05fe9ef5ce90ae9eb with kubernetes.io/cluster/weli4a-clus=shared
Tagging subnet: subnet-0ef53cd147f09d5d1 with kubernetes.io/cluster/weli4a-clus=shared
Tagging subnet: subnet-0870351b311b13372 with kubernetes.io/cluster/weli4a-clus=shared
Tagging subnet: subnet-0866bbb6b23bbc53f with kubernetes.io/cluster/weli4a-clus=shared
Subnet tagging complete.
```

