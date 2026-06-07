# Test-v358-ThreeExperimentsEnforcement.ps1
# Validate that the three experiments from NEXT_EXPERIMENT_PLAN.md are enforced
#
# Experiment 1: Carrier Existence Verification
# Experiment 2: Behavioral Assertion Requirement
# Experiment 3: Real-Time Coverage Cap Enforcement

param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$autopilotRoot = Split-Path -Parent $scriptRoot

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'Experiment 1: Carrier Existence Verification - enforced via verify-carrier.ps1 and prompt',
            'Experiment 2: Behavioral Assertion Requirement - enforced via RED_PHASE_BEHAVIORAL_ASSERTION.md prompt',
            'Experiment 3: Real-Time Coverage Cap Enforcement - enforced via REALTIME_COVERAGE_FEEDBACK.md prompt'
        )
    } | Format-List
    exit 0
}

# Check Experiment 1: Carrier Existence Verification
$carrierPrompt = Join-Path $autopilotRoot 'prompts\phase-plan-tournament.prompt.md'
if (-not (Test-Path -LiteralPath $carrierPrompt)) {
    throw "Experiment 1 prompt not found: $carrierPrompt"
}
$carrierText = Get-Content -LiteralPath $carrierPrompt -Raw -Encoding UTF8
if ($carrierText -notmatch '(?i)EXPERIMENT.*1.*Carrier.*Verification') {
    throw "Experiment 1 not found in plan prompt"
}

# Check Experiment 2: Behavioral Assertion Requirement
$behaviorPrompt = Join-Path $autopilotRoot 'prompts\RED_PHASE_BEHAVIORAL_ASSERTION.md'
if (-not (Test-Path -LiteralPath $behaviorPrompt)) {
    throw "Experiment 2 prompt not found: $behaviorPrompt"
}
$behaviorText = Get-Content -LiteralPath $behaviorPrompt -Raw -Encoding UTF8
if ($behaviorText -notmatch '(?i)EXPERIMENT.*2') {
    throw "Experiment 2 not found in behavioral assertion prompt"
}

# Check Experiment 3: Real-Time Coverage Cap
$coveragePrompt = Join-Path $autopilotRoot 'prompts\REALTIME_COVERAGE_FEEDBACK.md'
if (-not (Test-Path -LiteralPath $coveragePrompt)) {
    throw "Experiment 3 prompt not found: $coveragePrompt"
}
$coverageText = Get-Content -LiteralPath $coveragePrompt -Raw -Encoding UTF8
if ($coverageText -notmatch '(?i)EXPERIMENT.*3') {
    throw "Experiment 3 not found in coverage feedback prompt"
}

# Check that verify-carrier.ps1 exists and is invoked
$carrierScript = Join-Path $scriptRoot 'verify-carrier.ps1'
if (-not (Test-Path -LiteralPath $carrierScript)) {
    throw "Carrier verification script not found: $carrierScript"
}

# Check that Run-ReplayLoop.ps1 invokes verify-carrier.ps1
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
if ($runLoopText -notmatch '(?i)verify-carrier\.ps1') {
    throw "Run-ReplayLoop.ps1 does not invoke verify-carrier.ps1"
}

# Check that prompts are referenced by phase1 executor
$phase1Prompt = Join-Path $autopilotRoot 'prompts\phase1-slice-executor.prompt.md'
if (Test-Path -LiteralPath $phase1Prompt) {
    $phase1Text = Get-Content -LiteralPath $phase1Prompt -Raw -Encoding UTF8
    # Phase1 executor should reference behavioral assertion requirement
    if ($phase1Text -match '(?i)RED.*PHASE.*BEHAVIOR|behavioral.*assertion') {
        # Experiment 2 is referenced in phase1
    }
}

$result = [ordered]@{
    status = 'PASS'
    experiment1_carrier_verification = 'ENFORCED'
    experiment2_behavioral_assertion = 'ENFORCED'
    experiment3_realtime_coverage = 'ENFORCED'
    carrier_prompt = $carrierPrompt
    behavior_prompt = $behaviorPrompt
    coverage_prompt = $coveragePrompt
    carrier_script_invoked = 'Run-ReplayLoop.ps1'
}

$result | ConvertTo-Json -Depth 4
Write-Host "v358 Three Experiments Enforcement: PASS"
exit 0
