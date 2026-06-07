# Verify-BehavioralTestEnforcement.ps1
# Validates that behavioral test enforcement prompt changes are present and correct

[CmdletBinding()]
param(
    [string]$PromptPath = (Join-Path $PSScriptRoot "..\prompts\phase1-slice-executor.prompt.md")
)

$ErrorActionPreference = "Stop"

# Main verification
Write-Host "Verifying Behavioral Test Enforcement in phase1-slice-executor.prompt.md..." -ForegroundColor Cyan

$result = @{
    prompt_file_exists = (Test-Path $PromptPath)
    has_behavioral_section = $false
    has_behavioral_definition = $false
    has_structural_definition = $false
    has_behavioral_keywords = $false
    has_structural_keywords = $false
    has_enforcement_rules = $false
    has_blocker_rules = $false
    has_behavioral_requirement = $false
    has_verification_structure = $false
    overall_pass = $false
}

if ($result.prompt_file_exists) {
    $content = Get-Content $PromptPath -Raw -Encoding UTF8

    # Check for Behavioral Test Requirements section
    $result.has_behavioral_section = $content -match 'Behavioral Test Requirements'

    # Check for BEHAVIORAL test definition
    $result.has_behavioral_definition = $content -match 'BEHAVIORAL'

    # Check for STRUCTURAL test definition
    $result.has_structural_definition = $content -match 'STRUCTURAL'

    # Check for BEHAVIORAL keywords
    $result.has_behavioral_keywords = $content -match 'assert.*verify.*equals'

    # Check for STRUCTURAL keywords
    $result.has_structural_keywords = $content -match 'ClassNotFoundException.*NoSuchMethodException'

    # Check for enforcement rules
    $result.has_enforcement_rules = $content -match 'wrong_test_surface'

    # Check for blocker rules
    $result.has_blocker_rules = $content -match 'no_behavioral_tests_found'

    # Check for BEHAVIORAL requirement
    $result.has_behavioral_requirement = $content -match 'BEHAVIORAL.*GREEN'

    # Check for verification structure
    $result.has_verification_structure = $content -match 'verifier' -and $content -match 'VERIFICATION'

    # Overall pass if critical checks are present
    $result.overall_pass = $result.has_behavioral_section -and
                           $result.has_behavioral_definition -and
                           $result.has_structural_definition -and
                           $result.has_enforcement_rules
}

# Output results
Write-Host "`nVerification Results:" -ForegroundColor Cyan
foreach ($key in $result.Keys) {
    $color = if ($result[$key]) { "Green" } else { "Red" }
    Write-Host "  $key : $($result[$key])" -ForegroundColor $color
}

if ($result.overall_pass) {
    Write-Host "`nVERIFICATION: PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nVERIFICATION: FAIL" -ForegroundColor Red
    exit 1
}
