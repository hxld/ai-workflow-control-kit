# ============================================
# check-branch-name.ps1
# 验证分支名是否符合慧择 Git 规范
# 格式: [分支类型]-[银河版本号]-[分支备注]
# ============================================
# 用法:
#   .\check-branch-name.ps1 [branch-name]
#   如果不提供参数，则检查当前分支
# ============================================

param(
    [string]$BranchName
)

# 获取分支名
if ($BranchName) {
    $branch = $BranchName
} else {
    try {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $branch) {
            Write-Host "Error: 无法获取当前分支名，请确保在 Git 仓库中" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "Error: 无法获取当前分支名，请确保在 Git 仓库中" -ForegroundColor Red
        exit 1
    }
}

# 跳过特殊分支
$systemBranches = @('master', 'main', 'develop', 'dev', 'release', 'HEAD')
if ($branch -in $systemBranches -or $branch -match '^release/' -or $branch -match '^hotfix/') {
    Write-Host "OK: 系统分支 '$branch' 无需检查" -ForegroundColor Green
    exit 0
}

# 分支类型
$branchTypes = "feat|bug|experiment|wip"

# 正则表达式
# 格式: type-version 或 type-version_remark
$pattern = "^($branchTypes)-[a-z0-9_.]+([-_][a-z0-9_.]+)*$"

# 检查是否全小写
$lowercaseBranch = $branch.ToLower()
if ($branch -cne $lowercaseBranch) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host "  分支名格式错误!" -ForegroundColor Red
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "错误: 分支名应全部小写" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "当前分支: $branch"
    Write-Host "建议修改: $lowercaseBranch"
    Write-Host ""
    exit 1
}

# 检查格式
if ($branch -notmatch $pattern) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host "  分支名格式错误!" -ForegroundColor Red
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "正确格式: [分支类型]-[银河版本号]-[分支备注]"
    Write-Host ""
    Write-Host "分支类型:"
    Write-Host "  feat       - 功能分支 (一般迭代或者日常)"
    Write-Host "  bug        - 修复分支 (修复 bug)"
    Write-Host "  experiment - 实验性分支 (试验新技术等)"
    Write-Host "  wip        - 临时分支 (不确定类型时使用)"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  feat-bibd_at_v1.0.0"
    Write-Host "  feat-bibd_at_v1.0.1_scx"
    Write-Host "  bug-10564_scx"
    Write-Host "  wip-merge_conflict"
    Write-Host "  experiment-redis_cache"
    Write-Host ""
    Write-Host "当前分支: $branch" -ForegroundColor Yellow
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "OK: 分支名 '$branch' 符合规范" -ForegroundColor Green
exit 0
