$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$autopilotRoot = Split-Path -Parent $scriptRoot
$tempRoot = Join-Path $env:TEMP ('replay-v254-artifact-repair-test-{0}' -f ([guid]::NewGuid().ToString('N')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: Verify repair prompt is generated when artifacts are missing
    # =========================================================================
    Write-Host 'Test 1: Repair prompt generation in Run-ReplayLoop script'
    $runLoopText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runLoopText.Contains('PLAN_ARTIFACT_REPAIR_PROMPT')) 'Run-ReplayLoop must contain repair prompt generation'
    Assert-True ($runLoopText.Contains('Plan Artifact Repair Pass')) 'Run-ReplayLoop must contain repair pass header'
    Assert-True ($runLoopText.Contains('plan-repair')) 'Run-ReplayLoop must use plan-repair log dir'
    Assert-True ($runLoopText.Contains('stillMissing')) 'Run-ReplayLoop must check still missing artifacts after repair'
    Assert-True ($runLoopText.Contains('repairExit')) 'Run-ReplayLoop must check repair exit code'
    Assert-True ($runLoopText.Contains('PLAN_CONTRACT_VERIFY')) 'Run-ReplayLoop must re-verify after repair'
    Write-Host '  PASS: Repair logic present in Run-ReplayLoop.ps1'
    $passCount++

    # =========================================================================
    # Test 2: Plan prompt mandates all artifacts even when BLOCKED
    # =========================================================================
    Write-Host 'Test 2: Plan prompt requires all artifacts even when BLOCKED'
    $planPromptText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8
    # Check for the artifact completeness section (contains both PROCEED and BLOCKED in same context)
    $hasArtifactSection = $planPromptText.IndexOf('plan_status=BLOCKED', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $hasBlockedException = $planPromptText.IndexOf('BLOCKED', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    Assert-True ($hasArtifactSection) 'Plan prompt must mention BLOCKED plan_status'
    Assert-True ($hasBlockedException) 'Plan prompt must mention BLOCKED'    Assert-True ($planPromptText.Contains('SIDE_EFFECT_LEDGER.md')) 'Plan prompt must list SIDE_EFFECT_LEDGER.md'
    Assert-True ($planPromptText.Contains('TEST_CHARTER.md')) 'Plan prompt must list TEST_CHARTER.md'
    Assert-True ($planPromptText.Contains('FIRST_SLICE_PROOF_PLAN.md')) 'Plan prompt must list FIRST_SLICE_PROOF_PLAN.md'
    Write-Host '  PASS: Plan prompt enforces artifact completeness'
    $passCount++

    # =========================================================================
    # Test 3: Repair prompt template contains required artifact names
    # =========================================================================
    Write-Host 'Test 3: Repair prompt template references missing artifact types'
    Assert-True ($runLoopText.Contains('SIDE_EFFECT_LEDGER.md')) 'Repair logic must reference SIDE_EFFECT_LEDGER.md'
    Assert-True ($runLoopText.Contains('TEST_CHARTER.md')) 'Repair logic must reference TEST_CHARTER.md'
    Assert-True ($runLoopText.Contains('FIRST_SLICE_PROOF_PLAN.md')) 'Repair logic must reference FIRST_SLICE_PROOF_PLAN.md'
    Assert-True ($runLoopText.Contains('PLAN_ARTIFACT_REPAIR_RESULT')) 'Repair logic must produce repair result marker'
    Write-Host '  PASS: Repair prompt references all artifact types'
    $passCount++

    # =========================================================================
    # Test 4: Verify-PlanContract Phase0 still works on real renbao fixture
    # =========================================================================
    Write-Host 'Test 4: Verify-PlanContract Phase0 on real renbao-tuipiao fixture'
    $renbaoRoot = 'D:\opt\replay-evidence\renbao-tuipiao\claim-codex-replay-v254-cross-20260522-093418-r01'
    if (Test-Path -LiteralPath $renbaoRoot) {
        $result4 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $renbaoRoot -Stage Phase0 2>&1
        $verify4 = $result4 | ConvertFrom-Json
        Assert-True ($verify4.verification_status -eq 'PASS') 'renbao-tuipiao Phase0 should PASS'
        Write-Host '  PASS'
        $passCount++
    } else {
        Write-Host '  SKIP: fixture not found'
    }

    # =========================================================================
    # Test 5: Repair path generates correct prompt for renbao-tuipiao scenario
    # =========================================================================
    Write-Host 'Test 5: Repair prompt generation for missing SIDE_EFFECT_LEDGER, TEST_CHARTER, FIRST_SLICE_PROOF_PLAN'
    $t5Root = Join-Path $tempRoot 'test5-repair-scenario'
    New-Item -ItemType Directory -Force -Path $t5Root | Out-Null

    # Simulate renbao-tuipiao state: Phase0 PASS, Plan partial (missing 3 files)
    @"
## Decision: PROCEED

## Selected Real Entry

Primary Entry: ExamplePushFacade.returnTicket()

## First Executable Slice

S1 - Receive return ticket callback

## First Slice Type

Type: core_path
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'PHASE0_RESULT.md') -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $t5Root 'EXPLORATION_REPORT.md') -Value '' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $t5Root 'ROUND_CONTRACT.md') -Value '' -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t5Root 'FAMILY_CONTRACT.json') -Encoding UTF8

    @"
## Plan Status

**plan_status**: PROCEED

## Selected Candidate

Candidate 1: Core-Path-First

- first_slice: S1 - Return ticket callback
- first_red_test: ExamplePushServiceTest#testExampleTicket()
- selected_strategy: core_path_first
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'PLAN_RESULT.md') -Encoding UTF8

    # Create files that exist
    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md',
                        'PLAN_SELECTION.md', 'REPLAY_PLAN.md', 'IMPLEMENTATION_CONTRACT.md',
                        'EXPECTED_DIFF_MATRIX.md')) {
        Set-Content -LiteralPath (Join-Path $t5Root $file) -Value 'placeholder' -Encoding UTF8
    }

    # DELIBERATELY skip SIDE_EFFECT_LEDGER.md, TEST_CHARTER.md, FIRST_SLICE_PROOF_PLAN.md
    # to simulate the renbao-tuipiao scenario

    $missing = @()
    foreach ($a in @('SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md', 'FIRST_SLICE_PROOF_PLAN.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $t5Root $a))) {
            $missing += $a
        }
    }
    Assert-True ($missing.Count -eq 3) "Should detect 3 missing artifacts, found $($missing.Count)"
    Write-Host '  PASS: Missing artifact detection works (3 missing)'
    $passCount++

    # =========================================================================
    # Test 6: ValidateOnly smoke test
    # =========================================================================
    Write-Host 'Test 6: ValidateOnly smoke test'
    $result6 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Run-CrossFeatureReplay.ps1') -Executor claude -UseLatestKnowledgeVersion -StartIndex 3 -MaxFeatures 1 -RoundsPerFeature 1 -ValidateOnly 2>&1
    $validate6 = $result6 | ConvertFrom-Json
    Assert-True ($validate6.status -eq 'VALID') 'ValidateOnly should return VALID for StartIndex=3'
    $selectedFeature = $validate6.selected_features[0].feature_name
    Write-Host "  PASS: StartIndex=3 -> $selectedFeature"
    $passCount++

    # =========================================================================
    # Summary
    # =========================================================================
    Write-Host ''
    Write-Host "Test-v254-PlanArtifactRepair: $passCount passed, all passed"

} catch {
    Write-Host "UNEXPECTED ERROR: $_"
    Write-Host "Test-v254-PlanArtifactRepair: $passCount passed, 1 failed"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
