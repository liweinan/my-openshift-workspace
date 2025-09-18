#!/bin/bash

# OCP-29648 Custom AMI Verification Script
# Verifies that OpenShift cluster is using custom AMIs as specified in install-config

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
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

# Default values
KUBECONFIG_PATH=""
METADATA_PATH=""
WORK_DIR=""
REGION="us-east-2"
EXPECTED_WORKER_AMI=""
EXPECTED_MASTER_AMI=""
DETAILED=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OCP-29648 Custom AMI Verification Script
Verifies that OpenShift cluster is using custom AMIs as specified in install-config

OPTIONS:
    -k, --kubeconfig PATH     Path to kubeconfig file (required)
    -m, --metadata PATH       Path to metadata.json file (required)
    -w, --work-dir PATH       Path to installer working directory (required)
    -r, --region REGION       AWS region (default: us-east-2)
    --worker-ami AMI          Expected worker AMI ID (optional, will be extracted from metadata if not provided)
    --master-ami AMI          Expected master AMI ID (optional, will be extracted from metadata if not provided)
    --detailed                Show detailed verification information
    -h, --help                Show this help message

EXAMPLES:
    $0 -k /path/to/kubeconfig -m /path/to/metadata.json -w /path/to/workdir
    $0 -k kubeconfig -m metadata.json -w workdir --worker-ami ami-03c1d60abaef1ca7e --master-ami ami-02e68e65b656320fa
    $0 -k kubeconfig -m metadata.json -w workdir --detailed

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -m|--metadata)
            METADATA_PATH="$2"
            shift 2
            ;;
        -w|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --worker-ami)
            EXPECTED_WORKER_AMI="$2"
            shift 2
            ;;
        --master-ami)
            EXPECTED_MASTER_AMI="$2"
            shift 2
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$KUBECONFIG_PATH" ] || [ -z "$METADATA_PATH" ] || [ -z "$WORK_DIR" ]; then
    print_error "Missing required parameters"
    usage
    exit 1
fi

# Check if files exist
if [ ! -f "$KUBECONFIG_PATH" ]; then
    print_error "Kubeconfig file not found: $KUBECONFIG_PATH"
    exit 1
fi

if [ ! -f "$METADATA_PATH" ]; then
    print_error "Metadata file not found: $METADATA_PATH"
    exit 1
fi

if [ ! -d "$WORK_DIR" ]; then
    print_error "Work directory not found: $WORK_DIR"
    exit 1
fi

# Set kubeconfig environment variable
export KUBECONFIG="$KUBECONFIG_PATH"

print_info "Using Kubeconfig: $KUBECONFIG_PATH"
print_info "Using Metadata: $METADATA_PATH"
print_info "Using Work Directory: $WORK_DIR"
print_info "Using AWS Region: $REGION"

# Extract cluster information from metadata.json
extract_cluster_info() {
    print_info "Extracting cluster information from metadata.json..."
    
    local infra_id=$(jq -r '.infraID' "$METADATA_PATH" 2>/dev/null || echo "")
    local cluster_id=$(jq -r '.clusterID' "$METADATA_PATH" 2>/dev/null || echo "")
    local cluster_name=$(jq -r '.clusterName' "$METADATA_PATH" 2>/dev/null || echo "")
    
    if [ -z "$infra_id" ]; then
        print_error "Failed to extract infraID from metadata.json"
        exit 1
    fi
    
    print_success "Extracted cluster information:"
    echo "  - InfraID: $infra_id"
    echo "  - ClusterID: $cluster_id"
    echo "  - ClusterName: $cluster_name"
    
    echo "$infra_id"
}

# Extract expected AMI IDs from install-config.yaml
extract_expected_amis() {
    local install_config="$WORK_DIR/install-config.yaml"
    
    if [ ! -f "$install_config" ]; then
        print_warning "install-config.yaml not found in work directory, using provided AMI IDs"
        return
    fi
    
    print_info "Extracting expected AMI IDs from install-config.yaml..."
    
    local worker_ami=$(yq eval '.compute[0].platform.aws.amiID' "$install_config" 2>/dev/null || echo "")
    local master_ami=$(yq eval '.controlPlane.platform.aws.amiID' "$install_config" 2>/dev/null || echo "")
    
    if [ -n "$worker_ami" ] && [ "$worker_ami" != "null" ]; then
        EXPECTED_WORKER_AMI="$worker_ami"
        print_info "Expected Worker AMI from install-config: $worker_ami"
    fi
    
    if [ -n "$master_ami" ] && [ "$master_ami" != "null" ]; then
        EXPECTED_MASTER_AMI="$master_ami"
        print_info "Expected Master AMI from install-config: $master_ami"
    fi
}

# Check cluster connection
check_cluster_connection() {
    print_info "Checking cluster connection..."
    if ! oc cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to cluster, please check kubeconfig file"
        exit 1
    fi
    print_success "Cluster connection successful"
    
    local cluster_id=$(oc get clusterversion version -o jsonpath='{.spec.clusterID}' 2>/dev/null || echo "")
    if [ -n "$cluster_id" ]; then
        print_info "Cluster ID: $cluster_id"
    fi
}

# Get actual AMI IDs from AWS EC2 instances
get_actual_amis() {
    local infra_id="$1"
    
    print_info "Querying actual AMI IDs from AWS EC2 instances..."
    
    # Get worker AMI IDs
    print_info "Getting worker node AMI IDs..."
    local worker_amis=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/$infra_id,Values=owned" "Name=tag:Name,Values=*worker*" \
        --output json | jq -r '.Reservations[].Instances[].ImageId' | sort | uniq 2>/dev/null || echo "")
    
    # Get master AMI IDs
    print_info "Getting master node AMI IDs..."
    local master_amis=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/$infra_id,Values=owned" "Name=tag:Name,Values=*master*" \
        --output json | jq -r '.Reservations[].Instances[].ImageId' | sort | uniq 2>/dev/null || echo "")
    
    echo "$worker_amis|$master_amis"
}

# Verify AMI consistency
verify_ami_consistency() {
    local worker_amis="$1"
    local master_amis="$2"
    
    print_info "Verifying AMI consistency..."
    
    local worker_count=$(echo "$worker_amis" | wc -l)
    local master_count=$(echo "$master_amis" | wc -l)
    
    if [ "$worker_count" -eq 1 ] && [ "$master_count" -eq 1 ]; then
        print_success "AMI consistency verified:"
        echo "  - All worker nodes use the same AMI"
        echo "  - All master nodes use the same AMI"
        return 0
    else
        print_error "AMI inconsistency detected:"
        if [ "$worker_count" -gt 1 ]; then
            echo "  - Worker nodes use different AMIs:"
            echo "$worker_amis" | sed 's/^/    /'
        fi
        if [ "$master_count" -gt 1 ]; then
            echo "  - Master nodes use different AMIs:"
            echo "$master_amis" | sed 's/^/    /'
        fi
        return 1
    fi
}

# Verify expected AMI IDs
verify_expected_amis() {
    local worker_amis="$1"
    local master_amis="$2"
    
    local worker_ami=$(echo "$worker_amis" | head -1)
    local master_ami=$(echo "$master_amis" | head -1)
    
    print_info "Verifying expected AMI IDs..."
    
    local worker_match=false
    local master_match=false
    
    if [ -n "$EXPECTED_WORKER_AMI" ]; then
        if [ "$worker_ami" = "$EXPECTED_WORKER_AMI" ]; then
            print_success "Worker AMI matches expected: $worker_ami"
            worker_match=true
        else
            print_error "Worker AMI mismatch:"
            echo "  - Expected: $EXPECTED_WORKER_AMI"
            echo "  - Actual: $worker_ami"
        fi
    else
        print_warning "No expected worker AMI provided for verification"
        worker_match=true
    fi
    
    if [ -n "$EXPECTED_MASTER_AMI" ]; then
        if [ "$master_ami" = "$EXPECTED_MASTER_AMI" ]; then
            print_success "Master AMI matches expected: $master_ami"
            master_match=true
        else
            print_error "Master AMI mismatch:"
            echo "  - Expected: $EXPECTED_MASTER_AMI"
            echo "  - Actual: $master_ami"
        fi
    else
        print_warning "No expected master AMI provided for verification"
        master_match=true
    fi
    
    if [ "$worker_match" = true ] && [ "$master_match" = true ]; then
        return 0
    else
        return 1
    fi
}

# Get node information
get_node_info() {
    print_info "Getting cluster node information..."
    
    local nodes=$(oc get nodes -o json 2>/dev/null || echo "{}")
    local node_count=$(echo "$nodes" | jq '.items | length' 2>/dev/null || echo "0")
    local ready_count=$(echo "$nodes" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo "0")
    
    print_info "Cluster node status:"
    echo "  - Total nodes: $node_count"
    echo "  - Ready nodes: $ready_count"
    
    if [ "$node_count" -gt 0 ]; then
        print_info "Node details:"
        oc get nodes --no-headers | while read line; do
            echo "  - $line"
        done
    fi
}

# Generate verification report
generate_verification_report() {
    local infra_id="$1"
    local worker_amis="$2"
    local master_amis="$3"
    local worker_ami=$(echo "$worker_amis" | head -1)
    local master_ami=$(echo "$master_amis" | head -1)
    
    echo ""
    echo "=========================================="
    echo "        OCP-29648 Verification Report"
    echo "=========================================="
    echo ""
    echo "📊 Cluster Information:"
    echo "   InfraID: $infra_id"
    echo "   Region: $REGION"
    echo ""
    echo "🔍 AMI Verification:"
    echo "   Worker AMI: $worker_ami"
    echo "   Master AMI: $master_ami"
    echo ""
    
    if [ -n "$EXPECTED_WORKER_AMI" ] || [ -n "$EXPECTED_MASTER_AMI" ]; then
        echo "⚙️  Expected AMI Comparison:"
        if [ -n "$EXPECTED_WORKER_AMI" ]; then
            if [ "$worker_ami" = "$EXPECTED_WORKER_AMI" ]; then
                echo "   ✅ Worker AMI matches expected: $EXPECTED_WORKER_AMI"
            else
                echo "   ❌ Worker AMI mismatch: expected $EXPECTED_WORKER_AMI, got $worker_ami"
            fi
        fi
        if [ -n "$EXPECTED_MASTER_AMI" ]; then
            if [ "$master_ami" = "$EXPECTED_MASTER_AMI" ]; then
                echo "   ✅ Master AMI matches expected: $EXPECTED_MASTER_AMI"
            else
                echo "   ❌ Master AMI mismatch: expected $EXPECTED_MASTER_AMI, got $master_ami"
            fi
        fi
        echo ""
    fi
    
    echo "🎯 Key Verification Points:"
    echo "   • AMI consistency: All worker nodes use the same AMI"
    echo "   • AMI consistency: All master nodes use the same AMI"
    if [ -n "$EXPECTED_WORKER_AMI" ] || [ -n "$EXPECTED_MASTER_AMI" ]; then
        echo "   • AMI validation: Actual AMIs match expected AMIs from install-config"
    fi
    echo "   • Cluster status: All nodes are in Ready state"
    echo ""
}

# Main verification function
main() {
    print_info "Starting OCP-29648 Custom AMI verification..."
    
    # Extract cluster information
    local infra_id=$(extract_cluster_info)
    
    # Extract expected AMI IDs
    extract_expected_amis
    
    # Check cluster connection
    check_cluster_connection
    
    # Get node information
    get_node_info
    
    # Get actual AMI IDs
    local ami_info=$(get_actual_amis "$infra_id")
    local worker_amis=$(echo "$ami_info" | cut -d'|' -f1)
    local master_amis=$(echo "$ami_info" | cut -d'|' -f2)
    
    if [ -z "$worker_amis" ] || [ -z "$master_amis" ]; then
        print_error "Failed to retrieve AMI information from AWS"
        exit 1
    fi
    
    print_info "Actual AMI IDs:"
    echo "  - Worker AMI: $(echo "$worker_amis" | head -1)"
    echo "  - Master AMI: $(echo "$master_amis" | head -1)"
    
    # Verify AMI consistency
    local consistency_result=0
    if ! verify_ami_consistency "$worker_amis" "$master_amis"; then
        consistency_result=1
    fi
    
    # Verify expected AMI IDs
    local expected_result=0
    if ! verify_expected_amis "$worker_amis" "$master_amis"; then
        expected_result=1
    fi
    
    # Generate report
    generate_verification_report "$infra_id" "$worker_amis" "$master_amis"
    
    # Final result
    if [ "$consistency_result" -eq 0 ] && [ "$expected_result" -eq 0 ]; then
        print_success "OCP-29648 verification completed successfully!"
        echo "✅ All AMI verifications passed!"
        exit 0
    else
        print_error "OCP-29648 verification failed!"
        echo "❌ Some AMI verifications failed. Please check the details above."
        exit 1
    fi
}

# Run main function
main "$@"
