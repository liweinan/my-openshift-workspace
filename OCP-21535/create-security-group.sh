#!/bin/bash

# Set terminal encoding
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Set variables
SECURITY_GROUP_NAME="weli-rhel-ssh-sg"
REGION="us-east-1"
VPC_NAME="weli-vpc"
CIDR_BLOCK="10.0.0.0/16"

printf "Processing security group: ${SECURITY_GROUP_NAME}\n"

# Check if default VPC exists
printf "Checking default VPC...\n"
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --region "${REGION}" --query 'Vpcs[0].VpcId' --output text)

if [ "$DEFAULT_VPC_ID" = "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
    echo "No default VPC found, creating new VPC..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc --cidr-block "${CIDR_BLOCK}" --region "${REGION}" --query 'Vpc.VpcId' --output text)
    
    if [ $? -eq 0 ] && [ "$VPC_ID" != "None" ]; then
        echo "VPC created successfully: ${VPC_ID}"
        
        # Add name tag to VPC
        aws ec2 create-tags --resources "${VPC_ID}" --tags "Key=Name,Value=${VPC_NAME}" --region "${REGION}"
        
        # Create internet gateway
        IGW_ID=$(aws ec2 create-internet-gateway --region "${REGION}" --query 'InternetGateway.InternetGatewayId' --output text)
        echo "Internet gateway created successfully: ${IGW_ID}"
        
        # Attach internet gateway to VPC
        aws ec2 attach-internet-gateway --vpc-id "${VPC_ID}" --internet-gateway-id "${IGW_ID}" --region "${REGION}"
        echo "Internet gateway attached to VPC"
        
        # Get default route table
        ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" --region "${REGION}" --query 'RouteTables[0].RouteTableId' --output text)
        
        # Add default route to internet gateway
        aws ec2 create-route --route-table-id "${ROUTE_TABLE_ID}" --destination-cidr-block "0.0.0.0/0" --gateway-id "${IGW_ID}" --region "${REGION}"
        echo "Default route added"
        
        # Create subnet
        SUBNET_ID=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block "10.0.1.0/24" --availability-zone "${REGION}a" --region "${REGION}" --query 'Subnet.SubnetId' --output text)
        echo "Subnet created successfully: ${SUBNET_ID}"
        
        # Add name tag to subnet
        aws ec2 create-tags --resources "${SUBNET_ID}" --tags "Key=Name,Value=${VPC_NAME}-subnet" --region "${REGION}"
        
        # Configure subnet to auto-assign public IP
        aws ec2 modify-subnet-attribute --subnet-id "${SUBNET_ID}" --map-public-ip-on-launch --region "${REGION}"
        echo "Subnet configured to auto-assign public IP"
        
    else
        echo "VPC creation failed"
        exit 1
    fi
else
    echo "Found default VPC: ${DEFAULT_VPC_ID}"
    VPC_ID="${DEFAULT_VPC_ID}"
fi

# Check if security group already exists
echo "Checking if security group already exists..."
EXISTING_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" --region "${REGION}" --query 'SecurityGroups[0].GroupId' --output text)

if [ "$EXISTING_SG" != "None" ] && [ -n "$EXISTING_SG" ]; then
    echo "Security group already exists: ${EXISTING_SG}"
    echo "Security group name: ${SECURITY_GROUP_NAME}"
    echo "VPC ID: ${VPC_ID}"
else
    echo "Creating security group..."
    SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name "${SECURITY_GROUP_NAME}" --description "Security group for RHEL 8.1 with SSH access" --vpc-id "${VPC_ID}" --region "${REGION}" --query 'GroupId' --output text)
    
    if [ $? -eq 0 ] && [ "$SECURITY_GROUP_ID" != "None" ]; then
        echo "Security group created successfully: ${SECURITY_GROUP_ID}"
        
        # Add SSH rule (port 22)
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "SSH rule added (port 22)"
        
        # Add HTTP rule (port 80)
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "HTTP rule added (port 80)"
        
        # Add HTTPS rule (port 443)
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "HTTPS rule added (port 443)"
        
        # Add ICMP rule (ping)
        aws ec2 authorize-security-group-ingress --group-id "${SECURITY_GROUP_ID}" --protocol icmp --port -1 --cidr 0.0.0.0/0 --region "${REGION}"
        echo "ICMP rule added (ping)"
        
        echo "Security group configuration completed"
        echo "Security group ID: ${SECURITY_GROUP_ID}"
        echo "Security group name: ${SECURITY_GROUP_NAME}"
        echo "VPC ID: ${VPC_ID}"
    else
        echo "Security group creation failed"
        exit 1
    fi
fi

echo "Security group processing completed"