$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$testScript = Join-Path $scriptDir "test-convert.js"

if (-not (Test-Path $testScript)) {
    throw "未找到回归测试脚本: $testScript"
}

Write-Host "运行 yuque-to-markdown 回归测试..." -ForegroundColor Cyan
node $testScript

if ($LASTEXITCODE -ne 0) {
    throw "yuque-to-markdown 回归测试失败"
}

Write-Host "yuque-to-markdown 回归测试通过" -ForegroundColor Green
