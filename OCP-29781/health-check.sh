#!/bin/bash

# OCP-29781 Cluster Health Check Script

set -euo pipefail

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

# Check cluster operator status
check_clusteroperators() {
    local tmp_ret=0 tmp_clusteroperator input column last_column_name tmp_clusteroperator_1 rc null_version unavailable_operator degraded_operator skip_operator

    local skip_operator="aro" # ARO operator versioned but based on RP git commit ID not cluster version

    log_info "Checking that all operators do not report empty columns"
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
            log_error "The following line has empty columns: ${line}"
            (( tmp_ret += 1 ))
        fi
    done < "${input}"
    rm -f "${tmp_clusteroperator}"

    log_info "Checking that all operators report versions"
    if null_version=$(oc get clusteroperator -o json | jq '.items[] | select(.status.versions == null) | .metadata.name') && [[ ${null_version} != "" ]]; then
      log_error "Operators with null versions: ${null_version}"
      (( tmp_ret += 1 ))
    fi

    log_info "Checking that all operators report correct versions"
    if incorrect_version=$(oc get clusteroperator --no-headers | grep -v ${skip_operator} | awk -v var="${EXPECTED_VERSION}" '$2 != var') && [[ ${incorrect_version} != "" ]]; then
        log_error "Incorrect CO versions: ${incorrect_version}"
        (( tmp_ret += 1 ))
    fi

    log_info "Checking that all operators have AVAILABLE column as True"
    if unavailable_operator=$(oc get clusteroperator | awk '$3 == "False"' | grep "False"); then
        log_error "Some operators have AVAILABLE as False: ${unavailable_operator}"
        (( tmp_ret += 1 ))
    fi
    if oc get clusteroperator -o json | jq '.items[].status.conditions[] | select(.type == "Available") | .status' | grep -iv "True"; then
        log_error "Some operators are unavailable, please run 'oc get clusteroperator -o json' to check"
        (( tmp_ret += 1 ))
    fi

    log_info "Checking that all operators have PROGRESSING column as False"
    if progressing_operator=$(oc get clusteroperator | awk '$4 == "True"' | grep "True"); then
        log_error "Some operators have PROGRESSING as True: ${progressing_operator}"
        (( tmp_ret += 1 ))
    fi
    if oc get clusteroperator -o json | jq '.items[].status.conditions[] | select(.type == "Progressing") | .status' | grep -iv "False"; then
        log_error "Some operators are progressing, please run 'oc get clusteroperator -o json' to check"
        (( tmp_ret += 1 ))
    fi

    log_info "Checking that all operators have DEGRADED column as False"
    if degraded_operator=$(oc get clusteroperator | awk '$5 == "True"' | grep "True"); then
        log_error "Some operators have DEGRADED as True: ${degraded_operator}"
        (( tmp_ret += 1 ))
    fi
    if oc get clusteroperator -o json | jq '.items[].status.conditions[] | select(.type == "Degraded") | .status'  | grep -iv 'False'; then
        log_error "Some operators are degraded, please run 'oc get clusteroperator -o json' to check"
        (( tmp_ret += 1 ))
    fi

    return $tmp_ret
}

# Check machine config pools
check_mcp() {
    local updating_mcp unhealthy_mcp tmp_output

    tmp_output=$(mktemp)
    oc get machineconfigpools -o custom-columns=NAME:metadata.name,CONFIG:spec.configuration.name,UPDATING:status.conditions[?\(@.type==\"Updating\"\)].status --no-headers > "${tmp_output}" || true
    if [[ -s "${tmp_output}" ]]; then
        updating_mcp=$(cat "${tmp_output}" | grep -v "False")
        if [[ -n "${updating_mcp}" ]]; then
            log_warning "Some mcp are updating: ${updating_mcp}"
            return 1
        fi
    else
        log_error "Cannot successfully run 'oc get machineconfigpools'"
        return 1
    fi

    oc get machineconfigpools -o custom-columns=NAME:metadata.name,CONFIG:spec.configuration.name,UPDATING:status.conditions[?\(@.type==\"Updating\"\)].status,DEGRADED:status.conditions[?\(@.type==\"Degraded\"\)].status,DEGRADEDMACHINECOUNT:status.degradedMachineCount --no-headers > "${tmp_output}" || true
    if [[ -s "${tmp_output}" ]]; then
        unhealthy_mcp=$(cat "${tmp_output}" | grep -v "False.*False.*0")
        if [[ -n "${unhealthy_mcp}" ]]; then
            log_error "Detected unhealthy mcp: ${unhealthy_mcp}"
            return 2
        fi
    else
        log_error "Cannot successfully run 'oc get machineconfigpools'"
        return 1
    fi
    return 0
}

# Check node status
check_nodes() {
    local node_number ready_number
    node_number=$(oc get node --no-headers | wc -l)
    ready_number=$(oc get node --no-headers | awk '$2 == "Ready"' | wc -l)
    if (( node_number == ready_number )); then
        log_success "All node status checks passed"
        return 0
    else
        if (( ready_number == 0 )); then
            log_error "No ready nodes"
        else
            log_error "Found failed nodes:"
            oc get node --no-headers | awk '$2 != "Ready"'
        fi
        return 1
    fi
}

# Check Pod status
check_pods() {
    local spotted_pods

    spotted_pods=$(oc get pod --all-namespaces | grep -Evi "running|Completed" |grep -v NAMESPACE)
    if [[ -n "$spotted_pods" ]]; then
        log_warning "Found some abnormal pods:"
        echo "${spotted_pods}"
    fi
    log_info "Displaying all pods for reference/debugging"
    oc get pods --all-namespaces
}

# Wait for cluster operators to be continuously successful
wait_clusteroperators_continous_success() {
    local try=0 continous_successful_check=0 passed_criteria=3 max_retries=20
    while (( try < max_retries && continous_successful_check < passed_criteria )); do
        log_info "Check #${try}"
        if check_clusteroperators; then
            log_success "Passed #${continous_successful_check}"
            (( continous_successful_check += 1 ))
        else
            log_info "Cluster operators not ready yet, waiting and retrying..."
            continous_successful_check=0
        fi
        sleep 60
        (( try += 1 ))
    done
    if (( continous_successful_check != passed_criteria )); then
        log_error "Some cluster operators are not ready or unstable"
        log_info "Debug: Current CO output:"
        oc get co
        return 1
    else
        log_success "All cluster operator status checks passed"
        return 0
    fi
}

# Wait for MCP to be continuously successful
wait_mcp_continous_success() {
    local try=0 continous_successful_check=0 passed_criteria=5 max_retries=20 ret=0
    local continous_degraded_check=0 degraded_criteria=5
    while (( try < max_retries && continous_successful_check < passed_criteria )); do
        log_info "Check #${try}"
        ret=0
        check_mcp || ret=$?
        if [[ "$ret" == "0" ]]; then
            continous_degraded_check=0
            log_success "Passed #${continous_successful_check}"
            (( continous_successful_check += 1 ))
        elif [[ "$ret" == "1" ]]; then
            log_info "Some machines are updating..."
            continous_successful_check=0
            continous_degraded_check=0
        else
            continous_successful_check=0
            log_warning "Some machines are degraded #${continous_degraded_check}..."
            (( continous_degraded_check += 1 ))
            if (( continous_degraded_check >= degraded_criteria )); then
                break
            fi
        fi
        log_info "Waiting and retrying..."
        sleep 60
        (( try += 1 ))
    done
    if (( continous_successful_check != passed_criteria )); then
        log_error "Some mcp are not ready or unstable"
        log_info "Debug: Current mcp output:"
        oc get machineconfigpools
        return 1
    else
        log_success "All mcp status checks passed"
        return 0
    fi
}

# Main health check function
health_check() {
    log_info "Starting cluster health check"
    
    EXPECTED_VERSION=$(oc get clusterversion/version -o json | jq -r '.status.history[0].version')
    export EXPECTED_VERSION
    log_info "Expected version: ${EXPECTED_VERSION}"

    oc get machineconfig

    log_info "Step #1: Ensure no degraded or updating mcp"
    wait_mcp_continous_success || return 1

    log_info "Step #2: Check all cluster operators are stable and ready"
    wait_clusteroperators_continous_success || return 1

    log_info "Step #3: Ensure every machine is in 'Ready' state"
    check_nodes || return 1

    log_info "Step #4: Check all pods are in running or completed state"
    check_pods || return 1

    log_success "Cluster health check completed"
    return 0
}

# Display usage information
show_usage() {
    echo "Usage: $0 <cluster_dir>"
    echo ""
    echo "Parameters:"
    echo "  cluster_dir  - Cluster installation directory (e.g.: cluster1, cluster2)"
    echo ""
    echo "Examples:"
    echo "  $0 cluster1"
    echo "  $0 cluster2"
}

# Main function
main() {
    if [[ $# -ne 1 ]]; then
        show_usage
        exit 1
    fi

    local cluster_dir="$1"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"

    if [[ ! -f "${kubeconfig}" ]]; then
        log_error "Kubeconfig file not found: ${kubeconfig}"
        exit 1
    fi

    log_info "Using cluster directory: ${cluster_dir}"
    log_info "Using kubeconfig: ${kubeconfig}"

    export KUBECONFIG="${kubeconfig}"

    # Verify cluster connection
    if ! oc get nodes &> /dev/null; then
        log_error "Cannot connect to cluster"
        exit 1
    fi

    # Execute health check
    health_check
    local health_ret=$?

    if [[ $health_ret -eq 0 ]]; then
        log_success "Cluster health check passed"
    else
        log_error "Cluster health check failed"
    fi

    exit $health_ret
}

# Run main function
main "$@"