param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-EvolutionFixture {
    param(
        [string]$Root,
        [string]$StopFieldLine
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Utf8 (Join-Path $Root 'STOP_OR_CONTINUE_DECISION.md') @'
# Stop Decision

- decision: STOP_AND_EVOLVE
- reason: repeated machine gate drift
'@
    Write-Utf8 (Join-Path $Root 'EVOLUTION_RESULT.md') @"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
$StopFieldLine
- gate_budget_decision: existing_gate_enforcement
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Validate-EvolutionResult.ps1; replay-autopilot/prompts/skill-evolution.prompt.md
- closed_machine_gates: stop_and_evolve_result_contract
- pushed_commit: 0123456789abcdef
- actual_knowledge_version_after_push: v633
"@
}

function Invoke-EvolutionValidator {
    param([string]$ReplayRoot)
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\Validate-EvolutionResult.ps1') -ReplayRoot $ReplayRoot 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String)
    }
}

$scriptRoot = Split-Path -Parent $PSScriptRoot
$autopilotRoot = Split-Path -Parent $scriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v633-evolution-field-contract-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $assertionCount = 0

    Write-Host '[Scenario 1] ValidateOnly exposes the correct field name...'
    $validateOnly = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-EvolutionResult.ps1') -ReplayRoot $tempRoot -ValidateOnly 2>&1 | Out-String
    $validateOnlyCompact = $validateOnly -replace '\s+', ''
    Assert-True ($validateOnlyCompact -match 'stop_and_evolve_satisfied') 'ValidateOnly output must list stop_and_evolve_satisfied'
    Assert-False ($validateOnlyCompact -match 'stop_and_veolve_satisfied') 'ValidateOnly output must not list the misspelled stop_and_veolve_satisfied'
    $assertionCount += 2

    Write-Host '[Scenario 2] Correct EVOLUTION_RESULT field passes...'
    $validRoot = Join-Path $tempRoot 'valid'
    New-EvolutionFixture -Root $validRoot -StopFieldLine '- stop_and_evolve_satisfied: true'
    $valid = Invoke-EvolutionValidator -ReplayRoot $validRoot
    Assert-True ($valid.ExitCode -eq 0) "validator must pass with correct stop_and_evolve_satisfied field. Output: $($valid.Output)"
    $validJson = Get-Content -LiteralPath (Join-Path $validRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($validJson.status -eq 'PASS') 'valid fixture must write PASS verification status'
    $assertionCount += 2

    Write-Host '[Scenario 3] Misspelled EVOLUTION_RESULT field fails closed...'
    $invalidRoot = Join-Path $tempRoot 'invalid'
    New-EvolutionFixture -Root $invalidRoot -StopFieldLine '- stop_and_veolve_satisfied: true'
    $invalid = Invoke-EvolutionValidator -ReplayRoot $invalidRoot
    Assert-True ($invalid.ExitCode -ne 0) 'validator must fail when only misspelled stop_and_veolve_satisfied is present'
    $invalidJson = Get-Content -LiteralPath (Join-Path $invalidRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($invalidJson.issues) -contains 'stop_and_evolve_satisfied_missing_or_false') 'invalid fixture must report the canonical missing-field issue'
    Assert-True ($invalid.Output -match 'stop_and_evolve_satisfied') 'failure guidance must show the correct field name'
    Assert-False ($invalid.Output -match 'stop_and_veolve_satisfied') 'failure guidance must not show the misspelled field name'
    $assertionCount += 4

    Write-Host '[Scenario 4] Prompts preserve generic machine-field contracts...'
    $skillPrompt = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\skill-evolution.prompt.md') -Raw -Encoding UTF8
    $phase0Prompt = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase0-contract-gate.prompt.md') -Raw -Encoding UTF8
    Assert-True ($skillPrompt -match 'stop_and_evolve_satisfied') 'skill-evolution prompt must require the correct stop_and_evolve_satisfied field'
    Assert-False ($skillPrompt -match 'stop_and_veolve_satisfied') 'skill-evolution prompt must not contain the misspelled field'
    Assert-True ($phase0Prompt -match '- selected_real_entry: <baseline-existing\.package\.ClassName\.methodName>') 'Phase0 prompt must require a parseable selected_real_entry machine line'
    Assert-True ($phase0Prompt -match 'ClassName\.methodName') 'Phase0 prompt must describe class.method selected entry format'
    $pollutionPattern = '(?i)(com\.huize|claim-core|claim-server|claim-web|claim-api|claim-domain|claim-provider|AiApplyClaimApiTaskProcessor|AiCalculateLossApiTaskProcessor)'
    Assert-False ($phase0Prompt -match $pollutionPattern) 'Phase0 prompt must not contain project-specific claim examples'
    $assertionCount += 5

    Write-Host ''
    Write-Host "=== v633 EVOLUTION RESULT FIELD CONTRACT: ALL $assertionCount ASSERTIONS PASS ===" -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
