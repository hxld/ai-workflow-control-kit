<#
.SYNOPSIS
    Phase 0 Carrier Existence Verification Gate (v392)

.DESCRIPTION
    Validates that carriers claimed to exist in PHASE0_RESULT.md actually exist
    in the worktree. Prevents hallucinated carrier claims.

.PARAMETER ReplayRoot
    Path to the replay root directory.

.PARAMETER Worktree
    Path to the worktree (defaults to $ReplayRoot\worktree).

.PARAMETER ValidateOnly
    If specified, returns validation schema without running checks.

.OUTPUTS
    System.Collections.Hashtable
    Returns verification result with status, issues, and warnings.

.EXAMPLE
    $result = .\Verify-Phase0CarrierEvidence.ps1 -ReplayRoot "D:\replay-evidence\test"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,

    [string]$Worktree,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{
        schema_version = 'v462'
        stage = 'Phase0'
        checks = @(
            @{ name = 'selected_real_entry_exists'; description = 'Selected real entry carrier must exist in worktree' }
            @{ name = 'selected_real_entry_method_exists'; description = 'Selected real entry method must exist on the selected carrier' }
            @{ name = 'selected_real_entry_is_baseline_existing'; description = 'Selected real entry must not be a NEW/oracle-added carrier' }
            @{ name = 'carrier_search_commands_executed'; description = 'Search commands must be recorded in PHASE0_RESULT.md' }
            @{ name = 'no_hallucinated_carriers'; description = 'All claimed carriers must pass rg search verification' }
        )
        issues = @(
            @{ name = 'phase0_selected_real_entry_not_found'; severity = 'CRITICAL'; description = 'Selected real entry not found in worktree' }
            @{ name = 'phase0_selected_real_entry_missing'; severity = 'CRITICAL'; description = 'Selected real entry was not found or could not be parsed from PHASE0_RESULT.md' }
            @{ name = 'phase0_selected_real_entry_invalid_format'; severity = 'CRITICAL'; description = 'Selected real entry must be an existing class.method signature, not a class-only or prose value' }
            @{ name = 'phase0_selected_real_entry_not_baseline_existing'; severity = 'CRITICAL'; description = 'Selected real entry is described as NEW/oracle-added or not found in baseline' }
            @{ name = 'phase0_carrier_status_claim_mismatch'; severity = 'CRITICAL'; description = 'v454: carrier_status claims EXISTING but worktree rg search failed; carrier does not exist in baseline' }
            @{ name = 'phase0_selected_real_entry_method_not_found'; severity = 'CRITICAL'; description = 'Selected real entry method was not found on the selected carrier class in the baseline worktree' }
            @{ name = 'phase0_carrier_search_commands_missing'; severity = 'HIGH'; description = 'Search commands not recorded in PHASE0_RESULT.md' }
            @{ name = 'phase0_carrier_claim_hallucinated'; severity = 'CRITICAL'; description = 'Carrier claimed to exist but not found via rg' }
        )
    } | ConvertTo-Json -Depth 4
    exit 0
}

function Normalize-SelectedRealEntry {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $normalized = ([string]$Value).Trim().Trim('`').Trim()
    $normalized = $normalized -replace '^\s*(?:Entry|Carrier|Method)\s*:\s*', ''
    $normalized = $normalized -replace '\\', '/'

    if ($normalized -match '/([^/\s`]+)$') {
        $normalized = $matches[1]
    }

    $normalized = $normalized -replace '\.java(?=\.)', ''
    $normalized = $normalized -replace '\.java$', ''

    # Accept package-qualified or path-derived entries, but store the canonical
    # class.method shape used by the rest of this verifier.
    if ($normalized -cmatch '([A-Z][A-Za-z0-9_$]*)\.([A-Za-z_$][A-Za-z0-9_$]*(?:\s*\([^)]*\))?)') {
        return "$($matches[1]).$($matches[2])"
    }

    return $normalized.Trim()
}

function Get-SelectedRealEntryParts {
    param([string]$Value)

    $entryValue = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($entryValue)) {
        return [ordered]@{ Carrier = $null; Method = $null }
    }

    $entryValue = $entryValue.Trim('`').Trim()

    # Method-level entries may be package-qualified. Keep only the terminal
    # Class.method pair so com.example.RealEntry.handle is not parsed as com.example.
    $methodMatch = [regex]::Match(
        $entryValue,
        '^(?:[a-z_][A-Za-z0-9_$]*\.)*([A-Z][A-Za-z0-9_$]*)\.([A-Za-z_$][A-Za-z0-9_$]*)(?:\s*\([^)]*\))?$'
    )
    if ($methodMatch.Success) {
        return [ordered]@{
            Carrier = $methodMatch.Groups[1].Value
            Method = $methodMatch.Groups[2].Value
        }
    }

    # Class-only values are still useful for diagnostics, but they are not a
    # valid selected_real_entry because the first executable slice needs a method.
    $classMatch = [regex]::Match(
        $entryValue,
        '^(?:[a-z_][A-Za-z0-9_$]*\.)*([A-Z][A-Za-z0-9_$]*)$'
    )
    if ($classMatch.Success) {
        return [ordered]@{
            Carrier = $classMatch.Groups[1].Value
            Method = $null
        }
    }

    return [ordered]@{ Carrier = $null; Method = $null }
}

$replayRootFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReplayRoot)
$worktreePath = if ([string]::IsNullOrWhiteSpace($Worktree)) {
    Join-Path $replayRootFull 'worktree'
} else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Worktree)
}

$phase0ResultPath = Join-Path $replayRootFull 'PHASE0_RESULT.md'

$issues = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

# Check if PHASE0_RESULT.md exists
if (-not (Test-Path -LiteralPath $phase0ResultPath)) {
    [ordered]@{
        stage = 'Phase0'
        verification_status = 'SKIP'
        reason = 'PHASE0_RESULT.md not found'
        issues = @()
        warnings = @()
    } | ConvertTo-Json -Depth 4
    exit 0
}

$phase0Content = Get-Content -LiteralPath $phase0ResultPath -Raw -Encoding UTF8

# Extract selected_real_entry
$selectedRealEntry = $null
if ($phase0Content -match '(?m)^\s*-\s*\*{0,2}\s*selected_real_entry\s*\*{0,2}\s*:\s*`?([^\r\n`]+?)`?\s*$') {
    $selectedRealEntry = $matches[1].Trim()
} elseif ($phase0Content -match '(?m)\*{0,2}selected_real_entry\*{0,2}\s*[:=]\s*`?([^\r\n`]+?)`?\s*$') {
    $selectedRealEntry = $matches[1].Trim()
} elseif ($phase0Content -match '(?mi)^\s*\*{0,2}Selected\s+Real\s+Entry\*{0,2}\s*:\s*`?([^`\r\n]+?)`?\s*$') {
    $selectedRealEntry = $matches[1].Trim()
}

if ([string]::IsNullOrWhiteSpace($selectedRealEntry) -and $phase0Content -match '(?ims)^\s*(?:#+\s*)?\*{0,2}selected_real_entry\*{0,2}\s*:?\s*(.*?)(?=^\s*(?:##|#+\s|\*\*[A-Za-z0-9 _-]+\*\*\s*:)|\z)') {
    $selectedEntrySection = $matches[1]
    if ($selectedEntrySection -match '(?m)^\s*-\s*(?:Entry|Carrier|Method)\s*:\s*`?([^`\r\n]+?)`?\s*$') {
        $selectedRealEntry = $matches[1].Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($selectedRealEntry) -and $phase0Content -match '(?ims)^\s*#{1,3}\s+Selected\s+Real\s+Entry\b\s*(.*?)(?=^\s*#{1,3}\s+|\z)') {
    $selectedEntrySection = $matches[1]
    $selectedEntryPatterns = @(
        '(?m)^\s*(?:primary|entry|carrier|method)\s*:\s*`?([^`\r\n]+?)`?\s*$',
        '(?m)^\s*\*{0,2}(?:Primary\s+Entry|Entry\s+Point|Selected\s+Entry)\*{0,2}\s*:\s*`?([^`\r\n]+?)`?\s*$',
        '(?m)^\s*-\s*(?:Entry|Carrier|Method|Primary)\s*:\s*`?([^`\r\n]+?)`?\s*$',
        '(?m)^\s*\*{2}Entry\*{2}\s*:\s*`?([^`\r\n]+)`',  # v444: Handle **Entry**: `value` format
        '(?m)^\s*\*{2}Carrier\*{2}\s*:\s*`?([^`\r\n]+)',  # v444: Handle **Carrier**: value format
        '(?m)^\s*\*{2}Method\*{2}\s*:\s*`?([^`\r\n]+)'     # v444: Handle **Method**: value format
    )
    foreach ($pattern in $selectedEntryPatterns) {
        $match = [regex]::Match($selectedEntrySection, $pattern)
        if ($match.Success) {
            $selectedRealEntry = $match.Groups[1].Value.Trim()
            break
        }
    }
}

$selectedRealEntry = Normalize-SelectedRealEntry -Value $selectedRealEntry

# Extract carrier_class
$carrierClass = $null
if ($phase0Content -match '(?m)-\s*\*{0,2}\s*carrier_class\s*\*{0,2}\s*:\s*`?([^\r\n`]+?)`?\s*$') {
    $carrierClass = $matches[1].Trim()
}

# Extract carrier_status
$carrierStatus = $null
if ($phase0Content -match '(?m)-\s*\*{0,2}\s*carrier_status\s*\*{0,2}\s*:\s*([^\r\n]+?)\s*$') {
    $carrierStatus = $matches[1].Trim()
}

# v402: The selected real entry must be a baseline-existing method-level carrier.
# Class-only values and oracle/new/planned-carrier prose repeatedly slipped through as PASS.
$entryCarrier = $null
$entryMethod = $null
if (-not [string]::IsNullOrWhiteSpace($selectedRealEntry)) {
    $entryValue = [string]$selectedRealEntry
    # v456: Check only the selected_real_entry value for NEW/planned markers.
    # The prompt explicitly allows mentioning "Planned NEW Carrier" in the section context
    # alongside a valid EXISTING_BASELINE entry (phase0-contract-gate.prompt.md lines 56-59, 123).
    # Section-level scan removed to avoid false positives on legitimate planned carrier text.
    $entryOracleOrNewPattern = '(?i)(\bNEW\b|planned|oracle|addition|metadata|diff|evidence|not\s+found\s+in\s+baseline|new\s+file|does\s+not\s+exist)'
    if ($entryValue -match $entryOracleOrNewPattern) {
        $issues.Add('phase0_selected_real_entry_not_baseline_existing') | Out-Null
        $warnings.Add("phase0_selected_real_entry_not_baseline_existing: Selected real entry '$selectedRealEntry' is described as NEW/oracle-added/planned or not found in baseline; choose an existing worktree entry and move new carriers to planned_new_carrier/family scope") | Out-Null
    }

    $entryParts = Get-SelectedRealEntryParts -Value $entryValue
    $entryCarrier = [string]$entryParts.Carrier
    $entryMethod = [string]$entryParts.Method

    if ([string]::IsNullOrWhiteSpace($entryCarrier) -or [string]::IsNullOrWhiteSpace($entryMethod)) {
        $issues.Add('phase0_selected_real_entry_invalid_format') | Out-Null
        $warnings.Add("phase0_selected_real_entry_invalid_format: Selected real entry '$selectedRealEntry' must be an existing class.method signature, not a class-only or prose value") | Out-Null
    }
} else {
    $issues.Add('phase0_selected_real_entry_missing') | Out-Null
    $warnings.Add('phase0_selected_real_entry_missing: PHASE0_RESULT.md must expose selected_real_entry as a parseable existing class.method signature') | Out-Null
}

# Extract Verified from Current Worktree section to find claimed carriers
$claimedCarriers = @()
if ($phase0Content -match '## Verified from Current Worktree') {
    $worktreeSection = $phase0Content.Substring($phase0Content.IndexOf('## Verified from Current Worktree'))
    if ($worktreeSection -match '(?s)## Verified from Current Worktree.*?(?=##|\Z)') {
        $sectionContent = $matches[0]
        # Find all Java class claims like "AiAutoClaimFlowService.java exists" or "`AiAutoClaimFlowService.java` exists"
        $matches = [regex]::Matches($sectionContent, '``?([A-Za-z0-9_]+\.java)``?\s+exists')
        foreach ($m in $matches) {
            $className = $m.Groups[1].Value -replace '\.java$', ''
            $claimedCarriers += $className
        }
    }
}

# Extract search commands section.
#
# Accept legacy H1 and current H2 headings, but do not stop on shell comments
# inside fenced command blocks such as "# Search for ...".
$searchCommandsSection = $null
$searchLines = New-Object System.Collections.Generic.List[string]
$collectSearchSection = $false
$insideFence = $false
foreach ($line in ($phase0Content -split "\r?\n")) {
    if (-not $collectSearchSection) {
        if ($line -match '^#{1,2}\s+Search Commands Used\s*$') {
            $collectSearchSection = $true
            $searchLines.Add($line) | Out-Null
        }
        continue
    }

    if ($line -match '^\s*```') {
        $insideFence = -not $insideFence
        $searchLines.Add($line) | Out-Null
        continue
    }

    if (-not $insideFence -and $line -match '^#{1,2}\s+\S') {
        break
    }

    $searchLines.Add($line) | Out-Null
}
if ($searchLines.Count -gt 0) {
    $searchCommandsSection = ($searchLines -join [Environment]::NewLine)
}

# v392: Verify search commands were recorded
if ([string]::IsNullOrWhiteSpace($searchCommandsSection) -or $searchCommandsSection -notmatch 'rg\s+') {
    $issues.Add('phase0_carrier_search_commands_missing') | Out-Null
    $warnings.Add('phase0_carrier_search_commands_missing: No rg search commands recorded in PHASE0_RESULT.md') | Out-Null
}

# v392: Verify claimed carriers actually exist in worktree
if ($claimedCarriers.Count -gt 0 -and (Test-Path -LiteralPath $worktreePath)) {
    foreach ($carrier in $claimedCarriers) {
        # v462: Pattern matches both class and interface declarations
        $rgPattern = '(class|interface)\s+' + [regex]::Escape($carrier) + '\b'
        $rgExitCode = 1
        $carrierFound = $false

        # Try rg first
        try {
            $null = & rg --type java $rgPattern $worktreePath --files-with-matches 2>&1
            $rgExitCode = $LASTEXITCODE
            $carrierFound = $rgExitCode -eq 0
        } catch {
            $rgExitCode = 1
        }

        # v462: Fallback to Get-ChildItem if rg failed, with interface support
        if (-not $carrierFound) {
            $javaFiles = Get-ChildItem -LiteralPath $worktreePath -Recurse -Filter "*.java" -ErrorAction SilentlyContinue
            foreach ($file in $javaFiles) {
                $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                # v462: Match both class and interface declarations to handle Facades
                if ($content -match "(class|interface)\s+$carrier\b") {
                    $carrierFound = $true
                    break
                }
            }
        }

        if (-not $carrierFound) {
            $issues.Add('phase0_carrier_claim_hallucinated') | Out-Null
            $warnings.Add("phase0_carrier_claim_hallucinated: '$carrier' claimed to exist in PHASE0_RESULT.md but not found in worktree (rg exit code: $rgExitCode)") | Out-Null
        }
    }
}

# v392: Verify selected_real_entry carrier exists
if (-not [string]::IsNullOrWhiteSpace($selectedRealEntry) -and (Test-Path -LiteralPath $worktreePath)) {
    # Extract class name from selected_real_entry (e.g., "AiAutoClaimFlowService.handle(...)")
    if (-not [string]::IsNullOrWhiteSpace($entryCarrier)) {
        # v454: Strengthened carrier_status validation - reject any "NEW" substring regardless of context
        if ($carrierStatus -and $carrierStatus -match '(?i)NEW') {
            $issues.Add('phase0_selected_real_entry_not_baseline_existing') | Out-Null
            $warnings.Add("phase0_selected_real_entry_not_baseline_existing: Selected real entry '$selectedRealEntry' has carrier_status '$carrierStatus' indicating NEW/oracle-added/planned carrier; choose an existing worktree entry and move new carriers to planned_new_carrier/family scope") | Out-Null
        }

        # v462: Pattern matches both class and interface declarations
        $rgPattern = '(class|interface)\s+' + [regex]::Escape($entryCarrier) + '\b'
        $rgExitCode = 1
        $entryCarrierFound = $false

        $entryCarrierFiles = @()
        try {
            $entryCarrierFiles = @(& rg --type java $rgPattern $worktreePath --files-with-matches 2>&1)
            $rgExitCode = $LASTEXITCODE
            $entryCarrierFound = $rgExitCode -eq 0
        } catch {
            $rgExitCode = 1
        }

        if (-not $entryCarrierFound) {
            # v462: Try Get-ChildItem fallback with interface support
            $javaFiles = Get-ChildItem -LiteralPath $worktreePath -Recurse -Filter "*.java" -ErrorAction SilentlyContinue
            foreach ($file in $javaFiles) {
                $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                # v462: Match both class and interface declarations to handle Facades
                if ($content -match "(class|interface)\s+$entryCarrier\b") {
                    $entryCarrierFound = $true
                    $entryCarrierFiles += $file.FullName
                    break
                }
            }
        }

        # v454: Worktree cross-validation - rg search is source of truth
        if (-not $entryCarrierFound) {
            $issues.Add('phase0_selected_real_entry_not_found') | Out-Null
            # If carrier_status claimed EXISTING but rg says not found, this is a mismatch
            if ($carrierStatus -and $carrierStatus -match '(?i)EXISTING') {
                $issues.Add('phase0_carrier_status_claim_mismatch') | Out-Null
                $warnings.Add("phase0_carrier_status_claim_mismatch: carrier_status claimed '$carrierStatus' but worktree rg search failed to find '$entryCarrier' (rg exit code: $rgExitCode); carrier does not exist in baseline") | Out-Null
            }
            $warnings.Add("phase0_selected_real_entry_not_found: Selected real entry '$selectedRealEntry' (carrier: '$entryCarrier') not found in worktree (rg exit code: $rgExitCode); carrier does not exist in baseline") | Out-Null
        }

        if ($entryCarrierFound -and -not [string]::IsNullOrWhiteSpace($entryMethod)) {
            $methodPattern = '\b' + [regex]::Escape($entryMethod) + '\s*\('
            $methodFound = $false
            foreach ($filePath in @($entryCarrierFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
                if (Test-Path -LiteralPath $filePath) {
                    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($content -match $methodPattern) {
                        $methodFound = $true
                        break
                    }
                }
            }

            if (-not $methodFound) {
                $issues.Add('phase0_selected_real_entry_method_not_found') | Out-Null
                $warnings.Add("phase0_selected_real_entry_method_not_found: Selected real entry '$selectedRealEntry' method '$entryMethod' was not found on carrier '$entryCarrier' in baseline worktree") | Out-Null
            }
        }
    }
}

$verifyPath = Join-Path $replayRootFull 'PHASE0_CARRIER_EVIDENCE_VERIFY.json'
$verify = [ordered]@{
    stage = 'Phase0'
    verification_status = if ($issues.Count -gt 0) { 'FAIL' } else { 'PASS' }
    issues = @($issues)
    warnings = @($warnings)
    selected_real_entry = if ($selectedRealEntry) { $selectedRealEntry } else { $null }
    selected_entry_carrier = if ($entryCarrier) { $entryCarrier } else { $null }
    selected_entry_method = if ($entryMethod) { $entryMethod } else { $null }
    carrier_class = if ($carrierClass) { $carrierClass } else { $null }
    carrier_status = if ($carrierStatus) { $carrierStatus } else { $null }
    claimed_carriers_count = $claimedCarriers.Count
}
$verify | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $verifyPath -Encoding UTF8
Get-Content -LiteralPath $verifyPath -Encoding UTF8

if ($issues.Count -gt 0) {
    exit 1
}
