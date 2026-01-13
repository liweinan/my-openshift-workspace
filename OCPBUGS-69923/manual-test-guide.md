# OCPBUGS-69923 手动测试指南

## 问题描述

控制平面机器间歇性地被创建在与 machine spec 中指定的可用区不同的可用区中。这是因为 `FilterZonesBasedOnInstanceType` 返回的 zone 列表使用了 set 的 `UnsortedList()` 函数，该函数返回的顺序是不确定的。

当 CAPI 和 MAPI manifest 生成独立调用此函数时，它们可能收到不同顺序的 zones，导致 CAPI 和 MAPI manifest 之间的机器 zone 分配不匹配。

## 修复说明

此修复确保在进一步处理之前对 zone slices 进行排序，以保证 CAPI 和 MAPI manifest 中的 zone 分配顺序一致。

**注意**：此修复仅适用于以下场景：
- 默认使用区域中可用 AZ（即不使用 BYO subnets）
- 未在 machine pool `platform.aws.zones` 中定义特定 zones

## 前置条件

1. 已构建包含修复的 `openshift-install` 二进制文件
2. 拥有 AWS 账户和相应的凭证
3. 已安装 `oc`、`jq`、`yq` 等工具
4. 准备一个有效的 `install-config.yaml` 文件（不指定 zones）

## 验证二进制文件是否包含 PR #10188

在开始功能测试之前，建议先验证 `openshift-install` 二进制文件是否包含所需的修复。

### 方法 1: 检查二进制文件中的字符串（推荐）

修复在代码中添加了 `slices.Sort` 调用。可以通过搜索二进制文件中的相关字符串来验证：

```bash
# 检查二进制文件是否包含 slices.Sort 相关的符号
strings <path_to_openshift-install> | grep -i "slices.Sort" || echo "未找到 slices.Sort"

# 或者检查更具体的函数调用模式
strings <path_to_openshift-install> | grep -E "(slices|Sort.*Zones)" | head -20
```

**注意**：由于 Go 二进制文件的编译优化，字符串可能不完全匹配。如果找不到，可以尝试其他方法。

### 方法 2: 检查构建信息和 Git Commit

如果二进制文件包含构建信息，可以检查 git commit hash：

```bash
# 检查版本信息
openshift-install version

# 如果二进制文件包含调试信息，可以尝试提取
strings <path_to_openshift-install> | grep -E "(1957abe0|10188|OCPBUGS-69923)" | head -10
```

从你的构建日志中可以看到：
```
merging: #10188 1957abe0
```

可以搜索 commit hash `1957abe0` 或 PR 号 `10188`。

### 方法 3: 检查构建日志（最可靠）

从你提供的构建日志中，可以确认 PR 已被合并：

```
INFO[2026-01-13T08:58:49Z] Resolved source https://github.com/openshift/installer to main@89c086b7, merging: #10188 1957abe0
```

这表示构建确实包含了 PR #10188 (commit 1957abe0)。

### 方法 4: 通过功能测试验证（最准确）

最可靠的方法是进行功能测试。如果修复生效，应该能看到：
1. CAPI 和 MAPI manifest 中的 zone 分配一致
2. 多次运行 manifest 生成，zone 顺序保持一致

如果功能测试通过，说明修复已包含在二进制文件中。

### 方法 5: 反编译检查（高级）

如果有 Go 工具链，可以尝试：

```bash
# 使用 go tool 检查（需要二进制文件包含符号表）
go tool nm <path_to_openshift-install> | grep -i "sort\|zone" | head -20

# 或者使用 objdump（Linux）
objdump -t <path_to_openshift-install> | grep -i "sort\|zone" | head -20
```

### 快速验证脚本

可以使用项目中的 `verify_pr_10188.sh` 脚本进行快速验证：

```bash
./verify_pr_10188.sh <path_to_openshift-install>
```

**推荐做法**：结合构建日志确认（方法 3）和功能测试验证（方法 4）是最可靠的方式。

## 测试步骤

### 步骤 1: 准备安装配置文件

创建一个 `install-config.yaml` 文件，**确保不指定 `controlPlane.platform.aws.zones`**：

```yaml
apiVersion: v1
baseDomain: example.com
metadata:
  name: test-cluster-69923
platform:
  aws:
    region: us-east-2
controlPlane:
  name: master
  replicas: 3
  # 注意：不要在这里指定 zones
  platform:
    aws:
      # zones: []  # 不要指定 zones
compute:
- name: worker
  replicas: 3
  platform:
    aws:
      # zones: []  # 不要指定 zones
pullSecret: '{"auths":{...}}'
sshKey: 'ssh-rsa ...'
```

**重要**：
- 不要使用 BYO subnets
- 不要在 `controlPlane.platform.aws.zones` 中指定 zones
- 不要在 `compute[].platform.aws.zones` 中指定 zones

### 步骤 2: 生成 Manifests

使用修复后的 `openshift-install` 生成 manifests：

```bash
openshift-install create manifests --dir=<installation_directory>
```

### 步骤 3: 验证 CAPI 和 MAPI Manifest 中的 Zone 分配

#### 3.1 检查 CAPI Machine Manifest 中的 Zone 分配

**CAPI 文件结构**：
- CAPI 为每个 master 机器生成**独立的文件**
- 文件列表：`99_openshift-cluster-api_master-machines-0.yaml`, `99_openshift-cluster-api_master-machines-1.yaml`, `99_openshift-cluster-api_master-machines-2.yaml`
- 每个文件是一个独立的 `Machine` 对象，包含一个机器的配置
- **因此需要使用 for 循环遍历每个文件**

查找 CAPI 相关的 machine manifest 文件：

```bash
# 查找所有 CAPI master machine manifests
find <installation_directory>/openshift -name "*cluster-api*master*.yaml" -type f

# 方法 1: 提取每个机器的 zone 信息（详细输出）
for file in <installation_directory>/openshift/99_openshift-cluster-api_master-machines-*.yaml; do
  echo "=== $file ==="
  yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file"
done
```

**快速检查方法**（推荐）：

```bash
# 切换到安装目录
cd <installation_directory>

# 快速列出所有 CAPI machines 的 zone（按文件名排序）
# 注意：需要 for 循环，因为每个机器在单独的文件中
for file in openshift/99_openshift-cluster-api_master-machines-*.yaml; do
  echo "$(basename $file): $(yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file")"
done | sort
```

**示例输出**：
```
99_openshift-cluster-api_master-machines-0.yaml: us-east-1a
99_openshift-cluster-api_master-machines-1.yaml: us-east-1b
99_openshift-cluster-api_master-machines-2.yaml: us-east-1c
```

记录每个 CAPI machine 的 zone，例如：
- master-0: us-east-1a
- master-1: us-east-1b
- master-2: us-east-1c

#### 3.2 检查 MAPI Machine Manifest 中的 Zone 分配

**MAPI 文件结构**：
- MAPI 只生成**一个文件**：`99_openshift-machine-api_master-control-plane-machine-set.yaml`
- 这是一个 `ControlPlaneMachineSet` 对象
- 所有 zones 都存储在一个文件的 `failureDomains.aws[]` 数组中
- **因此不需要 for 循环，可以直接用一个 yq 命令提取所有 zones**

查找 MAPI 相关的 machine manifest 文件：

```bash
# 查找 MAPI manifest 文件
find <installation_directory>/openshift -name "*machine-api*master*.yaml" -type f

# 提取 MAPI ControlPlaneMachineSet 中的 zones（从 failureDomains）
cd <installation_directory>
yq eval '.spec.template.machines_v1beta1_machine_openshift_io.failureDomains.aws[].placement.availabilityZone' openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml
```

**快速检查方法**（推荐）：

```bash
# 切换到安装目录
cd <installation_directory>

# 列出 MAPI failureDomains 中的所有 zones（按顺序）
# 注意：不需要 for 循环，因为所有 zones 在一个文件的数组中
echo "MAPI Zones (from ControlPlaneMachineSet failureDomains):"
yq eval '.spec.template.machines_v1beta1_machine_openshift_io.failureDomains.aws[].placement.availabilityZone' openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml | nl -v0 -w1 -s': '

# 或者只显示前 3 个（对应 3 个 master）
echo "MAPI Zones (first 3, for masters):"
yq eval '.spec.template.machines_v1beta1_machine_openshift_io.failureDomains.aws[].placement.availabilityZone' openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml | head -3 | nl -v0 -w1 -s': '
```

**示例输出**：
```
MAPI Zones (from ControlPlaneMachineSet failureDomains):
0: us-east-1a
1: us-east-1b
2: us-east-1c
3: us-east-1d
4: us-east-1f
```

**注意**：MAPI 的 ControlPlaneMachineSet 包含所有可用的 zones，但实际分配给 master 的是前 N 个（N = master 数量，通常是 3）。需要比较的是前 3 个 zones 与 CAPI 的 3 个 zones 是否一致。

记录 MAPI 中前 N 个 zones（N = master 数量）。

#### 3.3 验证 Zone 分配一致性

**预期结果**：CAPI 和 MAPI manifest 中对应索引的机器应该分配到相同的 zone。

例如：
- CAPI master-0 和 MAPI master-0 都应该是 us-east-2a
- CAPI master-1 和 MAPI master-1 都应该是 us-east-2b
- CAPI master-2 和 MAPI master-2 都应该是 us-east-2c

**手动快速比较方法**：

```bash
# 切换到安装目录
cd <installation_directory>

# 1. 获取 CAPI zones（按文件顺序）
#    注意：CAPI 需要 for 循环，因为每个机器在单独的文件中
echo "=== CAPI Zones ==="
for file in openshift/99_openshift-cluster-api_master-machines-*.yaml; do
  echo "$(basename $file): $(yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file")"
done | sort

# 2. 获取 MAPI zones（前 3 个，对应 3 个 master）
#    注意：MAPI 不需要 for 循环，因为所有 zones 在一个文件的数组中
echo ""
echo "=== MAPI Zones (first 3) ==="
yq eval '.spec.template.machines_v1beta1_machine_openshift_io.failureDomains.aws[].placement.availabilityZone' openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml | head -3 | nl -v0 -w1 -s': '

# 3. 手动比较：CAPI 和 MAPI 的前 3 个 zones 应该完全一致
```

**为什么 CAPI 需要 for 循环，而 MAPI 不需要？**

- **CAPI**：每个 master 机器有**独立的文件**（3 个文件），每个文件是一个 Machine 对象，需要遍历每个文件
- **MAPI**：所有 master 机器信息在**一个文件**中（ControlPlaneMachineSet），所有 zones 存储在一个数组中，可以直接用 yq 提取数组

**示例输出**：
```bash
=== CAPI Zones ===
99_openshift-cluster-api_master-machines-0.yaml: us-east-1a
99_openshift-cluster-api_master-machines-1.yaml: us-east-1b
99_openshift-cluster-api_master-machines-2.yaml: us-east-1c

=== MAPI Zones (first 3) ===
0: us-east-1a
1: us-east-1b
2: us-east-1c
```

**验证脚本**（自动化验证）：

也可以使用项目中的 `verify-manifests.sh` 脚本进行自动化验证：

```bash
./verify-manifests.sh <installation_directory>
```

或者使用以下脚本：

```bash
#!/bin/bash

INSTALL_DIR="<installation_directory>"

echo "=== Verify CAPI and MAPI Zone Allocation Consistency ==="

# Get CAPI zones
echo "CAPI Machine Zones:"
capi_zones=()
for file in "$INSTALL_DIR"/openshift/99_openshift-cluster-api_master-machines-*.yaml; do
  zone=$(yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file")
  capi_zones+=("$zone")
  echo "  $(basename $file): $zone"
done

# Get MAPI zones (first N zones from failureDomains)
echo ""
echo "MAPI Machine Zones (from ControlPlaneMachineSet):"
mapi_zones=()
mapi_file="$INSTALL_DIR/openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml"
zones=$(yq eval '.spec.template.machines_v1beta1_machine_openshift_io.failureDomains.aws[].placement.availabilityZone' "$mapi_file")
master_count=${#capi_zones[@]}
mapi_index=0
for zone in $zones; do
  if [ $mapi_index -lt $master_count ]; then
    mapi_zones+=("$zone")
    echo "  master-$mapi_index: $zone"
    mapi_index=$((mapi_index + 1))
  else
    break
  fi
done

# Compare
echo ""
echo "=== Consistency Check ==="
all_match=true
for i in "${!capi_zones[@]}"; do
  if [ "${capi_zones[$i]}" != "${mapi_zones[$i]}" ]; then
    echo "❌ Mismatch: master-$i - CAPI: ${capi_zones[$i]}, MAPI: ${mapi_zones[$i]}"
    all_match=false
  else
    echo "✓ Match: master-$i - Zone: ${capi_zones[$i]}"
  fi
done

if [ "$all_match" = true ]; then
  echo ""
  echo "✅ All machines have consistent zone allocation!"
  exit 0
else
  echo ""
  echo "❌ Zone allocation inconsistency detected!"
  exit 1
fi
```

### 步骤 4: 部署集群并验证实际 Zone

如果 manifest 验证通过，继续部署集群：

```bash
openshift-install create cluster --dir=<installation_directory>
```

等待集群安装完成。

### 步骤 5: 验证实际创建的机器的 Zone

#### 5.1 获取集群访问权限

```bash
export KUBECONFIG=<installation_directory>/auth/kubeconfig
```

#### 5.2 检查所有 Master 机器的 Zone 信息

```bash
# 获取所有 master 机器
oc get machine -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=master

# 对每个 master 机器，检查以下信息：
for machine in $(oc get machine -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=master -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Machine: $machine ==="
  
  # 1. Zone label
  echo "Zone Label:"
  oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.metadata.labels.machine\.openshift\.io/zone}' && echo
  
  # 2. ProviderID 中的 zone
  echo "ProviderID Zone:"
  oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerID}' | grep -oP 'aws:///\K[^/]+' && echo
  
  # 3. Spec 中的 availabilityZone
  echo "Spec AvailabilityZone:"
  oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.placement.availabilityZone}' && echo
  
  # 4. Subnet 信息（如果使用 subnet filter）
  echo "Subnet Filter:"
  oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.subnet.filters[*].values[0]}' && echo
  
  echo ""
done
```

#### 5.3 验证 Zone 一致性

**预期结果**：对于每个 master 机器，以下三个值应该一致：
1. `metadata.labels.machine.openshift.io/zone`（zone label）
2. `spec.providerID` 中的 zone（例如 `aws:///us-east-2a/...`）
3. `spec.providerSpec.value.placement.availabilityZone`（spec 中指定的 zone）

**验证脚本**：

```bash
#!/bin/bash

echo "=== 验证实际机器的 Zone 一致性 ==="

all_consistent=true

for machine in $(oc get machine -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=master -o jsonpath='{.items[*].metadata.name}'); do
  echo "Checking machine: $machine"
  
  zone_label=$(oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.metadata.labels.machine\.openshift\.io/zone}')
  provider_id=$(oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerID}')
  provider_zone=$(echo "$provider_id" | grep -oP 'aws:///\K[^/]+')
  spec_zone=$(oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.placement.availabilityZone}')
  
  echo "  Zone Label: $zone_label"
  echo "  ProviderID Zone: $provider_zone"
  echo "  Spec Zone: $spec_zone"
  
  if [ "$zone_label" = "$provider_zone" ] && [ "$provider_zone" = "$spec_zone" ]; then
    echo "  ✅ Zone 一致"
  else
    echo "  ❌ Zone 不一致！"
    all_consistent=false
  fi
  echo ""
done

if [ "$all_consistent" = true ]; then
  echo "✅ 所有机器的 zone 都一致！"
  exit 0
else
  echo "❌ 发现 zone 不一致的机器！"
  exit 1
fi
```

### 步骤 6: 多次运行验证（可选，但推荐）

为了验证修复的确定性，可以多次运行 manifest 生成步骤，确保每次生成的 zone 分配顺序都一致：

```bash
for i in {1..5}; do
  echo "=== 运行 $i ==="
  rm -rf <installation_directory>/openshift
  openshift-install create manifests --dir=<installation_directory>
  
  # 提取 zones
  echo "CAPI zones:"
  for file in <installation_directory>/openshift/99_openshift-cluster-api_master-machines-*.yaml; do
    yq eval '.spec.template.spec.providerSpec.value.placement.availabilityZone' "$file"
  done | sort
  
  echo "MAPI zones:"
  for file in <installation_directory>/openshift/99_openshift-machine-api_master-machines-*.yaml; do
    yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file"
  done | sort
  
  echo ""
done
```

**预期结果**：每次运行都应该产生相同的 zone 分配顺序。

## 成功标准

1. ✅ CAPI 和 MAPI manifest 中对应索引的机器分配到相同的 zone
2. ✅ 实际创建的机器的 zone label、providerID zone 和 spec zone 三者一致
3. ✅ 多次运行 manifest 生成，zone 分配顺序保持一致（确定性）

## 失败场景

如果发现以下情况，说明修复可能未生效或存在问题：

1. ❌ CAPI 和 MAPI manifest 中对应索引的机器分配到不同的 zone
2. ❌ 实际机器的 zone label 与 spec 中指定的 zone 不一致
3. ❌ 实际机器的 providerID zone 与 spec 中指定的 zone 不一致
4. ❌ 多次运行 manifest 生成，zone 分配顺序不一致

## 注意事项

1. 此修复**不适用于**以下场景：
   - BYO subnets（已有其他修复处理）
   - 在 `platform.aws.zones` 中明确指定了 zones（应保留用户指定的顺序）

2. 如果测试环境使用 Shared-VPC，需要确保测试场景符合修复的适用范围。

3. 建议在多个不同的 AWS 区域进行测试，以确保修复的通用性。

## 测试报告模板

```
测试日期: YYYY-MM-DD
测试人员: <your_name>
OpenShift Installer 版本: <version_with_fix>
AWS 区域: <region>

测试结果:
[ ] CAPI 和 MAPI manifest zone 分配一致
[ ] 实际机器 zone 一致性验证通过
[ ] 多次运行 manifest 生成，zone 顺序一致

问题发现:
<如有问题，请详细描述>

验证状态: [ ] PASS [ ] FAIL
```
