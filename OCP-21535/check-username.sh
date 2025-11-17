#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 设置变量
INSTANCE_NAME="rhel-8.1-instance"
REGION="us-east-1"
KEY_FILE="weli-rhel-key.pem"

printf "Checking instance public IP...\n"

# Get instance public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${INSTANCE_NAME}" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region "${REGION}")

if [ "$PUBLIC_IP" = "None" ] || [ -z "$PUBLIC_IP" ]; then
    printf "Cannot get instance public IP address\n"
    exit 1
fi

printf "Instance public IP: ${PUBLIC_IP}\n"
printf "Testing different usernames for RHEL 8.1...\n"

# Common RHEL usernames
USERS=("ec2-user" "rhel" "root" "admin")

# Check key file
if [ ! -f "${KEY_FILE}" ]; then
    printf "Error: Key file ${KEY_FILE} does not exist\n"
    exit 1
fi

chmod 400 "${KEY_FILE}"

# Test each username
for USER in "${USERS[@]}"; do
    printf "Testing username: ${USER}\n"
    
    # 使用ssh-keyscan检查连接
    if ssh-keyscan -H "${PUBLIC_IP}" >/dev/null 2>&1; then
        printf "SSH service is reachable\n"
        
        # 尝试SSH连接（使用超时避免长时间等待）
        if timeout 10 ssh -i "${KEY_FILE}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${USER}@${PUBLIC_IP}" "whoami" 2>/dev/null; then
            printf "SUCCESS: Correct username is '${USER}'\n"
            printf "You can now connect using:\n"
            printf "ssh -i ${KEY_FILE} ${USER}@${PUBLIC_IP}\n"
            exit 0
        else
            printf "Username '${USER}' failed\n"
        fi
    else
        printf "SSH service not reachable yet, instance might still be starting\n"
        break
    fi
done

printf "Could not determine correct username automatically\n"
printf "Common usernames for RHEL 8.1:\n"
printf "- ec2-user (most common)\n"
printf "- rhel\n"
printf "- root\n"
printf "\nTry connecting manually with:\n"
printf "ssh -i ${KEY_FILE} ec2-user@${PUBLIC_IP}\n"
