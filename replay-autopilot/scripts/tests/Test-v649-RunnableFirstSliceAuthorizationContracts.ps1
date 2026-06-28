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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v649-runnable-slice-auth-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src\main\java\demo') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>demo-root</artifactId><version>1</version></project>'

    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    $worktreePom = Join-Path $worktree 'pom.xml'
    $greenCommand = "mvn --% -f $worktreePom -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"

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
        red_expectation = 'business assertion fails before mapping is fixed'
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
- red_command: $greenCommand
- green_command: $greenCommand
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through the existing entry
- red_assertion: assertEquals("mapped", result)
- downstream_output_or_side_effect: returned payload value
- production_boundary: demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only or mock-only closure
- green_change_boundary: RealEntry.handle return mapping
- validation_command: $greenCommand
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType real_entry_behavior
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice contracts authorize valid runnable first slice'

    $runnable = Get-Content -LiteralPath (Join-Path $replayRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $callable = Get-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $charter = Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_PLAN_CONTRACT_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True ([string]$runnable.status -eq 'AUTHORIZED') 'RUNNABLE_SLICE_AUTHORIZATION_01.json must authorize copy-ready command'
    Assert-True ([bool]$runnable.uses_isolated_replay_pom) 'runnable authorization must prove isolated replay POM use'
    Assert-True (-not ([string]$runnable.red_command -match '(?i)\b(deploy|install)\b')) 'runnable authorization must reject forbidden Maven goals'
    Assert-True ([string]$callable.authorization_status -eq 'AUTHORIZED') 'CALLABLE_CARRIER_AUTHORIZATION_01.json must expose authorization_status'
    Assert-True ([string]$callable.carrier_origin -eq 'existing_production_entry') 'callable authorization must bind existing production entry origin'
    Assert-True ([string]$charter.status -eq 'AUTHORIZED') 'TEST_CHARTER_01.json must authorize side-effect/output proof charter'
    Assert-True (@($charter.negative_must_not_assertions).Count -gt 0) 'test charter must include must-not proof'
    Assert-True ([string]$plan.authorization -eq 'ALLOW') 'slice plan must remain ALLOW after the three preconditions pass'

    Write-Host 'v649 Runnable First-Slice Authorization Contracts: PASS'
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
