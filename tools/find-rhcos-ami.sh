#!/bin/bash

# RHCOS AMI Discovery Script
# Finds the latest RHCOS AMI ID for a given region using openshift-install

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
REGION="us-east-2"
ARCHITECTURE="x86_64"
OUTPUT_FORMAT="id"  # id, json, export, install-config
QUIET=false
OPENSHIFT_INSTALL_PATH=""
DUAL_AMI=false
MASTER_AMI_REGION=""
WORKER_AMI_REGION=""

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

RHCOS AMI Discovery Script
Finds the latest RHCOS AMI ID for a given region using openshift-install

OPTIONS:
    -r, --region REGION       AWS region (default: us-east-2)
    -a, --arch ARCHITECTURE   Architecture (default: x86_64)
    -f, --format FORMAT       Output format: id, json, export, install-config (default: id)
    -p, --path PATH           Path to openshift-install binary (optional)
    -d, --dual-ami            Generate dual AMI configuration (master and worker)
    --master-region REGION    Region for master AMI (for dual-ami mode)
    --worker-region REGION    Region for worker AMI (for dual-ami mode)
    -q, --quiet               Quiet mode - only output AMI ID
    -h, --help                Show this help message

OUTPUT FORMATS:
    id              - Output only the AMI ID (default)
    json            - Output full JSON information
    export          - Output as export command for environment variable
    install-config  - Output install-config.yaml snippet for dual AMI

EXAMPLES:
    $0                                    # Get AMI ID for us-east-2
    $0 -r us-west-2                       # Get AMI ID for us-west-2
    $0 -r us-east-1 -f export             # Output as export command
    $0 -r eu-west-1 -f json               # Output full JSON
    $0 -r ap-southeast-1 -q               # Quiet mode, only AMI ID
    $0 -p /path/to/openshift-install      # Use specific openshift-install binary
    $0 -d -f install-config               # Generate dual AMI install-config snippet
    $0 -d --master-region us-east-1 --worker-region us-west-2  # Different regions for master/worker

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -a|--arch)
            ARCHITECTURE="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -p|--path)
            OPENSHIFT_INSTALL_PATH="$2"
            shift 2
            ;;
        -d|--dual-ami)
            DUAL_AMI=true
            shift
            ;;
        --master-region)
            MASTER_AMI_REGION="$2"
            shift 2
            ;;
        --worker-region)
            WORKER_AMI_REGION="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET=true
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

# Validate output format
case "$OUTPUT_FORMAT" in
    id|json|export|install-config)
        ;;
    *)
        print_error "Invalid output format: $OUTPUT_FORMAT"
        print_error "Valid formats: id, json, export, install-config"
        exit 1
        ;;
esac

# Set default regions for dual AMI mode
if [ "$DUAL_AMI" = true ]; then
    if [ -z "$MASTER_AMI_REGION" ]; then
        MASTER_AMI_REGION="$REGION"
    fi
    if [ -z "$WORKER_AMI_REGION" ]; then
        WORKER_AMI_REGION="$REGION"
    fi
fi

# Determine openshift-install command
OPENSHIFT_INSTALL_CMD=""
if [ -n "$OPENSHIFT_INSTALL_PATH" ]; then
    # Use specified path
    if [ -f "$OPENSHIFT_INSTALL_PATH" ] && [ -x "$OPENSHIFT_INSTALL_PATH" ]; then
        OPENSHIFT_INSTALL_CMD="$OPENSHIFT_INSTALL_PATH"
    else
        print_error "openshift-install binary not found or not executable: $OPENSHIFT_INSTALL_PATH"
        exit 1
    fi
else
    # Use openshift-install from PATH
    if command -v openshift-install &> /dev/null; then
        OPENSHIFT_INSTALL_CMD="openshift-install"
    else
        print_error "openshift-install command not found"
        print_error "Please ensure openshift-install is installed and in your PATH, or use -p option to specify the path"
        exit 1
    fi
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq command not found"
    print_error "Please install jq: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

# Function to get AMI ID for a specific region
get_ami_id() {
    local target_region="$1"
    local stream_json="$2"
    
    local ami_id
    ami_id=$(echo "$stream_json" | jq -r --arg region "$target_region" --arg arch "$ARCHITECTURE" '.architectures[$arch].images.aws.regions[$region].image' 2>/dev/null)
    
    if [[ -z "$ami_id" || "$ami_id" = "null" ]]; then
        print_error "RHCOS AMI was NOT found in region $target_region for architecture $ARCHITECTURE"
        return 1
    fi
    
    echo "$ami_id"
}

# Main function
main() {
    if [ "$QUIET" = false ]; then
        print_info "Fetching RHCOS AMI using openshift-install..."
        if [ "$DUAL_AMI" = true ]; then
            print_info "Dual AMI mode: Master region: $MASTER_AMI_REGION, Worker region: $WORKER_AMI_REGION"
        else
            print_info "Region: $REGION"
        fi
        print_info "Architecture: $ARCHITECTURE"
    fi
    
    # Get the stream JSON from openshift-install
    local stream_json
    if ! stream_json=$("$OPENSHIFT_INSTALL_CMD" coreos print-stream-json 2>/dev/null); then
        print_error "Failed to get RHCOS stream JSON from openshift-install"
        print_error "Command used: $OPENSHIFT_INSTALL_CMD"
        exit 1
    fi
    
    # Handle dual AMI mode
    if [ "$DUAL_AMI" = true ]; then
        handle_dual_ami_mode "$stream_json"
        return
    fi
    
    # Extract AMI ID based on output format
    case "$OUTPUT_FORMAT" in
        "id")
            local ami_id
            ami_id=$(get_ami_id "$REGION" "$stream_json")
            if [ $? -ne 0 ]; then
                exit 1
            fi
            
            if [ "$QUIET" = false ]; then
                print_success "Found RHCOS AMI ID: $ami_id"
            else
                echo "$ami_id"
            fi
            ;;
            
        "json")
            local region_data
            region_data=$(echo "$stream_json" | jq --arg region "$REGION" --arg arch "$ARCHITECTURE" '.architectures[$arch].images.aws.regions[$region]' 2>/dev/null)
            
            if [[ -z "$region_data" || "$region_data" = "null" ]]; then
                print_error "RHCOS AMI data was NOT found in region $REGION for architecture $ARCHITECTURE"
                exit 1
            fi
            
            if [ "$QUIET" = false ]; then
                print_success "Found RHCOS AMI data for region $REGION:"
            fi
            echo "$region_data" | jq .
            ;;
            
        "export")
            local ami_id
            ami_id=$(get_ami_id "$REGION" "$stream_json")
            if [ $? -ne 0 ]; then
                exit 1
            fi
            
            if [ "$QUIET" = false ]; then
                print_success "Found RHCOS AMI ID: $ami_id"
                print_info "Export command:"
            fi
            echo "export RHCOS_AMI_ID=\"$ami_id\""
            ;;
    esac
}

# Handle dual AMI mode
handle_dual_ami_mode() {
    local stream_json="$1"
    
    # Get master and worker AMI IDs
    local master_ami
    local worker_ami
    
    master_ami=$(get_ami_id "$MASTER_AMI_REGION" "$stream_json")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    worker_ami=$(get_ami_id "$WORKER_AMI_REGION" "$stream_json")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    if [ "$QUIET" = false ]; then
        print_success "Found Master AMI ID: $master_ami (region: $MASTER_AMI_REGION)"
        print_success "Found Worker AMI ID: $worker_ami (region: $WORKER_AMI_REGION)"
    fi
    
    case "$OUTPUT_FORMAT" in
        "id")
            if [ "$QUIET" = false ]; then
                echo "Master AMI: $master_ami"
                echo "Worker AMI: $worker_ami"
            else
                echo "$master_ami"
                echo "$worker_ami"
            fi
            ;;
        "export")
            if [ "$QUIET" = false ]; then
                print_info "Export commands:"
            fi
            echo "export MASTER_AMI_ID=\"$master_ami\""
            echo "export WORKER_AMI_ID=\"$worker_ami\""
            ;;
        "install-config")
            if [ "$QUIET" = false ]; then
                print_info "Install-config.yaml snippet for dual AMI:"
            fi
            cat << EOF
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      amiID: $worker_ami
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      amiID: $master_ami
  replicas: 3
EOF
            ;;
        "json")
            if [ "$QUIET" = false ]; then
                print_info "Dual AMI configuration:"
            fi
            cat << EOF | jq .
{
  "master": {
    "region": "$MASTER_AMI_REGION",
    "ami_id": "$master_ami"
  },
  "worker": {
    "region": "$WORKER_AMI_REGION", 
    "ami_id": "$worker_ami"
  }
}
EOF
            ;;
    esac
}

# Run main function
main "$@"
