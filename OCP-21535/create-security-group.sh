#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 设置变量
SECURITY_GROUP_NAME="weli-rhel-ssh-sg"
REGION="us-east-1"
VPC_NAME="weli-vpc"
CIDR_BLOCK="10.0.0.0/16"

printf "Processing security group: ${SECURITY_GROUP_NAME}\n"

# 检查默认VPC是否存在
printf "Checking default VPC...\n"
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --region "${REGION}" --query 'Vpcs[0].VpcId' --output text)

if [ "$DEFAULT_VPC_ID" = "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
    echo "没有找到默认VPC，正在创建新的VPC..."
    
    # 创建VPC
    VPC_ID=$(aws ec2 create-vpc --cidr-block "${CIDR_BLOCK}" --region "${REGION}" --query 'Vpc.VpcId' --output text)
    
    if [ $? -eq 0 ] && [ "$VPC_ID" != "None" ]; then
        echo "VPC创建成功: ${VPC_ID}"
        
        # 为VPC添加名称标签
        aws ec2 create-tags --resources "${VPC_ID}" --tags "Key=Name,Value=${VPC_NAME}" --region "${REGION}"
        
        # 创建互联网网关
        IGW_ID=$(aws ec2 create-internet-gateway --region "${REGION}" --query 'InternetGateway.InternetGatewayId' --output text)
        echo "互联网网关创建成功: ${IGW_ID}"
        
        # 将互联网网关附加到VPC
        aws ec2 attach-internet-gateway --vpc-id "${VPC_ID}" --internet-gateway-id "${IGW_ID}" --region "${REGION}"
        echo "互联网网关已附加到VPC"
        
        # 获取默认路由表
        ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" --region "${REGION}" --query 'RouteTables[0].RouteTableId' --output text)
        
        # 添加默认路由到互联网网关
        aws ec2 create-route --route-table-id "${ROUTE_TABLE_ID}" --destination-cidr-block "0.0.0.0/0" --gateway-id "${IGW_ID}" --region "${REGION}"
        echo "默认路由已添加"
        
        # 创建子网
        SUBNET_ID=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block "10.0.1.0/24" --availability-zone "${REGION}a" --region "${REGION}" --query 'Subnet.SubnetId' --output text)
        echo "子网创建成功: ${SUBNET_ID}"
        
        # 为子网添加名称标签
        aws ec2 create-tags --resources "${SUBNET_ID}" --tags "Key=Name,Value=${VPC_NAME}-subnet" --region "${REGION}"
        
        # 配置子网自动分配公网IP
        aws ec2 modify-subnet-attribute --subnet-id "${SUBNET_ID}" --map-public-ip-on-launch --region "${REGION}"
        echo "子网已配置自动分配公网IP"
        
    else
        echo "VPC创建失败"
        exit 1
    fi
else
    echo "找到默认VPC: ${DEFAULT_VPC_ID}"
    VPC_ID="${DEFAULT_VPC_ID}"
fi

# 检查安全组是否已存在
echo "检查安全组是否已存在..."
EXISTING_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" --region "${REGION}" --query 'SecurityGroups[0].GroupId' --output text)

if [ "$EXISTING_SG" != "None" ] && [ -n "$EXISTING_SG" ]; then
    echo "安全组已存在: ${EXISTING_SG}"
    echo "安全组名称: ${SECURITY_GROUP_NAME}"
    echo "VPC ID: ${VPC_ID}"
else
    echo "正在创建安全组..."
    SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name "${SECURITY_GROUP_NAME}" --description "Security group for RHEL 8.1 with SSH access" --vpc-id "${VPC_ID}" --region "${REGION}" --query 'GroupId' --output text)
    
    if [ $? -eq 0 ] && [ "$SECURITY_GROUP_ID" != "None" ]; then
        echo "安全组创建成功: ${SECURITY_GROUP_ID}"
        
        # 添加SSH规则（端口22）
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "SSH规则已添加（端口22）"
        
        # 添加HTTP规则（端口80）
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "HTTP规则已添加（端口80）"
        
        # 添加HTTPS规则（端口443）
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "HTTPS规则已添加（端口443）"
        
        # 添加ICMP规则（ping）
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol icmp --port -1 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "ICMP规则已添加（ping）"
        
        echo "安全组配置完成"
        echo "安全组ID: ${SECURITY_GROUP_ID}"
        echo "安全组名称: ${SECURITY_GROUP_NAME}"
        echo "VPC ID: ${VPC_ID}"
    else
        echo "安全组创建失败"
        exit 1
    fi
fi

echo "安全组处理完成"
