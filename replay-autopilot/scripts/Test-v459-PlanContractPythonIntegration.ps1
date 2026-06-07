$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'

# Verify plan_contract_verify.py is actually invoked by the runner
$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8

# Check 1: Runner contains plan_contract_verify.py reference
Assert-True ($runLoopText -match 'plan_contract_verify\.py') 'Run-ReplayLoop.ps1 must invoke plan_contract_verify.py'

# Check 2: Python invocation uses correct parameters
Assert-True ($runLoopText -match '--enable_carrier_verify') 'plan_contract_verify.py must be called with --enable_carrier_verify'
Assert-True ($runLoopText -match '--enable_exact_contract_verify') 'plan_contract_verify.py must be called with --enable_exact_contract_verify'

# Check 3: Verify the script exists
$pythonScriptPath = Join-Path $scriptRoot 'plan_contract_verify.py'
Assert-True (Test-Path -LiteralPath $pythonScriptPath) 'plan_contract_verify.py must exist'

# Check 4: Verify the Python script has V457 verification function
$pythonScriptText = Get-Content -LiteralPath $pythonScriptPath -Raw -Encoding UTF8
Assert-True ($pythonScriptText -match 'verify_first_slice_proof_v457') 'plan_contract_verify.py must have verify_first_slice_proof_v457 function'
Assert-True ($pythonScriptText -match 'layer_validation_failed:core_entry_requires_facade_controller') 'plan_contract_verify.py must check layer validation for core_entry'

# Check 5: Verify Verify-PlanContract.ps1 has layer validation
$verifyPlanPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$verifyPlanText = Get-Content -LiteralPath $verifyPlanPath -Raw -Encoding UTF8
Assert-True ($verifyPlanText -match 'layer_validation_failed:core_entry_requires_facade_controller_no_facade_found') 'Verify-PlanContract.ps1 must check core_entry layer validation'

Write-Host 'v459 PlanContractPythonIntegration tests passed'
