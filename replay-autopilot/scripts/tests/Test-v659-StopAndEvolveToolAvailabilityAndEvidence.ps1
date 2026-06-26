#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
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

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$autopilotRoot = Split-Path -Parent $scriptsRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v659-tooling-evolution-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceToolAvailabilityGate.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -PassThru | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice tool availability gate should pass when mandatory tooling is present and runnable'
    $availability = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_TOOL_AVAILABILITY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$availability.status -eq 'PASS') 'PRE_SLICE_TOOL_AVAILABILITY.json must report PASS'
    Assert-True (@($availability.missing_scripts).Count -eq 0) 'availability gate must list no missing scripts'
    Assert-True (@($availability.unrunnable_scripts).Count -eq 0) 'availability gate must list no unrunnable scripts'

    $command = "mvn --% -f $(Join-Path $worktree 'pom.xml') -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"
    $sliceResult = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $sliceVerify = Join-Path $replayRoot 'SLICE_VERIFY_01.json'
    @{
        families = @(
            @{ id = 'core_entry'; required = $true },
            @{ id = 'stateful_side_effect'; required = $true }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    @{
        schema = 'carrier_invocation_contract.v1'
        status = 'PASS'
        resolved = $true
        signature_match = $true
        test_invokes_entry = $true
        carrier_origin = 'existing_production'
        production_entry_qn = 'demo.RealEntry.handle'
        test_invocation_method = 'new RealEntry().handle("input")'
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_INVOCATION_CONTRACT_01.json') -Encoding UTF8
    @{
        schema = 'slice_execution_contract.v1'
        family_id = 'stateful_side_effect'
        production_entry_qn = 'demo.RealEntry.handle'
        test_class = 'RealEntryContractTest'
        test_method = 'returnsMappedPayload'
        red_command = $command
        green_command = $command
        side_effect_or_output_probe = 'status row updated and progress log saved'
        red_assertion = 'assertEquals("mapped", result) fails before GREEN'
        must_not_assertion = 'must not use helper-only closure'
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_EXECUTION_CONTRACT_01.json') -Encoding UTF8
    @{
        slice_index = 1
        slice_status = 'DONE'
        touched_requirement_families = @('core_entry', 'stateful_side_effect')
        closed_requirement_families = @('core_entry', 'stateful_side_effect')
        target_subsurface_or_carrier = 'demo.RealEntry.handle'
        production_boundary = 'demo.RealEntry.handle'
        test_execution_command = $command
        test_execution_exit_code = 0
        red_command = $command
        red_exit_code = 1
        red_failure_assertion = 'assertEquals("mapped", result) fails before GREEN'
        green_command = $command
        green_exit_code = 0
        asserted_side_effects = @('status row updated', 'progress log saved')
        test_harness_module = 'demo-harness'
        entry_invocation = 'new RealEntry().handle("input")'
        must_not_assertions = @('must not use helper-only closure')
        side_effect_evidence = @{
            status = 'CLOSED'
            entry_call = 'new RealEntry().handle("input")'
            expected_writes_or_outputs = @('status row updated', 'progress log saved')
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
            must_not_writes = @('helper-only closure')
        }
        tests = @(
            @{ phase = 'RED'; result = 'fail'; exit_code = 1; command = $command; evidence = 'assert status row updated fails before GREEN' },
            @{ phase = 'GREEN'; result = 'pass'; exit_code = 0; command = $command; evidence = 'assert status row updated and progress log saved passes' }
        )
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sliceResult -Encoding UTF8
    @{
        slice_index = 1
        verification_status = 'PASS'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $true
        test_commands = @($command)
        changed_files = @('demo-harness/src/test/java/RealEntryContractTest.java')
        implemented_files = @('demo/src/main/java/demo/RealEntry.java')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceVerify -Encoding UTF8

    & python (Join-Path $scriptsRoot 'verify_carrier_execution_contract.py') --replay-root $replayRoot --slice-result $sliceResult --slice-verify $sliceVerify | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'carrier execution contract verifier should pass valid selected-carrier execution evidence'
    & python (Join-Path $scriptsRoot 'verify_red_green_side_effect_evidence.py') --slice-result $sliceResult --family-ledger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'RED/GREEN side-effect verifier should pass complete business side-effect schema'

    $badSliceResult = Join-Path $replayRoot 'SLICE_RESULT_BAD.json'
    @{
        slice_index = 1
        slice_status = 'DONE'
        touched_requirement_families = @('stateful_side_effect')
        closed_requirement_families = @('stateful_side_effect')
        red_command = $command
        red_exit_code = 0
        green_command = $command
        green_exit_code = 0
        asserted_side_effects = @('helper_only')
        test_harness_module = 'demo-harness'
        entry_invocation = 'helper_only'
        must_not_assertions = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badSliceResult -Encoding UTF8
    & python (Join-Path $scriptsRoot 'verify_red_green_side_effect_evidence.py') --slice-result $badSliceResult --family-ledger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'RED/GREEN side-effect verifier must fail closed on non-RED helper-only evidence'

    $runSliceText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    $availabilityGateText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Invoke-PreSliceToolAvailabilityGate.ps1') -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    Assert-True ($availabilityGateText -match 'function New-CompatTempFile') 'pre-slice availability gate must use Windows PowerShell-compatible temp files'
    Assert-True ($availabilityGateText -notmatch '\bNew-TemporaryFile\b') 'pre-slice availability gate must not require New-TemporaryFile on Windows PowerShell'
    Assert-True ($availabilityGateText -match 'probe_exception') 'pre-slice availability probe exceptions must be converted to JSON diagnostics'
    Assert-True ($runSliceText -match 'Invoke-PreSliceToolAvailabilityGate\.ps1') 'Run-SliceLoop.ps1 must invoke pre-slice tool availability gate'
    $toolGateCallIndex = $runSliceText.IndexOf("Join-Path `$PSScriptRoot 'Invoke-PreSliceToolAvailabilityGate.ps1'")
    $callableGateCallIndex = $runSliceText.IndexOf('$callableCarrierGate = Invoke-CallableCarrierAuthorizationGate')
    Assert-True ($toolGateCallIndex -ge 0) 'Run-SliceLoop.ps1 must contain the concrete pre-slice tool availability gate invocation'
    Assert-True ($callableGateCallIndex -ge 0) 'Run-SliceLoop.ps1 must contain the concrete callable-carrier authorization invocation'
    Assert-True ($toolGateCallIndex -lt $callableGateCallIndex) 'Run-SliceLoop.ps1 must write PRE_SLICE_TOOL_AVAILABILITY before callable-carrier authorization can stop the slice'
    Assert-True ($runSliceText -match 'PRE_SLICE_TOOL_AVAILABILITY_\{0:D2\}\.stdout\.log') 'Run-SliceLoop.ps1 must preserve pre-slice tool availability stdout evidence'
    Assert-True ($runSliceText -match 'PRE_SLICE_TOOL_AVAILABILITY_\{0:D2\}\.stderr\.log') 'Run-SliceLoop.ps1 must preserve pre-slice tool availability stderr evidence'
    Assert-True ($runSliceText -match 'if \(\$preSliceToolGateStatus -ne ''PASS''\)') 'Run-SliceLoop.ps1 must gate on PRE_SLICE_TOOL_AVAILABILITY status, not only process exit code'
    Assert-True ($runSliceText -match 'tooling_preflight_blocker') 'Run-SliceLoop.ps1 must classify availability failures as tooling_preflight_blocker'
    Assert-True ($promptText -match 'PRE_SLICE_TOOL_AVAILABILITY\.json') 'Phase1 prompt must require PRE_SLICE_TOOL_AVAILABILITY.json'
    Assert-True ($promptText -match 'red_exit_code') 'Phase1 prompt must require machine-readable RED/GREEN side-effect schema fields'

    Write-Host 'v659 Stop-And-Evolve Tool Availability And Evidence: PASS'
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
