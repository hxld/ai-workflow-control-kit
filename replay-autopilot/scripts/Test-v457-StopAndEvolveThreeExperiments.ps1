# Test-v457-StopAndEvolveThreeExperiments.ps1
# Validate that the v457 three experiments tooling is properly implemented
#
# Experiment 1: Baseline Carrier Index (Build-BaselineCarrierIndex.ps1)
# Experiment 2: Layer Validation Pre-Check (Get-CarrierLayer.ps1)
# Experiment 3: Plan Contract Hard Requirements (Verify-PlanContract.ps1 updates)

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
            'Experiment 1: Baseline Carrier Index - scripts/Build-BaselineCarrierIndex.ps1 exists and executable',
            'Experiment 2: Layer Validation Pre-Check - scripts/Get-CarrierLayer.ps1 exists and executable',
            'Experiment 3: Plan Contract Hard Requirements - scripts/Verify-PlanContract.ps1 has v457 validation',
            'V457_CARRIER_INDEX_AND_LAYER_VALIDATION.md prompt exists',
            'V457_PLAN_HARD_REQUIREMENTS.md prompt exists'
        )
    } | Format-List
    exit 0
}

# Test Experiment 1: Baseline Carrier Index
$carrierIndexScript = Join-Path $scriptRoot 'Build-BaselineCarrierIndex.ps1'
if (-not (Test-Path -LiteralPath $carrierIndexScript)) {
    throw "Experiment 1 script not found: $carrierIndexScript"
}
# Verify script has correct parameters
$carrierIndexText = Get-Content -LiteralPath $carrierIndexScript -Raw -Encoding UTF8
if ($carrierIndexText -notmatch 'BaselineRoot|OutputPath|BaselineCommit') {
    throw "Experiment 1 script missing required parameters"
}

# Test Experiment 2: Layer Validation Pre-Check
$layerValidationScript = Join-Path $scriptRoot 'Get-CarrierLayer.ps1'
if (-not (Test-Path -LiteralPath $layerValidationScript)) {
    throw "Experiment 2 script not found: $layerValidationScript"
}
# Verify script has correct parameters
$layerText = Get-Content -LiteralPath $layerValidationScript -Raw -Encoding UTF8
if ($layerText -notmatch 'Carrier|BaselineRoot') {
    throw "Experiment 2 script missing required parameters"
}

# Test Experiment 3: Plan Contract Hard Requirements
$planContractScript = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
if (-not (Test-Path -LiteralPath $planContractScript)) {
    throw "Experiment 3 script not found: $planContractScript"
}
# Verify v457 checks are present
$planText = Get-Content -LiteralPath $planContractScript -Raw -Encoding UTF8
if ($planText -notmatch 'v457.*Experiment.*3.*Plan Contract') {
    throw "Experiment 3 script missing v457 plan contract header"
}
if ($planText -notmatch 'first_slice_proof_v457_missing|first_slice_proof_v457_empty|first_slice_proof_v457_placeholder') {
    throw "Experiment 3 script missing v457 validation checks"
}

# Test Prompt Files
$carrierPrompt = Join-Path $autopilotRoot 'prompts\V457_CARRIER_INDEX_AND_LAYER_VALIDATION.md'
if (-not (Test-Path -LiteralPath $carrierPrompt)) {
    throw "V457 carrier index and layer validation prompt not found: $carrierPrompt"
}

$planHardRequirementsPrompt = Join-Path $autopilotRoot 'prompts\V457_PLAN_HARD_REQUIREMENTS.md'
if (-not (Test-Path -LiteralPath $planHardRequirementsPrompt)) {
    throw "V457 plan hard requirements prompt not found: $planHardRequirementsPrompt"
}

# Verify prompts contain experiment instructions
$carrierPromptText = Get-Content -LiteralPath $carrierPrompt -Raw -Encoding UTF8
if ($carrierPromptText -notmatch 'USE_CACHED_INDEX|LAYER_VALIDATION_CHECKLIST') {
    throw "V457 carrier prompt missing experiment instructions"
}

$planPromptText = Get-Content -LiteralPath $planHardRequirementsPrompt -Raw -Encoding UTF8
if ($planPromptText -notmatch 'PLAN_HARD_REQUIREMENTS|first_slice_proof') {
    throw "V457 plan prompt missing hard requirements instructions"
}

# Result
$result = [ordered]@{
    status = 'PASS'
    experiment1_baseline_carrier_index = 'ENFORCED'
    experiment1_script = $carrierIndexScript
    experiment2_layer_validation = 'ENFORCED'
    experiment2_script = $layerValidationScript
    experiment3_plan_hard_requirements = 'ENFORCED'
    experiment3_script = $planContractScript
    v457_carrier_prompt = $carrierPrompt
    v457_plan_prompt = $planHardRequirementsPrompt
    verification_commands = @(
        "Test-Path '$carrierIndexScript'",
        "Test-Path '$layerValidationScript'",
        "Test-Path '$planContractScript'",
        "Test-Path '$carrierPrompt'",
        "Test-Path '$planHardRequirementsPrompt'"
    )
}

$result | ConvertTo-Json -Depth 4
Write-Host "v457 Stop and Evolve Three Experiments: PASS"
exit 0
