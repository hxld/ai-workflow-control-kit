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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v670-pre-authorize-slice-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'demo-harness\src\test\java\demo') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'demo-core\src\main\java\demo') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>demo-root</artifactId><version>1</version></project>'

    $replayRoot = Join-Path $tempRoot 'replay-pass'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    $worktreePom = Join-Path $worktree 'pom.xml'
    $redCommand = "mvn --% -f `"$worktreePom`" -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"

    @{
        families = @(
            @{
                id = 'core_entry'
                required = $true
                status = 'OPEN'
                weight = 100
                required_proof_type = 'real_entry_behavior'
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        production_boundary = 'demo.RealEntry.handle(String): String'
        downstream_side_effect_or_output = 'returned payload value'
        red_expectation = 'assertEquals("mapped", result) fails before mapping is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.RealEntry.handle(String): String'
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        resolved_signature = @{ selected_carrier = @{ class_name = 'demo.RealEntry'; visibility = 'public'; formatted = 'String demo.RealEntry.handle(String)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- first_red_test: RealEntryContractTest#returnsMappedPayload
- red_command: $redCommand
- green_command: $redCommand
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through the existing entry
- red_assertion: assertEquals("mapped", result)
- downstream_output_or_side_effect: returned payload value
- production_boundary: demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only or mock-only closure
- green_change_boundary: RealEntry.handle return mapping
- validation_command: $redCommand
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType real_entry_behavior
    Assert-True ($LASTEXITCODE -eq 0) 'valid first slice passes pre-slice experiment contracts'

    $runnable = Get-Content -LiteralPath (Join-Path $replayRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$runnable.pre_authorize_slice.authorization_status -eq 'PASS') 'pre_authorize_slice authorization_status must be PASS'
    Assert-True ([string]$runnable.pre_authorize_slice.selected_existing_carrier -eq 'demo.RealEntry.handle(String): String') 'pre_authorize_slice must name selected existing carrier'
    Assert-True ([string]$runnable.pre_authorize_slice.callable_signature -eq 'demo.RealEntry.handle(String): String') 'pre_authorize_slice must name callable signature'
    Assert-True ([string]$runnable.pre_authorize_slice.nearest_existing_test_harness -eq 'demo-harness') 'pre_authorize_slice must name nearest existing test harness'
    Assert-True ([string]$runnable.pre_authorize_slice.red_command -match '-f') 'pre_authorize_slice must carry RED command'
    Assert-True ([string]$runnable.pre_authorize_slice.expected_failing_assertion -match 'assertEquals') 'pre_authorize_slice must carry expected failing assertion'
    Assert-True (@($runnable.pre_authorize_slice.forbidden_substitute_carriers).Count -gt 0) 'pre_authorize_slice must list forbidden substitute carriers'

    $missingRoot = Join-Path $tempRoot 'replay-blocked'
    New-Item -ItemType Directory -Force -Path $missingRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Destination (Join-Path $missingRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Force
    Write-Utf8 (Join-Path $missingRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- expected_green_assertion: mapped result should be returned
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $missingRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType real_entry_behavior 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'missing RED/test authorization stops before executor'

    $blocked = Get-Content -LiteralPath (Join-Path $missingRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$blocked.status -eq 'BLOCKED_NO_RUNNABLE_SLICE') 'missing fields must set runnable status BLOCKED_NO_RUNNABLE_SLICE'
    Assert-True ([string]$blocked.pre_authorize_slice.authorization_status -eq 'BLOCKED_NO_RUNNABLE_SLICE') 'pre_authorize_slice must expose blocked authorization status'
    $blocker = Get-Content -LiteralPath (Join-Path $missingRoot 'SLICE_RESULT_PRE_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($blocker.blocker_reasons | ForEach-Object { [string]$_ }) -contains 'BLOCKED_NO_RUNNABLE_SLICE') 'pre-slice blocker must carry BLOCKED_NO_RUNNABLE_SLICE reason'

    $runnerText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runnerText -match 'Invoke-PreSliceExperimentContracts\.ps1') 'Run-SliceLoop must invoke pre-slice experiment contracts before executor'
    Assert-True ($runnerText -match 'Authorize-PreSliceEvidence\.ps1') 'Run-SliceLoop must invoke pre-slice authorization gate before executor'

    Write-Host 'v670 Pre-Authorize Slice Schema: PASS'
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
