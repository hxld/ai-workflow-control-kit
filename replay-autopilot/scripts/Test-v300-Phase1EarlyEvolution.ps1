param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runnerPath = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

Assert-True ($runnerText.Contains('Phase 1 stopped replay early: $phase1Status')) `
    'Runner must have a Phase1 early-stop branch'
Assert-True ($runnerText.Contains('Knowledge version refreshed for next round after phase1 early-stop evolution')) `
    'Phase1 early-stop branch must refresh knowledge after evolution'
Assert-True ($runnerText.Contains("-Stage 'Evolution'")) `
    'Phase1 early-stop evolution failures must write an Evolution blocker'
Assert-True ($runnerText.Contains("'-PromptPath', $evolutionPrompt")) `
    'Phase1 early-stop branch must execute EVOLUTION_PROMPT.md'

$phase1BranchPattern = '(?s)if \(@\(''INVALID_PLAN'', ''INVALID_REPLAY''\) -contains \$phase1Status\).*?Write-Host "Phase 1 stopped replay early: \$phase1Status".*?if \(\$runEvolutionActual\).*?& powershell @evolutionArgs.*?continue.*?break'
Assert-True ([regex]::IsMatch($runnerText, $phase1BranchPattern)) `
    'Phase1 INVALID_* branch must run evolution and continue before final break'

[ordered]@{
    status = 'PASS'
    assertions = 5
    cases = @(
        'phase1_early_stop_branch_exists',
        'phase1_early_stop_refreshes_knowledge',
        'phase1_evolution_failure_writes_blocker',
        'phase1_branch_executes_evolution_prompt',
        'phase1_branch_continues_after_successful_evolution'
    )
} | ConvertTo-Json -Depth 5
