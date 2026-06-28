<#
.SYNOPSIS
Regression test for Codex-primary external-practice model policy.
#>

param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$scriptPath = Join-Path $repoRoot 'scripts\Start-ExternalPracticeSearch.ps1'
$text = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

Assert-True `
    ($text -match 'function\s+Resolve-ExternalPracticeDefaultModel') `
    'external practice search must use an executor-aware default model resolver'

Assert-True `
    ($text -match "if\s*\(\s*\`$Executor\s+-eq\s+'codex'\s*\)[\s\S]{0,180}codex_model") `
    'Codex primary external-practice agent must default to codex_model'

Assert-True `
    ($text -match "if\s*\(\s*\`$Executor\s+-eq\s+'claude'\s*\)[\s\S]{0,220}claude_deep_review_model") `
    'Claude external-practice agent may keep the Claude deep-review model fallback'

$primaryBlockMatch = [regex]::Match($text, "(?s)if \(\`$RunAgent\) \{(?<block>.*?)\`$primaryAttempt = Invoke-ExternalPracticeAgentAttempt")
Assert-True $primaryBlockMatch.Success 'test must locate primary external-practice agent block'
$primaryBlock = $primaryBlockMatch.Groups['block'].Value

Assert-True `
    ($primaryBlock -match 'Resolve-ExternalPracticeDefaultModel\s+-Config\s+\$config\s+-Executor\s+\$executor') `
    'primary external-practice model default must be selected from the primary executor'

Assert-True `
    (-not ($primaryBlock -match "claude_deep_review_model")) `
    'primary external-practice Codex path must not directly inherit claude_deep_review_model'

Assert-True `
    ($text -match 'function\s+Resolve-ExternalPracticeDefaultReasoningEffort') `
    'external practice search must use an executor-aware default reasoning resolver'

Assert-True `
    ($primaryBlock -match 'Resolve-ExternalPracticeDefaultReasoningEffort\s+-Config\s+\$config\s+-Executor\s+\$executor') `
    'primary external-practice reasoning effort must be selected from the primary executor'

Write-Host 'v642 Codex external-practice model policy test passed.'
