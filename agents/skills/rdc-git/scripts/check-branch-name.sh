#!/bin/sh
#
# check-branch-name.sh
# 验证分支名是否符合慧择 Git 规范
# 格式: [分支类型]-[银河版本号]-[分支备注]
#
# 用法:
#   ./check-branch-name.sh [branch-name]
#   如果不提供参数，则检查当前分支
#

# 获取分支名
if [ -n "$1" ]; then
    branch_name="$1"
else
    branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -z "$branch_name" ]; then
        echo "Error: 无法获取当前分支名，请确保在 Git 仓库中"
        exit 1
    fi
fi

# 跳过特殊分支
case "$branch_name" in
    master|main|develop|dev|release|release/*|hotfix/*|HEAD)
        echo "OK: 系统分支 '$branch_name' 无需检查"
        exit 0
        ;;
esac

# 分支类型
branch_types="feat|bug|experiment|wip"

# 正则表达式
# 格式: type-version 或 type-version_remark
pattern="^($branch_types)-[a-z0-9_.]+([-_][a-z0-9_.]+)*$"

# 检查是否全小写
lowercase_branch=$(echo "$branch_name" | tr '[:upper:]' '[:lower:]')
if [ "$branch_name" != "$lowercase_branch" ]; then
    echo ""
    echo "=================================================="
    echo "  分支名格式错误!"
    echo "=================================================="
    echo ""
    echo "错误: 分支名应全部小写"
    echo ""
    echo "当前分支: $branch_name"
    echo "建议修改: $lowercase_branch"
    echo ""
    exit 1
fi

# 检查格式
if ! echo "$branch_name" | grep -qE "$pattern"; then
    echo ""
    echo "=================================================="
    echo "  分支名格式错误!"
    echo "=================================================="
    echo ""
    echo "正确格式: [分支类型]-[银河版本号]-[分支备注]"
    echo ""
    echo "分支类型:"
    echo "  feat       - 功能分支 (一般迭代或者日常)"
    echo "  bug        - 修复分支 (修复 bug)"
    echo "  experiment - 实验性分支 (试验新技术等)"
    echo "  wip        - 临时分支 (不确定类型时使用)"
    echo ""
    echo "示例:"
    echo "  feat-bibd_at_v1.0.0"
    echo "  feat-bibd_at_v1.0.1_scx"
    echo "  bug-10564_scx"
    echo "  wip-merge_conflict"
    echo "  experiment-redis_cache"
    echo ""
    echo "当前分支: $branch_name"
    echo "=================================================="
    echo ""
    exit 1
fi

echo "OK: 分支名 '$branch_name' 符合规范"
exit 0
