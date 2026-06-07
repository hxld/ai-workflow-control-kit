#
# install-hooks.ps1
# 一键安装 Git hooks 到当前仓库 (Windows PowerShell)
#
# 用法:
#   .\install-hooks.ps1
#   或: powershell -ExecutionPolicy Bypass -File install-hooks.ps1
#

$ErrorActionPreference = "Stop"

# 获取脚本所在目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 检查是否在 Git 仓库中
try {
    $null = git rev-parse --git-dir 2>&1
} catch {
    Write-Host "Error: 当前目录不是 Git 仓库" -ForegroundColor Red
    Write-Host "请在 Git 仓库根目录执行此脚本"
    exit 1
}

# 获取 .git/hooks 目录
$GitDir = git rev-parse --git-dir
$HooksDir = Join-Path $GitDir "hooks"

Write-Host "Installing Git hooks..."
Write-Host ""

# 创建 hooks 目录 (如果不存在)
if (-not (Test-Path $HooksDir)) {
    New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null
}

# 安装 commit-msg hook
$CommitMsgSource = Join-Path $ScriptDir "commit-msg"
$CommitMsgTarget = Join-Path $HooksDir "commit-msg"

if (Test-Path $CommitMsgSource) {
    Copy-Item $CommitMsgSource $CommitMsgTarget -Force
    Write-Host "[OK] commit-msg hook installed" -ForegroundColor Green
} else {
    Write-Host "[SKIP] commit-msg not found" -ForegroundColor Yellow
}

# 安装 pre-commit hook
$PreCommitSource = Join-Path $ScriptDir "pre-commit"
$PreCommitTarget = Join-Path $HooksDir "pre-commit"

if (Test-Path $PreCommitSource) {
    Copy-Item $PreCommitSource $PreCommitTarget -Force
    Write-Host "[OK] pre-commit hook installed" -ForegroundColor Green
} else {
    Write-Host "[SKIP] pre-commit not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Git hooks 安装完成!" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "已安装的 hooks:"
Write-Host "  - commit-msg: 验证 commit message 格式"
Write-Host "  - pre-commit: 检查敏感文件和大文件"
Write-Host ""
Write-Host "hooks 位置: $HooksDir"
Write-Host ""
Write-Host "注意: Git for Windows 自带 bash 环境，hooks 使用 bash 脚本"
Write-Host ""
