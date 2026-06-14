# Invoke-EconomyCheckpoint.ps1
# Experiment 1 from NEXT_EXPERIMENT_PLAN.md: Discovery Mode Checkpoint System

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $true)]
    [string]$CheckpointId,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

# Checkpoint configuration from NEXT_EXPERIMENT_PLAN.md
$checkpointConfig = @{
    "CP1_CARRIER_SEARCH" = @{
        cost_tokens = 100
        required_pass = $true
        abort_on_fail = $true
        description = "Carrier search finds at least one valid carrier"
        validation_command = "Test-CarrierSearchResult"
    }
    "CP2_LAYER_VALIDATION" = @{
        cost_tokens = 500
        required_pass = $true
        abort_on_fail = $false  # Allow warnings for discovery mode
        description = "Layer validation passes or has recoverable warnings"
        discovery_mode = $true
        validation_command = "Test-LayerValidationResult"
    }
    "CP3_PLAN_GENERATION" = @{
        cost_tokens = 2000
        required_pass = $true
        abort_on_fail = $true
        description = "Plan generation with executable test path"
        validation_command = "Test-PlanGenerationResult"
    }
    "CP4_TEST_CHARTER" = @{
        cost_tokens = 5000
        required_pass = $true
        abort_on_fail = $true
        description = "Test charter with valid test surface"
        validation_command = "Test-TestCharterResult"
    }
    "CP5_IMPLEMENTATION" = @{
        cost_tokens = 10000
        required_pass = $true
        abort_on_fail = $false
        description = "Implementation start with RED phase"
        validation_command = "Test-ImplementationResult"
    }
}

function Test-CarrierSearchResult {
    param([string]$ReplayRoot)

    $carrierFile = Join-Path $ReplayRoot "CARRIER_SEARCH_RESULT.json"
    if (-not (Test-Path -LiteralPath $carrierFile)) {
        return @{
            passed = $false
            reason = "CARRIER_SEARCH_RESULT.json not found"
        }
    }

    $carrierResult = Get-Content -LiteralPath $carrierFile -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($null -eq $carrierResult.carriers -or $carrierResult.carriers.Count -eq 0) {
        return @{
            passed = $false
            reason = "No carriers found in search result"
        }
    }

    return @{
        passed = $true
        carrier_count = $carrierResult.carriers.Count
        reason = "Found $($carrierResult.carriers.Count) valid carrier(s)"
    }
}

function Test-LayerValidationResult {
    param([string]$ReplayRoot)

    $layerFile = Join-Path $ReplayRoot "LAYER_VALIDATION_RESULT.json"
    if (-not (Test-Path -LiteralPath $layerFile)) {
        return @{
            passed = $false
            reason = "LAYER_VALIDATION_RESULT.json not found"
        }
    }

    $layerResult = Get-Content -LiteralPath $layerFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $status = ''
    if ($layerResult.PSObject.Properties.Name -contains 'validation_status') {
        $status = [string]$layerResult.validation_status
    }
    if ([string]::IsNullOrWhiteSpace($status) -and $layerResult.PSObject.Properties.Name -contains 'verification_status') {
        $status = [string]$layerResult.verification_status
    }
    $normalizedStatus = $status.Trim().ToUpperInvariant()
    $canProceed = $layerResult.PSObject.Properties.Name -contains 'can_proceed' -and [bool]$layerResult.can_proceed

    # For discovery mode, WARN is acceptable
    if ($normalizedStatus -in @("PASS", "PASSED") -or ($canProceed -and [string]::IsNullOrWhiteSpace($normalizedStatus))) {
        return @{
            passed = $true
            status = if ([string]::IsNullOrWhiteSpace($normalizedStatus)) { "PASS" } else { $normalizedStatus }
            reason = "Layer validation passed"
        }
    }

    if ($normalizedStatus -eq "WARN" -or $normalizedStatus -eq "REVIEW") {
        return @{
            passed = $true
            status = $normalizedStatus
            reason = "Layer validation returned WARN - acceptable in discovery mode"
        }
    }

    return @{
        passed = $false
        status = $status
        reason = "Layer validation failed with status: $status"
    }
}

function Test-PlanGenerationResult {
    param([string]$ReplayRoot)

    $planFile = Join-Path $ReplayRoot "PLAN_CONTRACT_VERIFY.json"
    if (-not (Test-Path -LiteralPath $planFile)) {
        return @{
            passed = $false
            reason = "PLAN_CONTRACT_VERIFY.json not found"
        }
    }

    $planResult = Get-Content -LiteralPath $planFile -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($null -eq $planResult.executable_slices -or $planResult.executable_slices.Count -eq 0) {
        return @{
            passed = $false
            reason = "No executable slices in plan"
        }
    }

    return @{
        passed = $true
        slice_count = $planResult.executable_slices.Count
        reason = "Plan contains $($planResult.executable_slices.Count) executable slice(s)"
    }
}

function Get-LatestFileByPattern {
    param(
        [string]$Root,
        [string]$Pattern
    )

    $matches = @(Get-ChildItem -LiteralPath $Root -Filter $Pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime, Name -Descending)
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[0]
}

function Test-TestCharterResult {
    param([string]$ReplayRoot)

    $validationFile = Get-LatestFileByPattern -Root $ReplayRoot -Pattern "TEST_CHARTER_VALIDATION_*.json"
    if ($null -ne $validationFile) {
        $validation = Get-Content -LiteralPath $validationFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $status = [string]$validation.verification_status
        $canProceed = $validation.can_proceed -eq $true
        $statusPass = $status -in @('PASSED', 'PASS')

        if ($canProceed -and $statusPass) {
            return @{
                passed = $true
                validation_artifact = $validationFile.Name
                verification_status = $status
                warning_count = $validation.warning_count
                reason = "Test charter prevalidation passed via $($validationFile.Name)"
            }
        }

        $failureSummary = ''
        if ($null -ne $validation.failures) {
            $failureSummary = (@($validation.failures) | ForEach-Object {
                if ($null -ne $_.code) { [string]$_.code } else { ($_ | ConvertTo-Json -Depth 6 -Compress) }
            }) -join ', '
        }
        if ([string]::IsNullOrWhiteSpace($failureSummary)) {
            $failureSummary = "status=$status can_proceed=$canProceed"
        }
        return @{
            passed = $false
            validation_artifact = $validationFile.Name
            verification_status = $status
            reason = "Test charter prevalidation failed via $($validationFile.Name): $failureSummary"
        }
    }

    $charterFile = Join-Path $ReplayRoot "TEST_CHARTER.json"
    if (Test-Path -LiteralPath $charterFile) {
        $charter = Get-Content -LiteralPath $charterFile -Raw -Encoding UTF8 | ConvertFrom-Json

        if ($null -eq $charter.test_surface -or [string]::IsNullOrWhiteSpace($charter.test_surface)) {
            return @{
                passed = $false
                reason = "Test charter missing test_surface"
            }
        }

        return @{
            passed = $true
            test_surface = $charter.test_surface
            reason = "Test charter has valid test_surface: $($charter.test_surface)"
        }
    }

    $charterMarkdown = Join-Path $ReplayRoot "TEST_CHARTER.md"
    if (Test-Path -LiteralPath $charterMarkdown) {
        $content = Get-Content -LiteralPath $charterMarkdown -Raw -Encoding UTF8
        $hasTestClass = $content -match '(?im)^\s*##\s+Test Class\b'
        $hasEntryPoint = $content -match '(?im)^\s*##\s+Entry Point\b'
        if ($hasTestClass -and $hasEntryPoint) {
            return @{
                passed = $true
                charter_artifact = "TEST_CHARTER.md"
                reason = "TEST_CHARTER.md has test class and entry point"
            }
        }

        return @{
            passed = $false
            charter_artifact = "TEST_CHARTER.md"
            reason = "TEST_CHARTER.md missing test class or entry point"
        }
    }

    return @{
        passed = $false
        reason = "No TEST_CHARTER_VALIDATION_*.json, TEST_CHARTER.json, or TEST_CHARTER.md found"
    }
}

function Test-ImplementationResult {
    param([string]$ReplayRoot)

    $sliceResult = Get-ChildItem -LiteralPath $ReplayRoot -Filter "SLICE_RESULT_*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $sliceResult) {
        return @{
            passed = $false
            reason = "No SLICE_RESULT_*.json found"
        }
    }

    $slice = Get-Content -LiteralPath $sliceResult.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $tests = @($slice.tests)

    $redTest = $tests | Where-Object { $_.phase -eq "RED" } | Select-Object -First 1
    if ($null -eq $redTest) {
        return @{
            passed = $false
            reason = "RED phase not found in slice result"
        }
    }

    if ($redTest.result -match "compil|error") {
        return @{
            passed = $false
            reason = "RED phase blocked by compilation error"
        }
    }

    return @{
        passed = $true
        red_result = $redTest.result
        reason = "RED phase executed with result: $($redTest.result)"
    }
}

function Invoke-CheckpointValidation {
    param(
        [string]$ReplayRoot,
        [hashtable]$Config
    )

    Write-Host "INFO: Running checkpoint: $($Config.description)" -ForegroundColor Cyan

    $validationCommand = $Config.validation_command

    # Dispatch to appropriate validation function
    $validationResult = & $validationCommand -ReplayRoot $ReplayRoot

    $result = [ordered]@{
        checkpoint_id = $CheckpointId
        description = $Config.description
        cost_tokens = $Config.cost_tokens
        required_pass = $Config.required_pass
        abort_on_fail = $Config.abort_on_fail
        discovery_mode = $Config.discovery_mode -eq $true
        validation_passed = $validationResult.passed
        validation_reason = $validationResult.reason
        can_proceed = $validationResult.passed -or (-not $Config.required_pass)
        should_abort = (-not $validationResult.passed) -and $Config.abort_on_fail
        validated_at = (Get-Date).ToString('s')
    }

    # Add additional fields from validation result
    foreach ($key in $validationResult.Keys) {
        if ($key -notin @('passed', 'reason')) {
            $result[$key] = $validationResult[$key]
        }
    }

    return $result
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Description = 'Experiment 1: Discovery Mode Checkpoint System'
        Checkpoints = @($checkpointConfig.Keys)
        ValidationCommands = @(
            'Test-CarrierSearchResult: Validates carrier search found valid carriers',
            'Test-LayerValidationResult: Validates layer status (PASS or WARN in discovery mode)',
            'Test-PlanGenerationResult: Validates plan has executable slices',
            'Test-TestCharterResult: Validates modern TEST_CHARTER_VALIDATION_*.json or legacy charter artifacts',
            'Test-ImplementationResult: Validates RED phase executed without compilation errors'
        )
        ExpectedMetrics = @{
            coverage_delta = '≥30% for S1 with discovery mode'
            slice_unblock_rate = '≥80% for S1'
            rounds_to_progress = '≤1 (S1 completes)'
        }
    }
    $result | ConvertTo-Json -Depth 10
    exit 0
}

# Main execution
if (-not $checkpointConfig.ContainsKey($CheckpointId)) {
    Write-Host "ERROR: Unknown checkpoint ID: $CheckpointId" -ForegroundColor Red
    Write-Host "Available checkpoints: $($checkpointConfig.Keys -join ', ')" -ForegroundColor Yellow
    exit 1
}

$checkpoint = $checkpointConfig[$CheckpointId]
$result = Invoke-CheckpointValidation -ReplayRoot $ReplayRoot -Config $checkpoint

# Write result to checkpoint file
$checkpointResultPath = Join-Path $ReplayRoot "CHECKPOINT_$($CheckpointId).json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $checkpointResultPath -Encoding UTF8

Write-Host "Checkpoint result written to $checkpointResultPath" -ForegroundColor Green

if ($result.should_abort) {
    Write-Host "Checkpoint failed with abort_on_fail=true" -ForegroundColor Red
    Write-Host "Reason: $($result.validation_reason)" -ForegroundColor Red
    exit 1
}

if (-not $result.can_proceed) {
    Write-Host "Checkpoint failed but abort not required" -ForegroundColor Yellow
    Write-Host "Reason: $($result.validation_reason)" -ForegroundColor Yellow
    exit 0
}

Write-Host "Checkpoint PASSED: $($CheckpointId)" -ForegroundColor Green
exit 0
