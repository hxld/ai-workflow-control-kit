# layer_validation_gate.ps1
# Experiment 2 from NEXT_EXPERIMENT_PLAN.md: Service Layer Async Task Exception
# Enhanced to detect async task triggers, HIGH oracle weight, and baseline references

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$SelectedCarrier,

    [Parameter(Mandatory = $false)]
    [string]$SliceAuthorizationPath,

    [Parameter(Mandatory = $false)]
    [string]$OracleDiffAnalysisPath,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Find-AsyncTaskTrigger {
    <#
    .SYNOPSIS
    Detects if a carrier is triggered by an existing async task processor.

    .DESCRIPTION
    Searches for async task processor classes that reference the carrier.
    Returns the processor class name if found, $null otherwise.

    Common async task processors:
    - AiApplyClaimApiTaskProcessor
    - AiAutoClaimFlowService
    - AbstractFlowService
    - FlowTaskHandler
    #>
    param(
        [string]$Carrier,
        [string]$BasePath
    )

    Write-Host "INFO: Searching for async task trigger for $Carrier" -ForegroundColor Gray

    $worktreePath = $BasePath
    if (-not (Test-Path -LiteralPath $worktreePath)) {
        Write-Host "WARN: BasePath not found: $worktreePath" -ForegroundColor Yellow
        return $null
    }

    # Get carrier class name from file path
    $carrierClassName = [System.IO.Path]::GetFileNameWithoutExtension($Carrier)

    # Known async task processors that trigger Service layer carriers
    $knownAsyncProcessors = @(
        'AiApplyClaimApiTaskProcessor',
        'AiAutoClaimFlowService',
        'AbstractFlowService',
        'FlowTaskHandler',
        'AsyncTaskProcessor',
        'AbstractAsyncTaskProcessor'
    )

    # Search for references in async task processors
    foreach ($processor in $knownAsyncProcessors) {
        $processorPath = Get-ChildItem -LiteralPath $worktreePath -Recurse -Filter "$processor.java" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $processorPath) {
            $content = Get-Content -LiteralPath $processorPath.FullName -Raw -Encoding UTF8
            if ($content -match [regex]::Escape($carrierClassName)) {
                Write-Host "INFO: Found async task trigger: $processor" -ForegroundColor Green
                return $processor
            }
        }
    }

    # Fallback: Search for any file that references both the carrier and task processor patterns
    $searchPattern = "$carrierClassName.*(?:TaskProcessor|FlowService|AsyncTask)"
    $matchingFiles = Get-ChildItem -LiteralPath $worktreePath -Recurse -Filter "*.java" -ErrorAction SilentlyContinue |
        Where-Object {
            $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $null -ne $content -and $content -match $searchPattern
        }

    if ($null -ne $matchingFiles -and $matchingFiles.Count -gt 0) {
        $triggerFile = $matchingFiles | Select-Object -First 1
        $triggerProcessor = [System.IO.Path]::GetFileNameWithoutExtension($triggerFile.Name)
        Write-Host "INFO: Found async task trigger via pattern search: $triggerProcessor" -ForegroundColor Green
        return $triggerProcessor
    }

    Write-Host "INFO: No async task trigger found for $Carrier" -ForegroundColor Gray
    return $null
}

function Get-CarrierOracleWeight {
    <#
    .SYNOPSIS
    Gets oracle weight for a carrier from oracle diff analysis.

    .DESCRIPTION
    Reads oracle diff analysis to determine if the carrier has HIGH weight.
    Returns weight string (HIGH, MEDIUM, LOW, NONE) and addition count.
    #>
    param(
        [string]$Carrier,
        [string]$OracleDiffAnalysisPath
    )

    if ([string]::IsNullOrWhiteSpace($OracleDiffAnalysisPath) -or -not (Test-Path -LiteralPath $OracleDiffAnalysisPath)) {
        Write-Host "WARN: Oracle diff analysis not found at $OracleDiffAnalysisPath" -ForegroundColor Yellow
        return @{
            weight = 'NONE'
            additions = 0
        }
    }

    try {
        $oracleDiff = Get-Content -LiteralPath $OracleDiffAnalysisPath -Raw -Encoding UTF8 | ConvertFrom-Json

        if ($null -eq $oracleDiff.production_changes) {
            return @{
                weight = 'NONE'
                additions = 0
            }
        }

        # Find the carrier in oracle diff
        $carrierEntry = $oracleDiff.production_changes | Where-Object {
            $_.file -match [regex]::Escape($Carrier) -or $_.file -match [regex]::Escape([System.IO.Path]::GetFileName($Carrier))
        } | Select-Object -First 1

        if ($null -ne $carrierEntry) {
            $weight = if ($carrierEntry.weight) { $carrierEntry.weight } else { 'NONE' }
            $additions = if ($carrierEntry.additions) { $carrierEntry.additions } else { 0 }

            Write-Host "INFO: Oracle weight for $Carrier`: $weight ($additions additions)" -ForegroundColor Gray

            return @{
                weight = $weight
                additions = $additions
            }
        }

        return @{
            weight = 'NONE'
            additions = 0
        }
    } catch {
        Write-Host "ERROR: Failed to parse oracle diff analysis: $_" -ForegroundColor Red
        return @{
            weight = 'NONE'
            additions = 0
        }
    }
}

function Test-CarrierInBaseline {
    <#
    .SYNOPSIS
    Tests if a carrier is referenced by a baseline entry.

    .DESCRIPTION
    Checks if the carrier is referenced by any baseline entry class.
    Returns $true if referenced, $false otherwise.
    #>
    param(
        [string]$Carrier,
        [string]$BasePath
    )

    Write-Host "INFO: Checking if $Carrier is in baseline" -ForegroundColor Gray

    $worktreePath = $BasePath
    if (-not (Test-Path -LiteralPath $worktreePath)) {
        Write-Host "WARN: BasePath not found: $worktreePath" -ForegroundColor Yellow
        return $false
    }

    # Known baseline entry classes
    $baselineEntryPatterns = @(
        '.*Entry.*\.java',
        '.*Controller.*\.java',
        '.*Facade.*\.java',
        '.*Api.*\.java'
    )

    $carrierClassName = [System.IO.Path]::GetFileNameWithoutExtension($Carrier)

    foreach ($pattern in $baselineEntryPatterns) {
        $entryFiles = Get-ChildItem -LiteralPath $worktreePath -Recurse -Filter $pattern -ErrorAction SilentlyContinue
        foreach ($entryFile in $entryFiles) {
            $content = Get-Content -LiteralPath $entryFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($null -ne $content -and $content -match [regex]::Escape($carrierClassName)) {
                Write-Host "INFO: Carrier referenced by baseline entry: $($entryFile.Name)" -ForegroundColor Green
                return $true
            }
        }
    }

    Write-Host "INFO: Carrier not found in baseline entries" -ForegroundColor Gray
    return $false
}

function Get-ServiceLayerAllowlist {
    <#
    .SYNOPSIS
    Reads SERVICE_LAYER_ALLOWLIST.json from replay root if available.

    .DESCRIPTION
    This function checks for the presence of SERVICE_LAYER_ALLOWLIST.json in the replay root.
    If found, it returns the allowlist patterns for Service layer validation.

    Returns hashtable with:
    - exists: boolean indicating if allowlist file exists
    - patterns: array of allowed patterns
    - rationale: explanation for allowlist
    - source: source of allowlist (e.g., oracle_post_hoc_analysis)
    #>
    param([string]$ReplayRoot)

    $allowlistPath = Join-Path $ReplayRoot 'SERVICE_LAYER_ALLOWLIST.json'
    $result = @{
        exists = $false
        patterns = @()
        rationale = ''
        source = ''
        schema_version = 0
    }

    if (Test-Path -LiteralPath $allowlistPath) {
        try {
            $allowlist = Get-Content -LiteralPath $allowlistPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $result.exists = $true
            $result.patterns = @($allowlist.patterns)
            $result.rationale = $allowlist.rationale
            $result.source = $allowlist.source
            $result.schema_version = $allowlist.schema_version
        } catch {
            Write-Host "ERROR: Failed to parse SERVICE_LAYER_ALLOWLIST.json: $_" -ForegroundColor Red
        }
    }

    return $result
}

function Test-CarrierAllowlistMatch {
    <#
    .SYNOPSIS
    Tests if a selected carrier matches allowlist patterns.

    .DESCRIPTION
    Checks if the selected carrier matches any pattern in the Service layer allowlist.
    Returns boolean indicating match status.
    #>
    param(
        [string]$SelectedCarrier,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        # Convert glob-style pattern to regex
        $regexPattern = $pattern -replace '\*', '.*'
        if ($SelectedCarrier -match $regexPattern) {
            return @{
                matched = $true
                pattern = $pattern
            }
        }
    }

    return @{
        matched = $false
        pattern = $null
    }
}

function Invoke-LayerValidationGate {
    <#
    .SYNOPSIS
    Main function for layer validation gate processing.

    .DESCRIPTION
    Processes Service layer allowlist and validates carrier selection.
    Includes Service layer async task exception logic from Experiment 2.

    Service layer exception conditions:
    1. Carrier is triggered by existing async task processor
    2. Oracle analysis shows HIGH weight
    3. Carrier is referenced by baseline entry

    Writes result to LAYER_VALIDATION_RESULT.json.
    #>
    param(
        [string]$ReplayRoot,
        [string]$SelectedCarrier,
        [string]$OracleDiffAnalysisPath
    )

    Write-Host "INFO: Processing layer validation gate..." -ForegroundColor Cyan

    # Get allowlist
    $allowlist = Get-ServiceLayerAllowlist -ReplayRoot $ReplayRoot

    # Get carrier layer
    $layer = if ($SelectedCarrier -match 'Service') { 'Service' } elseif ($SelectedCarrier -match 'Facade|Controller') { 'Facade' } elseif ($SelectedCarrier -match 'Impl|Repository|Dao') { 'Repository' } else { 'Unknown' }

    # Initialize result
    $result = [ordered]@{
        stage = 'Layer_Validation_Gate'
        allowlist_available = $allowlist.exists
        selected_carrier = $SelectedCarrier
        carrier_layer = $layer
        validation_status = 'PASS'
        validation_reason = ''
        matched_pattern = $null
        schema_version = $allowlist.schema_version
        service_layer_exception = $false
        service_layer_exception_reason = ''
        trigger_processor = $null
        oracle_weight = 'NONE'
        oracle_additions = 0
        in_baseline = $false
        processed_at = (Get-Date).ToString('s')
    }

    # Check if carrier is in Service layer
    if ($layer -eq 'Service') {
        Write-Host "INFO: Service layer carrier detected" -ForegroundColor Yellow

        # Check for Service layer async task exception (Experiment 2)
        $worktree = Join-Path $ReplayRoot 'worktree'

        # 1. Check async task trigger
        $triggerProcessor = Find-AsyncTaskTrigger -Carrier $SelectedCarrier -BasePath $worktree

        # 2. Check oracle weight
        $oracleInfo = Get-CarrierOracleWeight -Carrier $SelectedCarrier -OracleDiffAnalysisPath $OracleDiffAnalysisPath

        # 3. Check baseline reference
        $inBaseline = Test-CarrierInBaseline -Carrier $SelectedCarrier -BasePath $worktree

        # Update result with exception info
        $result.trigger_processor = $triggerProcessor
        $result.oracle_weight = $oracleInfo.weight
        $result.oracle_additions = $oracleInfo.additions
        $result.in_baseline = $inBaseline

        # Service layer exception: all three conditions must be met
        $serviceLayerException = ($null -ne $triggerProcessor) -and ($oracleInfo.weight -eq 'HIGH') -and $inBaseline

        if ($serviceLayerException) {
            Write-Host "INFO: Service layer exception conditions met" -ForegroundColor Green
            Write-Host "  - Trigger processor: $triggerProcessor" -ForegroundColor Green
            Write-Host "  - Oracle weight: HIGH ($($oracleInfo.additions) additions)" -ForegroundColor Green
            Write-Host "  - In baseline: $inBaseline" -ForegroundColor Green

            $result.validation_status = 'PASS'
            $result.validation_reason = 'Service layer exception: async task triggered, HIGH oracle weight, in baseline'
            $result.service_layer_exception = $true
            $result.service_layer_exception_reason = 'All three conditions met: async trigger, HIGH weight, baseline reference'
            $result.layer_class = 'service_async_task_triggered'
        } else {
            Write-Host "WARN: Service layer exception conditions NOT met" -ForegroundColor Yellow
            Write-Host "  - Trigger processor: $(if ($triggerProcessor) { $triggerProcessor } else { 'NONE' })" -ForegroundColor Gray
            Write-Host "  - Oracle weight: $($oracleInfo.weight) ($($oracleInfo.additions) additions)" -ForegroundColor Gray
            Write-Host "  - In baseline: $inBaseline" -ForegroundColor Gray

            # Check allowlist as fallback
            if ($allowlist.exists) {
                $matchResult = Test-CarrierAllowlistMatch -SelectedCarrier $SelectedCarrier -Patterns $allowlist.patterns
                if ($matchResult.matched) {
                    Write-Host "INFO: Carrier matches allowlist pattern: $($matchResult.pattern)" -ForegroundColor Green
                    $result.validation_status = 'PASS'
                    $result.validation_reason = "Carrier matches allowlist pattern: $($matchResult.pattern)"
                    $result.matched_pattern = $matchResult.pattern
                } else {
                    Write-Host "WARN: Service layer carrier does not meet exception conditions or allowlist" -ForegroundColor Yellow
                    $result.validation_status = 'FAIL'
                    $result.validation_reason = 'Service layer carrier: no async trigger, no HIGH weight, not in baseline, no allowlist match'
                }
            } else {
                Write-Host "WARN: Service layer carrier with no allowlist" -ForegroundColor Yellow
                $result.validation_status = 'REVIEW'
                $result.validation_reason = 'Service layer carrier: requires allowlist or exception conditions'
            }
        }
    } else {
        # Non-Service layer: standard allowlist check
        if (-not $allowlist.exists) {
            Write-Host "INFO: No Service layer allowlist found, passing by default" -ForegroundColor Yellow
            $result.validation_reason = 'Non-Service layer carrier, no allowlist required'
        } else {
            Write-Host "INFO: Service layer allowlist found with $($allowlist.patterns.Count) patterns" -ForegroundColor Green

            # Test carrier against allowlist
            $matchResult = Test-CarrierAllowlistMatch -SelectedCarrier $SelectedCarrier -Patterns $allowlist.patterns

            if ($matchResult.matched) {
                Write-Host "INFO: Carrier '$SelectedCarrier' matches allowlist pattern '$($matchResult.pattern)'" -ForegroundColor Green
                $result.validation_status = 'PASS'
                $result.validation_reason = "Carrier matches oracle-derived allowlist pattern: $($matchResult.pattern)"
                $result.matched_pattern = $matchResult.pattern
            } else {
                Write-Host "INFO: Carrier '$SelectedCarrier' does not match allowlist (non-Service layer)" -ForegroundColor Gray
                $result.validation_reason = 'Non-Service layer carrier, allowlist not applicable'
            }
        }
    }

    # Write result
    $resultPath = Join-Path $ReplayRoot 'LAYER_VALIDATION_RESULT.json'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    Write-Host "Layer validation result written to $resultPath" -ForegroundColor Green
    return $result
}

function Update-SliceAuthorization {
    <#
    .SYNOPSIS
    Updates slice authorization with layer validation result.

    .DESCRIPTION
    If slice authorization file exists, updates it with layer validation status.
    #>
    param(
        [string]$ReplayRoot,
        [string]$SliceAuthorizationPath,
        [hashtable]$LayerValidationResult
    )

    if (-not [string]::IsNullOrWhiteSpace($SliceAuthorizationPath) -and (Test-Path -LiteralPath $SliceAuthorizationPath)) {
        Write-Host "INFO: Updating slice authorization with layer validation result" -ForegroundColor Cyan

        try {
            $auth = Get-Content -LiteralPath $SliceAuthorizationPath -Raw -Encoding UTF8 | ConvertFrom-Json

            # Add layer validation info
            $auth | Add-Member -Force -MemberType NoteProperty -Name 'layer_validation_status' -Value $LayerValidationResult.validation_status
            $auth | Add-Member -Force -MemberType NoteProperty -Name 'layer_validation_reason' -Value $LayerValidationResult.validation_reason

            # If layer validation passed, ensure authorization is granted
            if ($LayerValidationResult.validation_status -eq 'PASS') {
                if ($auth.authorization_status -eq 'BLOCKED') {
                    # Check if blocked only due to layer validation
                    $layerBlocker = $auth.blockers | Where-Object { $_.code -eq 'wrong_test_surface' } | Select-Object -First 1
                    if ($null -ne $layerBlocker -and $layerBlocker.reason -match 'Service layer') {
                        Write-Host "INFO: Overriding wrong_test_surface block due to allowlist match" -ForegroundColor Green
                        $auth.authorization_status = 'AUTHORIZED'
                        $auth.blockers = @($auth.blockers | Where-Object { $_.code -ne 'wrong_test_surface' })
                        $auth.layer_override_applied = $true
                    }
                }
            }

            # Write updated authorization
            $auth | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SliceAuthorizationPath -Encoding UTF8

            Write-Host "Slice authorization updated" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to update slice authorization: $_" -ForegroundColor Red
        }
    }
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Description = 'Experiment 2: Service Layer Async Task Exception'
        ValidationCommands = @(
            'Check SERVICE_LAYER_ALLOWLIST.json exists in replay root',
            'Detect async task trigger for Service layer carriers',
            'Get oracle weight (HIGH/MEDIUM/LOW/NONE) for carrier',
            'Check if carrier is referenced by baseline entry',
            'Apply Service layer exception if all 3 conditions met',
            'Write LAYER_VALIDATION_RESULT.json',
            'Update slice authorization if applicable'
        )
        ExpectedMetrics = @{
            wrong_test_surface_false_positives = '0 rounds'
            slices_reaching_red_phase = '≥1'
            preslice_authorization_pass_rate = '100% (for valid carriers)'
            service_layer_exception_rate = '>0% for Service layer carriers with async trigger + HIGH weight + baseline reference'
        }
    }
    $result | Format-List
    exit 0
}

# Main execution
$result = Invoke-LayerValidationGate -ReplayRoot $ReplayRoot -SelectedCarrier $SelectedCarrier -OracleDiffAnalysisPath $OracleDiffAnalysisPath

# Update slice authorization if provided
if (-not [string]::IsNullOrWhiteSpace($SliceAuthorizationPath)) {
    Update-SliceAuthorization -ReplayRoot $ReplayRoot -SliceAuthorizationPath $SliceAuthorizationPath -LayerValidationResult $result
}

exit 0
