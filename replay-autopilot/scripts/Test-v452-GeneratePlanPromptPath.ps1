# v452: generate_plan prompt path invocation
# Ensures Run-ReplayLoop passes large plan prompts by file path, not command-line content.

param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$generatorPath = Join-Path $scriptRoot 'generate_plan.ps1'

$runnerContent = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$generatorContent = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8

$cases = New-Object System.Collections.Generic.List[string]

$cases.Add((Assert-True -Name 'runner_uses_plan_prompt_path' -Condition (
    $runnerContent -match '-PlanPromptPath\s+\$planPrompt'
))) | Out-Null

$cases.Add((Assert-True -Name 'runner_does_not_pass_plan_prompt_content' -Condition (
    $runnerContent -notmatch '-PlanPrompt\s+\$planPromptContent'
))) | Out-Null

$cases.Add((Assert-True -Name 'generator_accepts_plan_prompt_path' -Condition (
    $generatorContent -match '\[string\]\$PlanPromptPath'
))) | Out-Null

$cases.Add((Assert-True -Name 'generator_reads_prompt_path' -Condition (
    $generatorContent -match 'Get-Content\s+-LiteralPath\s+\$PlanPromptPath\s+-Raw\s+-Encoding\s+UTF8'
))) | Out-Null

$tempRoot = Join-Path $env:TEMP ("v452-generate-plan-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $promptPath = Join-Path $tempRoot 'PLAN_PROMPT.md'
    $longPrompt = ('x' * 70000)
    Set-Content -LiteralPath $promptPath -Value $longPrompt -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $generatorPath -ReplayRoot $tempRoot -PlanPromptPath $promptPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "generate_plan exited with $LASTEXITCODE"
    }

    $augmentedPath = Join-Path $tempRoot 'PLAN_PROMPT_WITH_CONTRACT.md'
    $resultPath = Join-Path $tempRoot 'PLAN_CONTRACT_GENERATION.json'
    $cases.Add((Assert-True -Name 'long_prompt_augmented' -Condition (Test-Path -LiteralPath $augmentedPath))) | Out-Null
    $cases.Add((Assert-True -Name 'generation_result_written' -Condition (Test-Path -LiteralPath $resultPath))) | Out-Null
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 6
