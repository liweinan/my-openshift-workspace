#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 设置变量
STACK_NAME="weli-rhel-stack"
TEMPLATE_FILE="rhel-infrastructure.yaml"
REGION="us-east-1"

printf "CloudFormation RHEL Infrastructure Deployment\n"
printf "============================================\n\n"

# 检查模板文件是否存在
if [ ! -f "${TEMPLATE_FILE}" ]; then
    printf "Error: Template file ${TEMPLATE_FILE} not found\n"
    exit 1
fi

# 验证模板
printf "1. Validating CloudFormation template...\n"
aws cloudformation validate-template --template-body file://"${TEMPLATE_FILE}" --region "${REGION}"

if [ $? -ne 0 ]; then
    printf "Template validation failed\n"
    exit 1
fi

printf "Template validation successful\n\n"

# 检查并删除现有密钥对
printf "1.5. Checking and cleaning up existing key pairs...\n"
KEY_PAIR_NAME="weli-rhel-key"
if aws ec2 describe-key-pairs --key-names "${KEY_PAIR_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    printf "Key pair ${KEY_PAIR_NAME} already exists. Deleting it first...\n"
    aws ec2 delete-key-pair --key-name "${KEY_PAIR_NAME}" --region "${REGION}"
    if [ $? -eq 0 ]; then
        printf "Old key pair deleted successfully\n"
    else
        printf "Warning: Failed to delete old key pair\n"
    fi
fi

# 删除本地密钥文件（如果存在）
if [ -f "${KEY_PAIR_NAME}.pem" ]; then
    printf "Removing existing local key file: ${KEY_PAIR_NAME}.pem\n"
    rm -f "${KEY_PAIR_NAME}.pem"
fi

# 创建新的密钥对
printf "Creating new key pair: ${KEY_PAIR_NAME}\n"
aws ec2 create-key-pair \
    --key-name "${KEY_PAIR_NAME}" \
    --query 'KeyMaterial' \
    --output text \
    --region "${REGION}" > "${KEY_PAIR_NAME}.pem"

if [ $? -eq 0 ]; then
    chmod 400 "${KEY_PAIR_NAME}.pem"
    printf "Key pair created and saved: ${KEY_PAIR_NAME}.pem\n"
else
    printf "Failed to create key pair\n"
    exit 1
fi

# 检查堆栈是否已存在
printf "2. Checking if stack already exists...\n"
if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].StackStatus' --output text)
    printf "Stack ${STACK_NAME} already exists with status: ${STACK_STATUS}\n"
    
    if [ "$STACK_STATUS" = "DELETE_IN_PROGRESS" ]; then
        printf "Stack is currently being deleted. Waiting for deletion to complete...\n"
        aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}"
        printf "Stack deletion completed\n"
    else
        printf "Deleting existing stack to ensure clean deployment...\n"
        aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
        
        if [ $? -eq 0 ]; then
            printf "Stack deletion initiated. Waiting for completion...\n"
            aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}"
            printf "Stack deletion completed\n"
        else
            printf "Failed to delete existing stack\n"
            exit 1
        fi
    fi
fi

printf "Creating new stack...\n"
aws cloudformation create-stack \
    --stack-name "${STACK_NAME}" \
    --template-body file://"${TEMPLATE_FILE}" \
    --region "${REGION}" \
    --capabilities CAPABILITY_NAMED_IAM

if [ $? -eq 0 ]; then
    printf "Stack creation initiated. Waiting for completion...\n"
    aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" --region "${REGION}"
else
    printf "Stack creation failed\n"
    exit 1
fi

# 检查堆栈状态
printf "\n3. Checking stack status...\n"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].StackStatus' --output text)

if [ "$STACK_STATUS" = "CREATE_COMPLETE" ] || [ "$STACK_STATUS" = "UPDATE_COMPLETE" ]; then
    printf "Stack deployment successful!\n\n"
    
    # 获取输出
    printf "4. Getting stack outputs...\n"
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].Outputs' \
        --output table
    
    # 密钥对信息
    printf "\n5. Key pair information...\n"
    KEY_PAIR_NAME=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].Outputs[?OutputKey==`KeyPairName`].OutputValue' \
        --output text)
    
    if [ "$KEY_PAIR_NAME" != "None" ] && [ -n "$KEY_PAIR_NAME" ]; then
        printf "Key pair: ${KEY_PAIR_NAME}\n"
        if [ -f "${KEY_PAIR_NAME}.pem" ]; then
            printf "Key file: ${KEY_PAIR_NAME}.pem (already created)\n"
        else
            printf "Warning: Key file ${KEY_PAIR_NAME}.pem not found\n"
        fi
    fi
    
    # 显示连接信息
    printf "\n6. Connection information:\n"
    PUBLIC_IP=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].Outputs[?OutputKey==`PublicIP`].OutputValue' \
        --output text)
    
    if [ "$PUBLIC_IP" != "None" ] && [ -n "$PUBLIC_IP" ]; then
        printf "Public IP: ${PUBLIC_IP}\n"
        printf "SSH Command: ssh -i ${KEY_PAIR_NAME}.pem ec2-user@${PUBLIC_IP}\n"
    fi
    
    printf "\nDeployment completed successfully!\n"
else
    printf "Stack deployment failed. Status: ${STACK_STATUS}\n"
    exit 1
fi
