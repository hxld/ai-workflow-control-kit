# Pre-Execution Constraint Check (v466 enhanced)
# This script validates all constraints before Phase1 executor starts

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$PlanResultPath,
    [string]$BaselineRoot = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $content = Get-Content -LiteralPath $Path
    $text = $content -join "`n"
    try {
        return $text | ConvertFrom-Json
    } catch {
        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        if ($start -ge 0 -and $end -gt $start) {
            return $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
        }
        throw
    }
}

function Test-CarrierInBaseline {
    param(
        [string]$Carrier,
        [string]$Worktree,
        [string]$BaselineRoot
    )
    if ([string]::IsNullOrWhiteSpace($Carrier)) {
        return @{ Exists = $false; Reason = 'Carrier is empty or null' }
    }

    # Extract simple class name from full qualified name or method signature
    $simpleName = $Carrier -replace '.*\.([^\.]+)\..*$', '$1'
    $simpleName = $simpleName -replace '\(.*$', ''

    # Search in worktree first
    $rgResult = rg "--type=java" "--files-matching-match" $simpleName $Worktree 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rgResult)) {
        return @{ Exists = $true; Path = $rgResult; Reason = $null }
    }

    # Search in baseline if provided
    if (-not [string]::IsNullOrWhiteSpace($BaselineRoot) -and (Test-Path -LiteralPath $BaselineRoot)) {
        $rgResult = rg "--type=java" "--files-matching-match" $simpleName $BaselineRoot 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rgResult)) {
            return @{ Exists = $true; Path = $rgResult; Reason = $null }
        }
    }

    return @{ Exists = $false; Reason = "Carrier '$Carrier' not found in baseline or worktree" }
}

function Test-ValidLayer {
    param([string]$Carrier, [string]$Worktree)

    if ([string]::IsNullOrWhiteSpace($Carrier)) {
        return @{ Valid = $false; Layer = 'Unknown'; Reason = 'Carrier is empty' }
    }

    # Extract class name
    $className = $Carrier -replace '.*\.([^\.]+)$', '$1'
    $className = $className -replace '\(.*$', ''

    # Check layer based on naming pattern
    if ($className -match 'Facade$|FacadeImpl$') {
        return @{ Valid = $true; Layer = 'Facade'; Reason = $null }
    }
    if ($className -match 'Controller$|ApiController$|RestController$') {
        return @{ Valid = $true; Layer = 'Controller'; Reason = $null }
    }
    if ($className -match 'Service$') {
        return @{ Valid = $false; Layer = 'Service'; Reason = 'Service layer not valid for core_entry without existing entry point' }
    }
    if ($className -match 'TaskProcessor$|Task$') {
        return @{ Valid = $false; Layer = 'Task'; Reason = 'Task layer not valid for core_entry' }
    }

    # Try to find file and check package
    $filePath = rg "--type=java" "-l" "-g" "*$className.java" $Worktree 2>$null | Select-Object -First 1
    if ($filePath) {
        $content = Get-Content -LiteralPath $filePath
        $contentText = $content -join "`n"
        if ($contentText -match '\s+(public|protected|private)\s+(abstract\s+)?(class|interface)\s+') {
            return @{ Valid = $false; Layer = 'Unknown'; Reason = 'Could not determine layer from naming pattern' }
        }
    }

    return @{ Valid = $false; Layer = 'Unknown'; Reason = 'Layer detection failed' }
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$planResultFull = Resolve-AbsolutePath $PlanResultPath

# Load plan result
$plan = Read-JsonObject -Path $planResultFull

if ($null -eq $plan) {
    $result = [ordered]@{
        stage = 'PreExecutionConstraintCheck'
        status = 'FAIL'
        required = $true
        checks = @()
        error = 'PLAN_RESULT not found or invalid'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'PRE_EXECUTION_CONSTRAINT_CHECK.json')
    exit 1
}

$checks = @()
$overallStatus = 'PASS'

# Check 1: Carrier exists in baseline
$selectedCarrier = if ($plan.PSObject.Properties.Name -contains 'selected_carrier') { $plan.selected_carrier } elseif ($plan.PSObject.Properties.Name -contains 'target_carrier') { $plan.target_carrier } else { $null }
$carrierExists = Test-CarrierInBaseline -Carrier $selectedCarrier -Worktree $worktreeFull -BaselineRoot $BaselineRoot

$checks += [ordered]@{
    name = 'carrier_exists_in_baseline'
    status = if ($carrierExists.Exists) { 'PASS' } else { 'FAIL' }
    carrier = $selectedCarrier
    reason = if ($carrierExists.Exists) { $null } else { $carrierExists.Reason }
}

if (-not $carrierExists.Exists) {
    $overallStatus = 'FAIL'
}

# Check 2: Carrier in valid layer
$layerValid = Test-ValidLayer -Carrier $selectedCarrier -Worktree $worktreeFull

$checks += [ordered]@{
    name = 'carrier_in_valid_layer'
    status = if ($layerValid.Valid) { 'PASS' } else { 'FAIL' }
    layer = $layerValid.Layer
    reason = if ($layerValid.Valid) { $null } else { $layerValid.Reason }
}

if (-not $layerValid.Valid) {
    $overallStatus = 'FAIL'
}

# Check 3: Plan schema is complete
$requiredFields = @('target_carrier_file_path', 'expected_test_class', 'side_effects')
$missingFields = @()

foreach ($field in $requiredFields) {
    if (-not $plan.PSObject.Properties.Name -contains $field) {
        $missingFields += $field
    } elseif ([string]::IsNullOrWhiteSpace($plan.$field) -or $plan.$field -eq 'TBD' -or $plan.$field -eq 'NEW') {
        $missingFields += "$field (value: $($plan.$field))"
    }
}

$checks += [ordered]@{
    name = 'plan_schema_complete'
    status = if ($missingFields.Count -eq 0) { 'PASS' } else { 'FAIL' }
    required_fields = $requiredFields
    missing_fields = $missingFields
}

if ($missingFields.Count -gt 0) {
    $overallStatus = 'FAIL'
}

# Check 4: TEST_CHARTER.md exists and is valid
$testCharterPath = Join-Path $replayRootFull 'TEST_CHARTER.md'
$testCharterExists = Test-Path -LiteralPath $testCharterPath

if ($testCharterExists) {
    $testCharterContent = Get-Content -LiteralPath $testCharterPath
    $testCharterText = $testCharterContent -join "`n"
    $hasTestSurface = $testCharterText -match 'test_surface|entry_point|test_method'
} else {
    $hasTestSurface = $false
    $testCharterText = ''
}

$checks += [ordered]@{
    name = 'test_charter_valid'
    status = if ($testCharterExists -and $hasTestSurface) { 'PASS' } else { 'FAIL' }
    test_charter_exists = $testCharterExists
    has_test_surface = $hasTestSurface
}

if (-not ($testCharterExists -and $hasTestSurface)) {
    $overallStatus = 'FAIL'
}

# Check 5: FIRST_SLICE_PROOF_PLAN.md schema validation (v466)
$firstSliceProofPath = Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md'
$firstSliceProofExists = Test-Path -LiteralPath $firstSliceProofPath
$firstSliceProofSchemaValid = $false
$firstSliceProofMissingFields = @()

if ($firstSliceProofExists) {
    $firstSliceProofContentArray = Get-Content -LiteralPath $firstSliceProofPath
    $firstSliceProofContent = $firstSliceProofContentArray -join "`n"

    # Required fields for V457 schema
    $requiredProofFields = @(
        'target_carrier_file_path',
        'target_carrier_line_number',
        'expected_test_class',
        'expected_test_method',
        'expected_assertions',
        'expected_side_effects',
        'minimum_side_effect_or_blocker'
    )

    foreach ($field in $requiredProofFields) {
        # Build pattern without using $ in string to avoid encoding issues
        $patternStart = '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?'
        $patternEnd = '\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
        $fullPattern = $patternStart + [regex]::Escape($field) + $patternEnd
        $match = [regex]::Match($firstSliceProofContent, $fullPattern)

        if (-not $match.Success) {
            $firstSliceProofMissingFields += $field
        } else {
            $value = $match.Groups[1].Value.Trim()
            # Check for placeholder values
            if ($value -match '^(TBD|unknown|UNKNOWN|N/A|placeholder|NONE|none)$') {
                $firstSliceProofMissingFields += "$field (placeholder: $value)"
            }
            # Special check for minimum_side_effect_or_blocker
            if ($field -eq 'minimum_side_effect_or_blocker' -and $value -eq 'PLAN_BLOCKED_REAL_CARRIER') {
                # This is valid blocker value, don't fail
            } elseif ($field -eq 'expected_assertions' -or $field -eq 'expected_side_effects') {
                # Check for JSON array format with minimum items
                try {
                    $arrayValue = $value | ConvertFrom-Json
                    $minItems = if ($field -eq 'expected_assertions') { 3 } else { 1 }
                    if ($arrayValue.Count -lt $minItems) {
                        $firstSliceProofMissingFields += "$field (insufficient items: $($arrayValue.Count)/$minItems)"
                    }
                } catch {
                    $firstSliceProofMissingFields += "$field (invalid JSON format)"
                }
            }
        }
    }

    $firstSliceProofSchemaValid = ($firstSliceProofMissingFields.Count -eq 0)
}

$checks += [ordered]@{
    name = 'first_slice_proof_schema_valid'
    status = if ($firstSliceProofExists -and $firstSliceProofSchemaValid) { 'PASS' } else { 'FAIL' }
    first_slice_proof_exists = $firstSliceProofExists
    schema_valid = $firstSliceProofSchemaValid
    missing_fields = $firstSliceProofMissingFields
}

if (-not ($firstSliceProofExists -and $firstSliceProofSchemaValid)) {
    $overallStatus = 'FAIL'
}

# Check 6: Family-specific layer validation (v466)
# core_entry family requires Facade or Controller layer, not Service
$combinedArtifacts = "$firstSliceProofContent $testCharterContent"
$highestWeightGatePattern = '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?highest_weight_open_gate\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
$highestWeightGateMatch = [regex]::Match($combinedArtifacts, $highestWeightGatePattern)

$isCoreEntryFamily = $false
if ($highestWeightGateMatch.Success) {
    $highestWeightGate = $highestWeightGateMatch.Groups[1].Value.Trim()
    $isCoreEntryFamily = $highestWeightGate -match 'core_entry'
}

$familyLayerValid = $true
$familyLayerReason = $null

if ($isCoreEntryFamily) {
    # Check if selected carrier is Service layer
    $selectedCarrierPattern = '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:selected_carrier|selected_real_entry)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
    $selectedCarrierMatch = [regex]::Match($combinedArtifacts, $selectedCarrierPattern)

    if ($selectedCarrierMatch.Success) {
        $carrierForLayerCheck = $selectedCarrierMatch.Groups[1].Value.Trim()
        # Extract actual carrier name before any parenthetical notes
        $actualCarrier = $carrierForLayerCheck.Split('(')[0].Trim()

        # Check if it's Service layer without Facade/Controller
        if ($actualCarrier -match 'Service$' -and $actualCarrier -notmatch 'Facade|Controller') {
            $familyLayerValid = $false
            $familyLayerReason = "core_entry family requires Facade/Controller layer, but selected carrier '$actualCarrier' is in Service layer"
        }
    }
}

$checks += [ordered]@{
    name = 'family_layer_validation'
    status = if ($familyLayerValid) { 'PASS' } else { 'FAIL' }
    is_core_entry_family = $isCoreEntryFamily
    layer_valid = $familyLayerValid
    reason = $familyLayerReason
}

if (-not $familyLayerValid) {
    $overallStatus = 'FAIL'
}

# Build result
$result = [ordered]@{
    stage = 'PreExecutionConstraintCheck'
    status = $overallStatus
    required = $true
    can_proceed_to_phase1 = ($overallStatus -eq 'PASS')
    checks = $checks
    selected_carrier = $selectedCarrier
    timestamp = (Get-Date -Format 'o')
}

$outputPath = Join-Path $replayRootFull 'PRE_EXECUTION_CONSTRAINT_CHECK.json'
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

if ($overallStatus -ne 'PASS') {
    Write-Host "PRE_EXECUTION_CONSTRAINT_FAIL: $($checks.Where({$_.status -eq 'FAIL'}).Count -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "PRE_EXECUTION_CONSTRAINT_PASS: All constraints satisfied" -ForegroundColor Green
exit 0
