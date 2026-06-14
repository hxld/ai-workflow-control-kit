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
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-TestModuleFixture {
    param([string]$Worktree)
    New-Item -ItemType Directory -Force -Path (Join-Path $Worktree 'sample-module\src\test\java\sample') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $Worktree 'pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $Worktree 'sample-module\pom.xml') -Encoding UTF8
    'class SampleBehaviorTest {}' | Set-Content -LiteralPath (Join-Path $Worktree 'sample-module\src\test\java\sample\SampleBehaviorTest.java') -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-compile-evidence-contract-sync-v507-" + [guid]::NewGuid().ToString('N'))

try {
    $runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
    Assert-True 'runner_has_compile_evidence_contract_sync_function' ($runLoopText.Contains('function Sync-PlanTestCompileEvidenceContract'))
    Assert-True 'runner_syncs_existing_evidence_before_success_return' ($runLoopText.Contains('Sync-PlanTestCompileEvidenceContract -Plan $plan -Infra $infra -PlanResultJsonPath $PlanResultJsonPath -EvidencePath $evidencePath') -and $runLoopText.Contains('Test-TestCompileEvidenceHasSuccessSignal -Path $evidencePath'))

    $functionBlock = [regex]::Match(
        $runLoopText,
        '(?s)function Resolve-ReplayEvidencePath.+?(?=function Repair-Phase0ManualOracleWaitText)'
    ).Value
    Assert-True 'runner_plan_evidence_functions_extractable' (-not [string]::IsNullOrWhiteSpace($functionBlock))
    Invoke-Expression $functionBlock

    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    New-TestModuleFixture -Worktree $worktree

    $planPath = Join-Path $replayRoot 'PLAN_RESULT.json'
    Write-Json (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl sample-module -am test-compile'
        module = 'sample-module'
        exit_code = 0
        timed_out = $false
        stdout_tail = 'BUILD SUCCESS'
        stderr_tail = ''
    })
    Write-Json $planPath ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'sample-module/src/main/java/sample/SampleCarrier.java'
        target_carrier_line_number = 12
        expected_test_class = 'sample-module/src/test/java/sample/SampleBehaviorTest.java'
        expected_test_method = 'testSampleBehavior'
        side_effects = @(
            [ordered]@{
                side_effect = 'output state changes'
                state = 'sample.result'
                proof = 'assert result state'
            }
        )
        expected_assertions = @('assert result state')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'sample-module'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl sample-module -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $replayRoot -PlanResultPath $planPath -Worktree $worktree | Out-Null
    Assert-True 'schema_fails_before_runner_sync_when_exit_code_missing' ($LASTEXITCODE -ne 0)
    $beforeSchema = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_missing_compile_exit_code_before_sync' ((@($beforeSchema.checks.test_infrastructure_issues) -join ' ') -match 'compilation_dry_run_exit_code missing')

    Ensure-PlanTestCompileEvidence -ReplayRoot $replayRoot -Worktree $worktree -PlanResultJsonPath $planPath
    $syncedPlan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'runner_syncs_compile_exit_code_from_existing_evidence' ([int]$syncedPlan.test_infrastructure_check.compilation_dry_run_exit_code -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $replayRoot -PlanResultPath $planPath -Worktree $worktree | Out-Null
    Assert-True 'schema_passes_after_runner_syncs_compile_exit_code' ($LASTEXITCODE -eq 0)

    Write-Host 'PASS: v507 plan compile evidence contract sync'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
