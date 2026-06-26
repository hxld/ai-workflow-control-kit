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

function New-SliceVerifierFixture {
    param([string]$Root, [bool]$WithSideEffectVerificationPass)

    $replayRoot = Join-Path $Root 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    $testPath = 'app-server/src/test/java/com/example/task/ApplyTaskProcessorBehaviorTest.java'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    Write-Utf8 -Path (Join-Path $worktree 'app-core\src\main\java\com\example\task\ApplyTaskProcessor.java') -Value @'
package com.example.task;

public class ApplyTaskProcessor {
    public void handleTaskResponse(Object task, Object response) {}
}
'@
    Write-Utf8 -Path (Join-Path $worktree $testPath) -Value @'
package com.example.task;

import org.junit.Assert;
import org.junit.Test;

public class ApplyTaskProcessorBehaviorTest {
    @Test
    public void handleTaskResponseWritesAuditLog() {
        new ApplyTaskProcessor().handleTaskResponse(new Object(), new Object());
        Assert.assertEquals("DONE", "DONE");
    }
}
'@

    & git -C $worktree init --quiet
    & git -C $worktree config user.email 'replay@example.test'
    & git -C $worktree config user.name 'Replay Test'
    & git -C $worktree add .
    & git -C $worktree commit --quiet -m 'baseline'
    Write-Utf8 -Path (Join-Path $worktree 'app-core\src\main\java\com\example\task\ApplyTaskProcessor.java') -Value @'
package com.example.task;

public class ApplyTaskProcessor {
    public void handleTaskResponse(Object task, Object response) {
        String auditLog = "DONE";
    }
}
'@

    $slice = [ordered]@{
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        coverage_delta = 10
        current_slice_changed_files = @('app-core/src/main/java/com/example/task/ApplyTaskProcessor.java', $testPath)
        implemented_files = @('app-core/src/main/java/com/example/task/ApplyTaskProcessor.java', $testPath)
        target_subsurface_or_carrier = 'com.example.task.ApplyTaskProcessor.handleTaskResponse'
        production_boundary = 'app-core/src/main/java/com/example/task/ApplyTaskProcessor.java'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        gap_flags = @('side_effect_ledger_gap', 'tooling_enforcement_stop', 'family_sibling_gap')
        tests = @(
            [ordered]@{
                phase = 'RED'
                result = 'fail'
                command = 'mvn -s settings.xml -f worktree/pom.xml -pl app-server -am -Dfile.encoding=UTF-8 -Dtest=ApplyTaskProcessorBehaviorTest#handleTaskResponseWritesAuditLog test'
                evidence = 'business assertion failed before production side effect'
            },
            [ordered]@{
                phase = 'GREEN'
                result = 'pass'
                command = 'mvn -s settings.xml -f worktree/pom.xml -pl app-server -am -Dfile.encoding=UTF-8 -Dtest=ApplyTaskProcessorBehaviorTest#handleTaskResponseWritesAuditLog test'
                evidence = 'Tests run: 1, Failures: 0'
            }
        )
        matched_test_count = 1
        real_entry_invoked = $true
        green_exit_code = 0
        test_execution_exit_code = 0
        test_compilation_exit_code = 0
        side_effect_assertions = @('captured AuditLogService output through real ApplyTaskProcessor entry')
        behavior_test_charter = [ordered]@{
            proof_kind = 'real_entry_behavior'
            production_entry = 'com.example.task.ApplyTaskProcessor.handleTaskResponse'
            state_or_output = 'audit log state captured'
            must_not = 'Do not use helper-only, static-only, DTO-only, terminal-payload-only, mock-only, subclass-only, or assertion-free proof.'
            RED_command = 'mvn -s settings.xml -f worktree/pom.xml -pl app-server -am -Dfile.encoding=UTF-8 -Dtest=ApplyTaskProcessorBehaviorTest#handleTaskResponseWritesAuditLog test'
            expected_RED_failure = 'audit log assertion fails before production side effect'
            GREEN_command = 'mvn -s settings.xml -f worktree/pom.xml -pl app-server -am -Dfile.encoding=UTF-8 -Dtest=ApplyTaskProcessorBehaviorTest#handleTaskResponseWritesAuditLog test'
            evidence_files = @($testPath)
        }
        side_effect_evidence = [ordered]@{
            status = 'PENDING'
            test_name = $testPath
            entry_call = ''
            expected_writes_or_outputs = @()
        }
    }
    $slicePath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    Write-Json -Path $slicePath -Value $slice
    Write-Json -Path (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Value ([ordered]@{
        authorization = 'ALLOW'
        selected_carrier = 'com.example.task.ApplyTaskProcessor.handleTaskResponse'
        real_entry = 'com.example.task.ApplyTaskProcessor.handleTaskResponse'
        downstream_side_effect_or_output = 'audit log state captured'
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        requires_side_effect_evidence = $true
        issues = @()
    })
    Write-Json -Path (Join-Path $replayRoot 'CARRIER_LOCK.json') -Value ([ordered]@{
        status = 'LOCKED'
        qualified_entry = 'com.example.task.ApplyTaskProcessor.handleTaskResponse'
        expected_production_files = @('app-core/src/main/java/com/example/task/ApplyTaskProcessor.java')
    })

    if ($WithSideEffectVerificationPass) {
        Write-Json -Path (Join-Path $replayRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json') -Value ([ordered]@{
            gate = 'side_effect_ledger_complete'
            can_proceed = $true
            validation_status = 'PASS'
            has_side_effects = $true
            has_verification = $true
            reason = 'executable_side_effect_evidence_verified'
            verification_source = 'SLICE_RESULT_and_test_source'
            evidence_files = @((Join-Path $worktree $testPath))
        })
    }

    return [pscustomobject]@{
        ReplayRoot = $replayRoot
        Worktree = $worktree
        SliceResult = $slicePath
    }
}

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$sliceVerifier = Join-Path $scriptsRoot 'SliceVerifier.ps1'
$runSliceLoop = Join-Path $scriptsRoot 'Run-SliceLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v680-slice-verifier-' + [guid]::NewGuid().ToString('N'))

try {
    $cases = New-Object System.Collections.Generic.List[string]

    $withoutPass = New-SliceVerifierFixture -Root (Join-Path $tempRoot 'without-pass') -WithSideEffectVerificationPass $false
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sliceVerifier -ReplayRoot $withoutPass.ReplayRoot -Worktree $withoutPass.Worktree -SliceResult $withoutPass.SliceResult -SliceIndex 1 *> (Join-Path $tempRoot 'without-pass.out.log')
    $withoutResult = Read-Json -Path (Join-Path $withoutPass.ReplayRoot 'SLICE_VERIFY_01.json')
    $cases.Add((Assert-True 'without_side_effect_verification_keeps_ledger_gap' (@($withoutResult.gap_flags) -contains 'side_effect_ledger_gap'))) | Out-Null
    $cases.Add((Assert-True 'without_side_effect_verification_blocks_next_slice' (-not [bool]$withoutResult.authorized_for_next_slice))) | Out-Null

    $withPass = New-SliceVerifierFixture -Root (Join-Path $tempRoot 'with-pass') -WithSideEffectVerificationPass $true
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sliceVerifier -ReplayRoot $withPass.ReplayRoot -Worktree $withPass.Worktree -SliceResult $withPass.SliceResult -SliceIndex 1 *> (Join-Path $tempRoot 'with-pass.out.log')
    $withResult = Read-Json -Path (Join-Path $withPass.ReplayRoot 'SLICE_VERIFY_01.json')
    $cases.Add((Assert-True 'side_effect_verification_pass_removes_ledger_gap' (-not (@($withResult.gap_flags) -contains 'side_effect_ledger_gap')))) | Out-Null
    $cases.Add((Assert-True 'side_effect_verification_pass_removes_tooling_stop' (-not (@($withResult.gap_flags) -contains 'tooling_enforcement_stop')))) | Out-Null
    $cases.Add((Assert-True 'side_effect_verification_pass_authorizes_next_slice' ([bool]$withResult.authorized_for_next_slice))) | Out-Null
    $cases.Add((Assert-True 'side_effect_verification_pass_keeps_synthesis_unapproved' (-not [bool]$withResult.authorized_for_synthesis))) | Out-Null
    $cases.Add((Assert-True 'side_effect_verification_pass_records_exemption' (@($withResult.verifier_adjustments_applied.exempted_gap_flags) -contains 'side_effect_ledger_gap'))) | Out-Null
    $cases.Add((Assert-True 'side_effect_verification_pass_records_warning' (@($withResult.warnings) -contains 'side_effect_ledger_executable_evidence_verified'))) | Out-Null

    $loopText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
    $cases.Add((Assert-True 'run_slice_loop_refreshes_verifier_after_side_effect_gate' ($loopText.Contains('Invoke-SliceVerifierRefresh') -and $loopText.Contains('side_effect_ledger_existing_artifact') -and $loopText.Contains('side_effect_ledger_after_repair')))) | Out-Null

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($sliceVerifier, [ref]$tokens, [ref]$parseErrors) | Out-Null
    $cases.Add((Assert-True 'slice_verifier_parses' (-not $parseErrors -or $parseErrors.Count -eq 0))) | Out-Null

    [ordered]@{
        status = 'PASS'
        test_name = 'v680_slice_verifier_consumes_side_effect_verification'
        assertions = $cases.Count
        cases = @($cases)
    } | ConvertTo-Json -Depth 8
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
