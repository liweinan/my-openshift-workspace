#!/bin/bash

# OCP-23541 - [ipi-on-aws] [Hyperthreading] Create cluster with hyperthreading disabled on worker and master nodes
# Automated setup script

set -euo pipefail

# Color definitions
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

# Show help information
show_help() {
    cat << EOF
OCP-23541 Hyperthreading Disabled Test Automation Script

Usage:
    $0 [选项]

选项:
    -r, --region <region>        AWS region (default: us-east-2)
    -n, --cluster-name <name>    Cluster name (default: hyperthreading-test)
    -i, --instance-type <type>   Instance type (default: m6i.xlarge)
    -w, --worker-count <count>   Worker node count (default: 3)
    -m, --master-count <count>   Master node count (default: 3)
    -d, --dir <directory>        Installation directory (default: test)
    --skip-install               Skip cluster installation, only generate config files
    -h, --help                   Show this help message

示例:
    # Basic usage
    $0

    # Custom parameters
    $0 --region us-west-2 --cluster-name my-test --instance-type m5.2xlarge

    # Only generate config files
    $0 --skip-install

EOF
}

# Default parameters
AWS_REGION="us-east-2"
CLUSTER_NAME="hyperthreading-test"
INSTANCE_TYPE="m6i.xlarge"
WORKER_COUNT=3
MASTER_COUNT=3
INSTALL_DIR="test"
SKIP_INSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -n|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -i|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -w|--worker-count)
            WORKER_COUNT="$2"
            shift 2
            ;;
        -m|--master-count)
            MASTER_COUNT="$2"
            shift 2
            ;;
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

print_info "Starting OCP-23541 hyperthreading disabled test setup..."
print_info "Cluster name: $CLUSTER_NAME"
print_info "AWS region: $AWS_REGION"
print_info "Instance type: $INSTANCE_TYPE"
print_info "Worker node count: $WORKER_COUNT"
print_info "Master node count: $MASTER_COUNT"
print_info "Installation directory: $INSTALL_DIR"

# Check required tools
check_prerequisites() {
    print_info "Checking required tools..."
    
    local missing_tools=()
    
    if ! command -v openshift-install &> /dev/null; then
        missing_tools+=("openshift-install")
    fi
    
    if ! command -v oc &> /dev/null; then
        missing_tools+=("oc")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install missing tools and try again"
        exit 1
    fi
    
    print_success "All required tools are installed"
}

# Check AWS credentials
check_aws_credentials() {
    print_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured or invalid"
        print_error "Please run 'aws configure' to configure AWS credentials"
        exit 1
    fi
    
    local aws_account=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS credentials are valid, account ID: $aws_account"
}

# Create installation directory
create_install_directory() {
    print_info "Creating installation directory: $INSTALL_DIR"
    
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Directory $INSTALL_DIR already exists"
        read -p "Delete existing directory? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
            print_info "Existing directory deleted"
        else
            print_error "Installation directory already exists, please choose another directory or delete existing one"
            exit 1
        fi
    fi
    
    mkdir -p "$INSTALL_DIR"
    print_success "Installation directory created successfully"
}

# Generate install-config.yaml
generate_install_config() {
    print_info "Generating install-config.yaml..."
    
    # 检查是否存在pull-secret.json
    local pull_secret_file=""
    if [ -f "../tools/pull-secret.json" ]; then
        pull_secret_file="../tools/pull-secret.json"
    elif [ -f "pull-secret.json" ]; then
        pull_secret_file="pull-secret.json"
    else
        print_error "pull-secret.json file not found"
        print_error "Please place pull-secret.json file in current directory or ../tools/ directory"
        exit 1
    fi
    
    # 生成install-config.yaml
    cat > "$INSTALL_DIR/install-config.yaml" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
compute:
- hyperthreading: Disabled
  name: worker
  platform:
    aws:
      type: $INSTANCE_TYPE
  replicas: $WORKER_COUNT
controlPlane:
  hyperthreading: Disabled
  name: master
  platform:
    aws:
      type: $INSTANCE_TYPE
  replicas: $MASTER_COUNT
metadata:
  creationTimestamp: null
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineCIDR: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $AWS_REGION
pullSecret: '$(cat "$pull_secret_file" | jq -c .)'
sshKey: '$(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vbqajDhA...")'
EOF
    
    print_success "install-config.yaml generated successfully"
    print_info "Configuration file content:"
    cat "$INSTALL_DIR/install-config.yaml"
}

# Install cluster
install_cluster() {
    if [ "$SKIP_INSTALL" = true ]; then
        print_info "跳过集群安装（仅生成配置文件）"
        return 0
    fi
    
    print_info "Starting cluster installation..."
    print_warning "This may take 30-60 minutes, please be patient..."
    
    if openshift-install create cluster --dir "$INSTALL_DIR" --log-level info; then
        print_success "Cluster installation successful!"
    else
        print_error "Cluster installation failed"
        exit 1
    fi
}

# Verify hyperthreading is disabled
verify_hyperthreading_disabled() {
    if [ "$SKIP_INSTALL" = true ]; then
        print_info "Skipping hyperthreading verification (cluster not installed)"
        return 0
    fi
    
    print_info "Verifying hyperthreading disabled status..."
    
    # 设置kubeconfig
    export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
    
    # Wait for nodes to be ready
    print_info "Waiting for all nodes to be ready..."
    oc wait --for=condition=Ready nodes --all --timeout=600s
    
    # 获取节点列表
    local nodes=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')
    print_info "Found nodes: $nodes"
    
    # 验证每个节点的超线程状态
    for node in $nodes; do
        print_info "Verifying node: $node"
        
        # 创建debug pod并检查CPU信息
        local cpu_info=$(oc debug "node/$node" -- chroot /host cat /proc/cpuinfo 2>/dev/null || echo "")
        
        if [ -n "$cpu_info" ]; then
            local siblings=$(echo "$cpu_info" | grep "siblings" | head -1 | awk '{print $3}')
            local cpu_cores=$(echo "$cpu_info" | grep "cpu cores" | head -1 | awk '{print $4}')
            
            print_info "Node $node: siblings=$siblings, cpu_cores=$cpu_cores"
            
            if [ "$siblings" = "$cpu_cores" ]; then
                print_success "Node $node: Hyperthreading is disabled (siblings == cpu_cores)"
            else
                print_error "Node $node: Hyperthreading may not be disabled (siblings != cpu_cores)"
            fi
        else
            print_warning "Cannot get CPU information for node $node"
        fi
    done
}

# Verify MachineConfigPool
verify_machine_config_pools() {
    if [ "$SKIP_INSTALL" = true ]; then
        print_info "Skipping MachineConfigPool verification (cluster not installed)"
        return 0
    fi
    
    print_info "Verifying MachineConfigPool status..."
    
    # 检查MachineConfigPool
    oc get machineconfigpools
    
    # 检查是否有disable-hyperthreading配置
    print_info "Checking hyperthreading disabled configuration..."
    
    local master_config=$(oc get machineconfigpools master -o jsonpath='{.status.configuration.name}')
    local worker_config=$(oc get machineconfigpools worker -o jsonpath='{.status.configuration.name}')
    
    print_info "Master configuration: $master_config"
    print_info "Worker configuration: $worker_config"
    
    # 检查MachineConfig中是否包含disable-hyperthreading
    if oc get machineconfig "$master_config" -o yaml | grep -q "disable-hyperthreading"; then
        print_success "Master nodes contain hyperthreading disabled configuration"
    else
        print_warning "Master nodes may not contain hyperthreading disabled configuration"
    fi
    
    if oc get machineconfig "$worker_config" -o yaml | grep -q "disable-hyperthreading"; then
        print_success "Worker nodes contain hyperthreading disabled configuration"
    else
        print_warning "Worker nodes may not contain hyperthreading disabled configuration"
    fi
}

# Show test results
show_test_results() {
    print_info "Test results summary:"
    echo "=================================="
    echo "Cluster name: $CLUSTER_NAME"
    echo "AWS region: $AWS_REGION"
    echo "Instance type: $INSTANCE_TYPE"
    echo "Installation directory: $INSTALL_DIR"
    
    if [ "$SKIP_INSTALL" = false ]; then
        echo "Kubeconfig: $INSTALL_DIR/auth/kubeconfig"
        echo ""
        echo "Verification commands:"
        echo "  export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig"
        echo "  oc get nodes"
        echo "  oc get machineconfigpools"
        echo "  oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo"
    fi
    
    echo ""
    echo "Cleanup commands:"
    echo "  openshift-install destroy cluster --dir $INSTALL_DIR"
}

# 主函数
main() {
    check_prerequisites
    check_aws_credentials
    create_install_directory
    generate_install_config
    install_cluster
    verify_hyperthreading_disabled
    verify_machine_config_pools
    show_test_results
    
    print_success "OCP-23541 test setup completed!"
}

# 执行主函数
main "$@"
