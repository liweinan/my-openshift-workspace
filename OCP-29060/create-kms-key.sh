#!/bin/bash

# OCP-29060 KMS Key Creation Script
# Creates a KMS symmetric key for OpenShift cluster encryption

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
DESCRIPTION="OpenShift cluster encryption key for testing"
KEY_POLICY_FILE=""
OUTPUT_FILE="kms-key-info.json"
DRY_RUN=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OCP-29060 KMS Key Creation Script
Creates a KMS symmetric key for OpenShift cluster encryption

OPTIONS:
    -r, --region REGION       AWS region (default: us-east-2)
    -d, --description DESC    Key description (default: "OpenShift cluster encryption key for testing")
    -p, --policy-file FILE    Path to custom key policy JSON file (optional)
    -o, --output FILE         Output file for key information (default: kms-key-info.json)
    --dry-run                 Show what would be created without actually creating
    -h, --help                Show this help message

EXAMPLES:
    $0                                    # Create KMS key in us-east-2
    $0 -r us-west-2                       # Create KMS key in us-west-2
    $0 -d "My custom key"                 # Create with custom description
    $0 -p custom-policy.json              # Use custom key policy
    $0 --dry-run                          # Show what would be created

OUTPUT:
    The script will output:
    - Key ID
    - Key ARN
    - Key information saved to JSON file (if --output specified)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -d|--description)
            DESCRIPTION="$2"
            shift 2
            ;;
        -p|--policy-file)
            KEY_POLICY_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found"
    print_error "Please install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq command not found"
    print_error "Please install jq: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

# Get current user ARN
get_user_arn() {
    print_info "Getting current user ARN..."
    local user_arn
    user_arn=$(aws sts get-caller-identity --output json | jq -r '.Arn')
    
    if [[ -z "$user_arn" || "$user_arn" = "null" ]]; then
        print_error "Failed to get user ARN. Please check AWS credentials."
        exit 1
    fi
    
    print_success "User ARN: $user_arn"
    echo "$user_arn"
}

# Generate default key policy
generate_key_policy() {
    local user_arn="$1"
    
    cat << EOF
{
    "Id": "key-consolepolicy-3",
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "$user_arn"
            },
            "Action": "kms:*",
            "Resource": "*"
        }
    ]
}
EOF
}

# Create KMS key
create_kms_key() {
    local user_arn="$1"
    local key_policy
    
    print_info "Creating KMS key in region: $REGION"
    print_info "Description: $DESCRIPTION"
    
    # Generate or read key policy
    if [ -n "$KEY_POLICY_FILE" ]; then
        if [ ! -f "$KEY_POLICY_FILE" ]; then
            print_error "Key policy file not found: $KEY_POLICY_FILE"
            exit 1
        fi
        key_policy=$(cat "$KEY_POLICY_FILE")
        print_info "Using custom key policy from: $KEY_POLICY_FILE"
    else
        key_policy=$(generate_key_policy "$user_arn")
        print_info "Using default key policy"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would create KMS key with the following policy:"
        echo "$key_policy" | jq .
        return 0
    fi
    
    # Create the KMS key
    local create_result
    create_result=$(aws kms create-key \
        --region "$REGION" \
        --description "$DESCRIPTION" \
        --policy "$key_policy" \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_error "Failed to create KMS key"
        exit 1
    fi
    
    # Extract key information
    local key_id
    local key_arn
    key_id=$(echo "$create_result" | jq -r '.KeyMetadata.KeyId')
    key_arn=$(echo "$create_result" | jq -r '.KeyMetadata.Arn')
    
    print_success "KMS key created successfully!"
    print_success "Key ID: $key_id"
    print_success "Key ARN: $key_arn"
    
    # Save key information to file
    if [ -n "$OUTPUT_FILE" ]; then
        cat << EOF > "$OUTPUT_FILE"
{
    "keyId": "$key_id",
    "keyArn": "$key_arn",
    "region": "$REGION",
    "description": "$DESCRIPTION",
    "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        print_success "Key information saved to: $OUTPUT_FILE"
    fi
    
    # Output for easy copying
    echo ""
    print_info "Key information for install-config.yaml:"
    echo "Key ID: $key_id"
    echo "Key ARN: $key_arn"
    echo ""
    print_info "Add this to your install-config.yaml controlPlane section:"
    cat << EOF
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      rootVolume:
        kmsKeyARN: $key_arn
  replicas: 3
EOF
}

# Main function
main() {
    print_info "Starting OCP-29060 KMS key creation..."
    
    # Get user ARN
    local user_arn
    user_arn=$(get_user_arn)
    
    # Create KMS key
    create_kms_key "$user_arn"
    
    print_success "KMS key creation completed successfully!"
}

# Run main function
main "$@"
