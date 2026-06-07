# Plan Schema Fail-Fast Checker (Experiment 3 from NEXT_EXPERIMENT_PLAN.md)
# Validates plan schema completeness and rejects plans with missing required fields

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$PlanResultPath = ''
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
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
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

$replayRootFull = Resolve-AbsolutePath $ReplayRoot

# Determine plan result path
if ([string]::IsNullOrWhiteSpace($PlanResultPath)) {
    $possiblePaths = @(
        (Join-Path $replayRootFull 'PLAN_RESULT.json'),
        (Join-Path $replayRootFull 'PLAN.json'),
        (Join-Path $replayRootFull 'REPLAY_PLAN.md')
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path -LiteralPath $path) {
            $PlanResultPath = $path
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($PlanResultPath) -or -not (Test-Path -LiteralPath $PlanResultPath)) {
    $result = [ordered]@{
        stage = 'PlanSchemaFailFast'
        status = 'FAIL'
        error = 'Plan file not found'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'PLAN_SCHEMA_FAILFAST.json') -Encoding UTF8
    exit 1
}

$plan = Read-JsonObject -Path $PlanResultPath

if ($null -eq $plan) {
    $result = [ordered]@{
        stage = 'PlanSchemaFailFast'
        status = 'FAIL'
        error = 'Plan is null or invalid JSON'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'PLAN_SCHEMA_FAILFAST.json') -Encoding UTF8
    exit 1
}

$missingFields = @()
$placeholderFields = @()
$emptyArrayFields = @()

$planStatus = ''
if ($plan.PSObject.Properties.Name -contains 'plan_status') {
    $planStatus = ([string]$plan.plan_status).Trim().ToUpperInvariant()
} elseif ($plan.PSObject.Properties.Name -contains 'status') {
    $planStatus = ([string]$plan.status).Trim().ToUpperInvariant()
}

if ([string]::IsNullOrWhiteSpace($planStatus)) {
    $missingFields += 'plan_status'
}

# Required fields with no placeholders allowed. PROCEED plans must be executable;
# blocked plans must explain the blocker instead of inventing carriers.
$requiredFields = [ordered]@{}
$arrayFields = @()
if ($planStatus -eq 'PROCEED') {
    $requiredFields = [ordered]@{
        'plan_status' = $true
        'target_carrier_file_path' = $true
        'target_carrier_line_number' = $true
        'expected_test_class' = $true
        'expected_test_method' = $true
        'side_effects' = $true
    }
    $arrayFields = @('side_effects', 'expected_assertions')
} elseif (@('BLOCKED', 'INVALID_PLAN') -contains $planStatus) {
    $requiredFields = [ordered]@{
        'plan_status' = $true
    }
    if ($planStatus -eq 'BLOCKED') {
        $requiredFields['blocker'] = $true
    } else {
        $requiredFields['invalid_reason'] = $true
    }
} elseif (-not [string]::IsNullOrWhiteSpace($planStatus)) {
    $missingFields += "valid_plan_status:$planStatus"
}

foreach ($field in $requiredFields.Keys) {
    if (-not $plan.PSObject.Properties.Name -contains $field) {
        $missingFields += $field
    } else {
        $value = $plan.$field
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace("$value")) {
            $missingFields += $field
        } elseif ($value -is [string] -and ($value -eq 'TBD' -or $value -eq 'NEW' -or $value -eq 'unknown' -or $value -eq 'UNKNOWN')) {
            $placeholderFields += "$field (value: $value)"
        }
    }
}

foreach ($field in $arrayFields) {
    if ($plan.PSObject.Properties.Name -contains $field) {
        $value = $plan.$field
        if ($null -ne $value -and $value -is [System.Array]) {
            if ($value.Count -eq 0) {
                $emptyArrayFields += $field
            }
        } elseif ($null -eq $value) {
            $emptyArrayFields += $field
        }
    }
}

$overallStatus = 'PASS'
$issues = @()

if ($missingFields.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Missing required fields: $($missingFields -join ', ')"
}

if ($placeholderFields.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Placeholder values found: $($placeholderFields -join ', ')"
}

if ($emptyArrayFields.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Empty arrays found: $($emptyArrayFields -join ', ')"
}

# Build result
$result = [ordered]@{
    stage = 'PlanSchemaFailFast'
    status = $overallStatus
    required = $true
    can_proceed = ($overallStatus -eq 'PASS')
    checks = [ordered]@{
        plan_status = $planStatus
        valid_plan_status = (@('PROCEED', 'BLOCKED', 'INVALID_PLAN') -contains $planStatus)
        all_required_fields_present = ($missingFields.Count -eq 0)
        missing_fields = @($missingFields)
        no_placeholder_values = ($placeholderFields.Count -eq 0)
        placeholder_fields = @($placeholderFields)
        required_arrays_populated = ($emptyArrayFields.Count -eq 0)
        empty_array_fields = @($emptyArrayFields)
    }
    issues = @($issues)
    timestamp = (Get-Date -Format 'o')
}

$outputPath = Join-Path $replayRootFull 'PLAN_SCHEMA_FAILFAST.json'
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

if ($overallStatus -ne 'PASS') {
    Write-Host "PLAN_SCHEMA_INCOMPLETE: $($issues -join '; ')" -ForegroundColor Red
    exit 1
}

Write-Host "PLAN_SCHEMA_COMPLETE: All required fields present with valid values" -ForegroundColor Green
exit 0
