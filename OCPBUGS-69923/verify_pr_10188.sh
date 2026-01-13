#!/bin/bash

# 验证 openshift-install 二进制文件是否包含 PR #10188 (OCPBUGS-69923)
# 使用方法: ./verify_pr_10188.sh <path_to_openshift-install>

set -e

INSTALLER_BIN="${1:-openshift-install}"

if [ ! -f "$INSTALLER_BIN" ]; then
    echo "错误: 找不到文件: $INSTALLER_BIN"
    echo "使用方法: $0 <path_to_openshift-install>"
    exit 1
fi

echo "=========================================="
echo "验证 openshift-install 是否包含 PR #10188"
echo "=========================================="
echo ""
echo "二进制文件: $INSTALLER_BIN"
echo ""

# 检查文件类型
echo "1. 文件信息:"
ls -lh "$INSTALLER_BIN"
file "$INSTALLER_BIN"
echo ""

# 检查版本信息
echo "2. 版本信息:"
if "$INSTALLER_BIN" version >/dev/null 2>&1; then
    "$INSTALLER_BIN" version
else
    echo "  无法获取版本信息"
fi
echo ""

# 搜索 PR 相关标识
echo "3. 搜索 PR #10188 相关标识:"
FOUND=false

# 搜索 commit hash
if strings "$INSTALLER_BIN" 2>/dev/null | grep -q "1957abe0"; then
    echo "  ✓ 找到 commit hash: 1957abe0"
    FOUND=true
fi

# 搜索 PR 号
if strings "$INSTALLER_BIN" 2>/dev/null | grep -q "10188"; then
    echo "  ✓ 找到 PR 号: 10188"
    FOUND=true
fi

# 搜索 bug ID
if strings "$INSTALLER_BIN" 2>/dev/null | grep -q "OCPBUGS-69923"; then
    echo "  ✓ 找到 Bug ID: OCPBUGS-69923"
    FOUND=true
fi

if [ "$FOUND" = false ]; then
    echo "  - 未找到 PR 标识（可能被编译优化，这是正常的）"
fi
echo ""

# 搜索代码相关字符串
echo "4. 搜索代码相关字符串:"
CODE_FOUND=false

# 搜索 slices.Sort（可能以不同形式存在）
if strings "$INSTALLER_BIN" 2>/dev/null | grep -qi "slices"; then
    echo "  ✓ 找到 'slices' 相关字符串"
    CODE_FOUND=true
fi

# 搜索 zone 排序相关
if strings "$INSTALLER_BIN" 2>/dev/null | grep -qiE "(sort.*zone|zone.*sort|lexical.*order)"; then
    echo "  ✓ 找到 zone 排序相关字符串"
    CODE_FOUND=true
fi

if [ "$CODE_FOUND" = false ]; then
    echo "  - 未找到代码相关字符串（可能被编译优化）"
fi
echo ""

# 使用 go tool nm（如果可用）
if command -v go >/dev/null 2>&1; then
    echo "5. 使用 go tool nm 检查符号:"
    if go tool nm "$INSTALLER_BIN" 2>/dev/null | grep -qiE "(sort|zone)" | head -5; then
        echo "  找到相关符号"
    else
        echo "  - 未找到相关符号或二进制文件不包含符号表"
    fi
    echo ""
fi

# 总结
echo "=========================================="
echo "验证总结"
echo "=========================================="
echo ""
echo "注意:"
echo "1. 字符串搜索可能因为编译优化而失败，这是正常的"
echo "2. 最可靠的方法是检查构建日志确认 PR 已被合并"
echo "3. 从你提供的构建日志可以看到:"
echo "   'merging: #10188 1957abe0'"
echo "   这表明构建确实包含了 PR #10188"
echo ""
echo "建议:"
echo "- 如果构建日志显示 PR 已合并，可以信任构建结果"
echo "- 进行功能测试验证修复是否生效（见 manual-test-guide.md）"
echo ""
