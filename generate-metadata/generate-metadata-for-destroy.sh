#!/bin/bash

# generate-metadata-for-destroy.sh
# Used to dynamically generate metadata.json for destroying OpenShift clusters when the original metadata.json file is not available
# Based on OCP-22168 test case requirements

set -o nounset
set -o errexit
set -o pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Display help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Dynamically generate metadata.json file for destroying OpenShift clusters

OPTIONS:
    -c, --cluster-name CLUSTER_NAME    Cluster name (required)
    -r, --region REGION                AWS region (required)
    -i, --infra-id INFRA_ID           Infrastructure ID (required)
    -u, --cluster-id CLUSTER_ID       Cluster UUID (required)
    -o, --output-dir OUTPUT_DIR       Output directory (default: ./cleanup)
    -h, --help                        Display this help information

EXAMPLES:
    # Basic usage
    $0 -c "my-cluster" -r "us-east-1" -i "my-cluster-abc123" -u "12345678-1234-1234-1234-123456789012"
    
    # Specify output directory
    $0 -c "my-cluster" -r "us-east-1" -i "my-cluster-abc123" -u "12345678-1234-1234-1234-123456789012" -o "/tmp/cleanup"

NOTES:
    - This script is based on OCP-22168 test case requirements
    - The generated metadata.json file can be used with the openshift-install destroy cluster command
    - Supports OpenShift 4.16+ metadata.json format
EOF
}

# 默认值
OUTPUT_DIR="./cleanup"
CLUSTER_NAME=""
REGION=""
INFRA_ID=""
CLUSTER_ID=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -i|--infra-id)
            INFRA_ID="$2"
            shift 2
            ;;
        -u|--cluster-id)
            CLUSTER_ID="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
validate_parameters() {
    local missing_params=()
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        missing_params+=("--cluster-name")
    fi
    
    if [[ -z "$REGION" ]]; then
        missing_params+=("--region")
    fi
    
    if [[ -z "$INFRA_ID" ]]; then
        missing_params+=("--infra-id")
    fi
    
    if [[ -z "$CLUSTER_ID" ]]; then
        missing_params+=("--cluster-id")
    fi
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        log_error "Missing required parameters: ${missing_params[*]}"
        echo
        show_help
        exit 1
    fi
}

# Validate AWS CLI and jq
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed or not in PATH"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# Validate AWS credentials and region
validate_aws() {
    log_info "验证 AWS 配置..."
    
    # 检查 AWS 凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are invalid or not configured"
        exit 1
    fi
    
    # 检查区域是否有效
    if ! aws ec2 describe-regions --region-names "$REGION" &> /dev/null; then
        log_error "AWS region '$REGION' is invalid"
        exit 1
    fi
    
    log_success "AWS 配置验证通过"
}

# Validate if cluster resources exist
validate_cluster_resources() {
    log_info "验证集群资源..."
    
    # 检查 VPC 标签
    local vpc_found=false
    local vpcs=$(aws --region "$REGION" ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/$INFRA_ID,Values=owned" --query 'Vpcs[].VpcId' --output text)
    
    if [[ -n "$vpcs" ]]; then
        log_success "Found VPC: $vpcs"
        vpc_found=true
    else
        log_warning "No VPC found tagged with 'kubernetes.io/cluster/$INFRA_ID: owned'"
    fi
    
    # 检查 openshiftClusterID 标签
    local cluster_resources=$(aws --region "$REGION" resourcegroupstaggingapi get-tag-values --key openshiftClusterID --query "TagValues[?contains(@, '$CLUSTER_ID')]" --output text 2>/dev/null || echo "")
    
    if [[ -n "$cluster_resources" ]]; then
        log_success "Found resources tagged with 'openshiftClusterID: $CLUSTER_ID'"
    else
        log_warning "No resources found tagged with 'openshiftClusterID: $CLUSTER_ID'"
    fi
    
    if [[ "$vpc_found" == false && -z "$cluster_resources" ]]; then
        log_error "No resources related to the specified cluster were found, please check if parameters are correct"
        exit 1
    fi
}

# Generate metadata.json file
generate_metadata() {
    log_info "生成 metadata.json 文件..."
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    # 生成 metadata.json 内容
    local metadata_file="$OUTPUT_DIR/metadata.json"
    
    cat > "$metadata_file" << EOF
{
  "clusterName": "$CLUSTER_NAME",
  "clusterID": "$CLUSTER_ID",
  "infraID": "$INFRA_ID",
  "aws": {
    "region": "$REGION",
    "identifier": [
      {
        "kubernetes.io/cluster/$INFRA_ID": "owned"
      },
      {
        "openshiftClusterID": "$CLUSTER_ID"
      },
      {
        "sigs.k8s.io/cluster-api-provider-aws/cluster/$INFRA_ID": "owned"
      }
    ]
  }
}
EOF
    
    log_success "metadata.json file generated: $metadata_file"
    
    # 显示生成的内容
    log_info "Generated metadata.json content:"
    cat "$metadata_file" | jq .
}

# Validate generated metadata.json
validate_metadata() {
    log_info "验证生成的 metadata.json..."
    
    local metadata_file="$OUTPUT_DIR/metadata.json"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "metadata.json file does not exist: $metadata_file"
        exit 1
    fi
    
    # 验证 JSON 格式
    if ! jq empty "$metadata_file" 2>/dev/null; then
        log_error "metadata.json file format is invalid"
        exit 1
    fi
    
    # 验证必需字段
    local required_fields=("clusterName" "clusterID" "infraID" "aws.region" "aws.identifier")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$metadata_file" > /dev/null 2>&1; then
            log_error "metadata.json missing required field: $field"
            exit 1
        fi
    done
    
    log_success "metadata.json 验证通过"
}

# Provide destroy command examples
show_destroy_example() {
    log_info "销毁命令示例:"
    echo
    echo "cd $OUTPUT_DIR"
    echo "openshift-install destroy cluster --dir . --log-level debug"
    echo
    log_warning "Note: Please ensure to run the destroy command in the correct directory"
}

# Provide verification command examples
show_verification_example() {
    log_info "Command examples for verifying resource cleanup:"
    echo
    echo "# Check openshiftClusterID tags"
    echo "aws --region $REGION resourcegroupstaggingapi get-tag-values --key openshiftClusterID | grep '$CLUSTER_ID'"
    echo
    echo "# Check kubernetes.io/cluster tags"
    echo "aws --region $REGION resourcegroupstaggingapi get-tag-keys | grep 'kubernetes.io/cluster/$INFRA_ID'"
    echo
    echo "# Check all related resources"
    echo "aws --region $REGION resourcegroupstaggingapi get-resources --tag-filters 'Key=openshiftClusterID,Values=$CLUSTER_ID'"
    echo "aws --region $REGION resourcegroupstaggingapi get-resources --tag-filters 'Key=kubernetes.io/cluster/$INFRA_ID,Values=owned'"
}

# 主函数
main() {
    log_info "Starting to generate metadata.json file..."
    log_info "Cluster name: $CLUSTER_NAME"
    log_info "AWS region: $REGION"
    log_info "Infrastructure ID: $INFRA_ID"
    log_info "Cluster ID: $CLUSTER_ID"
    log_info "Output directory: $OUTPUT_DIR"
    echo
    
    # 执行验证和生成步骤
    validate_parameters
    check_dependencies
    validate_aws
    validate_cluster_resources
    generate_metadata
    validate_metadata
    
    echo
    log_success "metadata.json file generation completed!"
    echo
    show_destroy_example
    echo
    show_verification_example
}

# 运行主函数
main "$@"
