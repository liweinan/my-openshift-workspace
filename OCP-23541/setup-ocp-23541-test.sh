#!/bin/bash

# OCP-23541 - [ipi-on-aws] [Hyperthreading] Create cluster with hyperthreading disabled on worker and master nodes
# 自动化设置脚本

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
OCP-23541 超线程禁用测试自动化脚本

用法:
    $0 [选项]

选项:
    -r, --region <region>        AWS区域 (默认: us-east-2)
    -n, --cluster-name <name>    集群名称 (默认: hyperthreading-test)
    -i, --instance-type <type>   实例类型 (默认: m6i.xlarge)
    -w, --worker-count <count>   工作节点数量 (默认: 3)
    -m, --master-count <count>   主节点数量 (默认: 3)
    -d, --dir <directory>        安装目录 (默认: test)
    --skip-install               跳过集群安装，仅生成配置文件
    -h, --help                   显示此帮助信息

示例:
    # 基本用法
    $0

    # 自定义参数
    $0 --region us-west-2 --cluster-name my-test --instance-type m5.2xlarge

    # 仅生成配置文件
    $0 --skip-install

EOF
}

# 默认参数
AWS_REGION="us-east-2"
CLUSTER_NAME="hyperthreading-test"
INSTANCE_TYPE="m6i.xlarge"
WORKER_COUNT=3
MASTER_COUNT=3
INSTALL_DIR="test"
SKIP_INSTALL=false

# 解析命令行参数
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
            print_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

print_info "开始OCP-23541超线程禁用测试设置..."
print_info "集群名称: $CLUSTER_NAME"
print_info "AWS区域: $AWS_REGION"
print_info "实例类型: $INSTANCE_TYPE"
print_info "工作节点数量: $WORKER_COUNT"
print_info "主节点数量: $MASTER_COUNT"
print_info "安装目录: $INSTALL_DIR"

# 检查必需工具
check_prerequisites() {
    print_info "检查必需工具..."
    
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
        print_error "缺少必需工具: ${missing_tools[*]}"
        print_error "请安装缺少的工具后重试"
        exit 1
    fi
    
    print_success "所有必需工具已安装"
}

# 检查AWS凭证
check_aws_credentials() {
    print_info "检查AWS凭证..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS凭证未配置或无效"
        print_error "请运行 'aws configure' 配置AWS凭证"
        exit 1
    fi
    
    local aws_account=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS凭证有效，账户ID: $aws_account"
}

# 创建安装目录
create_install_directory() {
    print_info "创建安装目录: $INSTALL_DIR"
    
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "目录 $INSTALL_DIR 已存在"
        read -p "是否删除现有目录? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
            print_info "已删除现有目录"
        else
            print_error "安装目录已存在，请选择其他目录或删除现有目录"
            exit 1
        fi
    fi
    
    mkdir -p "$INSTALL_DIR"
    print_success "安装目录创建成功"
}

# 生成install-config.yaml
generate_install_config() {
    print_info "生成install-config.yaml..."
    
    # 检查是否存在pull-secret.json
    local pull_secret_file=""
    if [ -f "../tools/pull-secret.json" ]; then
        pull_secret_file="../tools/pull-secret.json"
    elif [ -f "pull-secret.json" ]; then
        pull_secret_file="pull-secret.json"
    else
        print_error "未找到pull-secret.json文件"
        print_error "请将pull-secret.json文件放在当前目录或../tools/目录中"
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
    
    print_success "install-config.yaml生成成功"
    print_info "配置文件内容:"
    cat "$INSTALL_DIR/install-config.yaml"
}

# 安装集群
install_cluster() {
    if [ "$SKIP_INSTALL" = true ]; then
        print_info "跳过集群安装（仅生成配置文件）"
        return 0
    fi
    
    print_info "开始安装集群..."
    print_warning "这可能需要30-60分钟，请耐心等待..."
    
    if openshift-install create cluster --dir "$INSTALL_DIR" --log-level info; then
        print_success "集群安装成功！"
    else
        print_error "集群安装失败"
        exit 1
    fi
}

# 验证超线程禁用
verify_hyperthreading_disabled() {
    if [ "$SKIP_INSTALL" = true ]; then
        print_info "跳过超线程验证（集群未安装）"
        return 0
    fi
    
    print_info "验证超线程禁用状态..."
    
    # 设置kubeconfig
    export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
    
    # 等待节点就绪
    print_info "等待所有节点就绪..."
    oc wait --for=condition=Ready nodes --all --timeout=600s
    
    # 获取节点列表
    local nodes=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')
    print_info "发现节点: $nodes"
    
    # 验证每个节点的超线程状态
    for node in $nodes; do
        print_info "验证节点: $node"
        
        # 创建debug pod并检查CPU信息
        local cpu_info=$(oc debug "node/$node" -- chroot /host cat /proc/cpuinfo 2>/dev/null || echo "")
        
        if [ -n "$cpu_info" ]; then
            local siblings=$(echo "$cpu_info" | grep "siblings" | head -1 | awk '{print $3}')
            local cpu_cores=$(echo "$cpu_info" | grep "cpu cores" | head -1 | awk '{print $4}')
            
            print_info "节点 $node: siblings=$siblings, cpu_cores=$cpu_cores"
            
            if [ "$siblings" = "$cpu_cores" ]; then
                print_success "节点 $node: 超线程已禁用 (siblings == cpu_cores)"
            else
                print_error "节点 $node: 超线程可能未禁用 (siblings != cpu_cores)"
            fi
        else
            print_warning "无法获取节点 $node 的CPU信息"
        fi
    done
}

# 验证MachineConfigPool
verify_machine_config_pools() {
    if [ "$SKIP_INSTALL" = true ]; then
        print_info "跳过MachineConfigPool验证（集群未安装）"
        return 0
    fi
    
    print_info "验证MachineConfigPool状态..."
    
    # 检查MachineConfigPool
    oc get machineconfigpools
    
    # 检查是否有disable-hyperthreading配置
    print_info "检查超线程禁用配置..."
    
    local master_config=$(oc get machineconfigpools master -o jsonpath='{.status.configuration.name}')
    local worker_config=$(oc get machineconfigpools worker -o jsonpath='{.status.configuration.name}')
    
    print_info "Master配置: $master_config"
    print_info "Worker配置: $worker_config"
    
    # 检查MachineConfig中是否包含disable-hyperthreading
    if oc get machineconfig "$master_config" -o yaml | grep -q "disable-hyperthreading"; then
        print_success "Master节点包含超线程禁用配置"
    else
        print_warning "Master节点可能未包含超线程禁用配置"
    fi
    
    if oc get machineconfig "$worker_config" -o yaml | grep -q "disable-hyperthreading"; then
        print_success "Worker节点包含超线程禁用配置"
    else
        print_warning "Worker节点可能未包含超线程禁用配置"
    fi
}

# 显示测试结果
show_test_results() {
    print_info "测试结果总结:"
    echo "=================================="
    echo "集群名称: $CLUSTER_NAME"
    echo "AWS区域: $AWS_REGION"
    echo "实例类型: $INSTANCE_TYPE"
    echo "安装目录: $INSTALL_DIR"
    
    if [ "$SKIP_INSTALL" = false ]; then
        echo "Kubeconfig: $INSTALL_DIR/auth/kubeconfig"
        echo ""
        echo "验证命令:"
        echo "  export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig"
        echo "  oc get nodes"
        echo "  oc get machineconfigpools"
        echo "  oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo"
    fi
    
    echo ""
    echo "清理命令:"
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
    
    print_success "OCP-23541测试设置完成！"
}

# 执行主函数
main "$@"
