param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Json {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$constraintGate = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
$promptPath = Join-Path $autopilotRoot 'prompts\phase-plan-tournament.prompt.md'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v687-control-plane-harness-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    $carrierPath = Join-Path $worktree 'replay-autopilot\scripts\Invoke-SliceSchemaFailFast.ps1'
    $testDir = Join-Path $worktree 'replay-autopilot\scripts\tests'
    $testPath = Join-Path $testDir 'Test-v655-StopAndEvolveExperimentArtifacts.ps1'

    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $carrierPath) | Out-Null
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    'param(); Write-Host "PASS: control-plane regression"; exit 0' | Set-Content -LiteralPath $testPath -Encoding UTF8
    'function Invoke-SliceSchemaFailFast { }' | Set-Content -LiteralPath $carrierPath -Encoding UTF8

    $command = "powershell -NoProfile -ExecutionPolicy Bypass -File $testPath"
    Write-Json (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = $command
        exit_code = 0
        stdout_tail = 'PASS: control-plane regression'
    })
    Write-Json (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'replay-autopilot/scripts/Invoke-SliceSchemaFailFast.ps1'
        target_carrier_line_number = 41
        expected_test_class = 'Test-v655-StopAndEvolveExperimentArtifacts'
        expected_test_method = 'validates_machine_contract_fields_and_artifact_side_effects'
        side_effects = @(
            [ordered]@{
                type = 'control_plane_artifact'
                description = 'writes schema/evolution verification JSON artifacts'
            }
        )
        expected_assertions = @('assert schema fail-fast artifact', 'assert evolution result verification artifact', 'assert malformed machine fields fail closed')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'replay-autopilot/scripts/tests'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = $command
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    @'
# Test Charter

## RED Phase

### Test Class: Test-v655-StopAndEvolveExperimentArtifacts

Scenario: replay-autopilot control-plane schema artifacts fail closed.
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Encoding UTF8
    @'
# First Slice Proof Plan

highest_weight_open_gate: exact_contract_gap
selected_carrier: replay-autopilot/scripts/Invoke-SliceSchemaFailFast.ps1
target_carrier_file_path: replay-autopilot/scripts/Invoke-SliceSchemaFailFast.ps1
target_carrier_line_number: 41
expected_test_class: Test-v655-StopAndEvolveExperimentArtifacts
expected_test_method: validates_machine_contract_fields_and_artifact_side_effects
expected_assertions: ["assert schema fail-fast artifact", "assert evolution result verification artifact", "assert malformed machine fields fail closed"]
expected_side_effects: [{"type":"control_plane_artifact","description":"writes schema/evolution verification JSON artifacts"}]
minimum_side_effect_or_blocker: schema/evolution verification JSON artifacts are written and asserted
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $replayRoot -PlanResultPath (Join-Path $replayRoot 'PLAN_RESULT.json') -Worktree $worktree | Out-Null
    Assert-True 'plan_schema_accepts_control_plane_powershell_harness' ($LASTEXITCODE -eq 0)
    $schema = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'plan_schema_reports_test_infrastructure_valid' ([bool]$schema.checks.test_infrastructure_check_valid)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $constraintGate -ReplayRoot $replayRoot -Worktree $worktree -PlanResultPath (Join-Path $replayRoot 'PLAN_RESULT.json') -BaselineRoot $worktree | Out-Null
    Assert-True 'pre_execution_accepts_control_plane_powershell_harness' ($LASTEXITCODE -eq 0)
    $constraints = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'pre_execution_reports_test_infrastructure_pass' ([string]($constraints.checks | Where-Object { $_.name -eq 'test_infrastructure_check' }).status -eq 'PASS')

    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    Assert-True 'plan_prompt_documents_control_plane_harness_exception' ($promptText -match 'Replay-autopilot control-plane' -and $promptText -match 'replay-autopilot/scripts/tests' -and $promptText -match 'Test-v\*\.ps1')

    Write-Host ''
    Write-Host 'v687 Control Plane PowerShell Harness: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
