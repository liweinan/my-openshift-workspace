#!/bin/bash

# OCP-29781 集群健康检查脚本

set -euo pipefail

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

# 检查集群操作员状态
check_clusteroperators() {
    local tmp_ret=0 tmp_clusteroperator input column last_column_name tmp_clusteroperator_1 rc null_version unavailable_operator degraded_operator skip_operator

    local skip_operator="aro" # ARO operator versioned but based on RP git commit ID not cluster version

    log_info "检查所有操作员不报告空列"
    tmp_clusteroperator=$(mktemp /tmp/health_check-script.XXXXXX)
    input="${tmp_clusteroperator}"
    oc get clusteroperator >"${tmp_clusteroperator}"
    column=$(head -n 1 "${tmp_clusteroperator}" | awk '{print NF}')
    last_column_name=$(head -n 1 "${tmp_clusteroperator}" | awk '{print $NF}')
    if [[ ${last_column_name} == "MESSAGE" ]]; then
        (( column -= 1 ))
        tmp_clusteroperator_1=$(mktemp /tmp/health_check-script.XXXXXX)
        awk -v end=${column} '{for(i=1;i<=end;i++) printf $i"\t"; print ""}' "${tmp_clusteroperator}" > "${tmp_clusteroperator_1}"
        input="${tmp_clusteroperator_1}"
    fi

    while IFS= read -r line
    do
        rc=$(echo "${line}" | awk '{print NF}')
        if (( rc != column )); then
            log_error "以下行有空列: ${line}"
            (( tmp_ret += 1 ))
        fi
    done < "${input}"
    rm -f "${tmp_clusteroperator}"

    log_info "检查所有操作员报告版本"
    if null_version=$(oc get clusteroperator -o json | jq '.items[] | select(.status.versions == null) | .metadata.name') && [[ ${null_version} != "" ]]; then
      log_error "空版本操作员: ${null_version}"
      (( tmp_ret += 1 ))
    fi

    log_info "检查所有操作员报告正确版本"
    if incorrect_version=$(oc get clusteroperator --no-headers | grep -v ${skip_operator} | awk -v var="${EXPECTED_VERSION}" '$2 != var') && [[ ${incorrect_version} != "" ]]; then
        log_error "不正确的CO版本: ${incorrect_version}"
        (( tmp_ret += 1 ))
    fi

    log_info "检查所有操作员的AVAILABLE列为True"
    if unavailable_operator=$(oc get clusteroperator | awk '$3 == "False"' | grep "False"); then
        log_error "某些操作员的AVAILABLE为False: ${unavailable_operator}"
        (( tmp_ret += 1 ))
    fi
    if oc get clusteroperator -o json | jq '.items[].status.conditions[] | select(.type == "Available") | .status' | grep -iv "True"; then
        log_error "某些操作员不可用，请运行 'oc get clusteroperator -o json' 检查"
        (( tmp_ret += 1 ))
    fi

    log_info "检查所有操作员的PROGRESSING列为False"
    if progressing_operator=$(oc get clusteroperator | awk '$4 == "True"' | grep "True"); then
        log_error "某些操作员的PROGRESSING为True: ${progressing_operator}"
        (( tmp_ret += 1 ))
    fi
    if oc get clusteroperator -o json | jq '.items[].status.conditions[] | select(.type == "Progressing") | .status' | grep -iv "False"; then
        log_error "某些操作员正在进行中，请运行 'oc get clusteroperator -o json' 检查"
        (( tmp_ret += 1 ))
    fi

    log_info "检查所有操作员的DEGRADED列为False"
    if degraded_operator=$(oc get clusteroperator | awk '$5 == "True"' | grep "True"); then
        log_error "某些操作员的DEGRADED为True: ${degraded_operator}"
        (( tmp_ret += 1 ))
    fi
    if oc get clusteroperator -o json | jq '.items[].status.conditions[] | select(.type == "Degraded") | .status'  | grep -iv 'False'; then
        log_error "某些操作员已降级，请运行 'oc get clusteroperator -o json' 检查"
        (( tmp_ret += 1 ))
    fi

    return $tmp_ret
}

# 检查机器配置池
check_mcp() {
    local updating_mcp unhealthy_mcp tmp_output

    tmp_output=$(mktemp)
    oc get machineconfigpools -o custom-columns=NAME:metadata.name,CONFIG:spec.configuration.name,UPDATING:status.conditions[?\(@.type==\"Updating\"\)].status --no-headers > "${tmp_output}" || true
    if [[ -s "${tmp_output}" ]]; then
        updating_mcp=$(cat "${tmp_output}" | grep -v "False")
        if [[ -n "${updating_mcp}" ]]; then
            log_warning "某些mcp正在更新: ${updating_mcp}"
            return 1
        fi
    else
        log_error "无法成功运行 'oc get machineconfigpools'"
        return 1
    fi

    oc get machineconfigpools -o custom-columns=NAME:metadata.name,CONFIG:spec.configuration.name,UPDATING:status.conditions[?\(@.type==\"Updating\"\)].status,DEGRADED:status.conditions[?\(@.type==\"Degraded\"\)].status,DEGRADEDMACHINECOUNT:status.degradedMachineCount --no-headers > "${tmp_output}" || true
    if [[ -s "${tmp_output}" ]]; then
        unhealthy_mcp=$(cat "${tmp_output}" | grep -v "False.*False.*0")
        if [[ -n "${unhealthy_mcp}" ]]; then
            log_error "检测到不健康的mcp: ${unhealthy_mcp}"
            return 2
        fi
    else
        log_error "无法成功运行 'oc get machineconfigpools'"
        return 1
    fi
    return 0
}

# 检查节点状态
check_nodes() {
    local node_number ready_number
    node_number=$(oc get node --no-headers | wc -l)
    ready_number=$(oc get node --no-headers | awk '$2 == "Ready"' | wc -l)
    if (( node_number == ready_number )); then
        log_success "所有节点状态检查通过"
        return 0
    else
        if (( ready_number == 0 )); then
            log_error "没有任何就绪节点"
        else
            log_error "发现失败的节点:"
            oc get node --no-headers | awk '$2 != "Ready"'
        fi
        return 1
    fi
}

# 检查Pod状态
check_pods() {
    local spotted_pods

    spotted_pods=$(oc get pod --all-namespaces | grep -Evi "running|Completed" |grep -v NAMESPACE)
    if [[ -n "$spotted_pods" ]]; then
        log_warning "发现一些异常Pod:"
        echo "${spotted_pods}"
    fi
    log_info "显示所有Pod以供参考/调试"
    oc get pods --all-namespaces
}

# 等待集群操作员连续成功
wait_clusteroperators_continous_success() {
    local try=0 continous_successful_check=0 passed_criteria=3 max_retries=20
    while (( try < max_retries && continous_successful_check < passed_criteria )); do
        log_info "检查 #${try}"
        if check_clusteroperators; then
            log_success "通过 #${continous_successful_check}"
            (( continous_successful_check += 1 ))
        else
            log_info "集群操作员尚未就绪，等待并重试..."
            continous_successful_check=0
        fi
        sleep 60
        (( try += 1 ))
    done
    if (( continous_successful_check != passed_criteria )); then
        log_error "某些集群操作员未就绪或不稳定"
        log_info "调试: 当前CO输出:"
        oc get co
        return 1
    else
        log_success "所有集群操作员状态检查通过"
        return 0
    fi
}

# 等待MCP连续成功
wait_mcp_continous_success() {
    local try=0 continous_successful_check=0 passed_criteria=5 max_retries=20 ret=0
    local continous_degraded_check=0 degraded_criteria=5
    while (( try < max_retries && continous_successful_check < passed_criteria )); do
        log_info "检查 #${try}"
        ret=0
        check_mcp || ret=$?
        if [[ "$ret" == "0" ]]; then
            continous_degraded_check=0
            log_success "通过 #${continous_successful_check}"
            (( continous_successful_check += 1 ))
        elif [[ "$ret" == "1" ]]; then
            log_info "某些机器正在更新..."
            continous_successful_check=0
            continous_degraded_check=0
        else
            continous_successful_check=0
            log_warning "某些机器已降级 #${continous_degraded_check}..."
            (( continous_degraded_check += 1 ))
            if (( continous_degraded_check >= degraded_criteria )); then
                break
            fi
        fi
        log_info "等待并重试..."
        sleep 60
        (( try += 1 ))
    done
    if (( continous_successful_check != passed_criteria )); then
        log_error "某些mcp未就绪或不稳定"
        log_info "调试: 当前mcp输出:"
        oc get machineconfigpools
        return 1
    else
        log_success "所有mcp状态检查通过"
        return 0
    fi
}

# 主健康检查函数
health_check() {
    log_info "开始集群健康检查"
    
    EXPECTED_VERSION=$(oc get clusterversion/version -o json | jq -r '.status.history[0].version')
    export EXPECTED_VERSION
    log_info "期望版本: ${EXPECTED_VERSION}"

    oc get machineconfig

    log_info "步骤 #1: 确保没有降级或更新的mcp"
    wait_mcp_continous_success || return 1

    log_info "步骤 #2: 检查所有集群操作员稳定且就绪"
    wait_clusteroperators_continous_success || return 1

    log_info "步骤 #3: 确保每台机器处于'Ready'状态"
    check_nodes || return 1

    log_info "步骤 #4: 检查所有Pod处于运行或完成状态"
    check_pods || return 1

    log_success "集群健康检查完成"
    return 0
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 <cluster_dir>"
    echo ""
    echo "参数:"
    echo "  cluster_dir  - 集群安装目录 (例如: cluster1, cluster2)"
    echo ""
    echo "示例:"
    echo "  $0 cluster1"
    echo "  $0 cluster2"
}

# 主函数
main() {
    if [[ $# -ne 1 ]]; then
        show_usage
        exit 1
    fi

    local cluster_dir="$1"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"

    if [[ ! -f "${kubeconfig}" ]]; then
        log_error "未找到kubeconfig文件: ${kubeconfig}"
        exit 1
    fi

    log_info "使用集群目录: ${cluster_dir}"
    log_info "使用kubeconfig: ${kubeconfig}"

    export KUBECONFIG="${kubeconfig}"

    # 验证集群连接
    if ! oc get nodes &> /dev/null; then
        log_error "无法连接到集群"
        exit 1
    fi

    # 执行健康检查
    health_check
    local health_ret=$?

    if [[ $health_ret -eq 0 ]]; then
        log_success "集群健康检查通过"
    else
        log_error "集群健康检查失败"
    fi

    exit $health_ret
}

# 运行主函数
main "$@"
