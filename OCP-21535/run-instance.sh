#!/bin/bash
set -x

# Set terminal encoding
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Set variables
IMAGE_ID="ami-0258229bf3cd8af20"
INSTANCE_TYPE="m5.xlarge"
KEY_NAME="weli-rhel-key"
SECURITY_GROUP_ID="sg-0faf59d58a5daebe4"
SUBNET_ID="subnet-0d863bd5fb43d9137"
REGION="us-east-1"
INSTANCE_NAME="rhel-8.1-instance"

printf "Launching EC2 instance...\n"

aws ec2 run-instances \
  --image-id "${IMAGE_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --key-name "${KEY_NAME}" \
  --security-group-ids "${SECURITY_GROUP_ID}" \
  --subnet-id "${SUBNET_ID}" \
  --region "${REGION}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
  --output table

if [ $? -eq 0 ]; then
    printf "Instance launch command executed successfully\n"
    printf "Please wait a few minutes for the instance to fully start, then use the following command to check instance status:\n"
    printf "aws ec2 describe-instances --filters \"Name=tag:Name,Values=${INSTANCE_NAME}\" --region ${REGION} --output table\n"
else
    printf "Instance launch failed\n"
    exit 1
fi