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

    $replayRoot2 = Join-Path $tempRoot 'replay-existing-rules'
    New-Item -ItemType Directory -Force -Path $replayRoot2 | Out-Null
    Set-Content -LiteralPath (Join-Path $replayRoot2 'BLOCKER_FINGERPRINTS.json') -Encoding UTF8 -Value (@{
        fingerprints = @('wrong_test_surface')
    } | ConvertTo-Json -Depth 6)
    [ordered]@{
        schema = 'replay_verifiable_rule_pack.v1'
        generated_at = '2026-01-01T00:00:00'
        replay_root = $replayRoot2
        source_audit_pack = (Join-Path $replayRoot2 'PLAN_CONTRACT_VERIFY.json')
        rules = @(
            [ordered]@{
                id = 'rule_plan_oracle_overlap_enforced'
                fingerprint = 'oracle_overlap_below_threshold'
                severity = 'P0'
                machine_gate = 'plan_oracle_overlap_enforced'
                regression_test = 'scripts\Test-v600-OracleOverlapEvolutionProposalDetection.ps1'
                next_validation = 'scripts\Validate-VerifiableRuleClosure.ps1'
                verification_status = 'PENDING'
                acceptance = @('machine gate referenced')
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot2 'VERIFIABLE_RULES.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $replayRoot2 'VERIFIABLE_RULES.md') -Encoding UTF8 -Value '# Existing rules'

    Set-Content -LiteralPath $controlSummaryPath -Encoding UTF8 -Value ([ordered]@{
        latest = [ordered]@{
            replay_root = $replayRoot2
            feature = 'fixture'
            verification_capped_coverage = 0
            oracle_adjusted_coverage = 0
            fingerprints = @('wrong_test_surface')
        }
        control_decision = [ordered]@{
            repeated_blockers = @('wrong_test_surface')
        }
    } | ConvertTo-Json -Depth 8)

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $replayRoot2 `
        -ControlSummaryPath $controlSummaryPath `
        -BlockerRegistryPath $registryPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Write-FailureAuditPack existing-rule scenario exited with $LASTEXITCODE"
    }

    $audit2 = Get-Content -LiteralPath (Join-Path $replayRoot2 'FAILURE_AUDIT_PACK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $rules2 = Get-Content -LiteralPath (Join-Path $replayRoot2 'VERIFIABLE_RULES.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $latestRules2 = Get-Content -LiteralPath $latestRulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$audit2.preserved_existing_verifiable_rules) 'Failure audit should mark existing rules as preserved.'
    Assert-True ($audit2.verifiable_rule_count -eq 1) 'Preserved rule count mismatch.'
    Assert-True ($rules2.rules[0].machine_gate -eq 'plan_oracle_overlap_enforced') 'Existing rule pack was overwritten.'
    Assert-True ($latestRules2.rules[0].machine_gate -eq 'plan_oracle_overlap_enforced') 'Latest copied rules should preserve existing rule pack.'

    Write-Host 'Test-v596-FailureAuditVerifiableRules PASS'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
