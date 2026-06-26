#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Json {
    param($Value, [string]$Path)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v672-experiments-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Value '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>' -Encoding UTF8
    $mvn = "mvn --% -f $(Join-Path $worktree 'pom.xml') -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"

    Write-Json @{
        families = @(
            @{ id = 'core_entry'; required = $true; status = 'OPEN'; weight = 100; required_proof_type = 'real_entry_behavior'; coverage_cap_if_open = 45 },
            @{ id = 'stateful_side_effect'; required = $true; status = 'OPEN'; weight = 80; required_proof_type = 'stateful_side_effect'; coverage_cap_if_open = 60 }
        )
    } (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json')
    Write-Json @{
        verification_status = 'PASS'
        authorized_for_next_slice = $true
        touched_requirement_families = @('core_entry', 'stateful_side_effect')
        closed_requirement_families = @('core_entry')
        gap_flags = @()
    } (Join-Path $replayRoot 'SLICE_VERIFY_01.json')

    $ledger = Get-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($family in @($ledger.families)) {
        if ([string]$family.id -eq 'core_entry') { $family.status = 'EXECUTABLE_CLOSED' }
    }
    $ledger | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify-family-ledger-from-slice-verify.ps1') -ReplayRoot $replayRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'family ledger verifier accepts only verifier-closed CLOSED families'
    $familyCheck = Get-Content -LiteralPath (Join-Path $replayRoot 'FAMILY_LEDGER_FROM_SLICE_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$familyCheck.status -eq 'PASS') 'family ledger verifier writes PASS artifact'
    $ledgerAfter = Get-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $stateful = @($ledgerAfter.families | Where-Object { [string]$_.id -eq 'stateful_side_effect' })[0]
    Assert-True ([bool]$stateful.touched_not_closed) 'touched but unclosed family is recorded as touched_not_closed'

    $badRoot = Join-Path $tempRoot 'bad-ledger'
    Copy-Item -LiteralPath $replayRoot -Destination $badRoot -Recurse
    $badLedger = Get-Content -LiteralPath (Join-Path $badRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($family in @($badLedger.families)) {
        if ([string]$family.id -eq 'stateful_side_effect') { $family.status = 'EXECUTABLE_CLOSED' }
    }
    $badLedger | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $badRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify-family-ledger-from-slice-verify.ps1') -ReplayRoot $badRoot 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'family ledger verifier rejects CLOSED family absent from verifier closed list'

    Write-Json @{
        schema_version = 1
        family_id = 'core_entry'
        existing_test_harness_module = 'demo-harness'
        isolated_pom_maven_command = $mvn
        real_entry_signature = 'demo.RealEntry.handle(String): String'
        trigger_positive_assertion = 'returns mapped payload'
        trigger_negative_assertion = 'does not use helper-only carrier'
        side_effect_proof_method = 'entry return payload assertion'
        forbidden_substitute_carriers = @('helper_only', 'static_only', 'mock_only')
        real_entry_fqn = 'demo.RealEntry.handle(String): String'
        test_harness_module = 'demo-harness'
        test_class = 'RealEntryContractTest'
        test_method = 'returnsMappedPayload'
        red_command = $mvn
        green_command = $mvn
        expected_red_failure = 'business assertion fails before change'
        green_business_assertion = 'business assertion passes after change'
        isolated_pom_path = (Join-Path $worktree 'pom.xml')
        maven_settings_arg = '-Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8'
        required_side_effects = @('returned payload value')
        negative_guard_assertion = 'does not use helper-only carrier'
        uses_isolated_replay_pom = $true
        contract_status = 'AUTHORIZED'
    } (Join-Path $replayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'validate-first-slice-executable-contract.ps1') -ReplayRoot $replayRoot -Worktree $worktree | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'first-slice executable contract validator accepts complete experiment contract'

    Write-Json @{
        schema = 'test_charter.v1'
        family_id = 'core_entry'
        proof_type = 'real_entry_behavior'
        production_entry = 'demo.RealEntry.handle(String): String'
        business_assertion = 'returns mapped payload'
        state_or_output_surface = 'returned payload value'
        negative_must_not_assertions = @('does not use helper-only carrier')
    } (Join-Path $replayRoot 'TEST_CHARTER_01.json')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify-proof-type-policy.ps1') -ReplayRoot $replayRoot -Slice 1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'proof-type policy wrapper accepts authorizing proof type'

    $promptText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $scriptsRoot) 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    foreach ($needle in @('existing_test_harness_module', 'isolated_pom_maven_command', 'side_effect_proof_method', 'forbidden_substitute_carriers', 'missing_stateful_tracer_contract')) {
        Assert-True ($promptText -match [regex]::Escape($needle)) "phase1 prompt must name $needle"
    }
    foreach ($needle in @('validate-first-slice-executable-contract.ps1', 'verify-proof-type-policy.ps1', 'verify-family-ledger-from-slice-verify.ps1')) {
        Assert-True ($promptText -match [regex]::Escape($needle)) "phase1 prompt must invoke $needle"
    }
    $runSliceText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runSliceText -match 'validate-first-slice-executable-contract\.ps1') 'Run-SliceLoop must invoke exact first-slice executable contract command'
    Assert-True ($runSliceText -match 'verify-family-ledger-from-slice-verify\.ps1') 'Run-SliceLoop must invoke exact family ledger verifier command'
    $preSliceText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') -Raw -Encoding UTF8
    Assert-True ($preSliceText -match 'verify-proof-type-policy\.ps1') 'pre-slice contract runner must invoke exact proof-type policy command'

    Write-Host 'v672 Stop-And-Evolve Experiment Commands: PASS'
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
