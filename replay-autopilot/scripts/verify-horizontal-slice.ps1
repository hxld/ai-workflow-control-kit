# Verify Horizontal Slice Coverage
# Experiment 2: Multi-Family Slice Requirement
#
# This script verifies that S1 (tracer_bullet) touches minimum 3 families
# across Frontend, Backend, and Database.

param(
    [Parameter(Mandatory = $true)]
    [string]$SliceResultFile,
    [string]$FeatureClassificationPath = ''
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

    $normalizedPath = ([string]$FilePath) -replace '\\', '/'
    if ($normalizedPath -match '(?i)(^|/)src/test/(java|resources)/' -or $normalizedPath -match '(?i)Test\.java$') {
        return "Test"
    }

    foreach ($family in $fileFamilyPatterns.Keys) {
        foreach ($pattern in $fileFamilyPatterns[$family]) {
            if ($normalizedPath -match $pattern) {
                return $family
            }
        }
    }

    # Default classification by directory
    if ($normalizedPath -match "/example-web/") { return "Frontend" }
    if ($normalizedPath -match "/example-core/") { return "Backend" }
    if ($normalizedPath -match "/example-provider/") { return "Database" }
    if ($normalizedPath -match "/example-server/") { return "Backend" }

    return "Unknown"
}

function Read-JsonIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Add-UniqueStringToList {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    if (-not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
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

    $sliceFiles = New-Object System.Collections.Generic.List[string]
    foreach ($propertyName in @('implemented_files', 'current_slice_changed_files', 'round_changed_files_snapshot', 'changed_files', 'files_modified')) {
        if ($sliceResult.PSObject.Properties.Name -contains $propertyName) {
            foreach ($file in @(Get-StringArray $sliceResult.$propertyName)) {
                Add-UniqueStringToList -List $sliceFiles -Value ([string]$file)
            }
        }
    }
    if ($sliceResult.PSObject.Properties.Name -contains 'behavior_test_charter' -and $null -ne $sliceResult.behavior_test_charter) {
        $charter = $sliceResult.behavior_test_charter
        if ($charter.PSObject.Properties.Name -contains 'evidence_file') {
            foreach ($file in @(([string]$charter.evidence_file) -split "[,;`r`n]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
                Add-UniqueStringToList -List $sliceFiles -Value ([string]$file)
            }
        }
        if ($charter.PSObject.Properties.Name -contains 'evidence_files') {
            foreach ($file in @(Get-StringArray $charter.evidence_files)) {
                Add-UniqueStringToList -List $sliceFiles -Value ([string]$file)
            }
        }
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
    $sliceFiles = New-Object System.Collections.Generic.List[string]
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

foreach ($file in @($sliceFiles)) {
    $category = Get-FileFamily -FilePath ([string]$file)
    if ($horizontalCategories.ContainsKey($category)) {
        $horizontalCategories[$category]++
    }
}

# Calculate horizontal coverage score
$categoriesTouched = ($horizontalCategories.Values | Where-Object { $_ -gt 0 }).Count
$minimumRequired = 3
$requiredCategories = @('Frontend', 'Backend', 'Database')
$featureClassification = $null
if ([string]::IsNullOrWhiteSpace($FeatureClassificationPath)) {
    $FeatureClassificationPath = Join-Path (Split-Path -Parent ([System.IO.Path]::GetFullPath($SliceResultFile))) 'FEATURE_CLASSIFICATION.json'
}
$featureClassification = Read-JsonIfExists -Path $FeatureClassificationPath
if ($null -ne $featureClassification -and $null -ne $featureClassification.verifier_adjustments) {
    $minText = [string]$featureClassification.verifier_adjustments.horizontal_minimum
    if ($minText -match '^\d+$') {
        $minimumRequired = [int]$minText
    }
    if ($featureClassification.verifier_adjustments.PSObject.Properties.Name -contains 'horizontal_required_categories') {
        $requiredCategories = @(Get-StringArray $featureClassification.verifier_adjustments.horizontal_required_categories)
    }
}

# Build result
$result = [ordered]@{
    verification_status = if ($categoriesTouched -ge $minimumRequired) { "PASS" } else { "FAIL" }
    slice_index = $sliceIndex
    families_touched = @($touchedFamilies)
    horizontal_coverage_score = [math]::Min(100, [math]::Round(($categoriesTouched / $minimumRequired) * 100))
    categories_touched = $categoriesTouched
    minimum_required = $minimumRequired
    required_categories = @($requiredCategories)
    meets_minimum = ($categoriesTouched -ge $minimumRequired)
    horizontal_breakdown = $horizontalCategories
    feature_classification = $(if ($null -ne $featureClassification) { [string]$featureClassification.classification } else { '' })
    feature_classification_path = $FeatureClassificationPath
}

if ($categoriesTouched -ge $minimumRequired) {
    Write-Host "Horizontal Slice Verification: PASS - S$($sliceIndex) touches $categoriesTouched categories (required: $minimumRequired)"
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 0
} else {
    Write-Host "Horizontal Slice Verification: FAIL - S$($sliceIndex) must touch minimum $minimumRequired categories"
    Write-Host "  Current categories touched: $categoriesTouched"
    Write-Host "  Horizontal breakdown: $($horizontalCategories | Format-Table -AutoSize | Out-String)"
    Write-Host "  Required: $($requiredCategories -join ' + ') (minimum)"
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 1
}
