#!/bin/bash
#
# get-cluster-node-ips.sh
# 获取 OpenShift 集群所有节点的 IP 地址
#
# 用法:
#   ./get-cluster-node-ips.sh [OPTIONS]
#
# 选项:
#   -c, --cluster-name NAME    集群名称 (必需)
#   -r, --region REGION        AWS 区域 (默认: us-east-1)
#   -f, --format FORMAT        输出格式: table, json, export (默认: table)
#   -t, --type TYPE           节点类型: all, bootstrap, master, worker (默认: all)
#   -v, --verbose             详细输出
#   -h, --help                显示帮助信息
#
# 示例:
#   ./get-cluster-node-ips.sh -c weli-testy
#   ./get-cluster-node-ips.sh -c weli-testy -r us-west-2 -f json
#   ./get-cluster-node-ips.sh -c weli-testy -t bootstrap -f export
#

set -euo pipefail

# 颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认值
CLUSTER_NAME=""
REGION="us-east-1"
FORMAT="table"
NODE_TYPE="all"
VERBOSE=false

# 打印函数
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

# 显示帮助
show_help() {
    cat << EOF
get-cluster-node-ips.sh - 获取 OpenShift 集群所有节点的 IP 地址

用法:
    $0 [OPTIONS]

选项:
    -c, --cluster-name NAME    集群名称 (必需)
    -r, --region REGION        AWS 区域 (默认: us-east-1)
    -f, --format FORMAT        输出格式: table, json, export (默认: table)
    -t, --type TYPE           节点类型: all, bootstrap, master, worker (默认: all)
    -v, --verbose             详细输出
    -h, --help                显示帮助信息

输出格式:
    table    - 表格格式显示
    json     - JSON 格式输出
    export   - 导出为环境变量格式

节点类型:
    all      - 所有节点 (bootstrap, master, worker)
    bootstrap - 仅 bootstrap 节点
    master   - 仅 master 节点
    worker   - 仅 worker 节点

示例:
    $0 -c weli-testy
    $0 -c weli-testy -r us-west-2 -f json
    $0 -c weli-testy -t bootstrap -f export
    $0 -c weli-testy -t master -f table -v

EOF
}

# 检查依赖
check_dependencies() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI 未安装或不在 PATH 中"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq 未安装或不在 PATH 中"
        exit 1
    fi
    
    # 检查 AWS 凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS 凭证未配置或无效"
        exit 1
    fi
}

# 获取 bootstrap 节点 IP
get_bootstrap_ip() {
    local bootstrap_ip
    
    # 首先尝试直接匹配
    bootstrap_ip=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=${CLUSTER_NAME}-bootstrap" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
        --output json 2>/dev/null)
    
    # 如果没找到，尝试带 infraID 的格式
    if [[ "$bootstrap_ip" == "[]" ]] || [[ -z "$bootstrap_ip" ]]; then
        bootstrap_ip=$(aws ec2 describe-instances \
            --region "$REGION" \
            --filters "Name=tag:Name,Values=${CLUSTER_NAME}-*-bootstrap" \
            --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
            --output json 2>/dev/null)
    fi
    
    if [[ "$bootstrap_ip" == "[]" ]] || [[ -z "$bootstrap_ip" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_warning "未找到 bootstrap 节点"
        fi
        return 1
    fi
    
    echo "$bootstrap_ip"
}

# 获取 master 节点 IP
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

# 获取 worker 节点 IP
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

# 格式化输出为表格
format_table() {
    local data="$1"
    local node_type="$2"
    
    if [[ "$data" == "[]" ]] || [[ -z "$data" ]]; then
        return 0
    fi
    
    echo ""
    echo "=== $node_type 节点 ==="
    echo "Instance ID          | State      | Public IP      | Private IP"
    echo "---------------------|------------|----------------|----------------"
    
    echo "$data" | jq -r '.[] | .[] | [.[0], .[1], (.[2] // "N/A"), (.[3] // "N/A")] | @tsv' | while IFS=$'\t' read -r instance_id state public_ip private_ip; do
        printf "%-20s | %-10s | %-14s | %s\n" "$instance_id" "$state" "$public_ip" "$private_ip"
    done
}

# 格式化输出为 JSON
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

# 格式化输出为环境变量
format_export() {
    local bootstrap_data="$1"
    local master_data="$2"
    local worker_data="$3"
    
    echo "# OpenShift 集群节点 IP 地址"
    echo "# 集群名称: $CLUSTER_NAME"
    echo "# 区域: $REGION"
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
    
    # 汇总变量
    echo "# 汇总变量"
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
        print_error "集群名称是必需的 (-c, --cluster-name)"
        show_help
        exit 1
    fi
    
    # 验证格式
    if [[ "$FORMAT" != "table" && "$FORMAT" != "json" && "$FORMAT" != "export" ]]; then
        print_error "无效的输出格式: $FORMAT"
        print_error "支持的格式: table, json, export"
        exit 1
    fi
    
    # 验证节点类型
    if [[ "$NODE_TYPE" != "all" && "$NODE_TYPE" != "bootstrap" && "$NODE_TYPE" != "master" && "$NODE_TYPE" != "worker" ]]; then
        print_error "无效的节点类型: $NODE_TYPE"
        print_error "支持的类型: all, bootstrap, master, worker"
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "集群名称: $CLUSTER_NAME"
        print_info "AWS 区域: $REGION"
        print_info "输出格式: $FORMAT"
        print_info "节点类型: $NODE_TYPE"
    fi
    
    # 获取节点信息
    local bootstrap_data="[]"
    local master_data="[]"
    local worker_data="[]"
    
    if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "bootstrap" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "获取 bootstrap 节点信息..."
        fi
        bootstrap_data=$(get_bootstrap_ip || echo "[]")
    fi
    
    if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "master" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "获取 master 节点信息..."
        fi
        master_data=$(get_master_ips || echo "[]")
    fi
    
    if [[ "$NODE_TYPE" == "all" || "$NODE_TYPE" == "worker" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "获取 worker 节点信息..."
        fi
        worker_data=$(get_worker_ips || echo "[]")
    fi
    
    # 检查是否找到任何节点
    if [[ "$bootstrap_data" == "[]" && "$master_data" == "[]" && "$worker_data" == "[]" ]]; then
        print_error "未找到任何节点。请检查:"
        print_error "1. 集群名称是否正确: $CLUSTER_NAME"
        print_error "2. AWS 区域是否正确: $REGION"
        print_error "3. 集群是否已创建"
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
    
    print_success "节点信息获取完成"
}

# 运行主函数
main "$@"
