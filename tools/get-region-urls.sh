#!/bin/bash

# Get Region URLs Script
# This script helps you get various URLs for different AWS regions

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REGION="us-east-2"
SERVICE="all"
FORMAT="table"
QUIET=false

# Print functions
print_info() {
    [[ "$QUIET" == "false" ]] && echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    [[ "$QUIET" == "false" ]] && echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    [[ "$QUIET" == "false" ]] && echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Show help
show_help() {
    cat << EOF
Get Region URLs Script

This script helps you get various URLs for different AWS regions including:
- AWS service endpoints
- OpenShift image registry URLs
- RHCOS image URLs
- S3 bucket URLs

Usage: $0 [OPTIONS]

Options:
    -r, --region REGION       AWS region (default: us-east-2)
    -s, --service SERVICE     Service type: aws, openshift, rhcos, s3, all (default: all)
    -f, --format FORMAT       Output format: table, json, export (default: table)
    -q, --quiet               Quiet mode (minimal output)
    -h, --help                Show this help message

Examples:
    $0                                    # Get all URLs for us-east-2
    $0 -r us-west-2 -s aws               # Get AWS service endpoints for us-west-2
    $0 -r eu-west-1 -s openshift -f json # Get OpenShift URLs in JSON format
    $0 -r ap-southeast-1 -s rhcos        # Get RHCOS URLs for ap-southeast-1
    $0 -r us-gov-west-1 -s s3            # Get S3 URLs for us-gov-west-1

Services:
    aws        - AWS service endpoints (EC2, S3, IAM, etc.)
    openshift  - OpenShift image registry URLs
    rhcos      - RHCOS image URLs
    s3         - S3 bucket and endpoint URLs
    all        - All service types (default)

Output Formats:
    table      - Human-readable table format
    json       - JSON format for programmatic use
    export     - Shell export statements

EOF
}

# Get AWS service endpoints
get_aws_endpoints() {
    local region="$1"
    local format="$2"
    
    case "$format" in
        "json")
            cat << EOF
{
  "region": "$region",
  "aws_endpoints": {
    "ec2": "https://ec2.$region.amazonaws.com",
    "s3": "https://s3.$region.amazonaws.com",
    "iam": "https://iam.amazonaws.com",
    "route53": "https://route53.amazonaws.com",
    "cloudformation": "https://cloudformation.$region.amazonaws.com",
    "elb": "https://elasticloadbalancing.$region.amazonaws.com",
    "elbv2": "https://elasticloadbalancing.$region.amazonaws.com",
    "kms": "https://kms.$region.amazonaws.com",
    "sts": "https://sts.amazonaws.com",
    "sns": "https://sns.$region.amazonaws.com",
    "sqs": "https://sqs.$region.amazonaws.com"
  }
}
EOF
            ;;
        "export")
            cat << EOF
export AWS_EC2_ENDPOINT="https://ec2.$region.amazonaws.com"
export AWS_S3_ENDPOINT="https://s3.$region.amazonaws.com"
export AWS_IAM_ENDPOINT="https://iam.amazonaws.com"
export AWS_ROUTE53_ENDPOINT="https://route53.amazonaws.com"
export AWS_CLOUDFORMATION_ENDPOINT="https://cloudformation.$region.amazonaws.com"
export AWS_ELB_ENDPOINT="https://elasticloadbalancing.$region.amazonaws.com"
export AWS_ELBV2_ENDPOINT="https://elasticloadbalancing.$region.amazonaws.com"
export AWS_KMS_ENDPOINT="https://kms.$region.amazonaws.com"
export AWS_STS_ENDPOINT="https://sts.amazonaws.com"
export AWS_SNS_ENDPOINT="https://sns.$region.amazonaws.com"
export AWS_SQS_ENDPOINT="https://sqs.$region.amazonaws.com"
EOF
            ;;
        *)
            cat << EOF
AWS Service Endpoints for $region:
┌─────────────────────┬─────────────────────────────────────────────┐
│ Service             │ Endpoint URL                                │
├─────────────────────┼─────────────────────────────────────────────┤
│ EC2                 │ https://ec2.$region.amazonaws.com          │
│ S3                  │ https://s3.$region.amazonaws.com           │
│ IAM                 │ https://iam.amazonaws.com                  │
│ Route53             │ https://route53.amazonaws.com              │
│ CloudFormation      │ https://cloudformation.$region.amazonaws.com │
│ ELB                 │ https://elasticloadbalancing.$region.amazonaws.com │
│ ELBv2               │ https://elasticloadbalancing.$region.amazonaws.com │
│ KMS                 │ https://kms.$region.amazonaws.com          │
│ STS                 │ https://sts.amazonaws.com                  │
│ SNS                 │ https://sns.$region.amazonaws.com          │
│ SQS                 │ https://sqs.$region.amazonaws.com          │
└─────────────────────┴─────────────────────────────────────────────┘
EOF
            ;;
    esac
}

# Get OpenShift image registry URLs
get_openshift_urls() {
    local region="$1"
    local format="$2"
    
    case "$format" in
        "json")
            cat << EOF
{
  "region": "$region",
  "openshift_urls": {
    "release_image": "quay.io/openshift-release-dev/ocp-release:4.15.0-ec.1-x86_64",
    "registry": "quay.io",
    "release_registry": "quay.io/openshift-release-dev",
    "community_registry": "quay.io/openshift",
    "redhat_registry": "registry.redhat.io",
    "mirror_registry": "registry.openshift.com"
  }
}
EOF
            ;;
        "export")
            cat << EOF
export OPENSHIFT_RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.15.0-ec.1-x86_64"
export OPENSHIFT_REGISTRY="quay.io"
export OPENSHIFT_RELEASE_REGISTRY="quay.io/openshift-release-dev"
export OPENSHIFT_COMMUNITY_REGISTRY="quay.io/openshift"
export REDHAT_REGISTRY="registry.redhat.io"
export MIRROR_REGISTRY="registry.openshift.com"
EOF
            ;;
        *)
            cat << EOF
OpenShift Image Registry URLs:
┌─────────────────────────────┬─────────────────────────────────────────────┐
│ Registry Type               │ URL                                          │
├─────────────────────────────┼─────────────────────────────────────────────┤
│ Release Image               │ quay.io/openshift-release-dev/ocp-release:4.15.0-ec.1-x86_64 │
│ Main Registry               │ quay.io                                      │
│ Release Registry            │ quay.io/openshift-release-dev               │
│ Community Registry          │ quay.io/openshift                           │
│ Red Hat Registry            │ registry.redhat.io                          │
│ Mirror Registry             │ registry.openshift.com                      │
└─────────────────────────────┴─────────────────────────────────────────────┘
EOF
            ;;
    esac
}

# Get RHCOS image URLs
get_rhcos_urls() {
    local region="$1"
    local format="$2"
    
    case "$format" in
        "json")
            cat << EOF
{
  "region": "$region",
  "rhcos_urls": {
    "meta_json": "https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/meta.json",
    "stream_json": "https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/stream.json",
    "base_url": "https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/",
    "ami_lookup": "Use: openshift-install coreos print-stream-json"
  }
}
EOF
            ;;
        "export")
            cat << EOF
export RHCOS_META_JSON_URL="https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/meta.json"
export RHCOS_STREAM_JSON_URL="https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/stream.json"
export RHCOS_BASE_URL="https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/"
EOF
            ;;
        *)
            cat << EOF
RHCOS Image URLs:
┌─────────────────────────────┬─────────────────────────────────────────────┐
│ Resource Type               │ URL                                          │
├─────────────────────────────┼─────────────────────────────────────────────┤
│ Meta JSON                   │ https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/meta.json │
│ Stream JSON                 │ https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/stream.json │
│ Base URL                    │ https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/ │
│ AMI Lookup                  │ Use: openshift-install coreos print-stream-json │
└─────────────────────────────┴─────────────────────────────────────────────┘
EOF
            ;;
    esac
}

# Get S3 URLs
get_s3_urls() {
    local region="$1"
    local format="$2"
    
    case "$format" in
        "json")
            cat << EOF
{
  "region": "$region",
  "s3_urls": {
    "endpoint": "https://s3.$region.amazonaws.com",
    "website_endpoint": "https://s3-website-$region.amazonaws.com",
    "dualstack_endpoint": "https://s3.dualstack.$region.amazonaws.com",
    "accelerate_endpoint": "https://s3-accelerate.amazonaws.com",
    "transfer_acceleration": "https://s3-accelerate.amazonaws.com"
  }
}
EOF
            ;;
        "export")
            cat << EOF
export S3_ENDPOINT="https://s3.$region.amazonaws.com"
export S3_WEBSITE_ENDPOINT="https://s3-website-$region.amazonaws.com"
export S3_DUALSTACK_ENDPOINT="https://s3.dualstack.$region.amazonaws.com"
export S3_ACCELERATE_ENDPOINT="https://s3-accelerate.amazonaws.com"
export S3_TRANSFER_ACCELERATION="https://s3-accelerate.amazonaws.com"
EOF
            ;;
        *)
            cat << EOF
S3 URLs for $region:
┌─────────────────────────────┬─────────────────────────────────────────────┐
│ S3 Endpoint Type            │ URL                                          │
├─────────────────────────────┼─────────────────────────────────────────────┤
│ Standard Endpoint           │ https://s3.$region.amazonaws.com           │
│ Website Endpoint            │ https://s3-website-$region.amazonaws.com   │
│ Dual-Stack Endpoint         │ https://s3.dualstack.$region.amazonaws.com │
│ Accelerate Endpoint         │ https://s3-accelerate.amazonaws.com        │
│ Transfer Acceleration       │ https://s3-accelerate.amazonaws.com        │
└─────────────────────────────┴─────────────────────────────────────────────┘
EOF
            ;;
    esac
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -s|--service)
                SERVICE="$2"
                shift 2
                ;;
            -f|--format)
                FORMAT="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate inputs
    if [[ ! "$FORMAT" =~ ^(table|json|export)$ ]]; then
        print_error "Invalid format: $FORMAT. Must be one of: table, json, export"
        exit 1
    fi

    if [[ ! "$SERVICE" =~ ^(aws|openshift|rhcos|s3|all)$ ]]; then
        print_error "Invalid service: $SERVICE. Must be one of: aws, openshift, rhcos, s3, all"
        exit 1
    fi

    print_info "Getting URLs for region: $REGION, service: $SERVICE, format: $FORMAT"

    # Generate output based on service type
    case "$SERVICE" in
        "aws")
            get_aws_endpoints "$REGION" "$FORMAT"
            ;;
        "openshift")
            get_openshift_urls "$REGION" "$FORMAT"
            ;;
        "rhcos")
            get_rhcos_urls "$REGION" "$FORMAT"
            ;;
        "s3")
            get_s3_urls "$REGION" "$FORMAT"
            ;;
        "all")
            if [[ "$FORMAT" == "json" ]]; then
                cat << EOF
{
  "region": "$REGION",
  "aws_endpoints": {
    "ec2": "https://ec2.$REGION.amazonaws.com",
    "s3": "https://s3.$REGION.amazonaws.com",
    "iam": "https://iam.amazonaws.com",
    "route53": "https://route53.amazonaws.com",
    "cloudformation": "https://cloudformation.$REGION.amazonaws.com",
    "elb": "https://elasticloadbalancing.$REGION.amazonaws.com",
    "elbv2": "https://elasticloadbalancing.$REGION.amazonaws.com",
    "kms": "https://kms.$REGION.amazonaws.com",
    "sts": "https://sts.amazonaws.com",
    "sns": "https://sns.$REGION.amazonaws.com",
    "sqs": "https://sqs.$REGION.amazonaws.com"
  },
  "openshift_urls": {
    "release_image": "quay.io/openshift-release-dev/ocp-release:4.15.0-ec.1-x86_64",
    "registry": "quay.io",
    "release_registry": "quay.io/openshift-release-dev",
    "community_registry": "quay.io/openshift",
    "redhat_registry": "registry.redhat.io",
    "mirror_registry": "registry.openshift.com"
  },
  "rhcos_urls": {
    "meta_json": "https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/meta.json",
    "stream_json": "https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/stream.json",
    "base_url": "https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-4.15/x86_64/",
    "ami_lookup": "Use: openshift-install coreos print-stream-json"
  },
  "s3_urls": {
    "endpoint": "https://s3.$REGION.amazonaws.com",
    "website_endpoint": "https://s3-website-$REGION.amazonaws.com",
    "dualstack_endpoint": "https://s3.dualstack.$REGION.amazonaws.com",
    "accelerate_endpoint": "https://s3-accelerate.amazonaws.com",
    "transfer_acceleration": "https://s3-accelerate.amazonaws.com"
  }
}
EOF
            elif [[ "$FORMAT" == "export" ]]; then
                echo "# AWS Service Endpoints"
                get_aws_endpoints "$REGION" "export"
                echo ""
                echo "# OpenShift URLs"
                get_openshift_urls "$REGION" "export"
                echo ""
                echo "# RHCOS URLs"
                get_rhcos_urls "$REGION" "export"
                echo ""
                echo "# S3 URLs"
                get_s3_urls "$REGION" "export"
            else
                echo "=== AWS Service Endpoints ==="
                get_aws_endpoints "$REGION" "$FORMAT"
                echo ""
                echo "=== OpenShift Image Registry URLs ==="
                get_openshift_urls "$REGION" "$FORMAT"
                echo ""
                echo "=== RHCOS Image URLs ==="
                get_rhcos_urls "$REGION" "$FORMAT"
                echo ""
                echo "=== S3 URLs ==="
                get_s3_urls "$REGION" "$FORMAT"
            fi
            ;;
    esac

    print_success "URLs retrieved successfully for region: $REGION"
}

# Run main function
main "$@"
