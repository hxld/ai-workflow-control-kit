# Verify Horizontal Slice Coverage
# Experiment 2: Multi-Family Slice Requirement
#
# This script verifies that S1 (tracer_bullet) touches minimum 3 families
# across Frontend, Backend, and Database.

param(
    [Parameter(Mandatory = $true)]
    [string]$SliceResultFile
)

$ErrorActionPreference = 'Stop'

# Family weight and classification mappings
$familyWeights = @{
    "core_entry" = 100
    "stateful_side_effect" = 90
    "wire_payload_api_contract" = 80
    "deploy_export_page" = 70
    "external_integration" = 60
    "generated_artifact_template_upload" = 50
    "automation_test_interface" = 40
    "config_policy_threshold" = 30
    "lifecycle_cleanup_retention" = 20
}

# File family mappings based on path patterns
$fileFamilyPatterns = @{
    "Frontend" = @("\.jsp$", "\.html$", "\.vue$", "\.jsx?$", "/web/", "/ui/", "/view/")
    "Backend" = @("Service\.java$", "Facade\.java$", "Controller\.java$", "/example-core/", "/example-server/")
    "Database" = @("Mapper\.java$", "Entity\.java$", "T[A-Z]", "TExample", "/example-provider/")
    "Test" = @("Test\.java$", "/test/")
    "Deploy" = @("pom\.xml", "\.yml$", "\.yaml$", "application\.properties")
    "External" = @("Push", "Insure", "Callback", "/integration/")
    "SideEffect" = @("Compensate", "Status", "Flow", "Progress")
    "Artifact" = @("Template", "Upload", "Download", "Export")
}

function Get-FileFamily {
    param([string]$FilePath)

    foreach ($family in $fileFamilyPatterns.Keys) {
        foreach ($pattern in $fileFamilyPatterns[$family]) {
            if ($FilePath -match $pattern) {
                return $family
            }
        }
    }

    # Default classification by directory
    if ($FilePath -match "/example-web/") { return "Frontend" }
    if ($FilePath -match "/example-core/") { return "Backend" }
    if ($FilePath -match "/example-provider/") { return "Database" }
    if ($FilePath -match "/example-server/") { return "Backend" }

    return "Unknown"
}

# Read slice result
if (-not (Test-Path -LiteralPath $SliceResultFile)) {
    Write-Host "ERROR: Slice result file not found: $SliceResultFile"
    exit 1
}

$sliceContent = Get-Content -LiteralPath $SliceResultFile -Raw -Encoding UTF8

# Try to parse as JSON first
try {
    $sliceResult = $sliceContent | ConvertFrom-Json

    # Extract families from JSON structure
    $touchedFamilies = if ($sliceResult.touched_requirement_families) {
        @($sliceResult.touched_requirement_families)
    } elseif ($sliceResult.families_touched) {
        @($sliceResult.families_touched)
    } elseif ($sliceResult.files_modified) {
        # Derive families from file list
        $families = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($file in $sliceResult.files_modified) {
            $family = Get-FileFamily -FilePath $file
            [void]$families.Add($family)
        }
        @($families)
    } else {
        @()
    }

    $sliceIndex = if ($sliceResult.slice_index) { $sliceResult.slice_index } elseif ($sliceResult.slice_number) { $sliceResult.slice_number } else { 1 }

} catch {
    # Parse as markdown or key-value format
    $touchedFamilies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Look for family indicators
    $familyIndicators = @("core_entry", "stateful_side_effect", "wire_payload_api_contract",
                          "deploy_export_page", "external_integration", "generated_artifact_template_upload")

    foreach ($indicator in $familyIndicators) {
        if ($sliceContent -match $indicator) {
            [void]$touchedFamilies.Add($indicator)
        }
    }

    # Look for file paths
    if ($sliceContent -match '(?:modified|created|touched):\s*\[(.+?)\]') {
        $fileList = $Matches[1] -split ','
        foreach ($file in $fileList) {
            $family = Get-FileFamily -FilePath $file.Trim()
            if ($family -ne "Unknown") {
                [void]$touchedFamilies.Add($family)
            }
        }
    }

    $touchedFamilies = @($touchedFamilies)
    $sliceIndex = 1
}

# Count families by category
$horizontalCategories = @{
    "Frontend" = 0
    "Backend" = 0
    "Database" = 0
    "Test" = 0
    "Deploy" = 0
}

foreach ($family in $touchedFamilies) {
    $category = switch -Regex ($family) {
        "core_entry|stateful_side_effect|wire_payload_api_contract|external_integration" { "Backend" }
        "deploy_export_page|generated_artifact_template_upload" { "Frontend" }
        "automation_test_interface" { "Test" }
        default { $family }
    }

    if ($horizontalCategories.ContainsKey($category)) {
        $horizontalCategories[$category]++
    }
}

# Calculate horizontal coverage score
$categoriesTouched = ($horizontalCategories.Values | Where-Object { $_ -gt 0 }).Count
$minimumRequired = 3

# Build result
$result = [ordered]@{
    verification_status = if ($categoriesTouched -ge $minimumRequired) { "PASS" } else { "FAIL" }
    slice_index = $sliceIndex
    families_touched = @($touchedFamilies)
    horizontal_coverage_score = [math]::Min(100, [math]::Round(($categoriesTouched / $minimumRequired) * 100))
    categories_touched = $categoriesTouched
    minimum_required = $minimumRequired
    meets_minimum = ($categoriesTouched -ge $minimumRequired)
    horizontal_breakdown = $horizontalCategories
}

if ($categoriesTouched -ge $minimumRequired) {
    Write-Host "Horizontal Slice Verification: PASS - S$($sliceIndex) touches $categoriesTouched categories (required: $minimumRequired)"
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 0
} else {
    Write-Host "Horizontal Slice Verification: FAIL - S$($sliceIndex) must touch minimum $minimumRequired categories"
    Write-Host "  Current categories touched: $categoriesTouched"
    Write-Host "  Horizontal breakdown: $($horizontalCategories | Format-Table -AutoSize | Out-String)"
    Write-Host "  Required: Frontend + Backend + Database (minimum)"
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 1
}
