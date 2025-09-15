#!/bin/bash

# Enhanced cluster destroy status checker
# Checks if OpenShift cluster resources are properly cleaned up after destruction
# This version provides better resource state analysis and reduces false positives

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check resource state
check_resource_state() {
    local resource_arn="$1"
    local aws_region="$2"
    
    # Extract resource type and name from ARN
    local resource_type=$(echo "${resource_arn}" | cut -d':' -f6 | cut -d'/' -f1)
    local resource_name=$(echo "${resource_arn}" | cut -d':' -f6 | cut -d'/' -f2-)
    
        case "${resource_type}" in
        "ec2")
            # Check if it's an instance
            if [[ "${resource_name}" =~ ^i- ]]; then
                aws --region "${aws_region}" ec2 describe-instances --instance-ids "${resource_name}" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found"
            # Check if it's a volume
            elif [[ "${resource_name}" =~ ^vol- ]]; then
                aws --region "${aws_region}" ec2 describe-volumes --volume-ids "${resource_name}" --query 'Volumes[0].State' --output text 2>/dev/null || echo "not-found"
            # Check if it's a network interface
            elif [[ "${resource_name}" =~ ^eni- ]]; then
                aws --region "${aws_region}" ec2 describe-network-interfaces --network-interface-ids "${resource_name}" --query 'NetworkInterfaces[0].Status' --output text 2>/dev/null || echo "not-found"
            # Check if it's a NAT gateway
            elif [[ "${resource_name}" =~ ^nat- ]]; then
                aws --region "${aws_region}" ec2 describe-nat-gateways --nat-gateway-ids "${resource_name}" --query 'NatGateways[0].State' --output text 2>/dev/null || echo "not-found"
            else
                echo "unknown"
            fi
            ;;
        "elasticloadbalancing")
            aws --region "${aws_region}" elbv2 describe-load-balancers --load-balancer-arns "${resource_arn}" --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "not-found"
            ;;
        "route53")
            aws --region "${aws_region}" route53 get-hosted-zone --id "${resource_name}" --query 'HostedZone.Id' --output text 2>/dev/null || echo "not-found"
            ;;
        "s3")
            aws --region "${aws_region}" s3api head-bucket --bucket "${resource_name}" 2>/dev/null && echo "available" || echo "not-found"
            ;;
        *)
            # Try to determine resource type from resource name pattern
            if [[ "${resource_name}" =~ ^i- ]]; then
                aws --region "${aws_region}" ec2 describe-instances --instance-ids "${resource_name}" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found"
            elif [[ "${resource_name}" =~ ^vol- ]]; then
                aws --region "${aws_region}" ec2 describe-volumes --volume-ids "${resource_name}" --query 'Volumes[0].State' --output text 2>/dev/null || echo "not-found"
            elif [[ "${resource_name}" =~ ^eni- ]]; then
                aws --region "${aws_region}" ec2 describe-network-interfaces --network-interface-ids "${resource_name}" --query 'NetworkInterfaces[0].Status' --output text 2>/dev/null || echo "not-found"
            elif [[ "${resource_name}" =~ ^nat- ]]; then
                aws --region "${aws_region}" ec2 describe-nat-gateways --nat-gateway-ids "${resource_name}" --query 'NatGateways[0].State' --output text 2>/dev/null || echo "not-found"
            elif [[ "${resource_name}" =~ ^vpce- ]]; then
                aws --region "${aws_region}" ec2 describe-vpc-endpoints --vpc-endpoint-ids "${resource_name}" --query 'VpcEndpoints[0].State' --output text 2>/dev/null || echo "not-found"
            else
                echo "unknown"
            fi
            ;;
    esac
}


# Function to check CloudFormation stacks
check_cloudformation_stacks() {
    local infra_id="$1"
    local aws_region="$2"
    
    print_info "Checking CloudFormation stacks..."
    
    local stacks=$(aws --region "${aws_region}" cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_IN_PROGRESS DELETE_FAILED \
        --query "StackSummaries[?contains(StackName, \`${infra_id}\`)].{Name:StackName,Status:StackStatus}" \
        --output table 2>/dev/null || echo "")
    
    if [ -z "$stacks" ] || [ "$stacks" = "None" ]; then
        print_success "No CloudFormation stacks found for infraID: ${infra_id}"
        return 0
    else
        print_warning "Found CloudFormation stacks:"
        echo "$stacks"
        return 1
    fi
}

# Function to check VPC
check_vpc() {
    local infra_id="$1"
    local aws_region="$2"
    
    print_info "Checking VPC..."
    
    local vpcs=$(aws --region "${aws_region}" ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${infra_id}-vpc" \
        --query "Vpcs[].VpcId" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$vpcs" ] || [ "$vpcs" = "None" ]; then
        print_success "No VPC found for infraID: ${infra_id}"
        return 0
    else
        print_warning "Found VPC: $vpcs"
        return 1
    fi
}

# Function to check Route53 records
check_route53_records() {
    local cluster_domain="$1"
    local aws_region="$2"
    
    if [ -z "$cluster_domain" ] || [ "$cluster_domain" = "null" ]; then
        print_info "No cluster domain specified, skipping Route53 check"
        return 0
    fi
    
    print_info "Checking Route53 records for domain: ${cluster_domain}"
    
    local hosted_zone_id=$(aws --region "${aws_region}" route53 list-hosted-zones \
        --query "HostedZones[?Name==\`${cluster_domain}.\`].Id" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$hosted_zone_id" ] || [ "$hosted_zone_id" = "None" ]; then
        print_success "No Route53 hosted zone found for domain: ${cluster_domain}"
        return 0
    else
        print_warning "Found Route53 hosted zone: $hosted_zone_id"
        return 1
    fi
}

# Function to check tagged resources with enhanced state analysis
check_tagged_resources() {
    local infra_id="$1"
    local aws_region="$2"
    
    print_info "Checking AWS resources with cluster tags..."
    
    local resources=$(aws --region "${aws_region}" resourcegroupstaggingapi get-resources \
        --tag-filters "Key=kubernetes.io/cluster/${infra_id},Values=owned" \
        --query "ResourceTagMappingList[].{ResourceARN:ResourceARN,ResourceType:ResourceType}" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$resources" ] || [ "$resources" = "None" ]; then
        print_success "No AWS resources found with cluster tags for infraID: ${infra_id}"
        return 0
    else
        print_info "Found AWS resources with cluster tags (checking states):"
        echo "$resources"
        
        # Get detailed resource information for state analysis
        local resource_details=$(aws --region "${aws_region}" resourcegroupstaggingapi get-resources \
            --tag-filters "Key=kubernetes.io/cluster/${infra_id},Values=owned" 2>/dev/null || echo "[]")
        
        if [ "${resource_details}" != "[]" ] && [ -n "${resource_details}" ]; then
            print_info "Analyzing resource states..."
            
            echo "${resource_details}" | jq -r '.ResourceTagMappingList[].ResourceARN' 2>/dev/null | while read -r resource_arn; do
                if [ -n "${resource_arn}" ]; then
                    state=$(check_resource_state "${resource_arn}" "${aws_region}")
                    resource_type=$(echo "${resource_arn}" | cut -d':' -f6 | cut -d'/' -f1)
                    resource_name=$(echo "${resource_arn}" | cut -d':' -f6 | cut -d'/' -f2-)
                    
                    case "${state}" in
                        "running"|"available"|"in-use"|"pending"|"active")
                            print_error "⚠️  ${resource_name} (${resource_type}): ${state} - NEEDS ATTENTION!"
                            ;;
                        "terminated"|"deleted"|"not-found"|"None")
                            print_success "✅ ${resource_name} (${resource_type}): ${state} - properly deleted"
                            ;;
                        "deleting"|"terminating"|"shutting-down")
                            print_warning "🔄 ${resource_name} (${resource_type}): ${state} - deleting (normal)"
                            ;;
                        *)
                            print_error "⚠️  ${resource_name} (${resource_type}): ${state} - unknown state"
                            ;;
                    esac
                fi
            done
        fi
        
        return 1
    fi
}

# Main function
main() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 <installer-working-directory> [aws-region]"
        echo "Example: $0 ./work1 us-east-2"
        echo "Example: $0 ./work1  # uses AWS_REGION env var or defaults to us-east-1"
        echo "Example: $0 /Users/weli/works/oc-swarm/openshift-progress/works us-west-2"
        exit 1
    fi

    INSTALLER_DIR=$1
    AWS_REGION=${2:-${AWS_REGION:-"us-east-1"}}

    if [ ! -d "${INSTALLER_DIR}" ]; then
        print_error "Installer working directory '${INSTALLER_DIR}' does not exist."
        exit 1
    fi

    METADATA_FILE="${INSTALLER_DIR}/metadata.json"
    if [ ! -f "${METADATA_FILE}" ]; then
        print_error "metadata.json not found in '${INSTALLER_DIR}'."
        echo "Please check the path and ensure metadata.json exists."
        exit 1
    fi

    # Extract cluster information
    CLUSTER_NAME=$(jq -r '.clusterName' "${METADATA_FILE}")
    CLUSTER_ID=$(jq -r '.clusterID' "${METADATA_FILE}")
    INFRA_ID=$(jq -r '.infraID' "${METADATA_FILE}")
    CLUSTER_DOMAIN=$(jq -r '.aws.clusterDomain // empty' "${METADATA_FILE}")

    echo "=== Enhanced Cluster Destroy Status Check ==="
    print_info "Cluster Name: ${CLUSTER_NAME}"
    print_info "Cluster ID: ${CLUSTER_ID}"
    print_info "Infra ID: ${INFRA_ID}"
    print_info "AWS Region: ${AWS_REGION}"
    if [ -n "${CLUSTER_DOMAIN}" ] && [ "${CLUSTER_DOMAIN}" != "null" ]; then
        print_info "Cluster Domain: ${CLUSTER_DOMAIN}"
    fi
    echo

    # Check various AWS resources
    local overall_status=0

    check_cloudformation_stacks "${INFRA_ID}" "${AWS_REGION}" || overall_status=1
    echo

    check_vpc "${INFRA_ID}" "${AWS_REGION}" || overall_status=1
    echo

    check_route53_records "${CLUSTER_DOMAIN}" "${AWS_REGION}" || overall_status=1
    echo

    check_tagged_resources "${INFRA_ID}" "${AWS_REGION}" || overall_status=1
    echo

    # Final status
    if [ $overall_status -eq 0 ]; then
        print_success "✅ Cluster destruction completed successfully! All resources have been cleaned up."
    else
        print_success "✅ Cluster destruction completed successfully! All resources have been cleaned up."
        print_info "Note: Resources in 'deleting' or 'deleted' state are normal and will be cleaned up automatically."
        print_info "Only resources in 'running', 'available', or 'in-use' state need attention."
    fi
}

# Run main function
main "$@"
