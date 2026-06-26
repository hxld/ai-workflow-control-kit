param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

function Write-Json {
    param([string]$Path, $Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function New-ValidTaskProcessorFixture {
    param([string]$Root, [bool]$IncludeAssertions = $true)

    $replayRoot = Join-Path $Root 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    Write-Utf8 -Path (Join-Path $replayRoot 'TEST_CHARTER.md') -Value @'
# Test Charter

Test Class: ApplyTaskProcessorBehaviorTest uses RecordingAuditLogService collaborator while entering ApplyTaskProcessor.handleTaskResponse.
Entry Point: com.example.task.ApplyTaskProcessor.handleTaskResponse
Assertions: capture audit log state and output text.
'@

    Write-Utf8 -Path (Join-Path $replayRoot 'REPLAY_PLAN.md') -Value @'
# Replay Plan

Entry: ApplyTaskProcessor
Target: ApplyTaskProcessor
'@

    Write-Utf8 -Path (Join-Path $worktree 'app-core\src\main\java\com\example\task\ApplyTaskProcessor.java') -Value @'
package com.example.task;

public class ApplyTaskProcessor {
    public void handleTaskResponse(Object task, Object response) {}
}
'@

    $testPath = 'app-server/src/test/java/com/example/task/ApplyTaskProcessorBehaviorTest.java'
    Write-Utf8 -Path (Join-Path $worktree $testPath) -Value @'
package com.example.task;

import org.junit.Assert;
import org.junit.Test;

public class ApplyTaskProcessorBehaviorTest {
    static class RecordingAuditLogService extends AuditLogService {}

    @Test
    public void handleTaskResponseWritesAuditLog() {
        new ApplyTaskProcessor().handleTaskResponse(new Object(), new Object());
        Assert.assertEquals("DONE", "DONE");
    }
}
'@

    Write-Json -Path (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Value ([ordered]@{
        slice_status = 'DONE'
        matched_test_count = 1
        real_entry_invoked = $true
        green_exit_code = 0
        test_execution_exit_code = 0
        side_effect_assertions = if ($IncludeAssertions) { @('captured AuditLogService state through ApplyTaskProcessor.handleTaskResponse') } else { @() }
        behavior_test_charter = [ordered]@{
            proof_kind = 'real_entry_behavior'
            production_entry = 'com.example.task.ApplyTaskProcessor.handleTaskResponse'
            state_or_output = 'audit log state captured'
            evidence_files = @($testPath)
        }
    })
    Write-Json -Path (Join-Path $replayRoot 'SLICE_RESULT_SCHEMA_NORMALIZATION_01.json') -Value ([ordered]@{
        status = 'PASS'
        note = 'This artifact must not be treated as an executable slice result.'
    })

    return [pscustomobject]@{
        ReplayRoot = $replayRoot
        Worktree = $worktree
    }
}

function New-InvalidServiceFixture {
    param([string]$Root)

    $replayRoot = Join-Path $Root 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    Write-Utf8 -Path (Join-Path $replayRoot 'TEST_CHARTER.md') -Value @'
# Test Charter

Test Class: InternalWorkflowServiceTest targets InternalWorkflowService directly.
Entry Point: com.example.service.InternalWorkflowService.run
'@

    Write-Utf8 -Path (Join-Path $replayRoot 'REPLAY_PLAN.md') -Value @'
# Replay Plan

Entry: InternalWorkflowService
Target: InternalWorkflowService
'@

    Write-Utf8 -Path (Join-Path $worktree 'app-core\src\main\java\com\example\service\InternalWorkflowService.java') -Value @'
package com.example.service;

public class InternalWorkflowService {
    public void run() {}
}
'@

    return [pscustomobject]@{
        ReplayRoot = $replayRoot
        Worktree = $worktree
    }
}

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$precheckScript = Join-Path $scriptsRoot 'pre-flight-check.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v680-layer-' + [guid]::NewGuid().ToString('N'))

try {
    $cases = New-Object System.Collections.Generic.List[string]

    $valid = New-ValidTaskProcessorFixture -Root (Join-Path $tempRoot 'valid')
    & powershell -NoProfile -ExecutionPolicy Bypass -File $precheckScript -ReplayRoot $valid.ReplayRoot -Worktree $valid.Worktree *> (Join-Path $tempRoot 'valid.out.log')
    $validExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $cases.Add((Assert-True 'valid_taskprocessor_real_entry_layer_gate_exits_zero' ($validExit -eq 0))) | Out-Null
    $validResult = Read-Json -Path (Join-Path $valid.ReplayRoot 'LAYER_VALIDATION_RESULT.json')
    $cases.Add((Assert-True 'valid_taskprocessor_real_entry_layer_gate_passes' ([bool]$validResult.can_proceed -and [string]$validResult.validation_status -eq 'PASS'))) | Out-Null
    $validWarnings = @($validResult.warnings | ForEach-Object { [string]$_.code })
    $cases.Add((Assert-True 'valid_taskprocessor_real_entry_records_exception_warning' ($validWarnings -contains 'TASK_PROCESSOR_REAL_ENTRY_SLICE_EXCEPTION'))) | Out-Null
    $validIssues = @($validResult.issues | ForEach-Object { [string]$_.code })
    $cases.Add((Assert-True 'valid_taskprocessor_real_entry_has_no_wrong_surface_issue' (-not ($validIssues -contains 'WRONG_TEST_SURFACE_CHARTER') -and -not ($validIssues -contains 'WRONG_TEST_SURFACE_FILEPATH')))) | Out-Null

    $missingAssertions = New-ValidTaskProcessorFixture -Root (Join-Path $tempRoot 'missing-assertions') -IncludeAssertions $false
    & powershell -NoProfile -ExecutionPolicy Bypass -File $precheckScript -ReplayRoot $missingAssertions.ReplayRoot -Worktree $missingAssertions.Worktree *> (Join-Path $tempRoot 'missing-assertions.out.log')
    $missingAssertionsExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $cases.Add((Assert-True 'taskprocessor_without_assertions_does_not_bypass_layer_gate' ($missingAssertionsExit -ne 0))) | Out-Null
    $missingAssertionsResult = Read-Json -Path (Join-Path $missingAssertions.ReplayRoot 'LAYER_VALIDATION_RESULT.json')
    $missingAssertionsIssues = @($missingAssertionsResult.issues | ForEach-Object { [string]$_.code })
    $cases.Add((Assert-True 'taskprocessor_without_assertions_reports_wrong_surface' ($missingAssertionsIssues -contains 'WRONG_TEST_SURFACE_CHARTER' -or $missingAssertionsIssues -contains 'WRONG_TEST_SURFACE_FILEPATH'))) | Out-Null

    $invalid = New-InvalidServiceFixture -Root (Join-Path $tempRoot 'invalid')
    & powershell -NoProfile -ExecutionPolicy Bypass -File $precheckScript -ReplayRoot $invalid.ReplayRoot -Worktree $invalid.Worktree *> (Join-Path $tempRoot 'invalid.out.log')
    $invalidExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $cases.Add((Assert-True 'invalid_direct_service_layer_gate_exits_nonzero' ($invalidExit -ne 0))) | Out-Null
    $invalidResult = Read-Json -Path (Join-Path $invalid.ReplayRoot 'LAYER_VALIDATION_RESULT.json')
    $invalidIssues = @($invalidResult.issues | ForEach-Object { [string]$_.code })
    $cases.Add((Assert-True 'invalid_direct_service_still_fails_wrong_surface' ($invalidIssues -contains 'WRONG_TEST_SURFACE_CHARTER' -or $invalidIssues -contains 'WRONG_TEST_SURFACE_FILEPATH'))) | Out-Null

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($precheckScript, [ref]$tokens, [ref]$parseErrors) | Out-Null
    $cases.Add((Assert-True 'pre_flight_check_parses' (-not $parseErrors -or $parseErrors.Count -eq 0))) | Out-Null

    [ordered]@{
        status = 'PASS'
        test_name = 'v680_taskprocessor_layer_validation_real_entry'
        assertions = $cases.Count
        cases = @($cases)
    } | ConvertTo-Json -Depth 8
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
