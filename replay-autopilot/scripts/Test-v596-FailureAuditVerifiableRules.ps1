param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = Join-Path $scriptRoot 'Write-FailureAuditPack.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-rules-' + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$controlDir = Join-Path $evidenceRoot '_control'
$replayRoot = Join-Path $tempRoot 'replay'

New-Item -ItemType Directory -Force -Path $controlDir, $replayRoot | Out-Null

Set-Content -LiteralPath (Join-Path $replayRoot 'BLOCKER_FINGERPRINTS.json') -Encoding UTF8 -Value (@{
    fingerprints = @('wrong_test_surface')
} | ConvertTo-Json -Depth 6)

$controlSummaryPath = Join-Path $controlDir 'RUN_CONTROL_LATEST.json'
Set-Content -LiteralPath $controlSummaryPath -Encoding UTF8 -Value ([ordered]@{
    latest = [ordered]@{
        replay_root = $replayRoot
        feature = 'fixture'
        verification_capped_coverage = 0
        oracle_adjusted_coverage = 0
        fingerprints = @('wrong_test_surface')
    }
    control_decision = [ordered]@{
        repeated_blockers = @('wrong_test_surface')
    }
} | ConvertTo-Json -Depth 8)

$registryPath = Join-Path $controlDir 'BLOCKER_REGISTRY.json'
Set-Content -LiteralPath $registryPath -Encoding UTF8 -Value ([ordered]@{
    blockers = [ordered]@{
        wrong_test_surface = [ordered]@{
            count = 3
        }
    }
} | ConvertTo-Json -Depth 8)

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $replayRoot `
        -ControlSummaryPath $controlSummaryPath `
        -BlockerRegistryPath $registryPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Write-FailureAuditPack exited with $LASTEXITCODE"
    }

    $auditPath = Join-Path $replayRoot 'FAILURE_AUDIT_PACK.json'
    $rulesPath = Join-Path $replayRoot 'VERIFIABLE_RULES.json'
    $rulesMdPath = Join-Path $replayRoot 'VERIFIABLE_RULES.md'
    $latestRulesPath = Join-Path $controlDir 'VERIFIABLE_RULES_LATEST.json'

    Assert-True (Test-Path -LiteralPath $auditPath -PathType Leaf) 'Failure audit JSON was not written.'
    Assert-True (Test-Path -LiteralPath $rulesPath -PathType Leaf) 'Verifiable rules JSON was not written.'
    Assert-True (Test-Path -LiteralPath $rulesMdPath -PathType Leaf) 'Verifiable rules MD was not written.'
    Assert-True (Test-Path -LiteralPath $latestRulesPath -PathType Leaf) 'Latest verifiable rules JSON was not copied.'

    $audit = Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rules = Get-Content -LiteralPath $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True ($audit.verifiable_rules_path -eq $rulesPath) 'Audit did not reference verifiable rules path.'
    Assert-True ($audit.verifiable_rule_count -eq 1) 'Audit verifiable rule count mismatch.'
    Assert-True ($rules.schema -eq 'replay_verifiable_rule_pack.v1') 'Rule pack schema mismatch.'
    Assert-True ($rules.rules.Count -eq 1) 'Rule pack should contain exactly one rule.'
    Assert-True ($rules.rules[0].fingerprint -eq 'wrong_test_surface') 'Rule fingerprint mismatch.'
    Assert-True ($rules.rules[0].machine_gate -eq 'real_entry_test_surface_required') 'Rule machine gate mismatch.'
    Assert-True ($rules.rules[0].verification_status -eq 'PENDING') 'Rule verification status mismatch.'
    Assert-True ($rules.rules[0].acceptance.Count -ge 3) 'Rule acceptance criteria missing.'

    Write-Host 'Test-v596-FailureAuditVerifiableRules PASS'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
