param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-PreExecutionCheck {
    param([string]$ReplayRoot, [string]$Worktree, [string]$PlanPath)

    $constraintScript = Join-Path $script:ScriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$constraintScript`" -ReplayRoot `"$ReplayRoot`" -Worktree `"$Worktree`" -PlanResultPath `"$PlanPath`" -BaselineRoot `"$Worktree`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    $resultPath = Join-Path $ReplayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json'
    $json = if (Test-Path -LiteralPath $resultPath) {
        Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $null
    }
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $stdout; Stderr = $stderr; Result = $json }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v608-pre-execution-surface-" + [guid]::NewGuid().ToString('N'))
$script:ScriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$repoRoot = Split-Path -Parent $script:ScriptRoot

try {
    $runnerText = Get-Content -LiteralPath (Join-Path $script:ScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    $planPromptText = Get-Content -LiteralPath (Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8
    foreach ($field in @('test_surface:', 'entry_point:', 'test_class:', 'test_method:')) {
        Assert-True "runner_requires_$field" ($runnerText.Contains($field)) 'Run-ReplayLoop plan artifact repair prompt must require machine TEST_CHARTER fields'
        Assert-True "plan_prompt_requires_$field" ($planPromptText.Contains($field)) 'Plan tournament prompt must require machine TEST_CHARTER fields'
    }

    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    $carrierRel = 'sample-core/src/main/java/com/example/SampleTaskProcessor.java'
    $carrierPath = Join-Path $worktree $carrierRel

    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Write-Utf8 $carrierPath @'
package com.example;

public class SampleTaskProcessor {
    public void handleTaskResponse() {
    }
}
'@
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'sample-module\pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'sample-module\src\test\java\com\example\SampleTaskProcessorTest.java') 'class SampleTaskProcessorTest {}'

    $dryRunCommand = ('mvn -f ' + $worktree + '\pom.xml -pl sample-module -am test-compile')
    Write-JsonFile (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        exit_code = 0
        command = $dryRunCommand
        stdout = 'BUILD SUCCESS'
    })
    Write-JsonFile (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = $carrierRel
        target_carrier_line_number = 4
        expected_test_class = 'SampleTaskProcessorTest'
        expected_test_method = 'testHandleTaskResponse_WhenInputValid'
        side_effects = @('STATE_CAPTURE: sample result is forwarded')
        expected_assertions = @(
            'assertEquals expected status',
            'verify downstream side effect',
            'assert no exception'
        )
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'sample-module'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = $dryRunCommand
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
# First Slice Proof Plan

highest_weight_open_gate: core_entry
selected_real_entry: com.example.SampleTaskProcessor.handleTaskResponse()
selected_carrier: com.example.SampleTaskProcessor.handleTaskResponse()
target_carrier_file_path: sample-core/src/main/java/com/example/SampleTaskProcessor.java
target_carrier_line_number: 4
expected_test_class: SampleTaskProcessorTest
expected_test_method: testHandleTaskResponse_WhenInputValid
expected_assertions: ["assertEquals expected status","verify downstream side effect","assert no exception"]
expected_side_effects: [{"state":"sample result","operation":"STATE_CAPTURE","proof":"verify downstream side effect"}]
minimum_side_effect_or_blocker: sample result is forwarded to downstream state
'@
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') @'
# Test Charter

## Source of Truth
- **Selected Real Entry**: `SampleTaskProcessor.handleTaskResponse()`
- **First Slice**: S1_core_entry
- **Test Surface**: `SampleTaskProcessorTest` (sample-module, no-Spring JUnit + Mockito)

## RED Phase

### RED Test: sample result is forwarded

Test: testHandleTaskResponse_WhenInputValid
Class: SampleTaskProcessorTest

## GREEN Phase

GREEN Assertions:
- verify downstream side effect is called
'@

    $passRun = Invoke-PreExecutionCheck -ReplayRoot $replayRoot -Worktree $worktree -PlanPath (Join-Path $replayRoot 'PLAN_RESULT.json')
    $passCheck = @($passRun.Result.checks | Where-Object { [string]$_.name -eq 'test_charter_valid' }) | Select-Object -First 1

    Assert-True 'markdown_test_surface_label_exits_zero' ($passRun.ExitCode -eq 0) "exit=$($passRun.ExitCode) stderr=$($passRun.Stderr)"
    Assert-True 'markdown_test_surface_label_accepted' ([bool]$passCheck.has_test_surface) ($passCheck | ConvertTo-Json -Depth 5)
    Assert-True 'surface_detection_names_test_surface' ([string]$passCheck.surface_detection -eq 'test_surface_label') ($passCheck | ConvertTo-Json -Depth 5)
    Assert-True 'pre_execution_passes_with_markdown_test_surface' ([string]$passRun.Result.status -eq 'PASS') ($passRun.Result | ConvertTo-Json -Depth 12)

    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') @'
# Test Charter

This document mentions RED and GREEN, but does not bind an executable test surface.
'@

    $failRun = Invoke-PreExecutionCheck -ReplayRoot $replayRoot -Worktree $worktree -PlanPath (Join-Path $replayRoot 'PLAN_RESULT.json')
    $failCheck = @($failRun.Result.checks | Where-Object { [string]$_.name -eq 'test_charter_valid' }) | Select-Object -First 1

    Assert-True 'missing_surface_exits_nonzero' ($failRun.ExitCode -ne 0) "exit=$($failRun.ExitCode)"
    Assert-True 'missing_surface_still_fails' ([string]$failCheck.status -eq 'FAIL') ($failCheck | ConvertTo-Json -Depth 5)
    Assert-True 'missing_surface_not_overaccepted' (-not [bool]$failCheck.has_test_surface) ($failCheck | ConvertTo-Json -Depth 5)

    [ordered]@{
        status = 'PASS'
        version = 'v608'
        assertions = @(
            'markdown_test_surface_label_exits_zero',
            'markdown_test_surface_label_accepted',
            'surface_detection_names_test_surface',
            'pre_execution_passes_with_markdown_test_surface',
            'missing_surface_exits_nonzero',
            'missing_surface_still_fails',
            'missing_surface_not_overaccepted',
            'runner_and_plan_prompt_require_machine_test_charter_fields'
        )
    } | ConvertTo-Json -Depth 5
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
