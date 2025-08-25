#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 设置变量
STACK_NAME="rhel-infrastructure"
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

# 检查堆栈是否已存在
printf "2. Checking if stack already exists...\n"
if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    printf "Stack ${STACK_NAME} already exists\n"
    read -p "Do you want to update the stack? (y/n): " -n 1 -r
    printf "\n"
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        printf "Updating stack...\n"
        aws cloudformation update-stack \
            --stack-name "${STACK_NAME}" \
            --template-body file://"${TEMPLATE_FILE}" \
            --region "${REGION}" \
            --capabilities CAPABILITY_NAMED_IAM
        
        if [ $? -eq 0 ]; then
            printf "Stack update initiated. Waiting for completion...\n"
            aws cloudformation wait stack-update-complete --stack-name "${STACK_NAME}" --region "${REGION}"
        else
            printf "Stack update failed\n"
            exit 1
        fi
    else
        printf "Stack update cancelled\n"
        exit 0
    fi
else
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
    
    # 下载密钥对
    printf "\n5. Downloading key pair...\n"
    KEY_PAIR_NAME=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].Outputs[?OutputKey==`KeyPairName`].OutputValue' \
        --output text)
    
    if [ "$KEY_PAIR_NAME" != "None" ] && [ -n "$KEY_PAIR_NAME" ]; then
        printf "Downloading key pair: ${KEY_PAIR_NAME}\n"
        aws ec2 create-key-pair \
            --key-name "${KEY_PAIR_NAME}" \
            --query 'KeyMaterial' \
            --output text \
            --region "${REGION}" > "${KEY_PAIR_NAME}.pem"
        
        if [ $? -eq 0 ]; then
            chmod 400 "${KEY_PAIR_NAME}.pem"
            printf "Key pair downloaded: ${KEY_PAIR_NAME}.pem\n"
        else
            printf "Failed to download key pair\n"
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
