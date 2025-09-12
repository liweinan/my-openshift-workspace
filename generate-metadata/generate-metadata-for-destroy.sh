帮我床架#!/bin/bash

# generate-metadata-for-destroy.sh
# 用于在没有原始 metadata.json 文件的情况下，动态生成 metadata.json 来销毁 OpenShift 集群
# 基于 OCP-22168 测试用例的要求

set -o nounset
set -o errexit
set -o pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 显示帮助信息
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

动态生成 metadata.json 文件用于销毁 OpenShift 集群

OPTIONS:
    -c, --cluster-name CLUSTER_NAME    集群名称 (必需)
    -r, --region REGION                AWS 区域 (必需)
    -i, --infra-id INFRA_ID           基础设施 ID (必需)
    -u, --cluster-id CLUSTER_ID       集群 UUID (必需)
    -o, --output-dir OUTPUT_DIR       输出目录 (默认: ./cleanup)
    -h, --help                        显示此帮助信息

EXAMPLES:
    # 基本用法
    $0 -c "my-cluster" -r "us-east-1" -i "my-cluster-abc123" -u "12345678-1234-1234-1234-123456789012"
    
    # 指定输出目录
    $0 -c "my-cluster" -r "us-east-1" -i "my-cluster-abc123" -u "12345678-1234-1234-1234-123456789012" -o "/tmp/cleanup"

NOTES:
    - 此脚本基于 OCP-22168 测试用例的要求
    - 生成的 metadata.json 文件可以用于 openshift-install destroy cluster 命令
    - 支持 OpenShift 4.16+ 的 metadata.json 格式
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
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 验证必需参数
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
        log_error "缺少必需参数: ${missing_params[*]}"
        echo
        show_help
        exit 1
    fi
}

# 验证 AWS CLI 和 jq
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安装或不在 PATH 中"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq 未安装或不在 PATH 中"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 验证 AWS 凭证和区域
validate_aws() {
    log_info "验证 AWS 配置..."
    
    # 检查 AWS 凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 凭证无效或未配置"
        exit 1
    fi
    
    # 检查区域是否有效
    if ! aws ec2 describe-regions --region-names "$REGION" &> /dev/null; then
        log_error "AWS 区域 '$REGION' 无效"
        exit 1
    fi
    
    log_success "AWS 配置验证通过"
}

# 验证集群资源是否存在
validate_cluster_resources() {
    log_info "验证集群资源..."
    
    # 检查 VPC 标签
    local vpc_found=false
    local vpcs=$(aws --region "$REGION" ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/$INFRA_ID,Values=owned" --query 'Vpcs[].VpcId' --output text)
    
    if [[ -n "$vpcs" ]]; then
        log_success "找到 VPC: $vpcs"
        vpc_found=true
    else
        log_warning "未找到标记为 'kubernetes.io/cluster/$INFRA_ID: owned' 的 VPC"
    fi
    
    # 检查 openshiftClusterID 标签
    local cluster_resources=$(aws --region "$REGION" resourcegroupstaggingapi get-tag-values --key openshiftClusterID --query "TagValues[?contains(@, '$CLUSTER_ID')]" --output text 2>/dev/null || echo "")
    
    if [[ -n "$cluster_resources" ]]; then
        log_success "找到标记为 'openshiftClusterID: $CLUSTER_ID' 的资源"
    else
        log_warning "未找到标记为 'openshiftClusterID: $CLUSTER_ID' 的资源"
    fi
    
    if [[ "$vpc_found" == false && -z "$cluster_resources" ]]; then
        log_error "未找到任何与指定集群相关的资源，请检查参数是否正确"
        exit 1
    fi
}

# 生成 metadata.json 文件
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
    
    log_success "metadata.json 文件已生成: $metadata_file"
    
    # 显示生成的内容
    log_info "生成的 metadata.json 内容:"
    cat "$metadata_file" | jq .
}

# 验证生成的 metadata.json
validate_metadata() {
    log_info "验证生成的 metadata.json..."
    
    local metadata_file="$OUTPUT_DIR/metadata.json"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "metadata.json 文件不存在: $metadata_file"
        exit 1
    fi
    
    # 验证 JSON 格式
    if ! jq empty "$metadata_file" 2>/dev/null; then
        log_error "metadata.json 文件格式无效"
        exit 1
    fi
    
    # 验证必需字段
    local required_fields=("clusterName" "clusterID" "infraID" "aws.region" "aws.identifier")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$metadata_file" > /dev/null 2>&1; then
            log_error "metadata.json 缺少必需字段: $field"
            exit 1
        fi
    done
    
    log_success "metadata.json 验证通过"
}

# 提供销毁命令示例
show_destroy_example() {
    log_info "销毁命令示例:"
    echo
    echo "cd $OUTPUT_DIR"
    echo "openshift-install destroy cluster --dir . --log-level debug"
    echo
    log_warning "注意: 请确保在正确的目录中运行销毁命令"
}

# 提供验证命令示例
show_verification_example() {
    log_info "验证资源清理的命令示例:"
    echo
    echo "# 检查 openshiftClusterID 标签"
    echo "aws --region $REGION resourcegroupstaggingapi get-tag-values --key openshiftClusterID | grep '$CLUSTER_ID'"
    echo
    echo "# 检查 kubernetes.io/cluster 标签"
    echo "aws --region $REGION resourcegroupstaggingapi get-tag-keys | grep 'kubernetes.io/cluster/$INFRA_ID'"
    echo
    echo "# 检查所有相关资源"
    echo "aws --region $REGION resourcegroupstaggingapi get-resources --tag-filters 'Key=openshiftClusterID,Values=$CLUSTER_ID'"
    echo "aws --region $REGION resourcegroupstaggingapi get-resources --tag-filters 'Key=kubernetes.io/cluster/$INFRA_ID,Values=owned'"
}

# 主函数
main() {
    log_info "开始生成 metadata.json 文件..."
    log_info "集群名称: $CLUSTER_NAME"
    log_info "AWS 区域: $REGION"
    log_info "基础设施 ID: $INFRA_ID"
    log_info "集群 ID: $CLUSTER_ID"
    log_info "输出目录: $OUTPUT_DIR"
    echo
    
    # 执行验证和生成步骤
    validate_parameters
    check_dependencies
    validate_aws
    validate_cluster_resources
    generate_metadata
    validate_metadata
    
    echo
    log_success "metadata.json 文件生成完成！"
    echo
    show_destroy_example
    echo
    show_verification_example
}

# 运行主函数
main "$@"
