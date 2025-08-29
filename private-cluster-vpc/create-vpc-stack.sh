#!/bin/bash

# AWS CLI profile to use. Leave empty to use the default profile.
AWS_PROFILE=""
# The AWS region where the stack will be created.
REGION="us-east-1"
# The name of the CloudFormation stack.
STACK_NAME="my-private-cluster-vpc"
# The CIDR block for the VPC.
VPC_CIDR="10.0.0.0/16"
# The number of Availability Zones to use (1, 2, or 3).
AZ_COUNT=2
# The path to the CloudFormation template file.
TEMPLATE_FILE="vpc-template-private-cluster.yaml"

# Construct the AWS CLI command
CMD="aws cloudformation deploy \
  --region ${REGION} \
  --stack-name ${STACK_NAME} \
  --template-file ${TEMPLATE_FILE} \
  --parameter-overrides \
    VpcCidr=${VPC_CIDR} \
    AvailabilityZoneCount=${AZ_COUNT} \
  --capabilities CAPABILITY_IAM"

if [ -n "${AWS_PROFILE}" ]; then
  CMD="${CMD} --profile ${AWS_PROFILE}"
fi

echo "Executing command:"
echo "${CMD}"
echo ""

# Execute the command
eval "${CMD}"
