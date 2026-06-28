param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [int]$SliceIndex,
    [string]$ForcedRequirementFamily = '',
    [string]$ForcedSliceType = '',
    [string]$ForcedSiblingSurface = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [string]$Object.$Name
    }
    return ''
}

function Get-BoolValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [bool]$Object.$Name
    }
    return $false
}

function Get-FamilyCarrierFromRank {
    param($CarrierRank, [string]$FamilyId)
    if ($null -eq $CarrierRank -or [string]::IsNullOrWhiteSpace($FamilyId) -or $null -eq $CarrierRank.families) {
        return ''
    }
    $row = @($CarrierRank.families | Where-Object { [string]$_.family -eq $FamilyId } | Select-Object -First 1)
    if ($row.Count -eq 0) { return '' }
    return [string]$row[0].production_carrier
}

function Test-SourceChainAppliesForSlice {
    param(
        $SourceChain,
        [string]$ForcedRequirementFamily,
        [string]$ForcedSliceType,
        [string]$ForcedSiblingSurface,
        [string]$EntryCall,
        [string]$CarrierText = ''
    )

    if ($null -eq $SourceChain -or -not [bool]$SourceChain.required_source_chain -or $null -eq $SourceChain.next_required_slice) {
        return $false
    }
    if ([string]$ForcedSliceType -ne 'exact_contract_slice') {
        return $false
    }
    if ([string]$ForcedRequirementFamily -eq 'core_entry' -or [string]$ForcedRequirementFamily -eq 'source_chain') {
        return $true
    }

    $sourceCarrier = Get-StringValue $SourceChain.next_required_slice 'carrier'
    $sourceEntry = Get-StringValue $SourceChain.next_required_slice 'entry'
    $currentText = @($ForcedSiblingSurface, $EntryCall, $CarrierText) -join ' '
    if (-not [string]::IsNullOrWhiteSpace($sourceCarrier) -and [string]$ForcedSiblingSurface -eq $sourceCarrier) {
        return $true
    }
    if ($currentText -match '(?i)\b(rebuildTaskData|RequestBuildContext|BaseRequest|source_chain|source field|wire field|input_data)\b') {
        return $true
    }
    if (-not [string]::IsNullOrWhiteSpace($sourceEntry) -and $currentText -match [regex]::Escape($sourceEntry)) {
        return $true
    }
    return $false
}

function Test-InvalidAuthorizationFieldValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return $Value -match '(?i)^\s*(planned|pending|not_required|not required|tbd|todo|n/a|null)\s*$'
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-PlanField {
    param([string]$Text, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $escaped = [regex]::Escape($Name)
    $lines = @($Text -split "\r?\n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ($line -match "^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?$escaped\s*\*{0,2}\s*:\s*`?([^`\r\n]*)`?\s*$") {
            $value = $matches[1].Trim().Trim('`').Trim()
            if ([string]::IsNullOrWhiteSpace($value)) {
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    $next = [string]$lines[$j]
                    if ([string]::IsNullOrWhiteSpace($next)) { continue }
                    if ($next -match '^\s*:\s*`?([^`\r\n]+)`?\s*$') {
                        $value = $matches[1].Trim().Trim('`').Trim()
                    }
                    break
                }
            }
            return $value.TrimEnd('.').Trim()
        }
    }
    return ''
}

function Get-PlanNewServiceWhitelist {
    <#
    .SYNOPSIS
    Extract NEW_SERVICE_WHITELIST from plan text.

    .DESCRIPTION
    Parses plan markdown for expected new services that should bypass
    carrier rank checks during creation. Format:

    ## NEW_SERVICE_WHITELIST
    - AiAutoClaimFlowService
    - AiNewServiceProcessor

    Returns array of service name strings.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $whitelist = @()
    $inWhitelistSection = $false
    $lines = @($Text -split "\r?\n")

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        # Detect section header
        if ($trimmed -match '^#+\s*NEW_SERVICE_WHITELIST\s*:?') {
            $inWhitelistSection = $true
            continue
        }
        # Exit section on next header
        if ($inWhitelistSection -and $trimmed -match '^#+\s*\w+') {
            break
        }
        # Parse list items
        if ($inWhitelistSection -and $trimmed -match '^[-*]\s*(.+)$') {
            $serviceName = $matches[1].Trim().Trim('`').Trim()
            if (-not [string]::IsNullOrWhiteSpace($serviceName)) {
                $whitelist += $serviceName
            }
        }
    }
    return $whitelist
}

function Extract-LayerFromCarrier {
    <#
    .SYNOPSIS
    Extract the architectural layer from a carrier name.

    .DESCRIPTION
    Analyzes carrier suffix to determine layer:
    - Facade, Controller, Api -> Facade/Controller layer (real entry)
    - Service, Task -> Service layer (internal)
    - Mapper, Dao -> Data layer

    .PARAMETER CarrierName
    The carrier class name to analyze.

    .RETURNS
    The layer name: "Facade", "Controller", "Api", "Service", "Mapper", or "Unknown".
    #>
    param([string]$CarrierName)
    if ([string]::IsNullOrWhiteSpace($CarrierName)) { return 'Unknown' }

    $carrierHead = (($CarrierName -split '\s*->\s*')[0]).Trim()
    $className = (($carrierHead -split '[.#:]')[0]).Trim()
    if ([string]::IsNullOrWhiteSpace($className)) { $className = $carrierHead }

    if ($className -match 'Facade(?:Impl)?$') { return 'Facade' }
    if ($className -match 'Controller(?:Impl)?$') { return 'Controller' }
    if ($className -match 'Api$') { return 'Api' }
    if ($className -match 'Service(?:Impl)?$') { return 'Service' }
    if ($className -match '(?i)TaskProcessor|Task$|Processor$' -or $carrierHead -match '(?i)\brebuildTaskData\b') { return 'Service' }
    if ($className -match 'Mapper$|Dao$') { return 'Mapper' }

    return 'Unknown'
}

function Get-OracleProductionRows {
    param([string]$ReplayRoot)

    $oracle = Read-JsonIfExists (Join-Path $ReplayRoot 'ORACLE_DIFF_ANALYSIS.json')
    if ($null -eq $oracle) { return @() }

    $rows = @()
    if ($null -ne $oracle.files) {
        $rows = @($oracle.files)
    } elseif ($null -ne $oracle.production_changes) {
        $rows = @($oracle.production_changes)
    }

    return @($rows | Where-Object {
        $path = if ($_.PSObject.Properties.Name -contains 'path') { [string]$_.path } else { [string]$_.file }
        $isProduction = if ($_.PSObject.Properties.Name -contains 'is_production') { [bool]$_.is_production } else { ($path -match '/src/main/java/|\\src\\main\\java\\') }
        $isProduction -and -not [string]::IsNullOrWhiteSpace($path)
    })
}

function Get-OracleFilePath {
    param($Row)
    if ($null -eq $Row) { return '' }
    if ($Row.PSObject.Properties.Name -contains 'path') { return [string]$Row.path }
    if ($Row.PSObject.Properties.Name -contains 'file') { return [string]$Row.file }
    return ''
}

function Get-BackendCarrierClassCandidates {
    param([string[]]$Texts)

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($text in @($Texts)) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        foreach ($match in [regex]::Matches([string]$text, '(?i)\b([A-Za-z_][A-Za-z0-9_]*(?:TaskProcessor|Processor|Service|Task))\b')) {
            $candidate = [string]$match.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidates.Contains($candidate)) {
                $candidates.Add($candidate) | Out-Null
            }
        }

        $carrierHead = (([string]$text -split '\s*->\s*')[0]).Trim()
        foreach ($token in @($carrierHead -split '[\s,#:(]+')) {
            if ([string]::IsNullOrWhiteSpace($token)) { continue }
            $leaf = @($token -split '\.')[-1]
            if ($leaf -match '(?i)(TaskProcessor|Processor|Service|Task)$' -and -not $candidates.Contains($leaf)) {
                $candidates.Add($leaf) | Out-Null
            }
        }
    }

    return @($candidates)
}

function Test-BackendTaskProcessorOracleReplay {
    <#
    .SYNOPSIS
    Allows backend-only executable replay when the archived oracle proves the
    actual high-weight production boundary is TaskProcessor/Service code.
    #>
    param(
        [string]$ReplayRoot,
        [string]$TargetCarrier,
        [string]$EntryCall = '',
        [string]$ForcedRequirementFamily = '',
        [string]$AdditionalEvidenceText = ''
    )

    if (@('deploy_export_page', 'generated_artifact_template_upload', 'external_integration', 'automation_test_interface') -contains $ForcedRequirementFamily) {
        return $false
    }

    $productionRows = @(Get-OracleProductionRows -ReplayRoot $ReplayRoot)
    if ($productionRows.Count -eq 0) {
        $evidenceText = @($TargetCarrier, $EntryCall, $AdditionalEvidenceText) -join ' '
        $targetLooksBackend = $evidenceText -match '(?i)(TaskProcessor|rebuildTaskData|Service|backend)\b'
        if ($targetLooksBackend -and $ForcedRequirementFamily -eq 'core_entry') {
            return $true
        }
        return $false
    }

    $highRows = @($productionRows | Where-Object {
        if ($_.PSObject.Properties.Name -contains 'weight') { [string]$_.weight -eq 'HIGH' } else { $true }
    })
    if ($highRows.Count -eq 0) { return $false }

    $allBackendServiceOrTask = $true
    $oracleClassNames = New-Object System.Collections.Generic.List[string]
    foreach ($row in $highRows) {
        $path = (Get-OracleFilePath -Row $row) -replace '\\', '/'
        $layer = if ($row.PSObject.Properties.Name -contains 'layer') { [string]$row.layer } else { '' }
        $className = [System.IO.Path]::GetFileNameWithoutExtension($path)
        if (-not [string]::IsNullOrWhiteSpace($className) -and -not $oracleClassNames.Contains($className)) {
            $oracleClassNames.Add($className) | Out-Null
        }
        $isBackend = (
            $layer -eq 'Service' -or
            $path -match '(?i)/(service|task|helper)/' -or
            $className -match '(?i)(Service|TaskProcessor|Processor)$'
        )
        $isPublicSurface = $path -match '(?i)/(controller|facade)/|(^|/)[^/]*(?:api|web)[^/]*/'
        if (-not $isBackend -or $isPublicSurface) {
            $allBackendServiceOrTask = $false
        }
    }

    $evidenceText = @($TargetCarrier, $EntryCall, $AdditionalEvidenceText) -join ' '
    if (-not $allBackendServiceOrTask) {
        $carrierClassCandidates = @(Get-BackendCarrierClassCandidates -Texts @($TargetCarrier, $EntryCall, $AdditionalEvidenceText))
        $hasTargetInOracle = $false
        foreach ($candidate in $carrierClassCandidates) {
            foreach ($className in @($oracleClassNames)) {
                if (-not [string]::IsNullOrWhiteSpace($className) -and $candidate -eq $className) {
                    $hasTargetInOracle = $true
                    break
                }
            }
            if ($hasTargetInOracle) { break }
        }
        if (-not $hasTargetInOracle) { return $false }
    }

    $hasOracleCarrierEvidence = $false
    foreach ($className in $oracleClassNames) {
        if (-not [string]::IsNullOrWhiteSpace($className) -and $evidenceText -match [regex]::Escape($className)) {
            $hasOracleCarrierEvidence = $true
            break
        }
    }
    if (-not $hasOracleCarrierEvidence -and $evidenceText -match '(?i)(TaskProcessor|rebuildTaskData|Service)\b') {
        $hasOracleCarrierEvidence = $true
    }

    $targetLooksBackend = $evidenceText -match '(?i)(TaskProcessor|rebuildTaskData|Service|backend)\b'
    return ($hasOracleCarrierEvidence -and $targetLooksBackend)
}

function Add-CorrectionSuggestion {
    <#
    .SYNOPSIS
    Generate correction suggestions when surface validation fails.

    .DESCRIPTION
    Searches BASELINE_INDEX.md for corresponding Facade and provides
    specific correction guidance (Experiment 3 from NEXT_EXPERIMENT_PLAN.md).

    .PARAMETER FailedCarrier
    The carrier that failed validation.

    .PARAMETER FailedLayer
    The layer of the failed carrier.

    .PARAMETER BaselineIndexPath
    Path to BASELINE_INDEX.md for Facade search.

    .RETURNS
    Hashtable with correction_suggestion, suggested_carriers, failed_layer, required_layer.
    #>
    param(
        [string]$FailedCarrier,
        [string]$FailedLayer,
        [string]$BaselineIndexPath = ''
    )

    $suggestedCarriers = @()
    $baseName = $FailedCarrier -replace 'Service$', '' -replace 'Task$', '' -replace 'Processor$', ''

    # Search BASELINE_INDEX.md for Facade with same base name
    if (-not [string]::IsNullOrWhiteSpace($BaselineIndexPath) -and (Test-Path -LiteralPath $BaselineIndexPath)) {
        try {
            $content = Get-Content -LiteralPath $BaselineIndexPath -Raw -Encoding UTF8
            # Look for Facade patterns with base name
            $patterns = @(
                "$baseName.*Facade",
                "${baseName}Facade",
                "${baseName}FacadeImpl"
            )
            foreach ($pattern in $patterns) {
                $matches = [regex]::Matches($content, "$pattern[^`r`n`"]*")
                if ($matches.Count -gt 0) {
                    $suggestedCarriers += $matches | ForEach-Object { $_.Value.Trim() }
                }
            }
        } catch {
            # Silently continue if search fails
        }
    }

    # Fallback: common public entry patterns.
    if ($suggestedCarriers.Count -eq 0) {
        $suggestedCarriers = @("${baseName}Facade", "${baseName}FacadeImpl", "${baseName}Controller")
    }

    # Remove duplicates and limit to top 3
    $suggestedCarriers = $suggestedCarriers | Select-Object -Unique | Select-Object -First 3

    return @{
        correction_suggestion = "Target carrier '$FailedCarrier' is in $FailedLayer layer. Use one of these Facade carriers instead: $($suggestedCarriers -join ', ')"
        suggested_carriers = $suggestedCarriers
        failed_layer = $FailedLayer
        required_layer = 'Facade or Controller'
    }
}

function Validate-TestSurface {
    <#
    .SYNOPSIS
    Validate that test targets the correct architectural layer.

    .DESCRIPTION
    For core_entry and stateful_side_effect families, tests should target
    Facade/Controller layer (real entries) rather than Service layer (internal).
    When validation fails, provides specific correction suggestions (Experiment 3).

    .PARAMETER TargetCarrier
    The carrier being tested.

    .PARAMETER ForcedRequirementFamily
    The requirement family for this slice.

    .PARAMETER TestName
    The test class name.

    .PARAMETER EntryCall
    The entry call being tested.

    .PARAMETER BaselineIndexPath
    Path to BASELINE_INDEX.md for Facade search.

    .RETURNS
    Ordered hashtable with status and details.
    #>
    param(
        [string]$TargetCarrier,
        [string]$ForcedRequirementFamily,
        [string]$TestName = '',
        [string]$EntryCall = '',
        [string]$BaselineIndexPath = '',
        [string]$ReplayRoot = '',
        [string]$AdditionalEvidenceText = ''
    )

    $result = [ordered]@{
        status = 'PASS'
        gap = ''
        reason = ''
        correction = ''
        target_layer = ''
        recommended_layer = ''
        backend_oracle_exception = $false
    }

    # Only validate for high-weight families
    $highWeight = @(
        'core_entry',
        'stateful_side_effect'
    ) -contains $ForcedRequirementFamily

    if (-not $highWeight) {
        return $result
    }

    if ([string]::IsNullOrWhiteSpace($TargetCarrier)) {
        return $result
    }

    $targetLayer = Extract-LayerFromCarrier -CarrierName $TargetCarrier
    $result.target_layer = $targetLayer

    # Real entry layers
    $realEntryLayers = @('Facade', 'Controller', 'Api')

    if ($realEntryLayers -notcontains $targetLayer) {
        if (Test-BackendTaskProcessorOracleReplay -ReplayRoot $ReplayRoot -TargetCarrier $TargetCarrier -EntryCall $EntryCall -ForcedRequirementFamily $ForcedRequirementFamily -AdditionalEvidenceText $AdditionalEvidenceText) {
            $result.status = 'PASS'
            $result.gap = 'backend_task_processor_oracle_exception'
            $result.recommended_layer = 'TaskProcessor/Service'
            $result.reason = "Backend-only oracle exception: archived high-weight production files are TaskProcessor/Service carriers, so '$TargetCarrier' is an executable replay surface for this requirement."
            $result.backend_oracle_exception = $true
            return $result
        }

        $result.status = 'FAIL'
        $result.gap = 'wrong_test_surface'
        $result.recommended_layer = 'Facade/Controller'
        $result.reason = "Target carrier '$TargetCarrier' is in $targetLayer layer, but real entries should be in Facade/Controller layer per architecture."

        # Use enhanced correction suggestion (Experiment 3)
        $correction = Add-CorrectionSuggestion -FailedCarrier $TargetCarrier -FailedLayer $targetLayer -BaselineIndexPath $BaselineIndexPath
        $result.correction = $correction.correction_suggestion
        $result.suggested_carriers = $correction.suggested_carriers
        $result.failed_layer = $correction.failed_layer
        $result.required_layer = $correction.required_layer
    }

    return $result
}

$root = Resolve-AbsolutePath $ReplayRoot
$outPath = Join-Path $root ('PRE_SLICE_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        slice_index = $SliceIndex
        output = $outPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$carrier = Read-JsonIfExists (Join-Path $root ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$carrierRank = Read-JsonIfExists (Join-Path $root ('CARRIER_RANK_{0:D2}.json' -f $SliceIndex))
if ($null -eq $carrierRank) { $carrierRank = Read-JsonIfExists (Join-Path $root 'CARRIER_RANK.json') }
$familyContractRaw = Read-JsonIfExists (Join-Path $root 'FAMILY_CONTRACT.json')
$familyContractFamilies = if ($null -ne $familyContractRaw -and $null -ne $familyContractRaw.families) { @($familyContractRaw.families) } else { $null }
$sideEffect = Read-JsonIfExists (Join-Path $root ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $SliceIndex))
$exact = Read-JsonIfExists (Join-Path $root ('EXACT_CONTRACT_ASSERTION_MATRIX_{0:D2}.json' -f $SliceIndex))
$nextExact = Read-JsonIfExists (Join-Path $root ('NEXT_SLICE_EXACT_CONTRACT_{0:D2}.json' -f $SliceIndex))
if ($null -eq $nextExact) { $nextExact = Read-JsonIfExists (Join-Path $root 'NEXT_SLICE_EXACT_CONTRACT.json') }
$previousVerify = if ($SliceIndex -gt 1) { Read-JsonIfExists (Join-Path $root ('SLICE_VERIFY_{0:D2}.json' -f ($SliceIndex - 1))) } else { $null }
$routingHints = Read-JsonIfExists (Join-Path $root 'EXACT_CONTRACT_ROUTING_HINTS.json')
$sourceChain = Read-JsonIfExists (Join-Path $root 'SOURCE_CHAIN_CONTRACT.json')
$firstSlicePlanText = Read-TextIfExists (Join-Path $root 'FIRST_SLICE_PROOF_PLAN.md')
$implementationContractText = Read-TextIfExists (Join-Path $root 'IMPLEMENTATION_CONTRACT.md')
$planText = @($firstSlicePlanText, $implementationContractText) -join "`n"
$plannedFirstRedTest = Get-PlanField -Text $planText -Name 'first_red_test'
$plannedSelectedCarrier = Get-PlanField -Text $planText -Name 'selected_carrier'
$plannedSelectedEntry = Get-PlanField -Text $planText -Name 'selected_real_entry'
$newServiceWhitelist = Get-PlanNewServiceWhitelist -Text $planText

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

# === V425-E1: NEW SERVICE WHITELIST ===
# If new services are declared in plan, skip carrier rank check for them
if ($newServiceWhitelist.Count -gt 0) {
    $warnings.Add("new_service_whitelist_active:$($newServiceWhitelist.Count -join ',')") | Out-Null
}

# === HORIZONTAL COVERAGE VALIDATION (v357) ===
# Get planned files from slice plan if available
$slicePlanPath = Join-Path $root ('SLICE_PLAN_{0:D2}.json' -f $SliceIndex)
if (Test-Path -LiteralPath $slicePlanPath) {
    $horizontalScript = Join-Path $PSScriptRoot '..\..\scripts\validate_horizontal_coverage.py'
    if (Test-Path -LiteralPath $horizontalScript) {
        $pythonExe = 'python3'
        $pythonCheck = Get-Command $pythonExe -ErrorAction SilentlyContinue
        if ($null -eq $pythonCheck) { $pythonExe = 'python' }
        try {
            $horizontalResult = & $pythonExe $horizontalScript --slice_plan $slicePlanPath 2>&1
            $horizontalJson = $horizontalResult | ConvertFrom-Json
            if ($null -ne $horizontalJson -and -not $horizontalJson.valid) {
                $issues.Add("horizontal_slice_minimum_not_met:$($horizontalJson.touched_count)/$($horizontalJson.required_count)") | Out-Null
                if ($null -ne $horizontalJson.missing_categories -and $horizontalJson.missing_categories.Count -gt 0) {
                    $warnings.Add("horizontal_missing_categories:$($horizontalJson.missing_categories -join ',')") | Out-Null
                }
            }
        } catch {
            # If validation fails, log but don't block
            $warnings.Add("horizontal_coverage_validation_error:$($_.Exception.Message)") | Out-Null
        }
    }
}

if ($null -eq $carrier) {
    $issues.Add('carrier_authorization_missing') | Out-Null
} elseif ([string]$carrier.authorization -ne 'ALLOW') {
    $issues.Add("carrier_authorization_not_allow:$($carrier.authorization)") | Out-Null
}
if ($null -ne $carrierRank) {
    $missingRankCarriers = @()
    if ($carrierRank.PSObject.Properties.Name -contains 'missing_required_rank1') {
        $missingRankCarriers = @(Get-StringArray $carrierRank.missing_required_rank1)
    }
    # Filter out families not required in current feature's FAMILY_CONTRACT.json
    if ($missingRankCarriers.Count -gt 0 -and $null -ne $familyContractFamilies) {
        $requiredIds = @($familyContractFamilies | Where-Object { [bool]$_.required } | ForEach-Object { [string]$_.id })
        if ($requiredIds.Count -gt 0) {
            $filteredMissing = @($missingRankCarriers | Where-Object { $requiredIds -contains $_ })
            $missingRankCarriers = $filteredMissing
        }
    }
    # === V425-E1: FILTER OUT NEW SERVICE WHITELIST ===
    # If a missing carrier is in the new service whitelist, it's expected to be created
    if ($missingRankCarriers.Count -gt 0 -and $newServiceWhitelist.Count -gt 0) {
        $filteredByWhitelist = @()
        foreach ($carrier in $missingRankCarriers) {
            $isWhitelisted = $false
            foreach ($whitelisted in $newServiceWhitelist) {
                if ($carrier -like "*$whitelisted*" -or $whitelisted -like "*$carrier*") {
                    $isWhitelisted = $true
                    $warnings.Add("carrier_rank_whitelisted:$carrier") | Out-Null
                    break
                }
            }
            if (-not $isWhitelisted) {
                $filteredByWhitelist += $carrier
            }
        }
        $missingRankCarriers = $filteredByWhitelist
    }
    if ($missingRankCarriers.Count -gt 0) {
        $forcedFamilyCarrier = Get-FamilyCarrierFromRank -CarrierRank $carrierRank -FamilyId $ForcedRequirementFamily
        $currentSliceMissing = @($missingRankCarriers | Where-Object { [string]$_ -eq $ForcedRequirementFamily })
        if ($currentSliceMissing.Count -gt 0 -or [string]::IsNullOrWhiteSpace($forcedFamilyCarrier)) {
            $issues.Add("carrier_rank_missing:$($missingRankCarriers -join ',')") | Out-Null
        } else {
            $warnings.Add("carrier_rank_missing_deferred:$($missingRankCarriers -join ',')") | Out-Null
        }
    }
    $rankRows = @()
    if ($null -ne $carrierRank.families) {
        if ($carrierRank.families -is [System.Array]) { $rankRows = @($carrierRank.families) } else { $rankRows = @($carrierRank.families) }
    }
    $topRank = @($rankRows | Where-Object { [bool]$_.required -and -not [string]::IsNullOrWhiteSpace([string]$_.production_carrier) } | Sort-Object @{Expression = 'rank'; Ascending = $true} | Select-Object -First 1)
    if ($topRank.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($ForcedRequirementFamily) -and [string]$topRank[0].family -ne $ForcedRequirementFamily) {
        $issues.Add("forced_family_not_highest_weight_open:$ForcedRequirementFamily!=rank1:$($topRank[0].family)") | Out-Null
    }
}

$highWeight = @(
    'core_entry',
    'stateful_side_effect',
    'deploy_export_page',
    'wire_payload_api_contract',
    'config_policy_threshold',
    'generated_artifact_template_upload',
    'external_integration',
    'automation_test_interface',
    'lifecycle_cleanup_retention'
) -contains $ForcedRequirementFamily

if ($highWeight -and $null -ne $carrier) {
    foreach ($fieldName in @('selected_carrier', 'production_boundary', 'downstream_side_effect_or_output', 'red_expectation', 'authorization')) {
        $fieldValue = Get-StringValue $carrier $fieldName
        if (Test-InvalidAuthorizationFieldValue -Value $fieldValue) {
            $issues.Add("carrier_authorization_field_not_ready:$fieldName=$fieldValue") | Out-Null
        }
    }
    if ($carrier.PSObject.Properties.Name -contains 'forbidden_synthetic_carrier' -and [bool]$carrier.forbidden_synthetic_carrier) {
        $issues.Add('carrier_authorization_synthetic_carrier') | Out-Null
    }
}

$isFirstTracer = $SliceIndex -eq 1 -and $ForcedRequirementFamily -eq 'core_entry'
$red = Get-StringValue $sideEffect 'red_result'
$green = Get-StringValue $sideEffect 'green_result'
$testName = Get-StringValue $sideEffect 'test_name'
$entryCall = Get-StringValue $sideEffect 'entry_call'
$expected = @(Get-StringArray $sideEffect.expected_writes_or_outputs)
$exactRows = if ($null -ne $exact) { @($exact.rows) } else { @() }
$validExactRows = @($exactRows | Where-Object {
    -not [string]::IsNullOrWhiteSpace((Get-StringValue $_ 'literal')) -and
    -not [string]::IsNullOrWhiteSpace((Get-StringValue $_ 'symbol_or_field')) -and
    -not [string]::IsNullOrWhiteSpace((Get-StringValue $_ 'test_assertion'))
})
$carrierTextForPlanLock = @(
    Get-StringValue $carrier 'selected_carrier',
    Get-StringValue $carrier 'real_entry',
    $ForcedSiblingSurface,
    $entryCall,
    $testName
) -join "`n"
$sourceChainDeclared = $null -ne $sourceChain -and [bool]$sourceChain.required_source_chain
$sourceChainRequired = Test-SourceChainAppliesForSlice -SourceChain $sourceChain -ForcedRequirementFamily $ForcedRequirementFamily -ForcedSliceType $ForcedSliceType -ForcedSiblingSurface $ForcedSiblingSurface -EntryCall $entryCall -CarrierText $carrierTextForPlanLock
$sourceChainCarrier = if ($sourceChainRequired -and $null -ne $sourceChain.next_required_slice) { [string]$sourceChain.next_required_slice.carrier } else { '' }
$matchesSourceChain = -not $sourceChainRequired -or (
    [string]$ForcedSiblingSurface -match '(?i)source|target|wire|input_data|RequestBuildContext|BaseRequest|DataAssembly|rebuildTaskData' -or
    [string]$entryCall -match '(?i)source|target|wire|input_data|RequestBuildContext|BaseRequest|DataAssembly|rebuildTaskData' -or
    [string]$sourceChainCarrier -eq '' -or
    [string]$ForcedSiblingSurface -eq $sourceChainCarrier
)
if ($sourceChainDeclared -and -not $sourceChainRequired) {
    $warnings.Add("source_chain_contract_not_applicable_to_forced_family:$ForcedRequirementFamily") | Out-Null
}
$unrequiredSourceChainCarrier = (
    -not $sourceChainDeclared -and
    $carrierTextForPlanLock -match '(?i)\b(DataAssembly|BuildContext|BaseRequest|BaseTaskData|InputData|source_chain|wire_payload|[a-z][a-z0-9]+_[a-z0-9_]+)\b'
)
if ($unrequiredSourceChainCarrier) {
    $issues.Add('blocked_plan_mismatch:unrequired_source_chain_carrier') | Out-Null
}
if ($SliceIndex -eq 1 -and -not [string]::IsNullOrWhiteSpace($plannedFirstRedTest) -and -not [string]::IsNullOrWhiteSpace($testName)) {
    $plannedClass = ($plannedFirstRedTest -split '#')[0]
    if ($testName -notmatch [regex]::Escape($plannedClass)) {
        $issues.Add("planned_red_test_mismatch:$testName!=${plannedFirstRedTest}") | Out-Null
    }
}
if ($SliceIndex -eq 1 -and -not [string]::IsNullOrWhiteSpace($plannedSelectedCarrier) -and -not [string]::IsNullOrWhiteSpace((Get-StringValue $carrier 'selected_carrier'))) {
    $plannedCarrierHead = (($plannedSelectedCarrier -split '\s*->\s*')[0]).Trim()
    if (-not [string]::IsNullOrWhiteSpace($plannedCarrierHead) -and (Get-StringValue $carrier 'selected_carrier') -notmatch [regex]::Escape($plannedCarrierHead.Split('.')[0])) {
        $issues.Add("selected_carrier_mismatch:planned=$plannedCarrierHead") | Out-Null
    }
}

if ($SliceIndex -eq 1 -and $highWeight) {
    if ([string]::IsNullOrWhiteSpace($plannedFirstRedTest)) {
        $issues.Add('planned_first_red_test_missing') | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($plannedSelectedCarrier)) {
        $issues.Add('planned_selected_carrier_missing') | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($plannedSelectedEntry)) {
        $issues.Add('planned_selected_entry_missing') | Out-Null
    }
}

if ($null -ne $previousVerify -and $previousVerify.PSObject.Properties.Name -contains 'authorized_for_next_slice' -and -not [bool]$previousVerify.authorized_for_next_slice -and -not ($sourceChainRequired -and $matchesSourceChain -and [string]$ForcedSliceType -eq 'exact_contract_slice')) {
    $issues.Add('previous_slice_not_authorized') | Out-Null
}

if ($highWeight -and -not $isFirstTracer) {
    $carrierRequiresSideEffect = Get-BoolValue $carrier 'requires_side_effect_evidence'
    $carrierRequiresExactContract = Get-BoolValue $carrier 'requires_exact_contract_assertions'
    $isExactContractOnlyHarness = (
        -not $carrierRequiresSideEffect -and
        (
            [string]$ForcedSliceType -eq 'exact_contract_slice' -or
            $carrierRequiresExactContract
        )
    )
    if ($null -eq $sideEffect) {
        $issues.Add('side_effect_evidence_missing') | Out-Null
    } else {
        $sideEffectStatus = Get-StringValue $sideEffect 'status'
        $isReadyEvidence = $sideEffectStatus -eq 'READY' -and $red -eq 'PENDING_BUSINESS_ASSERTION'
        $isReadyExactContractHarness = $isExactContractOnlyHarness -and $sideEffectStatus -eq 'NOT_REQUIRED' -and $red -eq 'PENDING_BUSINESS_ASSERTION' -and -not [string]::IsNullOrWhiteSpace($testName)
        if ([string]::IsNullOrWhiteSpace($testName)) { $issues.Add('test_name_missing') | Out-Null }
        if (-not $isReadyEvidence -and -not $isReadyExactContractHarness) {
            if ($sideEffectStatus -eq 'PLANNED' -or $red -eq 'PENDING' -or $green -eq 'PENDING') {
                $issues.Add("side_effect_evidence_not_ready:$sideEffectStatus/$red/$green") | Out-Null
            } else {
                if ($red -in @('', 'PENDING', 'NOT_RUN', 'BLOCKED')) { $issues.Add("red_result_not_business_assertion:$red") | Out-Null }
                if ($green -in @('', 'PENDING', 'NOT_RUN', 'BLOCKED')) { $issues.Add("green_result_not_pass:$green") | Out-Null }
            }
        } elseif ($isReadyExactContractHarness) {
            $warnings.Add('exact_contract_harness_allows_executor_without_side_effect_evidence') | Out-Null
        } else {
            $warnings.Add('ready_side_effect_harness_allows_executor') | Out-Null
        }
        if ($expected.Count -eq 0) { $issues.Add('expected_output_missing') | Out-Null }
        if ([string]::IsNullOrWhiteSpace($entryCall)) { $issues.Add('entry_call_missing') | Out-Null }
    }

    $exactPriority = $false
    if ($null -ne $routingHints -and [string]$routingHints.next_target -eq 'exact_contract_slice') {
        $exactPriority = $true
    }
    if ($ForcedSliceType -ne 'exact_contract_slice' -and $validExactRows.Count -gt 0 -and $ForcedRequirementFamily -eq 'stateful_side_effect') {
        $exactPriority = $true
    }
    if ($ForcedSliceType -eq 'stateful_success_slice') {
        $exactPriority = $false
    }
    if ($exactPriority -and $ForcedSliceType -ne 'exact_contract_slice') {
        $issues.Add('open_exact_contract_should_route_before_stateful_followup') | Out-Null
    }
}

$requiresActionableExactSubset = (
    $highWeight -and
    (
        [string]$ForcedSliceType -eq 'exact_contract_slice' -or
        ($null -ne $carrier -and $carrier.PSObject.Properties.Name -contains 'requires_exact_contract_assertions' -and [bool]$carrier.requires_exact_contract_assertions)
    )
)
if ($requiresActionableExactSubset) {
    if ($null -eq $nextExact) {
        $issues.Add('next_slice_exact_contract_missing') | Out-Null
    } elseif ([string]$nextExact.decision -ne 'ALLOW') {
        $issues.Add("next_slice_exact_contract_not_ready:$($nextExact.decision)") | Out-Null
        foreach ($item in @(Get-StringArray $nextExact.issues)) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $issues.Add("next_slice_exact_contract_issue:$item") | Out-Null
            }
        }
    } elseif ($null -eq $nextExact.rows -or @($nextExact.rows).Count -eq 0) {
        $issues.Add('next_slice_exact_contract_rows_empty') | Out-Null
    }
}

if ($isFirstTracer) {
    if ($red -in @('PENDING', '', 'NOT_RUN')) {
        $warnings.Add('s1_tracer_allows_planned_red_before_executor') | Out-Null
    }
}

if ($sourceChainRequired) {
    if (-not $matchesSourceChain) {
        $issues.Add('next_required_slice_mismatch:source_chain') | Out-Null
    }
    if ([string]$ForcedSliceType -ne 'exact_contract_slice') {
        $issues.Add('source_chain_requires_exact_contract_slice') | Out-Null
    }
    if ($matchesSourceChain -and -not [string]::IsNullOrWhiteSpace($testName) -and $red -eq 'PENDING_BUSINESS_ASSERTION') {
        for ($idx = $issues.Count - 1; $idx -ge 0; $idx--) {
            if ($issues[$idx] -match '^red_result_not_business_assertion:' -or $issues[$idx] -match '^green_result_not_pass:') {
                $issues.RemoveAt($idx)
            }
        }
        $warnings.Add('source_chain_allows_planned_business_red_before_executor') | Out-Null
    }
    $sourceChainOverridesPlan = (
        $matchesSourceChain -and
        [string]$ForcedSliceType -eq 'exact_contract_slice' -and
        -not [string]::IsNullOrWhiteSpace($testName) -and
        $red -eq 'PENDING_BUSINESS_ASSERTION'
    )
    if ($sourceChainOverridesPlan) {
        for ($idx = $issues.Count - 1; $idx -ge 0; $idx--) {
            if ($issues[$idx] -match '^planned_red_test_mismatch:' -or $issues[$idx] -match '^selected_carrier_mismatch:') {
                $issues.RemoveAt($idx)
            }
        }
        $warnings.Add('source_chain_overrides_initial_plan_lock') | Out-Null
    }
}

# === EXPERIMENT 3: PRE-AUTHORIZATION SURFACE VALIDATION ===
# Validate test surface before allowing implementation for high-weight families
# Baseline index path for Facade search (Experiment 3 correction suggestions)
$baselineIndexPath = Join-Path $root 'BASELINE_INDEX.md'
if ($highWeight -and $null -ne $carrier) {
    $targetCarrier = Get-StringValue $carrier 'selected_carrier'
    $surfaceValidation = Validate-TestSurface -TargetCarrier $targetCarrier -ForcedRequirementFamily $ForcedRequirementFamily -TestName $testName -EntryCall $entryCall -BaselineIndexPath $baselineIndexPath -ReplayRoot $root -AdditionalEvidenceText (@($plannedSelectedEntry, $ForcedSiblingSurface) -join ' ')

    if ($surfaceValidation.status -eq 'FAIL') {
        $issues.Add("surface_validation:$($surfaceValidation.gap):$($surfaceValidation.reason)") | Out-Null
        $warnings.Add("surface_layer:$($surfaceValidation.target_layer)->$($surfaceValidation.recommended_layer)") | Out-Null
    } elseif ($surfaceValidation.backend_oracle_exception) {
        $warnings.Add("surface_validation:$($surfaceValidation.gap)") | Out-Null
    }
}

# Final surface validation for result output
$surfaceValidationResult = $null
if ($highWeight -and $null -ne $carrier) {
    $targetCarrier = Get-StringValue $carrier 'selected_carrier'
    $surfaceValidationResult = Validate-TestSurface -TargetCarrier $targetCarrier -ForcedRequirementFamily $ForcedRequirementFamily -TestName $testName -EntryCall $entryCall -BaselineIndexPath $baselineIndexPath -ReplayRoot $root -AdditionalEvidenceText (@($plannedSelectedEntry, $ForcedSiblingSurface) -join ' ')
}

$decision = if ($issues.Count -eq 0) { 'ALLOW' } else { 'STOP' }
$result = [ordered]@{
    schema_version = 1
    decision = $decision
    replay_root = $root
    slice_index = $SliceIndex
    forced_requirement_family = $ForcedRequirementFamily
    forced_slice_type = $ForcedSliceType
    forced_sibling_surface = $ForcedSiblingSurface
    carrier_authorization = $(if ($null -ne $carrier) { [string]$carrier.authorization } else { 'MISSING' })
    red_result = $red
    green_result = $green
    test_name = $testName
    entry_call = $entryCall
    valid_exact_row_count = $validExactRows.Count
    next_slice_exact_contract_decision = $(if ($null -ne $nextExact) { [string]$nextExact.decision } else { 'MISSING' })
    source_chain_required = $sourceChainRequired
    next_required_slice = $(if ($sourceChainRequired) { $sourceChain.next_required_slice } else { $null })
    planned_first_red_test = $plannedFirstRedTest
    planned_selected_carrier = $plannedSelectedCarrier
    planned_selected_entry = $plannedSelectedEntry
    new_service_whitelist = @($newServiceWhitelist)
    carrier_rank = $carrierRank
    surface_validation = $surfaceValidationResult
    issues = @($issues)
    warnings = @($warnings)
    gate = 'pre_slice_carrier_and_evidence_authorization'
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 10
