#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Function to get cluster information from AWS VPC tags
get_cluster_info_from_vpc() {
    local cluster_name="$1"
    local aws_region="$2"
    
    # Get VPCs with cluster tags matching the cluster name
    local vpcs=$(aws --region "${aws_region}" ec2 describe-vpcs \
        --query "Vpcs[?Tags[?contains(Key, \`${cluster_name}\`)]]" \
        --output json 2>/dev/null || echo "[]")
    
    if [ "${vpcs}" = "[]" ] || [ -z "${vpcs}" ]; then
        print_error "No VPCs found with cluster name '${cluster_name}' in region ${aws_region}"
        return 1
    fi
    
    # Extract infraID from the first matching VPC
    local infra_id=$(echo "${vpcs}" | jq -r '.[0].Tags[] | select(.Key | startswith("kubernetes.io/cluster/")) | .Key' | head -1 | sed 's/kubernetes.io\/cluster\///')
    
    if [ -z "${infra_id}" ] || [ "${infra_id}" = "null" ]; then
        print_error "Could not extract infraID from VPC tags"
        return 1
    fi
    
    # Get cluster domain if available
    local cluster_domain=$(echo "${vpcs}" | jq -r '.[0].Tags[] | select(.Key == "clusterDomain") | .Value' | head -1)
    
    # Generate a cluster ID (since openshiftClusterID is deprecated)
    local cluster_id="generated-$(date +%s)-$(echo "${infra_id}" | cut -d'-' -f1-2)"
    
    echo "${infra_id}|${cluster_id}|${cluster_domain}"
}

# Function to get cluster information from existing metadata.json
get_cluster_info_from_metadata() {
    local metadata_file="$1"
    
    if [ ! -f "${metadata_file}" ]; then
        print_error "Metadata file not found: ${metadata_file}"
        return 1
    fi
    
    local cluster_name=$(jq -r '.clusterName' "${metadata_file}")
    local cluster_id=$(jq -r '.clusterID' "${metadata_file}")
    local infra_id=$(jq -r '.infraID' "${metadata_file}")
    local cluster_domain=$(jq -r '.aws.clusterDomain // empty' "${metadata_file}")
    
    if [ "${cluster_name}" = "null" ] || [ "${infra_id}" = "null" ]; then
        print_error "Invalid metadata.json file - missing required fields"
        return 1
    fi
    
    echo "${infra_id}|${cluster_id}|${cluster_domain}"
}

# --- Main Script ---
print_header "Generate metadata.json for Cluster Destruction"
echo "This script generates metadata.json for destroying clusters without original metadata"
echo ""

# Parse command line arguments
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <cluster-name-or-metadata-file> [aws-region] [output-file]"
    echo ""
    echo "Arguments:"
    echo "  cluster-name-or-metadata-file : Cluster name (e.g., qe-jialiu3) or path to existing metadata.json"
    echo "  aws-region                   : AWS region (required if using cluster name, ignored if using metadata file)"
    echo "  output-file                  : Path for generated metadata.json (default: ./metadata.json)"
    echo ""
    echo "Examples:"
    echo "  # Using cluster name (searches AWS for VPC tags)"
    echo "  $0 qe-jialiu3 us-east-2"
    echo "  $0 my-cluster us-west-2 ./cleanup/metadata.json"
    echo ""
    echo "  # Using existing metadata.json file"
    echo "  $0 /path/to/metadata.json"
    echo "  $0 ./work1/metadata.json ./cleanup/metadata.json"
    echo ""
    exit 1
fi

INPUT="$1"
AWS_REGION="${2:-}"
OUTPUT_FILE="${3:-./metadata.json}"

# Determine if input is a file or cluster name
if [ -f "${INPUT}" ]; then
    # Input is a metadata.json file
    MODE="metadata"
    METADATA_FILE="${INPUT}"
    print_info "Configuration (using existing metadata.json):"
    echo "  - Metadata File: ${METADATA_FILE}"
    echo "  - Output File: ${OUTPUT_FILE}"
else
    # Input is a cluster name
    MODE="vpc"
    CLUSTER_NAME="${INPUT}"
    if [ -z "${AWS_REGION}" ]; then
        print_error "AWS region is required when using cluster name"
        echo "Usage: $0 <cluster-name> <aws-region> [output-file]"
        exit 1
    fi
    print_info "Configuration (using AWS VPC search):"
    echo "  - Cluster Name: ${CLUSTER_NAME}"
    echo "  - AWS Region: ${AWS_REGION}"
    echo "  - Output File: ${OUTPUT_FILE}"
fi
echo ""

# Get cluster information based on mode
if [ "${MODE}" = "metadata" ]; then
    print_info "Retrieving cluster information from existing metadata.json..."
    cluster_info=$(get_cluster_info_from_metadata "${METADATA_FILE}")
    if [ $? -ne 0 ]; then
        print_error "Failed to read metadata.json file"
        exit 1
    fi
    CLUSTER_NAME=$(jq -r '.clusterName' "${METADATA_FILE}")
    AWS_REGION=$(jq -r '.aws.region' "${METADATA_FILE}")
else
    print_info "Retrieving cluster information from AWS VPC tags..."
    cluster_info=$(get_cluster_info_from_vpc "${CLUSTER_NAME}" "${AWS_REGION}")
    if [ $? -ne 0 ]; then
        print_error "Failed to retrieve cluster information from AWS"
        exit 1
    fi
fi

infra_id=$(echo "${cluster_info}" | cut -d'|' -f1)
cluster_id=$(echo "${cluster_info}" | cut -d'|' -f2)
cluster_domain=$(echo "${cluster_info}" | cut -d'|' -f3)

print_success "Found cluster information:"
echo "  - Cluster Name: ${CLUSTER_NAME}"
echo "  - Infra ID: ${infra_id}"
echo "  - Cluster ID: ${cluster_id}"
if [ -n "${cluster_domain}" ] && [ "${cluster_domain}" != "null" ]; then
    echo "  - Cluster Domain: ${cluster_domain}"
fi
echo ""

# Create output directory if needed
output_dir=$(dirname "${OUTPUT_FILE}")
if [ "${output_dir}" != "." ]; then
    mkdir -p "${output_dir}"
fi

# Create metadata.json
print_info "Generating metadata.json..."

# Build the metadata JSON structure
metadata_json=$(jq -n \
    --arg cluster_name "${CLUSTER_NAME}" \
    --arg cluster_id "${cluster_id}" \
    --arg infra_id "${infra_id}" \
    --arg region "${AWS_REGION}" \
    --arg cluster_domain "${cluster_domain}" \
    '{
        "clusterName": $cluster_name,
        "clusterID": $cluster_id,
        "infraID": $infra_id,
        "aws": {
            "region": $region,
            "identifier": [
                {"kubernetes.io/cluster/\($infra_id)": "owned"},
                {"sigs.k8s.io/cluster-api-provider-aws/cluster/\($infra_id)": "owned"}
            ]
        }
    } | if $cluster_domain != "" and $cluster_domain != "null" then .aws.clusterDomain = $cluster_domain else . end')

echo "${metadata_json}" > "${OUTPUT_FILE}"
print_success "Generated metadata.json: ${OUTPUT_FILE}"

# Display the generated metadata
echo ""
print_info "Generated metadata.json content:"
cat "${OUTPUT_FILE}" | jq .
echo ""

# Provide usage instructions
print_header "Usage Instructions"
echo "To destroy the cluster using the generated metadata.json:"
echo ""
echo "1. Create a working directory:"
echo "   mkdir cleanup"
echo ""
echo "2. Copy the metadata.json to the working directory:"
echo "   cp ${OUTPUT_FILE} cleanup/"
echo ""
echo "3. Run openshift-install destroy:"
echo "   openshift-install destroy cluster --dir cleanup"
echo ""
echo "4. Verify no orphaned resources remain:"
echo "   ./check-cluster-destroy-status.sh cleanup ${AWS_REGION}"
echo ""
print_info "Or use the automated script:"
echo "   ./destroy-cluster-without-metadata.sh ${CLUSTER_NAME} ${AWS_REGION}"
