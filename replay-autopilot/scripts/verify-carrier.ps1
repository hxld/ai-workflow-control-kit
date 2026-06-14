# Verify Carrier Selection
# Experiment 1: Carrier Verification Gate
#
# This script verifies that the selected carrier matches requirement keywords
# by searching the codebase for similar patterns.

param(
    [Parameter(Mandatory = $true)]
    [string]$Worktree,

    [Parameter(Mandatory = $true)]
    [string]$RequirementKeywords,

    [Parameter(Mandatory = $true)]
    [string]$PlannedCarrier,

    [string]$SearchPath = ''
)

$ErrorActionPreference = 'Stop'

# Keyword to carrier pattern mappings based on common project patterns
# Using ASCII-safe patterns to avoid encoding issues
$patternMap = @{
    # Configuration-related keywords
    "config" = @("ModuleConfigService", "ConfigService", "ConfigurationService")
    "configuration" = @("ModuleConfigService", "ConfigService", "ConfigurationService")
    "field" = @("ModuleConfigService", "ConfigService")

    # Auto-flow related keywords
    "auto" = @("AutoFlowService", "AutoClaimFlowService", "FlowService")
    "flow" = @("FlowService", "AutoFlowService", "AutoClaimFlowService")

    # Examine-related keywords
    "examine" = @("ExamineService", "ExamineFlow", "ExamineFacade")
    "review" = @("ExamineService", "ReviewService")

    # Refund/return ticket keywords
    "refund" = @("RefundService", "RefundFacade", "ReturnTicketService")
    "return" = @("ReturnTicketService", "RefundService")

    # Claim-related keywords
    "claim" = @("ClaimService", "ClaimFlowService", "AiClaimService")

    # AI-related keywords
    "ai" = @("AiClaimService", "AiAutoClaimFlowService", "AiReviewService")
}

# Normalize worktree path
$worktreeFull = [System.IO.Path]::GetFullPath($Worktree)

# Extract keywords from requirement
$keywords = $RequirementKeywords -split '\s+'

# Build suggested carriers list based on keywords
$suggestedCarriers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($kw in $keywords) {
    $normalizedKw = $kw.Trim().ToLower()
    if ($patternMap.ContainsKey($normalizedKw)) {
        foreach ($carrier in $patternMap[$normalizedKw]) {
            [void]$suggestedCarriers.Add($carrier)
        }
    }
}

# If search path provided, do actual codebase search
if ($SearchPath -and (Test-Path -LiteralPath $SearchPath)) {
    # Use ripgrep if available, otherwise fallback
    $rgPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\rg.cmd'
    if (Test-Path -LiteralPath $rgPath) {
        foreach ($kw in $keywords | Select-Object -First 3) {
            try {
                $searchResult = & $rgPath -i -l --type java -g "*Service.java" $kw $SearchPath 2>&1 | Select-Object -First 5
                if ($searchResult) {
                    foreach ($file in $searchResult) {
                        if ($file -match '([A-Za-z][A-Za-z0-9]*)Service\.java$') {
                            [void]$suggestedCarriers.Add($Matches[1] + "Service")
                        }
                    }
                }
            } catch {
                # Search failed, continue with pattern map
            }
        }
    }
}

# Check if planned carrier matches suggestions
$plannedCarrierName = $PlannedCarrier.Trim()
$carrierMatches = $false

foreach ($suggested in $suggestedCarriers) {
    if ($plannedCarrierName -like "*$suggested*") {
        $carrierMatches = $true
        break
    }
}

# Output result
$result = [ordered]@{
    verification_status = if ($carrierMatches) { "PASS" } else { "WARN" }
    planned_carrier = $PlannedCarrier
    suggested_carriers = @($suggestedCarriers) | Sort-Object
    requirement_keywords = @($keywords | Select-Object -First 10)
    carrier_matches_pattern = $carrierMatches
}

if ($carrierMatches) {
    Write-Host "Carrier Verification: PASS - Planned carrier '$PlannedCarrier' matches requirement keywords"
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 0
} else {
    if ($suggestedCarriers.Count -gt 0) {
        Write-Host "Carrier Verification: WARN - Planned carrier '$PlannedCarrier' may not match requirement keywords"
        Write-Host "  Suggested carriers: $(($suggestedCarriers | Sort-Object) -join ', ')"
        Write-Host "  Verify carrier selection matches requirement keywords"
    } else {
        Write-Host "Carrier Verification: SKIP - No specific carrier patterns detected from keywords"
        Write-Host "  Keywords: $($keywords -join ', ')"
    }
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 0  # Warning only, don't block
}
