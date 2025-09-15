#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to check if required tools are available
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v openshift-install &> /dev/null; then
        missing_tools+=("openshift-install")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install the missing tools and try again."
        exit 1
    fi
}

# Function to get cluster information from AWS
get_cluster_info() {
    local cluster_name="$1"
    local aws_region="$2"
    
    print_info "Searching for cluster resources in region ${aws_region}..."
    
    # Get VPCs with cluster tags
    local vpcs=$(aws --region "${aws_region}" ec2 describe-vpcs \
        --query 'Vpcs[?Tags[?Key==`kubernetes.io/cluster/*`]]' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "${vpcs}" = "[]" ] || [ -z "${vpcs}" ]; then
        print_error "No VPCs found with cluster tags in region ${aws_region}"
        return 1
    fi
    
    # Find VPCs matching cluster name pattern
    local matching_vpcs=$(echo "${vpcs}" | jq -r --arg cluster_name "${cluster_name}" \
        '.[] | select(.Tags[]? | select(.Key | startswith("kubernetes.io/cluster/")) | .Value == "owned" | .Key | contains($cluster_name))')
    
    if [ -z "${matching_vpcs}" ]; then
        print_error "No VPCs found matching cluster name pattern '${cluster_name}'"
        return 1
    fi
    
    # Extract infraID from the first matching VPC
    local infra_id=$(echo "${matching_vpcs}" | jq -r '.Tags[] | select(.Key | startswith("kubernetes.io/cluster/")) | .Key' | head -1 | sed 's/kubernetes.io\/cluster\///')
    
    if [ -z "${infra_id}" ] || [ "${infra_id}" = "null" ]; then
        print_error "Could not extract infraID from VPC tags"
        return 1
    fi
    
    # Get cluster ID from openshiftClusterID tag
    local cluster_id=$(echo "${matching_vpcs}" | jq -r '.Tags[] | select(.Key == "openshiftClusterID") | .Value' | head -1)
    
    if [ -z "${cluster_id}" ] || [ "${cluster_id}" = "null" ]; then
        print_error "Could not find openshiftClusterID in VPC tags"
        return 1
    fi
    
    # Get cluster domain if available
    local cluster_domain=$(echo "${matching_vpcs}" | jq -r '.Tags[] | select(.Key == "clusterDomain") | .Value' | head -1)
    
    echo "${infra_id}|${cluster_id}|${cluster_domain}"
}

# Function to create metadata.json
create_metadata_json() {
    local cluster_name="$1"
    local aws_region="$2"
    local output_dir="$3"
    
    print_header "Creating metadata.json for cluster destruction"
    
    # Get cluster information
    local cluster_info=$(get_cluster_info "${cluster_name}" "${aws_region}")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local infra_id=$(echo "${cluster_info}" | cut -d'|' -f1)
    local cluster_id=$(echo "${cluster_info}" | cut -d'|' -f2)
    local cluster_domain=$(echo "${cluster_info}" | cut -d'|' -f3)
    
    print_success "Found cluster information:"
    echo "  - Cluster Name: ${cluster_name}"
    echo "  - Infra ID: ${infra_id}"
    echo "  - Cluster ID: ${cluster_id}"
    if [ -n "${cluster_domain}" ] && [ "${cluster_domain}" != "null" ]; then
        echo "  - Cluster Domain: ${cluster_domain}"
    fi
    echo ""
    
    # Create output directory
    mkdir -p "${output_dir}"
    
    # Create metadata.json
    local metadata_file="${output_dir}/metadata.json"
    
    # Build the metadata JSON structure
    local metadata_json=$(jq -n \
        --arg cluster_name "${cluster_name}" \
        --arg cluster_id "${cluster_id}" \
        --arg infra_id "${infra_id}" \
        --arg region "${aws_region}" \
        --arg cluster_domain "${cluster_domain}" \
        '{
            "clusterName": $cluster_name,
            "clusterID": $cluster_id,
            "infraID": $infra_id,
            "aws": {
                "region": $region,
                "identifier": [
                    {"kubernetes.io/cluster/\($infra_id)": "owned"},
                    {"openshiftClusterID": $cluster_id},
                    {"sigs.k8s.io/cluster-api-provider-aws/cluster/\($infra_id)": "owned"}
                ]
            }
        } | if $cluster_domain != "" and $cluster_domain != "null" then .aws.clusterDomain = $cluster_domain else . end')
    
    echo "${metadata_json}" > "${metadata_file}"
    print_success "Created metadata.json: ${metadata_file}"
    
    # Display the created metadata
    echo ""
    print_info "Generated metadata.json content:"
    cat "${metadata_file}" | jq .
    echo ""
    
    echo "${metadata_file}"
}

# Function to verify cluster resources exist
verify_cluster_resources() {
    local cluster_id="$1"
    local infra_id="$2"
    local aws_region="$3"
    
    print_header "Verifying cluster resources exist before destruction"
    
    # Check openshiftClusterID
    print_info "Checking for resources with openshiftClusterID: ${cluster_id}"
    local cluster_resources=$(aws --region "${aws_region}" resourcegroupstaggingapi get-tag-values \
        --key openshiftClusterID 2>/dev/null | jq -r '.TagValues[]' | grep "${cluster_id}" || true)
    
    if [ -n "${cluster_resources}" ]; then
        print_success "Found resources with openshiftClusterID: ${cluster_id}"
    else
        print_warning "No resources found with openshiftClusterID: ${cluster_id}"
    fi
    
    # Check kubernetes.io/cluster tag
    print_info "Checking for resources with cluster tag: kubernetes.io/cluster/${infra_id}"
    local cluster_tag_resources=$(aws --region "${aws_region}" resourcegroupstaggingapi get-tag-keys 2>/dev/null | jq -r '.TagKeys[]' | grep "kubernetes.io/cluster/${infra_id}" || true)
    
    if [ -n "${cluster_tag_resources}" ]; then
        print_success "Found resources with cluster tag: kubernetes.io/cluster/${infra_id}"
    else
        print_warning "No resources found with cluster tag: kubernetes.io/cluster/${infra_id}"
    fi
    
    echo ""
}

# Function to destroy cluster
destroy_cluster() {
    local metadata_file="$1"
    local output_dir="$(dirname "${metadata_file}")"
    
    print_header "Destroying cluster using generated metadata.json"
    
    if [ ! -f "${metadata_file}" ]; then
        print_error "Metadata file not found: ${metadata_file}"
        return 1
    fi
    
    print_info "Using metadata file: ${metadata_file}"
    print_info "Working directory: ${output_dir}"
    echo ""
    
    # Run openshift-install destroy
    print_info "Running: openshift-install destroy cluster --dir ${output_dir}"
    echo ""
    
    if openshift-install destroy cluster --dir "${output_dir}" --log-level=info; then
        print_success "Cluster destruction completed successfully"
    else
        print_error "Cluster destruction failed"
        return 1
    fi
    
    echo ""
}

# Function to verify no orphaned resources
verify_no_orphaned_resources() {
    local cluster_id="$1"
    local infra_id="$2"
    local aws_region="$3"
    
    print_header "Verifying no orphaned resources remain"
    
    # Check openshiftClusterID
    print_info "Checking for remaining resources with openshiftClusterID: ${cluster_id}"
    local remaining_cluster_resources=$(aws --region "${aws_region}" resourcegroupstaggingapi get-tag-values \
        --key openshiftClusterID 2>/dev/null | jq -r '.TagValues[]' | grep "${cluster_id}" || true)
    
    if [ -n "${remaining_cluster_resources}" ]; then
        print_warning "Found remaining resources with openshiftClusterID: ${cluster_id}"
        echo "${remaining_cluster_resources}"
        
        # Get detailed resource information
        print_info "Getting detailed resource information..."
        aws --region "${aws_region}" resourcegroupstaggingapi get-resources \
            --tag-filters "Key=openshiftClusterID,Values=${cluster_id}" 2>/dev/null || echo "[]"
    else
        print_success "No resources found with openshiftClusterID: ${cluster_id}"
    fi
    
    echo ""
    
    # Check kubernetes.io/cluster tag
    print_info "Checking for remaining resources with cluster tag: kubernetes.io/cluster/${infra_id}"
    local remaining_cluster_tag_resources=$(aws --region "${aws_region}" resourcegroupstaggingapi get-tag-keys 2>/dev/null | jq -r '.TagKeys[]' | grep "kubernetes.io/cluster/${infra_id}" || true)
    
    if [ -n "${remaining_cluster_tag_resources}" ]; then
        print_warning "Found remaining resources with cluster tag: kubernetes.io/cluster/${infra_id}"
        echo "${remaining_cluster_tag_resources}"
        
        # Get detailed resource information
        print_info "Getting detailed resource information..."
        aws --region "${aws_region}" resourcegroupstaggingapi get-resources \
            --tag-filters "Key=kubernetes.io/cluster/${infra_id},Values=owned" 2>/dev/null || echo "[]"
    else
        print_success "No resources found with cluster tag: kubernetes.io/cluster/${infra_id}"
    fi
    
    echo ""
}

# --- Main Script ---
print_header "OpenShift Cluster Destruction Without Metadata.json"
echo "This script follows OCP-22168 test case for destroying clusters without metadata.json"
echo ""

# Check prerequisites
check_prerequisites

# Parse command line arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <cluster-name> <aws-region> [output-directory]"
    echo ""
    echo "Arguments:"
    echo "  cluster-name     : Name of the cluster to destroy (e.g., qe-jialiu3)"
    echo "  aws-region       : AWS region where the cluster is deployed (e.g., us-east-2)"
    echo "  output-directory : Directory to store generated metadata.json (default: ./cleanup)"
    echo ""
    echo "Examples:"
    echo "  $0 qe-jialiu3 us-east-2"
    echo "  $0 my-cluster us-west-2 ./destroy-work"
    echo ""
    exit 1
fi

CLUSTER_NAME="$1"
AWS_REGION="$2"
OUTPUT_DIR="${3:-./cleanup}"

print_info "Configuration:"
echo "  - Cluster Name: ${CLUSTER_NAME}"
echo "  - AWS Region: ${AWS_REGION}"
echo "  - Output Directory: ${OUTPUT_DIR}"
echo ""

# Step 1: Create metadata.json
METADATA_FILE=$(create_metadata_json "${CLUSTER_NAME}" "${AWS_REGION}" "${OUTPUT_DIR}")
if [ $? -ne 0 ]; then
    print_error "Failed to create metadata.json"
    exit 1
fi

# Extract cluster information for verification
CLUSTER_ID=$(jq -r '.clusterID' "${METADATA_FILE}")
INFRA_ID=$(jq -r '.infraID' "${METADATA_FILE}")

# Step 2: Verify cluster resources exist
verify_cluster_resources "${CLUSTER_ID}" "${INFRA_ID}" "${AWS_REGION}"

# Step 3: Destroy cluster
destroy_cluster "${METADATA_FILE}"
if [ $? -ne 0 ]; then
    print_error "Cluster destruction failed"
    exit 1
fi

# Step 4: Verify no orphaned resources
verify_no_orphaned_resources "${CLUSTER_ID}" "${INFRA_ID}" "${AWS_REGION}"

# --- Summary ---
print_header "Destruction Summary"
print_success "Cluster destruction process completed!"
echo ""
print_info "Generated files:"
echo "  - ${METADATA_FILE}"
echo ""
print_info "Next steps:"
echo "  1. Wait a few minutes and re-run this script to double-check for orphaned resources"
echo "  2. Check AWS Management Console to verify all resources are deleted/terminated"
echo "  3. If resources are not in 'deleted' or 'terminated' state, this may indicate a bug"
echo "  4. Test with a new cluster installation using the same cluster name to ensure no conflicts"
echo ""
print_warning "To re-run verification only:"
echo "  ./check-cluster-destroy-status.sh ${OUTPUT_DIR} ${AWS_REGION}"
