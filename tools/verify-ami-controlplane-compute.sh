#!/bin/bash

# 验证 OpenShift 集群中 Control Plane 和 Compute 节点使用的 AMI ID
# 
# 使用方法:
#   ./verify-ami-controlplane-compute.sh [metadata.json路径] [install-config.yaml路径]
#
# 环境变量:
#   KUBECONFIG: 集群的 kubeconfig 文件路径
#   AWS_REGION: AWS 区域（如果未指定，从 metadata.json 中获取）
#   AWS_SHARED_CREDENTIALS_FILE: AWS 凭证文件路径

set -o nounset
set -o errexit
set -o pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 参数
METADATA_FILE="${1:-metadata.json}"
INSTALL_CONFIG="${2:-install-config.yaml}"

echo "=========================================="
echo "验证 Control Plane 和 Compute 节点 AMI ID"
echo "=========================================="
echo ""

# 检查必需的工具
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ 错误: jq 命令未找到${NC}"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ 错误: aws 命令未找到${NC}"; exit 1; }

# 检查 metadata.json
if [[ ! -f "${METADATA_FILE}" ]]; then
    echo -e "${RED}❌ 错误: metadata.json 文件不存在: ${METADATA_FILE}${NC}"
    echo "   使用方法: $0 [metadata.json路径] [install-config.yaml路径]"
    exit 1
fi

# 获取 region 和 infraID
REGION=$(jq -r '.aws.region // empty' "${METADATA_FILE}")
INFRA_ID=$(jq -r '.infraID // empty' "${METADATA_FILE}")

if [[ -z "${REGION}" ]]; then
    REGION="${AWS_REGION:-}"
fi

if [[ -z "${REGION}" ]]; then
    echo -e "${RED}❌ 错误: 无法确定 AWS 区域${NC}"
    exit 1
fi

if [[ -z "${INFRA_ID}" ]]; then
    echo -e "${RED}❌ 错误: 无法从 metadata.json 获取 infraID${NC}"
    exit 1
fi

echo -e "${BLUE}集群信息:${NC}"
echo "  Region: ${REGION}"
echo "  Infra ID: ${INFRA_ID}"
echo ""

# 从 install-config.yaml 读取配置的 AMI（如果存在）
CONTROL_PLANE_AMI_CONFIG=""
COMPUTE_AMI_CONFIG=""
if [[ -f "${INSTALL_CONFIG}" ]]; then
    if command -v yq-go >/dev/null 2>&1; then
        CONTROL_PLANE_AMI_CONFIG=$(yq-go r "${INSTALL_CONFIG}" 'controlPlane.platform.aws.amiID' 2>/dev/null || echo "")
        COMPUTE_AMI_CONFIG=$(yq-go r "${INSTALL_CONFIG}" 'compute[0].platform.aws.amiID' 2>/dev/null || echo "")
    else
        CONTROL_PLANE_AMI_CONFIG=$(jq -r '.controlPlane.platform.aws.amiID // empty' "${INSTALL_CONFIG}" 2>/dev/null || echo "")
        COMPUTE_AMI_CONFIG=$(jq -r '.compute[0].platform.aws.amiID // empty' "${INSTALL_CONFIG}" 2>/dev/null || echo "")
    fi
fi

# 方法 1: 通过 AWS CLI 查询实际运行的 EC2 实例
echo "=========================================="
echo "方法 1: 通过 AWS CLI 查询 EC2 实例"
echo "=========================================="

# 查询 master 节点的 AMI
echo -e "${BLUE}查询 Master 节点 AMI...${NC}"
MASTER_AMI=$(aws ec2 describe-instances \
    --region "${REGION}" \
    --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
              "Name=tag:Name,Values=*master*" \
              "Name=instance-state-name,Values=running" \
    --output json 2>/dev/null | jq -r '.Reservations[].Instances[].ImageId' | sort | uniq)

if [[ -n "${MASTER_AMI}" ]]; then
    echo -e "${GREEN}✓ Master 节点 AMI: ${MASTER_AMI}${NC}"
    
    # 如果配置了 controlPlane AMI，进行对比
    if [[ -n "${CONTROL_PLANE_AMI_CONFIG}" ]]; then
        if [[ "${MASTER_AMI}" == "${CONTROL_PLANE_AMI_CONFIG}" ]]; then
            echo -e "  ${GREEN}✓ 与 install-config.yaml 中的 controlPlane.platform.aws.amiID 匹配${NC}"
        else
            echo -e "  ${RED}✗ 与 install-config.yaml 不匹配！${NC}"
            echo -e "    配置的 AMI: ${CONTROL_PLANE_AMI_CONFIG}"
            echo -e "    实际使用的 AMI: ${MASTER_AMI}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  未找到运行中的 master 节点${NC}"
fi

echo ""

# 查询 worker 节点的 AMI
echo -e "${BLUE}查询 Worker 节点 AMI...${NC}"
WORKER_AMI=$(aws ec2 describe-instances \
    --region "${REGION}" \
    --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
              "Name=tag:Name,Values=*worker*" \
              "Name=instance-state-name,Values=running" \
    --output json 2>/dev/null | jq -r '.Reservations[].Instances[].ImageId' | sort | uniq)

if [[ -n "${WORKER_AMI}" ]]; then
    echo -e "${GREEN}✓ Worker 节点 AMI: ${WORKER_AMI}${NC}"
    
    # 如果配置了 compute AMI，进行对比
    if [[ -n "${COMPUTE_AMI_CONFIG}" ]]; then
        if [[ "${WORKER_AMI}" == "${COMPUTE_AMI_CONFIG}" ]]; then
            echo -e "  ${GREEN}✓ 与 install-config.yaml 中的 compute[0].platform.aws.amiID 匹配${NC}"
        else
            echo -e "  ${RED}✗ 与 install-config.yaml 不匹配！${NC}"
            echo -e "    配置的 AMI: ${COMPUTE_AMI_CONFIG}"
            echo -e "    实际使用的 AMI: ${WORKER_AMI}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  未找到运行中的 worker 节点${NC}"
fi

echo ""

# 方法 2: 通过 oc 命令查看集群资源（如果可用）
if command -v oc >/dev/null 2>&1; then
    if [[ -n "${KUBECONFIG:-}" ]] && [[ -f "${KUBECONFIG}" ]]; then
        export KUBECONFIG
    elif [[ -f "${HOME}/.kube/config" ]]; then
        export KUBECONFIG="${HOME}/.kube/config"
    fi
    
    if oc get cluster 2>/dev/null | grep -q .; then
        echo "=========================================="
        echo "方法 2: 通过 oc 命令查看集群资源"
        echo "=========================================="
        
        # 查看 ControlPlaneMachineSet
        echo -e "${BLUE}查询 ControlPlaneMachineSet AMI...${NC}"
        CPMS_AMI=$(oc get controlplanemachineset.machine.openshift.io -n openshift-machine-api -o json 2>/dev/null | \
            jq -r '.items[] | .spec.template."machines_v1beta1_machine_openshift_io".spec.providerSpec.value.ami.id' | head -1)
        
        if [[ -n "${CPMS_AMI}" ]]; then
            echo -e "${GREEN}✓ ControlPlaneMachineSet AMI: ${CPMS_AMI}${NC}"
            if [[ -n "${MASTER_AMI}" ]] && [[ "${CPMS_AMI}" == "${MASTER_AMI}" ]]; then
                echo -e "  ${GREEN}✓ 与 EC2 实例使用的 AMI 匹配${NC}"
            else
                echo -e "  ${YELLOW}⚠️  与 EC2 实例使用的 AMI 不同${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  未找到 ControlPlaneMachineSet${NC}"
        fi
        
        echo ""
        
        # 查看 MachineSet
        echo -e "${BLUE}查询 MachineSet AMI...${NC}"
        MACHINESET_AMI=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o json 2>/dev/null | \
            jq -r '.items[] | .spec.template.spec.providerSpec.value.ami.id' | sort | uniq | head -1)
        
        if [[ -n "${MACHINESET_AMI}" ]]; then
            echo -e "${GREEN}✓ MachineSet AMI: ${MACHINESET_AMI}${NC}"
            if [[ -n "${WORKER_AMI}" ]] && [[ "${MACHINESET_AMI}" == "${WORKER_AMI}" ]]; then
                echo -e "  ${GREEN}✓ 与 EC2 实例使用的 AMI 匹配${NC}"
            else
                echo -e "  ${YELLOW}⚠️  与 EC2 实例使用的 AMI 不同${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  未找到 MachineSet${NC}"
        fi
        
        echo ""
    else
        echo -e "${YELLOW}⚠️  无法连接到集群，跳过 oc 命令验证${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}⚠️  oc 命令未找到，跳过集群资源验证${NC}"
    echo ""
fi

# 汇总结果
echo "=========================================="
echo "验证结果汇总"
echo "=========================================="
echo ""

if [[ -n "${MASTER_AMI}" ]]; then
    echo -e "Master 节点 AMI: ${GREEN}${MASTER_AMI}${NC}"
    if [[ -n "${CONTROL_PLANE_AMI_CONFIG}" ]]; then
        if [[ "${MASTER_AMI}" == "${CONTROL_PLANE_AMI_CONFIG}" ]]; then
            echo -e "  状态: ${GREEN}✓ 与配置匹配${NC}"
        else
            echo -e "  状态: ${RED}✗ 与配置不匹配${NC}"
        fi
    fi
else
    echo -e "Master 节点 AMI: ${YELLOW}未找到${NC}"
fi

echo ""

if [[ -n "${WORKER_AMI}" ]]; then
    echo -e "Worker 节点 AMI: ${GREEN}${WORKER_AMI}${NC}"
    if [[ -n "${COMPUTE_AMI_CONFIG}" ]]; then
        if [[ "${WORKER_AMI}" == "${COMPUTE_AMI_CONFIG}" ]]; then
            echo -e "  状态: ${GREEN}✓ 与配置匹配${NC}"
        else
            echo -e "  状态: ${RED}✗ 与配置不匹配${NC}"
        fi
    fi
else
    echo -e "Worker 节点 AMI: ${YELLOW}未找到${NC}"
fi

echo ""

# 如果配置了不同的 AMI，显示对比
if [[ -n "${CONTROL_PLANE_AMI_CONFIG}" ]] && [[ -n "${COMPUTE_AMI_CONFIG}" ]]; then
    if [[ "${CONTROL_PLANE_AMI_CONFIG}" != "${COMPUTE_AMI_CONFIG}" ]]; then
        echo -e "${BLUE}配置信息:${NC}"
        echo "  Control Plane AMI (配置): ${CONTROL_PLANE_AMI_CONFIG}"
        echo "  Compute AMI (配置): ${COMPUTE_AMI_CONFIG}"
        echo ""
    fi
fi

# 退出码
if [[ -n "${MASTER_AMI}" ]] && [[ -n "${WORKER_AMI}" ]]; then
    VERIFICATION_PASSED=true
    
    if [[ -n "${CONTROL_PLANE_AMI_CONFIG}" ]] && [[ "${MASTER_AMI}" != "${CONTROL_PLANE_AMI_CONFIG}" ]]; then
        VERIFICATION_PASSED=false
    fi
    
    if [[ -n "${COMPUTE_AMI_CONFIG}" ]] && [[ "${WORKER_AMI}" != "${COMPUTE_AMI_CONFIG}" ]]; then
        VERIFICATION_PASSED=false
    fi
    
    if [[ "${VERIFICATION_PASSED}" == true ]]; then
        exit 0
    else
        exit 1
    fi
else
    exit 1
fi

