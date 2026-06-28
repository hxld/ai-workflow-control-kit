#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Message - $Detail"
    }
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

function Write-JsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-PreSliceFixture {
    param(
        [string]$Root,
        [bool]$Complete = $true
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $worktree = Join-Path $Root 'worktree'
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project />'
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
selected_real_entry: com.example.ExampleProcessor.handle(com.example.Task)
selected_carrier: com.example.ExampleProcessor.handle(com.example.Task)
entry_file: module/src/main/java/com/example/ExampleProcessor.java
production_boundary: module/src/main/java/com/example/ExampleProcessor.java#handle -> writes status row
downstream_output_or_side_effect: status row update asserted by mapper capture
first_red_test: com.example.ExampleProcessorTest#failsBeforeStatusWrite
expected_red_failure: status row is not written before GREEN
red_assertion: status row is not written before GREEN
expected_green_assertion: captured status row has AUTO_FLOW_DONE
must_not_behavior: do not use helper/static/mock-only proof
test_harness_module: module
test_class: com.example.ExampleProcessorTest
test_method: failsBeforeStatusWrite
red_command: mvn --% -Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8 -f "$worktree\pom.xml" -pl module -am -Dtest=com.example.ExampleProcessorTest#failsBeforeStatusWrite -Dsurefire.failIfNoSpecifiedTests=false test
green_command: mvn --% -Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8 -f "$worktree\pom.xml" -pl module -am -Dtest=com.example.ExampleProcessorTest#failsBeforeStatusWrite -Dsurefire.failIfNoSpecifiedTests=false test
method_signature: public void handle(Task task)
"@
    if (-not $Complete) {
        Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
selected_real_entry: com.example.ExampleProcessor.handle(com.example.Task)
selected_carrier: com.example.ExampleProcessor.handle(com.example.Task)
first_red_test: com.example.ExampleProcessorTest#failsBeforeStatusWrite
test_harness_module: module
test_class: com.example.ExampleProcessorTest
test_method: failsBeforeStatusWrite
red_command: mvn --% -f "$worktree\pom.xml" -pl module -am -Dtest=com.example.ExampleProcessorTest#failsBeforeStatusWrite test
green_command: mvn --% -f "$worktree\pom.xml" -pl module -am -Dtest=com.example.ExampleProcessorTest#failsBeforeStatusWrite test
"@
    }

    Write-JsonFile (Join-Path $Root 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
        authorization = 'ALLOW'
        selected_carrier = 'com.example.ExampleProcessor.handle(com.example.Task)'
        real_entry = 'com.example.ExampleProcessor.handle(com.example.Task)'
        entry_file = 'module/src/main/java/com/example/ExampleProcessor.java'
    })
    Write-JsonFile (Join-Path $Root 'CALLABLE_CARRIER_AUTHORIZATION_01.json') ([ordered]@{
        can_proceed = $true
        selected_carrier = 'com.example.ExampleProcessor.handle(com.example.Task)'
        selected_real_entry = 'com.example.ExampleProcessor.handle(com.example.Task)'
        file_path = 'module/src/main/java/com/example/ExampleProcessor.java'
        resolved_signature = [ordered]@{
            selected_carrier = [ordered]@{
                formatted = 'public void handle(Task task)'
                visibility = 'public'
                class_name = 'ExampleProcessor'
            }
        }
    })
    Write-JsonFile (Join-Path $Root 'PRE_SLICE_AUTHORIZATION_01.json') ([ordered]@{ decision = 'ALLOW'; issues = @() })
    Write-JsonFile (Join-Path $Root 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        families = @([ordered]@{ id = 'core_entry'; required = $true; status = 'OPEN'; weight = 100; coverage_cap_if_open = 45 })
    })
}

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$preSliceScript = Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1'
$evidenceGate = Join-Path $scriptsRoot 'Validate-ExecutableEvidenceGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v675-execution-auth-" + [guid]::NewGuid().ToString('N'))

try {
    $passRoot = Join-Path $tempRoot 'pass'
    New-PreSliceFixture -Root $passRoot -Complete $true
    & powershell -NoProfile -ExecutionPolicy Bypass -File $preSliceScript -ReplayRoot $passRoot -Worktree (Join-Path $passRoot 'worktree') -SliceIndex 1 -ForcedRequirementFamily core_entry 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'complete pre-slice contract authorizes execution'
    $runnable = Get-Content -LiteralPath (Join-Path $passRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $execution = Get-Content -LiteralPath (Join-Path $passRoot 'SLICE_EXECUTION_CONTRACT_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$runnable.execution_authorized) 'runnable authorization exposes execution_authorized=true'
    Assert-True ([bool]$execution.execution_authorized) 'slice execution contract exposes execution_authorized=true'
    Assert-True (@($runnable.execution_authorization_missing_fields).Count -eq 0) 'complete contract has no missing execution fields'

    $blockedRoot = Join-Path $tempRoot 'blocked'
    New-PreSliceFixture -Root $blockedRoot -Complete $false
    & powershell -NoProfile -ExecutionPolicy Bypass -File $preSliceScript -ReplayRoot $blockedRoot -Worktree (Join-Path $blockedRoot 'worktree') -SliceIndex 1 -ForcedRequirementFamily core_entry 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'incomplete pre-slice contract blocks before execution'
    $blockedRunnable = Get-Content -LiteralPath (Join-Path $blockedRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $blockedPre = Get-Content -LiteralPath (Join-Path $blockedRoot 'SLICE_RESULT_PRE_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not [bool]$blockedRunnable.execution_authorized) 'blocked runnable authorization exposes execution_authorized=false'
    Assert-True ((@($blockedRunnable.execution_authorization_missing_fields) -join ';') -match 'side_effect_proof_method|exact_contract_assertions') 'blocked runnable names missing execution fields'
    Assert-True ((@($blockedPre.blocker_reasons) -join ';') -match 'execution_authorization_not_authorized') 'pre-slice blocker records execution authorization stop'

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
    $evidenceWorktree = Join-Path $evidenceRoot 'worktree'
    Write-Utf8 (Join-Path $evidenceWorktree 'module\src\main\java\com\example\ExampleProcessor.java') 'package com.example; public class ExampleProcessor { public void handle() {} }'
    $slicePath = Join-Path $evidenceRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slicePath ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'stateful_success_slice'
        coverage_delta = 10
        target_subsurface_or_carrier = 'com.example.ExampleProcessor.handle'
        production_boundary = 'com.example.ExampleProcessor.handle -> status row'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        implemented_files = @('module/src/main/java/com/example/ExampleProcessor.java')
        test_execution_command = 'mvn --% -f "' + $evidenceWorktree + '\pom.xml" -pl module -am -Dtest=com.example.ExampleProcessorTest#failsBeforeStatusWrite -Dsurefire.failIfNoSpecifiedTests=false test'
        test_execution_exit_code = 0
        matched_test_count = 0
        real_entry_invoked = $false
        tests = @([ordered]@{
            phase = 'VERIFY'
            result = 'blocked'
            command = ''
            evidence = 'executor reported no matching behavior test run'
        })
        side_effect_evidence = [ordered]@{
            status = 'BLOCKED'
            entry_call = ''
            expected_writes_or_outputs = @()
            red_result = 'NOT_RUN'
            green_result = 'PASS'
        }
        closed_assertions = @()
        gap_flags = @()
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $evidenceGate -ReplayRoot $evidenceRoot -Worktree $evidenceWorktree -SliceResultPath $slicePath -SliceIndex 1 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'success-shaped slice without behavior proof fails executable evidence gate'
    $gate = Get-Content -LiteralPath (Join-Path $evidenceRoot 'EXECUTABLE_EVIDENCE_GATE_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($gate.issues) -join ';'
    Assert-True ($issues -match 'matched_test_count_zero') 'evidence gate requires matched_test_count > 0' $issues
    Assert-True ($issues -match 'real_entry_not_invoked') 'evidence gate requires real_entry_invoked=true' $issues
    Assert-True ($issues -match 'no_side_effect_or_exact_output_assertion') 'evidence gate requires side-effect or exact-output assertion' $issues

    Write-Host 'v675 Execution Authorization And Behavior Evidence: PASS'
    exit 0
} catch {
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
