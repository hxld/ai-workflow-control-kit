# Test-v340-ExecutableEvidenceExperiments.ps1
# Tests for v340 executable evidence experiments from NEXT_EXPERIMENT_PLAN.md
# - Experiment E1: Executable Evidence Gate (test execution, DB verification)
# - Experiment E2: TODO Penalty Enforcement
# - Experiment E3: Requirement Contract Validation (exact test names, assertion contracts)

param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        script = $PSCommandPath
        tests = @(
            'experiment_e1_executable_evidence_gate',
            'experiment_e2_todo_penalty_enforcement',
            'experiment_e3_requirement_contract_validation'
        )
    } | ConvertTo-Json -Depth 6
    exit 0
}

$cases = New-Object System.Collections.Generic.List[string]
$evidence = [ordered]@{}

# === Test E1: Executable Evidence Gate ===
Write-Host "Test E1: Executable Evidence Gate"

$e1Script = Join-Path $scriptRoot 'verifier\executable_evidence.py'
$e1Exists = Test-Path -LiteralPath $e1Script

if ($e1Exists) {
    # Check script content for required functions
    $e1Content = Get-Content -LiteralPath $e1Script -Raw -Encoding UTF8
    $hasValidate = $e1Content -match 'def validate_executable_evidence'
    $hasTestExecutionCheck = $e1Content -match 'tests_not_executed'
    $hasDbVerificationCheck = $e1Content -match 'no_db_state_verification'
    $hasTodoCheck = $e1Content -match 'todo_stub_present'

    if ($hasValidate -and $hasTestExecutionCheck -and $hasDbVerificationCheck -and $hasTodoCheck) {
        $cases.Add('experiment_e1_executable_evidence_gate') | Out-Null
        $evidence.experiment_e1 = 'PASS'
        Write-Host "  E1: PASS - Executable Evidence Gate script found with all required checks"
    } else {
        $evidence.experiment_e1 = 'FAIL'
        Write-Host "  E1: FAIL - Script exists but missing required functions"
        Write-Host "    validate_executable_evidence: $hasValidate"
        Write-Host "    tests_not_executed check: $hasTestExecutionCheck"
        Write-Host "    no_db_state_verification check: $hasDbVerificationCheck"
        Write-Host "    todo_stub_present check: $hasTodoCheck"
    }
} else {
    $evidence.experiment_e1 = 'FAIL'
    Write-Host "  E1: FAIL - Script not found at $e1Script"
}

# === Test E2: TODO Penalty Enforcement ===
Write-Host "`nTest E2: TODO Penalty Enforcement"

$e2Script = Join-Path $scriptRoot 'coverage\calculate_coverage.py'
$e2Exists = Test-Path -LiteralPath $e2Script

if ($e2Exists) {
    $e2Content = Get-Content -LiteralPath $e2Script -Raw -Encoding UTF8
    $hasTodoCount = $e2Content -match 'def calculate_todo_count'
    $hasCoveragePenalty = $e2Content -match 'def calculate_coverage_with_todo_penalty'
    $hasPenaltyCalculation = $e2Content -match 'penalty.*=.*min\('
    $hasOracleAdjusted = $e2Content -match 'def calculate_oracle_adjusted_coverage'

    if ($hasTodoCount -and $hasCoveragePenalty -and $hasPenaltyCalculation -and $hasOracleAdjusted) {
        $cases.Add('experiment_e2_todo_penalty_enforcement') | Out-Null
        $evidence.experiment_e2 = 'PASS'
        Write-Host "  E2: PASS - TODO Penalty Enforcement script found with all required functions"
    } else {
        $evidence.experiment_e2 = 'FAIL'
        Write-Host "  E2: FAIL - Script exists but missing required functions"
        Write-Host "    calculate_todo_count: $hasTodoCount"
        Write-Host "    calculate_coverage_with_todo_penalty: $hasCoveragePenalty"
        Write-Host "    penalty calculation: $hasPenaltyCalculation"
        Write-Host "    calculate_oracle_adjusted_coverage: $hasOracleAdjusted"
    }
} else {
    $evidence.experiment_e2 = 'FAIL'
    Write-Host "  E2: FAIL - Script not found at $e2Script"
}

# === Test E3: Requirement Contract Validation ===
Write-Host "`nTest E3: Requirement Contract Validation"

$e3Script = Join-Path $scriptRoot 'verifier\requirement_contract.py'
$e3Exists = Test-Path -LiteralPath $e3Script

if ($e3Exists) {
    $e3Content = Get-Content -LiteralPath $e3Script -Raw -Encoding UTF8
    $hasValidate = $e3Content -match 'def validate_requirement_contract_binding'
    $hasSemanticValidation = $e3Content -match 'def validate_plan_semantic_binding'
    $hasTestNameFormat = $e3Content -match 'def validate_test_name_format'
    $hasAssertionValidation = $e3Content -match 'def validate_assertion_contracts'
    $hasTestNamePattern = $e3Content -match 'TEST_NAME_PATTERN'

    if ($hasValidate -and $hasSemanticValidation -and $hasTestNameFormat -and $hasAssertionValidation -and $hasTestNamePattern) {
        $cases.Add('experiment_e3_requirement_contract_validation') | Out-Null
        $evidence.experiment_e3 = 'PASS'
        Write-Host "  E3: PASS - Requirement Contract Validation script found with all required functions"
    } else {
        $evidence.experiment_e3 = 'FAIL'
        Write-Host "  E3: FAIL - Script exists but missing required functions"
        Write-Host "    validate_requirement_contract_binding: $hasValidate"
        Write-Host "    validate_plan_semantic_binding: $hasSemanticValidation"
        Write-Host "    validate_test_name_format: $hasTestNameFormat"
        Write-Host "    validate_assertion_contracts: $hasAssertionValidation"
        Write-Host "    TEST_NAME_PATTERN: $hasTestNamePattern"
    }
} else {
    $evidence.experiment_e3 = 'FAIL'
    Write-Host "  E3: FAIL - Script not found at $e3Script"
}

# === Test E4: Integration into Runner ===
Write-Host "`nTest E4: Integration into Runner"

$v340IntegrationFound = $false
$v340IntegrationChecks = @(
    @{File='Validate-ExecutableEvidenceGate.ps1'; Pattern='v340 Experiments Integration'},
    @{File='Validate-ExecutableEvidenceGate.ps1'; Pattern='verifier\executable_evidence.py'},
    @{File='Validate-ExecutableEvidenceGate.ps1'; Pattern='coverage\calculate_coverage.py'},
    @{File='Run-ReplayLoop.ps1'; Pattern='Invoke-RequirementContractValidation.ps1'}
)

foreach ($check in $v340IntegrationChecks) {
    $filePath = Join-Path $scriptRoot $check.File
    if (Test-Path -LiteralPath $filePath) {
        $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        if ($content -match [regex]::Escape($check.Pattern)) {
            $v340IntegrationFound = $true
        } else {
            $v340IntegrationFound = $false
            Write-Host "  Integration pattern '$($check.Pattern)' not found in $($check.File)"
            break
        }
    } else {
        $v340IntegrationFound = $false
        Write-Host "  File $($check.File) not found"
        break
    }
}

if ($v340IntegrationFound) {
    $cases.Add('experiment_e4_runner_integration') | Out-Null
    $evidence.experiment_e4 = 'PASS'
    Write-Host "  E4: PASS - v340 experiments integrated into runner"
} else {
    $evidence.experiment_e4 = 'FAIL'
    Write-Host "  E4: FAIL - v340 experiments not fully integrated into runner"
}

# === Summary ===
$allPass = $cases.Count -ge 4 -and
           $evidence.experiment_e1 -eq 'PASS' -and
           $evidence.experiment_e2 -eq 'PASS' -and
           $evidence.experiment_e3 -eq 'PASS' -and
           $evidence.experiment_e4 -eq 'PASS'

$result = [ordered]@{
    status = if ($allPass) { 'PASS' } else { 'FAIL' }
    script = $PSCommandPath
    cases = @($cases)
    evidence = $evidence
    version = 'v340'
    evolution_type = 'executable_evidence_experiments'
    source_decision = 'v339-autopilot-r02_STOP_AND_EVOLVE'
}

Write-Host "`n=== Summary ==="
Write-Host "Status: $($result.status)"
Write-Host "Passed Cases: $($cases.Count)/4"
Write-Host "  - E1 (Executable Evidence): $($evidence.experiment_e1)"
Write-Host "  - E2 (TODO Penalty): $($evidence.experiment_e2)"
Write-Host "  - E3 (Requirement Contract): $($evidence.experiment_e3)"
Write-Host "  - E4 (Runner Integration): $($evidence.experiment_e4)"

$result | ConvertTo-Json -Depth 10

if (-not $allPass) {
    exit 1
}
