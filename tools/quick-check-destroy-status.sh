#!/bin/bash

# Enhanced quick cluster destroy status checker
# Provides better resource state analysis and reduces false positives

set -o nounset
set -o errexit
set -o pipefail

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

# --- Configuration ---
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <installer-working-directory> [aws-region]"
  echo "Example: $0 ./work1 us-east-2"
  echo "Example: $0 ./work1  # uses AWS_REGION env var or defaults to us-east-1"
  echo "Example: $0 /Users/weli/works/oc-swarm/openshift-progress/works us-west-2"
  exit 1
fi

INSTALLER_DIR=$1
AWS_REGION=${2:-${AWS_REGION:-"us-east-1"}}

# --- Extract infraID ---
METADATA_FILE="${INSTALLER_DIR}/metadata.json"
if [ ! -f "${METADATA_FILE}" ]; then
  print_error "metadata.json not found in '${INSTALLER_DIR}'."
  echo "Please check the path and ensure metadata.json exists."
  exit 1
fi

INFRA_ID=$(jq -r '.infraID' "${METADATA_FILE}")
CLUSTER_NAME=$(jq -r '.clusterName' "${METADATA_FILE}")
CLUSTER_ID=$(jq -r '.clusterID' "${METADATA_FILE}")

echo "=== Enhanced Quick Cluster Destroy Status Check ==="
print_info "Cluster Name: ${CLUSTER_NAME}"
print_info "Cluster ID: ${CLUSTER_ID}"
print_info "Infra ID: ${INFRA_ID}"
print_info "Region: ${AWS_REGION}"
print_info "Metadata file: ${METADATA_FILE}"
echo ""

# --- Quick check for tagged resources with state analysis ---
print_info "Checking for resources with cluster tag..."
TAGGED_RESOURCES=$(aws --region "${AWS_REGION}" resourcegroupstaggingapi get-tag-keys 2>/dev/null | grep "kubernetes.io/cluster/${INFRA_ID}" || true)

if [ -n "${TAGGED_RESOURCES}" ]; then
  print_info "Found resources with cluster tag (checking states):"
  echo "${TAGGED_RESOURCES}"
  echo ""
  
  # Get resource details
  RESOURCE_DETAILS=$(aws --region "${AWS_REGION}" resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/${INFRA_ID},Values=owned" 2>/dev/null || echo "[]")
  
  if [ "${RESOURCE_DETAILS}" != "[]" ] && [ -n "${RESOURCE_DETAILS}" ]; then
    print_info "Analyzing resource states..."
    
    echo "${RESOURCE_DETAILS}" | jq -r '.ResourceTagMappingList[].ResourceARN' 2>/dev/null | while read -r resource_arn; do
      if [ -n "${resource_arn}" ]; then
        state=$(check_resource_state "${resource_arn}" "${AWS_REGION}")
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
else
  print_success "No resources found with cluster tag."
fi

echo ""

# --- Check CloudFormation stacks ---
print_info "Checking CloudFormation stacks..."
CF_STACKS=$(aws --region "${AWS_REGION}" cloudformation list-stacks \
  --query "StackSummaries[?contains(StackName, \`${INFRA_ID}\`) && StackStatus != 'DELETE_COMPLETE'].[StackName,StackStatus]" \
  --output text 2>/dev/null || echo "")

if [ -n "${CF_STACKS}" ]; then
  print_warning "Found CloudFormation stacks:"
  echo "${CF_STACKS}" | while read -r stack_name stack_status; do
    if [ -n "${stack_name}" ]; then
      case "${stack_status}" in
        "DELETE_IN_PROGRESS")
          print_warning "🔄 ${stack_name}: ${stack_status} - deleting (normal)"
          ;;
        "DELETE_FAILED")
          print_error "❌ ${stack_name}: ${stack_status} - deletion failed!"
          ;;
        *)
          print_error "⚠️  ${stack_name}: ${stack_status} - needs attention"
          ;;
      esac
    fi
  done
else
  print_success "No CloudFormation stacks found."
fi

echo ""
echo "=== Enhanced Quick Check Complete ==="
print_info "Note: Resources in 'deleting' or 'deleted' state are normal and will be cleaned up automatically."
print_info "Only resources in 'running', 'available', or 'in-use' state need attention."
