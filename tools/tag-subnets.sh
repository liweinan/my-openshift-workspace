#!/bin/bash

# Check for required arguments
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <stack-name> <cluster-name>"
  echo "Please provide the CloudFormation stack name and the desired OpenShift cluster name."
  exit 1
fi

STACK_NAME=$1
CLUSTER_NAME=$2
# You can specify your AWS region here if needed.
REGION="us-east-1"

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "Error: jq is not installed. Please install jq to run this script."
    exit 1
fi

echo "Querying stack '${STACK_NAME}' in region '${REGION}' for subnet outputs..."

# Get stack outputs
OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query "Stacks[0].Outputs" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "Error: Failed to describe stack '${STACK_NAME}'."
  exit 1
fi

# Get public and private subnet IDs from outputs
PUBLIC_SUBNET_IDS=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PublicSubnetIds") | .OutputValue')
PRIVATE_SUBNET_IDS=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue')

if [ -z "${PUBLIC_SUBNET_IDS}" ] && [ -z "${PRIVATE_SUBNET_IDS}" ]; then
    echo "Error: No public or private subnets found in the outputs for stack '${STACK_NAME}'."
    exit 1
fi

# Combine all subnet IDs, replacing commas with spaces for the loop
ALL_SUBNETS=$(echo "${PUBLIC_SUBNET_IDS},${PRIVATE_SUBNET_IDS}" | tr ',' ' ')

TAG_KEY="kubernetes.io/cluster/${CLUSTER_NAME}"
TAG_VALUE="shared"

echo "Tagging subnets for cluster '${CLUSTER_NAME}'..."

for SUBNET_ID in $ALL_SUBNETS; do
  if [ -n "$SUBNET_ID" ]; then
    echo "Tagging subnet: ${SUBNET_ID} with ${TAG_KEY}=${TAG_VALUE}"
    aws ec2 create-tags \
      --region "${REGION}" \
      --resources "${SUBNET_ID}" \
      --tags "Key=${TAG_KEY},Value=${TAG_VALUE}"
    if [ $? -ne 0 ]; then
      echo "Error: Failed to tag subnet ${SUBNET_ID}."
    fi
  fi
done

echo "Subnet tagging complete."
