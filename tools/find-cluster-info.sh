#!/bin/bash

# Find cluster information from qe.devcluster.openshift.com Route53 records
# This script searches for clusters and displays their infraIDs

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

# Main function
main() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 <cluster-name-pattern> [aws-region]"
        echo ""
        echo "Examples:"
        echo "  $0 weli"
        echo "  $0 weli-test"
        echo "  $0 test us-east-2"
        echo ""
        echo "This script searches qe.devcluster.openshift.com Route53 records"
        echo "and displays cluster names and their infraIDs."
        exit 1
    fi

    local name_pattern="$1"
    local aws_region="${2:-us-east-1}"
    local hosted_zone_id="Z3B3KOVA3TRCWP"  # qe.devcluster.openshift.com.

    echo "=== Find Cluster Information ==="
    print_info "Searching for clusters matching pattern: ${name_pattern}"
    print_info "AWS Region: ${aws_region}"
    print_info "Hosted Zone: qe.devcluster.openshift.com. (${hosted_zone_id})"
    echo ""

    # Get all A records that match the pattern
    local records=$(aws --region "${aws_region}" route53 list-resource-record-sets \
        --hosted-zone-id "${hosted_zone_id}" \
        --query "ResourceRecordSets[?contains(Name, \`${name_pattern}\`) && Type == 'A'].Name" \
        --output json 2>/dev/null || echo "[]")

    if [ "${records}" = "[]" ] || [ -z "${records}" ]; then
        print_warning "No records found matching pattern '${name_pattern}'"
        exit 1
    fi

    local cluster_count=0
    local found_clusters=()

    echo "${records}" | jq -r '.[]' | while read -r record_name; do
        if [ -n "${record_name}" ]; then
            # Extract cluster name from record name
            # Examples:
            # api.weli-test.qe.devcluster.openshift.com. -> weli-test
            # api.weli-test2.qe.devcluster.openshift.com. -> weli-test2
            # api.weli-test-21582-a.qe.devcluster.openshift.com. -> weli-test-21582-a
            
            local cluster_name=""
            if [[ "${record_name}" =~ api\.([^.]+)\.qe\.devcluster\.openshift\.com\. ]]; then
                cluster_name="${BASH_REMATCH[1]}"
            fi
            
            if [ -n "${cluster_name}" ]; then
                cluster_count=$((cluster_count + 1))
                
                echo "Cluster #${cluster_count}:"
                echo "  - Cluster Name: ${cluster_name}"
                echo "  - Route53 Record: ${record_name}"
                echo ""
                
                # Try to find infraID from VPC tags
                local infra_id=$(aws --region "${aws_region}" ec2 describe-vpcs \
                    --query "Vpcs[?Tags[?Value == \`${cluster_name}\`]].Tags[?Key | startswith(\`kubernetes.io/cluster/\`)].Key" \
                    --output text 2>/dev/null | head -1 | sed 's/kubernetes.io\/cluster\///' || echo "")
                
                if [ -n "${infra_id}" ] && [ "${infra_id}" != "None" ]; then
                    echo "  - Infra ID: ${infra_id}"
                    print_success "Found infraID for ${cluster_name}: ${infra_id}"
                else
                    echo "  - Infra ID: Not found in VPC tags"
                    print_warning "Could not find infraID for ${cluster_name}"
                    echo "  - Note: VPC may have been deleted but Route53 records remain"
                    echo "  - You can try to generate metadata.json directly with the cluster name"
                fi
                echo ""
            fi
        fi
    done

    if [ ${cluster_count} -eq 0 ]; then
        print_warning "No valid clusters found with pattern '${name_pattern}'"
        exit 1
    fi

    echo ""
    print_info "To generate metadata.json for a specific cluster, use:"
    echo "  ./generate-metadata-for-destroy.sh <cluster-name> <aws-region>"
    echo ""
    print_info "Example:"
    echo "  ./generate-metadata-for-destroy.sh weli-test ${aws_region}"
}

# Run main function
main "$@"
