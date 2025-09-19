#!/bin/bash

# OCP-29060 KMS Encryption Verification Script
# Verifies that OpenShift cluster volumes are encrypted with the correct KMS keys

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
EXPECTED_MASTER_KMS_KEY=""
EXPECTED_WORKER_KMS_KEY=""
DETAILED=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OCP-29060 KMS Encryption Verification Script
Verifies that OpenShift cluster volumes are encrypted with the correct KMS keys

OPTIONS:
    -k, --kubeconfig PATH     Path to kubeconfig file (required)
    -m, --metadata PATH       Path to metadata.json file (required)
    -w, --work-dir PATH       Path to installer working directory (required)
    -r, --region REGION       AWS region (default: us-east-2)
    --master-kms-key ARN      Expected master KMS key ARN (optional)
    --worker-kms-key ARN      Expected worker KMS key ARN (optional)
    --detailed                Show detailed verification information
    -h, --help                Show this help message

EXAMPLES:
    $0 -k /path/to/kubeconfig -m /path/to/metadata.json -w /path/to/workdir
    $0 -k kubeconfig -m metadata.json -w workdir --master-kms-key "arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    $0 -k kubeconfig -m metadata.json -w workdir --detailed

VERIFICATION STEPS:
    1. Extract cluster information from metadata.json
    2. Get master node volumes and verify KMS encryption
    3. Get worker node volumes and verify KMS encryption
    4. Compare with expected KMS keys (if provided)

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
        --master-kms-key)
            EXPECTED_MASTER_KMS_KEY="$2"
            shift 2
            ;;
        --worker-kms-key)
            EXPECTED_WORKER_KMS_KEY="$2"
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

# Get volumes for a specific node type
get_node_volumes() {
    local infra_id="$1"
    local node_type="$2"  # master or worker
    
    print_info "Getting $node_type node volumes..."
    
    local volumes
    volumes=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/$infra_id,Values=owned" "Name=tag:Name,Values=*$node_type*" \
        --output json | jq -r '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' 2>/dev/null || echo "")
    
    if [ -z "$volumes" ]; then
        print_warning "No volumes found for $node_type nodes"
        return 1
    fi
    
    echo "$volumes"
}

# Check volume KMS encryption
check_volume_encryption() {
    local volume_id="$1"
    local node_type="$2"
    
    local kms_key_id
    kms_key_id=$(aws ec2 describe-volumes \
        --region "$REGION" \
        --volume-ids "$volume_id" \
        --output json | jq -r '.Volumes[].KmsKeyId' 2>/dev/null || echo "")
    
    if [ -z "$kms_key_id" ]; then
        print_error "Failed to get KMS key for volume $volume_id"
        return 1
    fi
    
    if [ "$DETAILED" = true ]; then
        echo "  Volume $volume_id: $kms_key_id"
    fi
    
    echo "$kms_key_id"
}

# Verify KMS key consistency
verify_kms_consistency() {
    local volumes="$1"
    local node_type="$2"
    local expected_key="$3"
    
    print_info "Verifying KMS encryption for $node_type nodes..."
    
    local unique_keys=()
    local volume_count=0
    
    while IFS= read -r volume_id; do
        if [ -n "$volume_id" ]; then
            volume_count=$((volume_count + 1))
            local kms_key_id
            kms_key_id=$(check_volume_encryption "$volume_id" "$node_type")
            
            if [ $? -eq 0 ]; then
                # Add to unique keys if not already present
                if [[ ! " ${unique_keys[@]} " =~ " ${kms_key_id} " ]]; then
                    unique_keys+=("$kms_key_id")
                fi
            fi
        fi
    done <<< "$volumes"
    
    if [ $volume_count -eq 0 ]; then
        print_warning "No volumes found for $node_type nodes"
        return 1
    fi
    
    # Check consistency
    if [ ${#unique_keys[@]} -eq 1 ]; then
        print_success "$node_type nodes: All $volume_count volumes use the same KMS key"
        echo "  KMS Key: ${unique_keys[0]}"
        
        # Verify against expected key if provided
        if [ -n "$expected_key" ]; then
            if [ "${unique_keys[0]}" = "$expected_key" ]; then
                print_success "$node_type nodes: KMS key matches expected value"
                return 0
            else
                print_error "$node_type nodes: KMS key mismatch!"
                echo "  Expected: $expected_key"
                echo "  Actual: ${unique_keys[0]}"
                return 1
            fi
        fi
        
        return 0
    else
        print_error "$node_type nodes: Inconsistent KMS encryption detected!"
        echo "  Found ${#unique_keys[@]} different KMS keys:"
        for key in "${unique_keys[@]}"; do
            echo "    - $key"
        done
        return 1
    fi
}

# Get default EBS KMS key
get_default_ebs_kms_key() {
    print_info "Getting default EBS KMS key for region $REGION..."
    
    local default_key
    default_key=$(aws kms describe-key \
        --region "$REGION" \
        --key-id alias/aws/ebs \
        --output json | jq -r '.KeyMetadata.Arn' 2>/dev/null || echo "")
    
    if [ -n "$default_key" ]; then
        print_info "Default EBS KMS key: $default_key"
        echo "$default_key"
    else
        print_warning "Could not retrieve default EBS KMS key"
        echo ""
    fi
}

# Generate verification report
generate_verification_report() {
    local infra_id="$1"
    local master_result="$2"
    local worker_result="$3"
    local default_kms_key="$4"
    
    echo ""
    echo "=========================================="
    echo "        OCP-29060 KMS Verification Report"
    echo "=========================================="
    echo ""
    echo "📊 Cluster Information:"
    echo "   InfraID: $infra_id"
    echo "   Region: $REGION"
    echo ""
    echo "🔐 KMS Encryption Verification:"
    if [ "$master_result" = "0" ]; then
        echo "   ✅ Master nodes: KMS encryption verified"
    else
        echo "   ❌ Master nodes: KMS encryption verification failed"
    fi
    
    if [ "$worker_result" = "0" ]; then
        echo "   ✅ Worker nodes: KMS encryption verified"
    else
        echo "   ❌ Worker nodes: KMS encryption verification failed"
    fi
    echo ""
    
    if [ -n "$default_kms_key" ]; then
        echo "🔑 Default EBS KMS Key:"
        echo "   $default_kms_key"
        echo ""
    fi
    
    echo "🎯 Key Verification Points:"
    echo "   • Master nodes: Should use custom KMS key (if specified in install-config)"
    echo "   • Worker nodes: Should use default AWS KMS key for EBS"
    echo "   • All volumes of the same node type should use the same KMS key"
    echo "   • Cluster status: All nodes should be in Ready state"
    echo ""
}

# Main verification function
main() {
    print_info "Starting OCP-29060 KMS encryption verification..."
    
    # Extract cluster information
    local infra_id=$(extract_cluster_info)
    
    # Check cluster connection
    check_cluster_connection
    
    # Get default EBS KMS key
    local default_kms_key
    default_kms_key=$(get_default_ebs_kms_key)
    
    # Set expected worker KMS key to default if not specified
    if [ -z "$EXPECTED_WORKER_KMS_KEY" ] && [ -n "$default_kms_key" ]; then
        EXPECTED_WORKER_KMS_KEY="$default_kms_key"
    fi
    
    # Get master node volumes
    local master_volumes
    master_volumes=$(get_node_volumes "$infra_id" "master")
    local master_result=1
    if [ $? -eq 0 ]; then
        verify_kms_consistency "$master_volumes" "master" "$EXPECTED_MASTER_KMS_KEY"
        master_result=$?
    fi
    
    # Get worker node volumes
    local worker_volumes
    worker_volumes=$(get_node_volumes "$infra_id" "worker")
    local worker_result=1
    if [ $? -eq 0 ]; then
        verify_kms_consistency "$worker_volumes" "worker" "$EXPECTED_WORKER_KMS_KEY"
        worker_result=$?
    fi
    
    # Generate report
    generate_verification_report "$infra_id" "$master_result" "$worker_result" "$default_kms_key"
    
    # Final result
    if [ "$master_result" -eq 0 ] && [ "$worker_result" -eq 0 ]; then
        print_success "OCP-29060 KMS encryption verification completed successfully!"
        echo "✅ All KMS encryption verifications passed!"
        exit 0
    else
        print_error "OCP-29060 KMS encryption verification failed!"
        echo "❌ Some KMS encryption verifications failed. Please check the details above."
        exit 1
    fi
}

# Run main function
main "$@"
