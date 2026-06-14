# Oracle Feature Domain Compatibility Check
#
# Purpose: Early detection of oracle-feature domain mismatch before planning starts.
# Gate: Oracle Isolation Gate
# Version: v347
#
# This script analyzes oracle file paths and requirement content to detect
# feature domain incompatibilities BEFORE the plan tournament begins.
#
# Usage:
#   Invoke-OracleFeatureDomainCheck.ps1 -OracleDiffAnalysis <path> -RequirementSource <path> -OutPath <path>

param(
    [Parameter(Mandatory = $true)]
    [string]$OracleDiffAnalysis,
    [Parameter(Mandatory = $true)]
    [string]$RequirementSource,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'

# Domain keyword mappings (using English class names for reliability)
$DomainKeywords = @{
    'examine'        = @('examine', 'ExamineFlow', 'ExamineFacade', 'ExamineController')
    'push'           = @('push', 'ExamplePush', 'PushService', 'PushFacade')
    'ai'             = @('ai', 'Example', 'ExampleAuto', 'AiReview', 'AiConclusion')
    'compensate'     = @('compensate', 'Compensate', 'Compensation', 'CompensateTable')
    'route'          = @('route', 'CaseRoute', 'Routing', 'RouteService')
    'refund'         = @('refund', 'RefundTicket', 'RefundService', 'RefundFacade')
    'return_ticket'  = @('ExampleTicket', 'ExampleTicketContext', 'RenbaoCaishenfenExampleTicket')
    'dock'           = @('dock', 'Dock', 'DockService')
}

function Get-DomainFromPath {
    param([string]$Path)

    $lowerPath = $Path.ToLower()

    foreach ($domain in $DomainKeywords.Keys) {
        foreach ($keyword in $DomainKeywords[$domain]) {
            if ($lowerPath -like "*$($keyword.ToLower())*") {
                return $domain
            }
        }
    }

    return 'unknown'
}

function Get-DomainFromRequirement {
    param([string]$RequirementContent)

    $lowerContent = $RequirementContent.ToLower()

    foreach ($domain in $DomainKeywords.Keys) {
        foreach ($keyword in $DomainKeywords[$domain]) {
            if ($lowerContent -like "*$($keyword.ToLower())*") {
                return $domain
            }
        }
    }

    return 'unknown'
}

# Read oracle diff analysis
if (-not (Test-Path $OracleDiffAnalysis)) {
    $result = [ordered]@{
        check_status = 'SKIP'
        reason = "ORACLE_DIFF_ANALYSIS not found: $OracleDiffAnalysis"
        oracle_primary_domain = 'unknown'
        requirement_primary_domain = 'unknown'
        domain_compatibility = 'UNCERTAIN'
        mismatch_evidence = @()
        generated_at = (Get-Date).ToString('s')
    }
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Host "Oracle domain check skipped: $OracleDiffAnalysis not found"
    return
}

$oracleAnalysis = Get-Content -LiteralPath $OracleDiffAnalysis -Raw | ConvertFrom-Json

# Read requirement source
if (-not (Test-Path $RequirementSource)) {
    $result = [ordered]@{
        check_status = 'SKIP'
        reason = "REQUIREMENT_SOURCE not found: $RequirementSource"
        oracle_primary_domain = 'unknown'
        requirement_primary_domain = 'unknown'
        domain_compatibility = 'UNCERTAIN'
        mismatch_evidence = @()
        generated_at = (Get-Date).ToString('s')
    }
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Host "Oracle domain check skipped: $RequirementSource not found"
    return
}

$requirementContent = Get-Content -LiteralPath $RequirementSource -Raw -Encoding UTF8

# Analyze oracle file domains
$oracleFiles = @($oracleAnalysis.files | Where-Object { $_.is_production })
$domainCounts = @{}
$mismatchedFiles = @()

foreach ($file in $oracleFiles) {
    $domain = Get-DomainFromPath -Path $file.path
    if (-not $domainCounts.ContainsKey($domain)) {
        $domainCounts[$domain] = 0
    }
    $domainCounts[$domain]++
}

if ($domainCounts.Keys.Count -eq 0) {
    $oraclePrimaryDomain = 'unknown'
} else {
    $oraclePrimaryDomain = ($domainCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
}

# Analyze requirement domain
$requirementPrimaryDomain = Get-DomainFromRequirement -RequirementContent $requirementContent

# Calculate compatibility
$nonPrimaryCount = 0
$oracleTotalFiles = $oracleFiles.Count

foreach ($domain in $domainCounts.Keys) {
    if ($domain -ne $oraclePrimaryDomain -and $domain -ne 'unknown') {
        $nonPrimaryCount += $domainCounts[$domain]
    }
}

if ($oracleTotalFiles -eq 0) {
    $foreignRatio = 0
} else {
    $foreignRatio = [math]::Round(($nonPrimaryCount / $oracleTotalFiles) * 100, 1)
}

# Determine compatibility
$domainCompatibility = 'COMPATIBLE'
$reason = ""

if ($foreignRatio -gt 30) {
    $domainCompatibility = 'MISMATCH'
    $reason = "Oracle has $foreignRatio% files from non-primary domains"
} elseif ($oraclePrimaryDomain -ne 'unknown' -and $requirementPrimaryDomain -ne 'unknown' -and $oraclePrimaryDomain -ne $requirementPrimaryDomain) {
    $domainCompatibility = 'MISMATCH'
    $reason = "Oracle primary domain ($oraclePrimaryDomain) does not match requirement domain ($requirementPrimaryDomain)"
}

# Collect mismatch evidence
if ($domainCompatibility -eq 'MISMATCH') {
    foreach ($file in $oracleFiles) {
        $domain = Get-DomainFromPath -Path $file.path
        if ($domain -ne $oraclePrimaryDomain -and $domain -ne 'unknown') {
            $mismatchedFiles += [ordered]@{
                path = $file.path
                domain = $domain
                layer = $file.layer
                weight = $file.weight
            }
        }
    }
}

# Build result
$result = [ordered]@{
    check_status = 'PASS'
    oracle_primary_domain = $oraclePrimaryDomain
    requirement_primary_domain = $requirementPrimaryDomain
    domain_compatibility = $domainCompatibility
    foreign_domain_ratio = $foreignRatio
    domain_breakdown = $domainCounts
    mismatch_evidence = $mismatchedFiles
    reason = $reason
    generated_at = (Get-Date).ToString('s')
}

# Override check_status if mismatch detected
if ($domainCompatibility -eq 'MISMATCH') {
    $result.check_status = 'BLOCK'
}

$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutPath -Encoding UTF8

Write-Host "Oracle domain compatibility: $domainCompatibility (oracle: $oraclePrimaryDomain, requirement: $requirementPrimaryDomain, foreign: $foreignRatio%)"
Write-Host "Output: $OutPath"
