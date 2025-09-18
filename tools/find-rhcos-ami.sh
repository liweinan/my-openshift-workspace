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
OUTPUT_FORMAT="id"  # id, json, export
QUIET=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

RHCOS AMI Discovery Script
Finds the latest RHCOS AMI ID for a given region using openshift-install

OPTIONS:
    -r, --region REGION       AWS region (default: us-east-2)
    -a, --arch ARCHITECTURE   Architecture (default: x86_64)
    -f, --format FORMAT       Output format: id, json, export (default: id)
    -q, --quiet               Quiet mode - only output AMI ID
    -h, --help                Show this help message

OUTPUT FORMATS:
    id      - Output only the AMI ID (default)
    json    - Output full JSON information
    export  - Output as export command for environment variable

EXAMPLES:
    $0                                    # Get AMI ID for us-east-2
    $0 -r us-west-2                       # Get AMI ID for us-west-2
    $0 -r us-east-1 -f export             # Output as export command
    $0 -r eu-west-1 -f json               # Output full JSON
    $0 -r ap-southeast-1 -q               # Quiet mode, only AMI ID

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
    id|json|export)
        ;;
    *)
        print_error "Invalid output format: $OUTPUT_FORMAT"
        print_error "Valid formats: id, json, export"
        exit 1
        ;;
esac

# Check if openshift-install is available
if ! command -v openshift-install &> /dev/null; then
    print_error "openshift-install command not found"
    print_error "Please ensure openshift-install is installed and in your PATH"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq command not found"
    print_error "Please install jq: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

# Main function
main() {
    if [ "$QUIET" = false ]; then
        print_info "Fetching RHCOS AMI using openshift-install..."
        print_info "Region: $REGION"
        print_info "Architecture: $ARCHITECTURE"
    fi
    
    # Get the stream JSON from openshift-install
    local stream_json
    if ! stream_json=$(openshift-install coreos print-stream-json 2>/dev/null); then
        print_error "Failed to get RHCOS stream JSON from openshift-install"
        exit 1
    fi
    
    # Extract AMI ID based on output format
    case "$OUTPUT_FORMAT" in
        "id")
            local ami_id
            ami_id=$(echo "$stream_json" | jq -r --arg region "$REGION" --arg arch "$ARCHITECTURE" '.architectures[$arch].images.aws.regions[$region].image' 2>/dev/null)
            
            if [[ -z "$ami_id" || "$ami_id" = "null" ]]; then
                print_error "RHCOS AMI was NOT found in region $REGION for architecture $ARCHITECTURE"
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
            ami_id=$(echo "$stream_json" | jq -r --arg region "$REGION" --arg arch "$ARCHITECTURE" '.architectures[$arch].images.aws.regions[$region].image' 2>/dev/null)
            
            if [[ -z "$ami_id" || "$ami_id" = "null" ]]; then
                print_error "RHCOS AMI was NOT found in region $REGION for architecture $ARCHITECTURE"
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

# Run main function
main "$@"
