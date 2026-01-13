# OCPBUGS-69923: Control Plane Machines Zone Ordering Fix

## 问题描述

**OCPBUGS-69923**: `[AWS] Control plane machines are created in wrong zone`

控制平面机器间歇性地被创建在与 machine spec 中指定的可用区不同的可用区中。这是因为 `FilterZonesBasedOnInstanceType` 返回的 zone 列表使用了 set 的 `UnsortedList()` 函数，该函数返回的顺序是不确定的。

当 CAPI 和 MAPI manifest 生成独立调用此函数时，它们可能收到不同顺序的 zones，导致 CAPI 和 MAPI manifest 之间的机器 zone 分配不匹配。

## 修复说明

**PR #10188**: `OCPBUGS-69923: ensure deterministic zone ordering for control plane machines`

此修复确保在进一步处理之前对 zone slices 进行排序，以保证 CAPI 和 MAPI manifest 中的 zone 分配顺序一致。

**修复范围**：
- 仅适用于默认使用区域中可用 AZ 的场景（即不使用 BYO subnets）
- 未在 machine pool `platform.aws.zones` 中定义特定 zones 的场景
- BYO subnets 场景已有其他修复处理（PR #9662）
- 如果用户定义了 `platform.aws.zones`，应保留用户指定的顺序

## 相关文件

- `manual-test-guide.md` - 详细的手动测试指南
- `verify_pr_10188.sh` - 验证二进制文件是否包含修复的脚本
- `verify-manifests.sh` - 静态验证 manifests 中的 zone 分配一致性
- `verify-cluster.sh` - 验证已安装集群中的机器 zone 一致性

## 快速开始

### 1. 验证二进制文件包含修复

```bash
./verify_pr_10188.sh <path_to_openshift-install>
```

### 2. 静态验证 Manifests（推荐第一步）

在生成 manifests 后，验证 CAPI 和 MAPI manifest 中的 zone 分配是否一致：

```bash
# 生成 manifests
openshift-install create manifests --dir <installation_directory>

# 验证 zone 一致性
./verify-manifests.sh <installation_directory>
```

**预期结果**：CAPI 和 MAPI manifest 中对应索引的机器应分配到相同的 zone。

### 3. 验证已安装的集群

在集群安装完成后，验证实际创建的机器的 zone 一致性：

```bash
# 设置 kubeconfig
export KUBECONFIG=<installation_directory>/auth/kubeconfig

# 验证集群中的机器 zone 一致性
./verify-cluster.sh <installation_directory>/auth/kubeconfig
```

**预期结果**：每台机器的 zone label、providerID zone 和 spec zone 三者应一致。

### 完整测试流程

```bash
# 1. 验证二进制文件
./verify_pr_10188.sh /path/to/openshift-install

# 2. 准备 install-config.yaml（不指定 zones）
# 编辑 install-config.yaml，确保不指定 controlPlane.platform.aws.zones

# 3. 生成 manifests
openshift-install create manifests --dir ./test-cluster

# 4. 静态验证 manifests
./verify-manifests.sh ./test-cluster

# 5. 安装集群（手动执行）
openshift-install create cluster --dir ./test-cluster

# 6. 验证已安装的集群
./verify-cluster.sh ./test-cluster/auth/kubeconfig
```

## 测试要点

1. **Manifest 验证**：CAPI 和 MAPI manifest 中对应索引的机器应分配到相同的 zone
2. **实际部署验证**：实际创建的机器的 zone label、providerID zone 和 spec zone 应一致
3. **确定性验证**：多次运行 manifest 生成，zone 分配顺序应保持一致

## 相关链接

- [JIRA Issue: OCPBUGS-69923](https://issues.redhat.com/browse/OCPBUGS-69923)
- [GitHub PR: #10188](https://github.com/openshift/installer/pull/10188)
- [Related Fix: PR #9662 (BYO subnets)](https://github.com/openshift/installer/pull/9662)

## 注意事项

- 此修复不适用于 BYO subnets 场景（已有其他修复）
- 此修复不适用于用户明确指定 zones 的场景（应保留用户顺序）
- 建议在多个不同的 AWS 区域进行测试
