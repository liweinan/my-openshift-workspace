#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 设置变量
INSTANCE_NAME="rhel-8.1-instance"
REGION="us-east-1"
KEY_FILE="weli-rhel-key.pem"
USER="ec2-user"

printf "Getting instance public IP address...\n"

# Get instance public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${INSTANCE_NAME}" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region "${REGION}")

if [ "$PUBLIC_IP" = "None" ] || [ -z "$PUBLIC_IP" ]; then
    printf "Cannot get instance public IP address\n"
    printf "Please check if instance is running\n"
    exit 1
fi

printf "Instance public IP: ${PUBLIC_IP}\n"
printf "Connecting to instance...\n"

# Check if key file exists
if [ ! -f "${KEY_FILE}" ]; then
    printf "Error: Key file ${KEY_FILE} does not exist\n"
    printf "Please ensure key file is in current directory\n"
    exit 1
fi

# Set key file permissions
chmod 400 "${KEY_FILE}"

# Connect to instance
printf "Using following command to connect to instance:\n"
printf "ssh -i ${KEY_FILE} ${USER}@${PUBLIC_IP}\n"
printf "\n"
printf "Establishing SSH connection...\n"

ssh -i "${KEY_FILE}" "${USER}@${PUBLIC_IP}"
