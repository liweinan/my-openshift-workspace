#!/bin/bash

# OCP-81178: Check Public Only Subnets Configuration
# This script verifies that a cluster is deployed with public-only subnets
# Usage: ./check-public-only-subnets.sh <cluster-name> [aws-region]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Function to check if required tools are installed
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_status "ERROR" "Missing required tools: ${missing_tools[*]}"
        print_status "INFO" "Please install the missing tools and try again"
        exit 1
    fi
}

# Function to find VPC by cluster name
find_vpc() {
    local cluster_name=$1
    local region=$2
    
    print_status "INFO" "Searching for VPC with cluster name: $cluster_name" >&2
    
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --region "$region" \
        --filters "Name=tag:Name,Values=*${cluster_name}*" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$vpc_id" = "None" ] || [ -z "$vpc_id" ]; then
        print_status "ERROR" "VPC not found for cluster: $cluster_name" >&2
        print_status "INFO" "Make sure the cluster name is correct and the cluster is deployed" >&2
        exit 1
    fi
    
    print_status "SUCCESS" "Found VPC: $vpc_id" >&2
    echo "$vpc_id"
}

# Main function
main() {
    local cluster_name=${1:-}
    local region=${2:-us-east-1}
    
    if [ -z "$cluster_name" ]; then
        print_status "ERROR" "Usage: $0 <cluster-name> [aws-region]"
        print_status "INFO" "Example: $0 my-cluster us-east-1"
        exit 1
    fi
    
    print_status "INFO" "Starting OCP-81178 Public Only Subnets verification"
    print_status "INFO" "Cluster: $cluster_name"
    print_status "INFO" "Region: $region"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Find VPC
    local vpc_id
    vpc_id=$(find_vpc "$cluster_name" "$region")
    echo
    
    # Check subnets
    print_status "INFO" "Checking subnets in VPC: $vpc_id"
    local subnets_output
    subnets_output=$(aws ec2 describe-subnets \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' \
        --output table)
    
    echo "$subnets_output"
    
    # Count public vs private subnets
    local public_count
    local private_count
    public_count=$(aws ec2 describe-subnets \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'length(Subnets[?MapPublicIpOnLaunch==`true`])' \
        --output text)
    private_count=$(aws ec2 describe-subnets \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'length(Subnets[?MapPublicIpOnLaunch==`false`])' \
        --output text)
    
    print_status "INFO" "Subnet Summary: $public_count public, $private_count private"
    
    if [ "$private_count" -gt 0 ]; then
        print_status "ERROR" "Found private subnets! This is not a public-only deployment"
        exit 1
    else
        print_status "SUCCESS" "All subnets are public - public-only configuration confirmed"
    fi
    echo
    
    # Check NAT Gateways
    print_status "INFO" "Checking for NAT Gateways in VPC: $vpc_id"
    local nat_gateways
    nat_gateways=$(aws ec2 describe-nat-gateways \
        --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'NatGateways[*].NatGatewayId' \
        --output text)
    
    if [ -z "$nat_gateways" ] || [ "$nat_gateways" = "None" ]; then
        print_status "SUCCESS" "No NAT Gateways found - public-only configuration confirmed"
    else
        print_status "ERROR" "Found NAT Gateways: $nat_gateways"
        print_status "ERROR" "NAT Gateways should not exist in public-only deployment"
        exit 1
    fi
    echo
    
    # Check NAT instances
    print_status "INFO" "Checking for NAT instances in VPC: $vpc_id"
    local nat_instances
    nat_instances=$(aws ec2 describe-instances \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=*nat*" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    if [ -z "$nat_instances" ] || [ "$nat_instances" = "None" ]; then
        print_status "SUCCESS" "No NAT instances found - public-only configuration confirmed"
    else
        print_status "ERROR" "Found NAT instances: $nat_instances"
        print_status "ERROR" "NAT instances should not exist in public-only deployment"
        exit 1
    fi
    echo
    
    # Check route tables
    print_status "INFO" "Checking route tables in VPC: $vpc_id"
    local route_tables_output
    route_tables_output=$(aws ec2 describe-route-tables \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[*].[RouteTableId,Associations[0].SubnetId,Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId|[0]]' \
        --output table)
    
    echo "$route_tables_output"
    
    # Count routes to IGW vs NAT
    local igw_routes
    local nat_routes
    igw_routes=$(aws ec2 describe-route-tables \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'length(RouteTables[?Routes[?DestinationCidrBlock==`0.0.0.0/0` && GatewayId && starts_with(GatewayId, `igw-`)]])' \
        --output text)
    nat_routes=$(aws ec2 describe-route-tables \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'length(RouteTables[?Routes[?DestinationCidrBlock==`0.0.0.0/0` && ((NatGatewayId && starts_with(NatGatewayId, `nat-`)) || (InstanceId && starts_with(InstanceId, `i-`)))]])' \
        --output text)
    
    print_status "INFO" "Route Summary: $igw_routes routes to IGW, $nat_routes routes to NAT"
    
    if [ "$nat_routes" -gt 0 ]; then
        print_status "ERROR" "Found routes to NAT devices - this is not public-only"
        exit 1
    else
        print_status "SUCCESS" "All default routes go to Internet Gateway - public-only confirmed"
    fi
    echo
    
    # Check Internet Gateway
    print_status "INFO" "Checking Internet Gateway for VPC: $vpc_id"
    local igw_output
    igw_output=$(aws ec2 describe-internet-gateways \
        --region "$region" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].State]' \
        --output table)
    
    echo "$igw_output"
    
    local igw_id
    igw_id=$(aws ec2 describe-internet-gateways \
        --region "$region" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text)
    
    if [ "$igw_id" = "None" ] || [ -z "$igw_id" ]; then
        print_status "ERROR" "No Internet Gateway found for VPC"
        exit 1
    fi
    
    local igw_state
    igw_state=$(aws ec2 describe-internet-gateways \
        --region "$region" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[0].Attachments[0].State' \
        --output text)
    
    print_status "SUCCESS" "Internet Gateway $igw_id is $igw_state"
    echo
    
    # Final result
    print_status "SUCCESS" "🎉 OCP-81178 verification PASSED!"
    print_status "SUCCESS" "Cluster '$cluster_name' is correctly deployed with public-only subnets"
    exit 0
}

# Run main function with all arguments
main "$@"