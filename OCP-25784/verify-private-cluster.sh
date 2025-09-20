#!/bin/bash
# verify-private-cluster.sh
# OCP-25784 Private Cluster Verification Script

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEFAULT_CLUSTER_NAME="weli-priv-test"
DEFAULT_BASTION_IP=""
DEFAULT_AWS_REGION="us-east-1"

# --- Logging functions ---
log_info() {
    echo "[INFO] $@"
}

log_success() {
    echo "[SUCCESS] $@"
}

log_error() {
    echo "[ERROR] $@" >&2
}

log_warning() {
    echo "[WARNING] $@"
}

# --- Helper functions ---
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OCP-25784 Private Cluster Verification Script

OPTIONS:
    -c, --cluster-name NAME       OpenShift cluster name (default: $DEFAULT_CLUSTER_NAME)
    -b, --bastion-ip IP           Bastion host public IP address
    -r, --region REGION           AWS region (default: $DEFAULT_AWS_REGION)
    -h, --help                    Show this help message

EXAMPLES:
    # Verify with bastion host
    $0 --bastion-ip 18.207.177.234

    # Verify with custom cluster name
    $0 --cluster-name my-private-cluster --bastion-ip 18.207.177.234

ENVIRONMENT VARIABLES:
    CLUSTER_NAME                 Override default cluster name
    BASTION_IP                   Override bastion IP
    AWS_REGION                   Override default AWS region
EOF
}

# --- Default values ---
CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
BASTION_IP="${BASTION_IP:-$DEFAULT_BASTION_IP}"
AWS_REGION="${AWS_REGION:-$DEFAULT_AWS_REGION}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -b|--bastion-ip)
            BASTION_IP="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# --- Validation ---
if [[ -z "$BASTION_IP" ]]; then
    log_error "Bastion IP address is required. Use -b or --bastion-ip option."
    usage
    exit 1
fi

# --- Core functions ---
verify_bastion_connectivity() {
    log_info "Verifying bastion host connectivity..."
    
    if ping -c 3 "$BASTION_IP" &>/dev/null; then
        log_success "Bastion host is reachable: $BASTION_IP"
    else
        log_error "Cannot reach bastion host: $BASTION_IP"
        return 1
    fi
}

verify_cluster_access_from_bastion() {
    log_info "Verifying cluster access from bastion host..."
    
    local console_url="console-openshift-console.apps.${CLUSTER_NAME}.qe.devcluster.openshift.com"
    
    log_info "Testing console access from bastion host..."
    
    # Test console access via SSH
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no core@"$BASTION_IP" \
        "curl -s -k -o /dev/null -w '%{http_code}' https://$console_url" | grep -q "200\|302"; then
        log_success "Console is accessible from bastion host"
    else
        log_error "Console is not accessible from bastion host"
        return 1
    fi
}

verify_cluster_access_from_outside() {
    log_info "Verifying cluster access from outside VPC..."
    
    local console_url="console-openshift-console.apps.${CLUSTER_NAME}.qe.devcluster.openshift.com"
    
    log_info "Testing console access from outside VPC..."
    
    # Test DNS resolution
    if nslookup "$console_url" &>/dev/null; then
        log_warning "DNS resolution succeeded from outside VPC (unexpected for private cluster)"
    else
        log_success "DNS resolution failed from outside VPC (expected for private cluster)"
    fi
    
    # Test HTTP access
    if curl -s -k -o /dev/null -w '%{http_code}' --connect-timeout 10 "https://$console_url" | grep -q "200\|302"; then
        log_error "Console is accessible from outside VPC (unexpected for private cluster)"
        return 1
    else
        log_success "Console is not accessible from outside VPC (expected for private cluster)"
    fi
}

verify_cluster_health() {
    log_info "Verifying cluster health from bastion host..."
    
    # Check if kubeconfig exists on bastion
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no core@"$BASTION_IP" \
        "test -f /var/home/core/auth/kubeconfig"; then
        log_success "Kubeconfig found on bastion host"
    else
        log_error "Kubeconfig not found on bastion host"
        return 1
    fi
    
    # Check node status
    log_info "Checking node status..."
    local node_output
    node_output=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no core@"$BASTION_IP" \
        "export KUBECONFIG=/var/home/core/auth/kubeconfig && ./oc get nodes --no-headers" 2>/dev/null || echo "")
    
    if [[ -n "$node_output" ]]; then
        local ready_nodes
        ready_nodes=$(echo "$node_output" | grep -c "Ready" || echo "0")
        local total_nodes
        total_nodes=$(echo "$node_output" | wc -l)
        
        if [[ "$ready_nodes" -eq "$total_nodes" && "$total_nodes" -gt 0 ]]; then
            log_success "All $total_nodes nodes are in Ready state"
        else
            log_error "Not all nodes are ready: $ready_nodes/$total_nodes"
            return 1
        fi
    else
        log_error "Failed to get node status"
        return 1
    fi
    
    # Check cluster operators
    log_info "Checking cluster operators..."
    local operator_output
    operator_output=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no core@"$BASTION_IP" \
        "export KUBECONFIG=/var/home/core/auth/kubeconfig && ./oc get clusteroperators --no-headers" 2>/dev/null || echo "")
    
    if [[ -n "$operator_output" ]]; then
        local available_operators
        available_operators=$(echo "$operator_output" | grep -c "True.*False.*False" || echo "0")
        local total_operators
        total_operators=$(echo "$operator_output" | wc -l)
        
        if [[ "$available_operators" -eq "$total_operators" && "$total_operators" -gt 0 ]]; then
            log_success "All $total_operators cluster operators are available"
        else
            log_warning "Not all cluster operators are available: $available_operators/$total_operators"
        fi
    else
        log_error "Failed to get cluster operator status"
        return 1
    fi
}

verify_network_isolation() {
    log_info "Verifying network isolation..."
    
    local console_url="console-openshift-console.apps.${CLUSTER_NAME}.qe.devcluster.openshift.com"
    local api_url="api.${CLUSTER_NAME}.qe.devcluster.openshift.com"
    
    # Test from bastion (should work)
    log_info "Testing API access from bastion host..."
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no core@"$BASTION_IP" \
        "curl -s -k -o /dev/null -w '%{http_code}' --connect-timeout 10 https://$api_url:6443" | grep -q "200\|401\|403"; then
        log_success "API is accessible from bastion host"
    else
        log_warning "API is not accessible from bastion host"
    fi
    
    # Test from outside (should fail)
    log_info "Testing API access from outside VPC..."
    if curl -s -k -o /dev/null -w '%{http_code}' --connect-timeout 10 "https://$api_url:6443" | grep -q "200\|401\|403"; then
        log_error "API is accessible from outside VPC (unexpected for private cluster)"
        return 1
    else
        log_success "API is not accessible from outside VPC (expected for private cluster)"
    fi
}

verify_route53_private_zone() {
    log_info "Verifying Route53 private zone configuration..."
    
    local hosted_zone_name="${CLUSTER_NAME}.qe.devcluster.openshift.com"
    
    # Check if private hosted zone exists
    local zone_id
    zone_id=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Name=='$hosted_zone_name.'].Id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$zone_id" ]]; then
        log_success "Private hosted zone found: $zone_id"
        
        # Check if zone is private
        local is_private
        is_private=$(aws route53 get-hosted-zone --id "$zone_id" \
            --query 'HostedZone.Config.PrivateZone' \
            --output text 2>/dev/null || echo "false")
        
        if [[ "$is_private" == "true" ]]; then
            log_success "Hosted zone is configured as private"
        else
            log_error "Hosted zone is not configured as private"
            return 1
        fi
    else
        log_error "Private hosted zone not found for: $hosted_zone_name"
        return 1
    fi
}

generate_verification_report() {
    log_info "Generating verification report..."
    
    local report_file="$SCRIPT_DIR/verification-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
OCP-25784 Private Cluster Verification Report
Generated: $(date)
Cluster Name: $CLUSTER_NAME
Bastion IP: $BASTION_IP
AWS Region: $AWS_REGION

=== Verification Results ===

1. Bastion Host Connectivity: $([ "$1" == "0" ] && echo "PASS" || echo "FAIL")
2. Cluster Access from Bastion: $([ "$2" == "0" ] && echo "PASS" || echo "FAIL")
3. Cluster Access from Outside: $([ "$3" == "0" ] && echo "PASS" || echo "FAIL")
4. Cluster Health: $([ "$4" == "0" ] && echo "PASS" || echo "FAIL")
5. Network Isolation: $([ "$5" == "0" ] && echo "PASS" || echo "FAIL")
6. Route53 Private Zone: $([ "$6" == "0" ] && echo "PASS" || echo "FAIL")

=== Overall Result ===
$([ "$7" == "0" ] && echo "ALL VERIFICATIONS PASSED" || echo "SOME VERIFICATIONS FAILED")

EOF
    
    log_success "Verification report saved to: $report_file"
}

# --- Main execution ---
main() {
    log_info "Starting OCP-25784 Private Cluster Verification"
    log_info "Configuration:"
    log_info "  Cluster Name: $CLUSTER_NAME"
    log_info "  Bastion IP: $BASTION_IP"
    log_info "  AWS Region: $AWS_REGION"
    echo
    
    local overall_result=0
    local bastion_connectivity=0
    local cluster_access_bastion=0
    local cluster_access_outside=0
    local cluster_health=0
    local network_isolation=0
    local route53_private=0
    
    # Run verifications
    verify_bastion_connectivity || bastion_connectivity=1
    verify_cluster_access_from_bastion || cluster_access_bastion=1
    verify_cluster_access_from_outside || cluster_access_outside=1
    verify_cluster_health || cluster_health=1
    verify_network_isolation || network_isolation=1
    verify_route53_private_zone || route53_private=1
    
    # Calculate overall result
    overall_result=$((bastion_connectivity + cluster_access_bastion + cluster_access_outside + cluster_health + network_isolation + route53_private))
    
    # Generate report
    generate_verification_report "$bastion_connectivity" "$cluster_access_bastion" "$cluster_access_outside" "$cluster_health" "$network_isolation" "$route53_private" "$overall_result"
    
    echo
    if [[ "$overall_result" -eq 0 ]]; then
        log_success "All verifications passed! Private cluster is working correctly."
        exit 0
    else
        log_error "Some verifications failed. Please check the report for details."
        exit 1
    fi
}

# --- Run main function ---
main "$@"
