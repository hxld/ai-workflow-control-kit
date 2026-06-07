# v466: First Slice Proof Schema and Family Layer Validation Test
param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$constraintCheckPath = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'

$cases = @()

# Verify the script exists
$cases += (Assert-True -Name 'constraint_check_script_exists' -Condition (Test-Path -LiteralPath $constraintCheckPath))

# Read script content
$constraintCheckContent = Get-Content -LiteralPath $constraintCheckPath
$constraintCheckText = $constraintCheckContent -join "`n"

# Verify v466 additions exist
$cases += (Assert-True -Name 'has_first_slice_proof_schema_check' -Condition ($constraintCheckText -match 'first_slice_proof_schema_valid'))
$cases += (Assert-True -Name 'has_minimum_side_effect_field_check' -Condition ($constraintCheckText -match 'minimum_side_effect_or_blocker'))
$cases += (Assert-True -Name 'has_family_layer_validation_check' -Condition ($constraintCheckText -match 'family_layer_validation'))
$cases += (Assert-True -Name 'checks_core_entry_family_requires_facade' -Condition ($constraintCheckText -match 'core_entry'))

# Verify required proof fields
$cases += (Assert-True -Name 'has_target_carrier_file_path_field' -Condition ($constraintCheckText -match 'target_carrier_file_path'))
$cases += (Assert-True -Name 'has_target_carrier_line_number_field' -Condition ($constraintCheckText -match 'target_carrier_line_number'))
$cases += (Assert-True -Name 'has_expected_test_class_field' -Condition ($constraintCheckText -match 'expected_test_class'))
$cases += (Assert-True -Name 'has_expected_test_method_field' -Condition ($constraintCheckText -match 'expected_test_method'))
$cases += (Assert-True -Name 'has_expected_assertions_field' -Condition ($constraintCheckText -match 'expected_assertions'))
$cases += (Assert-True -Name 'has_expected_side_effects_field' -Condition ($constraintCheckText -match 'expected_side_effects'))

# Verify script can be parsed without errors
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($constraintCheckText, [ref]$parseErrors)
$cases += (Assert-True -Name 'powershell_parse_success' -Condition ($parseErrors.Count -eq 0))

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = $cases
} | ConvertTo-Json -Depth 6
