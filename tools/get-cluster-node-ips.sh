#!/bin/bash
#
# get-cluster-node-ips.sh
# Get IP addresses of all nodes in OpenShift cluster
#
# Usage:
#   ./get-cluster-node-ips.sh [OPTIONS]
#
# Options:
#   -c, --cluster-name NAME    Cluster name (required)
#   -r, --region REGION        AWS region (default: us-east-1)
#   -f, --format FORMAT        Output format: table, json, export (default: table)
#   -t, --type TYPE           Node type: all, bootstrap, master, worker (default: all)
#   -v, --verbose             Verbose output
#   -h, --help                Show help message
#
# Examples:
#   ./get-cluster-node-ips.sh -c weli-testy
#   ./get-cluster-node-ips.sh -c weli-testy -r us-west-2 -f json
#   ./get-cluster-node-ips.sh -c weli-testy -t bootstrap -f export
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME=""
REGION="us-east-1"
FORMAT="table"
NODE_TYPE="all"
VERBOSE=false

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Show help
show_help() {
    cat << EOF
get-cluster-node-ips.sh - Get IP addresses of all nodes in OpenShift cluster

Usage:
    $0 [OPTIONS]

选项:
    -c, --cluster-name NAME    Cluster name (required)
    -r, --region REGION        AWS region (default: us-east-1)
    -f, --format FORMAT        Output format: table, json, export (default: table)
    -t, --type TYPE           Node type: all, bootstrap, master, worker (default: all)
    -v, --verbose             Verbose output
    -h, --help                Show help message

Output formats:
    table    - Table format display
    json     - JSON format output
    export   - Export as environment variable format

Node types:
    all      - All nodes (bootstrap, master, worker)
    bootstrap - Only bootstrap node
    master   - Only master nodes
    worker   - Only worker nodes

Examples:
    $0 -c weli-testy
    $0 -c weli-testy -r us-west-2 -f json
    $0 -c weli-testy -t bootstrap -f export
    $0 -c weli-testy -t master -f table -v

EOF
}

# Check dependencies
check_dependencies() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed or not in PATH"
        exit 1
    fi
    
    # 检查 AWS 凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured or invalid"
        exit 1
    fi
}

# Get bootstrap node IP
get_bootstrap_ip() {
    local bootstrap_ip
    
    # First try direct matching
    bootstrap_ip=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=${CLUSTER_NAME}-bootstrap" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
        --output json 2>/dev/null)
    
    # If not found, try format with infraID
    if [[ "$bootstrap_ip" == "[]" ]] || [[ -z "$bootstrap_ip" ]]; then
        bootstrap_ip=$(aws ec2 describe-instances \
            --region "$REGION" \
            --filters "Name=tag:Name,Values=${CLUSTER_NAME}-*-bootstrap" \
            --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
            --output json 2>/dev/null)
    fi
    
    if [[ "$bootstrap_ip" == "[]" ]] || [[ -z "$bootstrap_ip" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_warning "Bootstrap node not found"
        fi
        return 1
    fi
    
    echo "$bootstrap_ip"
}

# Get master node IPs
get_master_ips() {
    local master_ips
    
    # 首先尝试直接匹配
    master_ips=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=${CLUSTER_NAME}-master-*" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
        --output json 2>/dev/null)
    
    # 如果没找到，尝试带 infraID 的格式
    if [[ "$master_ips" == "[]" ]] || [[ -z "$master_ips" ]]; then
        master_ips=$(aws ec2 describe-instances \
            --region "$REGION" \
            --filters "Name=tag:Name,Values=${CLUSTER_NAME}-*-master-*" \
            --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
            --output json 2>/dev/null)
    fi
    
    if [[ "$master_ips" == "[]" ]] || [[ -z "$master_ips" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_warning "未找到 master 节点"
        fi
        return 1
    fi
    
    echo "$master_ips"
}

# Get worker node IPs
get_worker_ips() {
    local worker_ips
    
    # 首先尝试直接匹配
    worker_ips=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=${CLUSTER_NAME}-worker-*" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
        --output json 2>/dev/null)
    
    # 如果没找到，尝试带 infraID 的格式
    if [[ "$worker_ips" == "[]" ]] || [[ -z "$worker_ips" ]]; then
        worker_ips=$(aws ec2 describe-instances \
            --region "$REGION" \
            --filters "Name=tag:Name,Values=${CLUSTER_NAME}-*-worker-*" \
            --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
            --output json 2>/dev/null)
    fi
    
    if [[ "$worker_ips" == "[]" ]] || [[ -z "$worker_ips" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_warning "未找到 worker 节点"
        fi
        return 1
    fi
    
    echo "$worker_ips"
}

# Format output as table
format_table() {
    local data="$1"
    local node_type="$2"
    
    if [[ "$data" == "[]" ]] || [[ -z "$data" ]]; then
        return 0
    fi
    
    echo ""
    echo "=== $node_type Nodes ==="
    echo "Instance ID          | State      | Public IP      | Private IP"
    echo "---------------------|------------|----------------|----------------"
    
    echo "$data" | jq -r '.[] | .[] | [.[0], .[1], (.[2] // "N/A"), (.[3] // "N/A")] | @tsv' | while IFS=$'\t' read -r instance_id state public_ip private_ip; do
        printf "%-20s | %-10s | %-14s | %s\n" "$instance_id" "$state" "$public_ip" "$private_ip"
    done
}

# Format output as JSON
format_json() {
    local bootstrap_data="$1"
    local master_data="$2"
    local worker_data="$3"
    
    local result="{}"
    
    if [[ "$bootstrap_data" != "[]" ]] && [[ -n "$bootstrap_data" ]]; then
        result=$(echo "$result" | jq --argjson data "$bootstrap_data" '.bootstrap = $data')
    fi
    
    if [[ "$master_data" != "[]" ]] && [[ -n "$master_data" ]]; then
        result=$(echo "$result" | jq --argjson data "$master_data" '.master = $data')
    fi
    
    if [[ "$worker_data" != "[]" ]] && [[ -n "$worker_data" ]]; then
        result=$(echo "$result" | jq --argjson data "$worker_data" '.worker = $data')
    fi
    
    echo "$result" | jq .
}

# Format output as environment variables
format_export() {
    local bootstrap_data="$1"
    local master_data="$2"
    local worker_data="$3"
    
    echo "# OpenShift cluster node IP addresses"
    echo "# Cluster name: $CLUSTER_NAME"
    echo "# Region: $REGION"
    echo ""
    
    # Bootstrap 节点
    if [[ "$bootstrap_data" != "[]" ]] && [[ -n "$bootstrap_data" ]]; then
        local bootstrap_public=$(echo "$bootstrap_data" | jq -r '.[0][0][2] // empty')
        local bootstrap_private=$(echo "$bootstrap_data" | jq -r '.[0][0][3] // empty')
        
        if [[ -n "$bootstrap_public" ]]; then
            echo "export BOOTSTRAP_PUBLIC_IP=\"$bootstrap_public\""
        fi
        if [[ -n "$bootstrap_private" ]]; then
            echo "export BOOTSTRAP_PRIVATE_IP=\"$bootstrap_private\""
        fi
        echo ""
    fi
    
    # Master 节点
    if [[ "$master_data" != "[]" ]] && [[ -n "$master_data" ]]; then
        local master_public_ips=()
        local master_private_ips=()
        
        while IFS=$'\t' read -r instance_id state public_ip private_ip; do
            if [[ -n "$public_ip" && "$public_ip" != "N/A" ]]; then
                master_public_ips+=("$public_ip")
            fi
            if [[ -n "$private_ip" && "$private_ip" != "N/A" ]]; then
                master_private_ips+=("$private_ip")
            fi
        done < <(echo "$master_data" | jq -r '.[] | .[] | [.[0], .[1], (.[2] // "N/A"), (.[3] // "N/A")] | @tsv')
        
        if [[ ${#master_public_ips[@]} -gt 0 ]]; then
            echo "export MASTER_PUBLIC_IPS=\"${master_public_ips[*]}\""
        fi
        if [[ ${#master_private_ips[@]} -gt 0 ]]; then
            echo "export MASTER_PRIVATE_IPS=\"${master_private_ips[*]}\""
        fi
        echo ""
    fi
    
    # Worker 节点
    if [[ "$worker_data" != "[]" ]] && [[ -n "$worker_data" ]]; then
        local worker_public_ips=()
        local worker_private_ips=()
        
        while IFS=$'\t' read -r instance_id state public_ip private_ip; do
            if [[ -n "$public_ip" && "$public_ip" != "N/A" ]]; then
                worker_public_ips+=("$public_ip")
            fi
            if [[ -n "$private_ip" && "$private_ip" != "N/A" ]]; then
                worker_private_ips+=("$private_ip")
            fi
        done < <(echo "$worker_data" | jq -r '.[] | .[] | [.[0], .[1], (.[2] // "N/A"), (.[3] // "N/A")] | @tsv')
        
        if [[ ${#worker_public_ips[@]} -gt 0 ]]; then
            echo "export WORKER_PUBLIC_IPS=\"${worker_public_ips[*]}\""
        fi
        if [[ ${#worker_private_ips[@]} -gt 0 ]]; then
            echo "export WORKER_PRIVATE_IPS=\"${worker_private_ips[*]}\""
        fi
        echo ""
    fi
    
    # Summary variables
    echo "# Summary variables"
    if [[ "$bootstrap_data" != "[]" ]] && [[ -n "$bootstrap_data" ]]; then
        local bootstrap_public=$(echo "$bootstrap_data" | jq -r '.[0][0][2] // empty')
        if [[ -n "$bootstrap_public" ]]; then
            echo "export BOOTSTRAP_IP=\"$bootstrap_public\""
        fi
    fi
    
    if [[ "$master_data" != "[]" ]] && [[ -n "$master_data" ]]; then
        local master_private_ips=()
        while IFS=$'\t' read -r instance_id state public_ip private_ip; do
            if [[ -n "$private_ip" && "$private_ip" != "N/A" ]]; then
                master_private_ips+=("$private_ip")
            fi
        done < <(echo "$master_data" | jq -r '.[] | .[] | [.[0], .[1], (.[2] // "N/A"), (.[3] // "N/A")] | @tsv')
        
        if [[ ${#master_private_ips[@]} -gt 0 ]]; then
            echo "export MASTER_IPS=\"${master_private_ips[*]}\""
        fi
    fi
}

# 主函数
main() {
    # 解析参数
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
            -f|--format)
                FORMAT="$2"
                shift 2
                ;;
            -t|--type)
                NODE_TYPE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 验证必需参数
    if [[ -z "$CLUSTER_NAME" ]]; then
        print_error "Cluster name is required (-c, --cluster-name)"
        show_help
        exit 1
    fi
    
    # 验证格式
    if [[ "$FORMAT" != "table" && "$FORMAT" != "json" && "$FORMAT" != "export" ]]; then
        print_error "Invalid output format: $FORMAT"
        print_error "Supported formats: table, json, export"
        exit 1
    fi
    
    # 验证节点类型
    if [[ "$NODE_TYPE" != "all" && "$NODE_TYPE" != "bootstrap" && "$NODE_TYPE" != "master" && "$NODE_TYPE" != "worker" ]]; then
        print_error "Invalid node type: $NODE_TYPE"
        print_error "Supported types: all, bootstrap, master, worker"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Cluster name: $CLUSTER_NAME"
        print_info "AWS region: $REGION"
        print_info "Output format: $FORMAT"
        print_info "Node type: $NODE_TYPE"
    fi
    
    # Get node information
    local bootstrap_data="[]"
    local master_data="[]"
    local worker_data="[]"
    
    if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "bootstrap" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Getting bootstrap node information..."
        fi
        bootstrap_data=$(get_bootstrap_ip || echo "[]")
    fi
    
    if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "master" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Getting master node information..."
        fi
        master_data=$(get_master_ips || echo "[]")
    fi
    
    if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "worker" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Getting worker node information..."
        fi
        worker_data=$(get_worker_ips || echo "[]")
    fi
    
    # 检查是否找到任何节点
    if [[ "$bootstrap_data" == "[]" && "$master_data" == "[]" && "$worker_data" == "[]" ]]; then
        print_error "No nodes found. Please check:"
        print_error "1. If cluster name is correct: $CLUSTER_NAME"
        print_error "2. If AWS region is correct: $REGION"
        print_error "3. If cluster has been created"
        exit 1
    fi
    
    # 输出结果
    case "$FORMAT" in
        "table")
            if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "bootstrap" ]]; then
                format_table "$bootstrap_data" "Bootstrap"
            fi
            if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "master" ]]; then
                format_table "$master_data" "Master"
            fi
            if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "worker" ]]; then
                format_table "$worker_data" "Worker"
            fi
            ;;
        "json")
            format_json "$bootstrap_data" "$master_data" "$worker_data"
            ;;
        "export")
            format_export "$bootstrap_data" "$master_data" "$worker_data"
            ;;
    esac
    
    print_success "Node information retrieval completed"
}

# 运行主函数
main "$@"
