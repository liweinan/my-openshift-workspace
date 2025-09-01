#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <cluster-name> <bastion-stack-name> [region]"
  echo "Example: $0 weli2-test-v8x54 weli2-test-v8x54-bastion us-east-1"
  exit 1
fi

CLUSTER_NAME=$1
BASTION_STACK_NAME=$2
REGION=${3:-"us-east-1"}

echo "Configuring bastion security group access to cluster API..."

# --- Get Bastion Security Group ID ---
echo "Getting bastion security group ID..."
BASTION_SG_ID=$(aws --region "${REGION}" cloudformation describe-stacks --stack-name "${BASTION_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey == `BastionSecurityGroupId`].OutputValue' --output text)

if [ -z "${BASTION_SG_ID}" ]; then
  echo "Error: Could not find bastion security group ID from stack ${BASTION_STACK_NAME}"
  exit 1
fi
echo "Found bastion security group: ${BASTION_SG_ID}"

# --- Find Master Security Groups ---
echo "Looking for master security groups..."
MASTER_SG_IDS=""

# Method 1: Look for security groups with control-plane role tag
MASTER_SG_IDS=$(aws --region "${REGION}" ec2 describe-security-groups \
  --filters "Name=tag:sigs.k8s.io/cluster-api-provider-aws/role,Values=control-plane" \
  --query 'SecurityGroups[].GroupId' --output text)

# Method 2: If not found, look for security groups attached to master instances
if [ -z "${MASTER_SG_IDS}" ]; then
  echo "Control-plane security groups not found, looking for master instance security groups..."
  MASTER_INSTANCE_IDS=$(aws --region "${REGION}" ec2 describe-instances \
    --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*master*" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  
  for instance_id in ${MASTER_INSTANCE_IDS}; do
    instance_sg_ids=$(aws --region "${REGION}" ec2 describe-instances --instance-ids "${instance_id}" \
      --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text)
    MASTER_SG_IDS="${MASTER_SG_IDS} ${instance_sg_ids}"
  done
fi

# Method 3: If still not found, look for security groups with cluster tag
if [ -z "${MASTER_SG_IDS}" ]; then
  echo "Master instance security groups not found, looking for cluster-tagged security groups..."
  MASTER_SG_IDS=$(aws --region "${REGION}" ec2 describe-security-groups \
    --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    --query 'SecurityGroups[].GroupId' --output text)
fi

if [ -z "${MASTER_SG_IDS}" ]; then
  echo "Error: Could not find any master security groups for cluster ${CLUSTER_NAME}"
  echo "Please ensure the cluster installation is complete and try again."
  exit 1
fi

echo "Found master security groups: ${MASTER_SG_IDS}"

# --- Authorize Access ---
echo "Authorizing bastion access to master security groups..."
for master_sg_id in ${MASTER_SG_IDS}; do
  echo "Adding ingress rule to security group ${master_sg_id}..."
  
  # Check if rule already exists
  existing_rule=$(aws --region "${REGION}" ec2 describe-security-groups \
    --group-ids "${master_sg_id}" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`6443\` && UserIdGroupPairs[0].GroupId==\`${BASTION_SG_ID}\`].FromPort" \
    --output text)
  
  if [ "${existing_rule}" == "6443" ]; then
    echo "Rule already exists for security group ${master_sg_id}"
  else
    aws --region "${REGION}" ec2 authorize-security-group-ingress \
      --group-id "${master_sg_id}" \
      --protocol tcp \
      --port 6443 \
      --source-group "${BASTION_SG_ID}"
    echo "Added ingress rule to security group ${master_sg_id}"
  fi
done

echo "Security group configuration completed successfully!"
echo "Bastion host should now be able to access the cluster API server."
