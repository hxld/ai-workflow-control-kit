# pre-flight-check.ps1
# DESIGN-Phase Layer Validation (v432: Enhanced with actual file path checking)

param(
    [Parameter(Mandatory = $false)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$Worktree,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

# v432: Test-CarrierLayer function (same logic as Invoke-AgentPrompt.ps1)
function Test-CarrierLayer {
    <#
    .SYNOPSIS
    Validates that a carrier path is in an executable architectural layer.

    .DESCRIPTION
    Checks if the carrier is in example-api (Facade), example-web (Controller),
    or example-core/facade (Facade implementation). Returns $false for
    Service layer (example-core without /facade/) and other internal layers.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$CarrierPath
    )

    # Normalize path
    $CarrierPath = $CarrierPath -replace '\\', '/'

    # Check for Facade layer (example-api)
    if ($CarrierPath -match 'example-api/.*Facade\.java') {
        return $true
    }

    # Check for Controller layer (example-web)
    if ($CarrierPath -match 'example-web/.*Controller\.java') {
        return $true
    }

    # Check for Facade implementation in example-core
    if ($CarrierPath -match 'example-core/.*facade/.*FacadeImpl\.java') {
        return $true
    }

    # All other layers are non-executable for entry points
    return $false
}

function Test-CharterLayer {
    <#
    .SYNOPSIS
    Validates that TEST_CHARTER.md specifies Facade/Controller layer, not Service layer.

    .DESCRIPTION
    Prevents wrong_test_surface violations by checking layer selection BEFORE execution.

    Returns $true if test targets Facade/Controller layer.
    Returns $false if test targets Service layer (wrong_test_surface violation).
    #>
    param(
        [string]$CharterPath,
        [string]$WorktreePath
    )

    if (-not (Test-Path -LiteralPath $CharterPath)) {
        Write-Host "WARNING: TEST_CHARTER.md not found at $CharterPath" -ForegroundColor Yellow
        return $true  # Pass if no charter (backward compatibility)
    }

    $charter = Get-Content -LiteralPath $CharterPath -Raw -Encoding UTF8

    # Extract test class name from charter
    $testClassMatch = [regex]::Match($charter, 'Test Class:|Target Test:|test class:', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($testClassMatch.Success) {
        $matchEnd = $testClassMatch.Index + $testClassMatch.Length
        $context = $charter.Substring([Math]::Min($matchEnd, $charter.Length), [Math]::Min(200, $charter.Length - $matchEnd))

        # Check if targeting Service layer directly
        if ($context -match '\w+Service') {
            Write-Host "ERROR: Test targets Service layer instead of Facade/Controller layer." -ForegroundColor Red
            Write-Host "Architectural Rule: Executable tests must enter through Facade/Controller layer." -ForegroundColor Yellow

            # Try to suggest Facade mapping
            if ($context -match '(\w+)Service') {
                $serviceName = $matches[1]
                $suggestedFacade = "${serviceName}Facade"
                Write-Host "Suggested Facade: $suggestedFacade" -ForegroundColor Cyan
            }

            return $false
        }
    }

    # If worktree provided, verify Facade exists
    if (-not [string]::IsNullOrWhiteSpace($WorktreePath) -and (Test-Path -LiteralPath $WorktreePath)) {
        # Look for Facade pattern in test class name
        if ($charter -match '(\w+)Facade' -or $charter -match '(\w+)Controller') {
            $facadeName = if ($matches[1]) { $matches[1] } else { $matches[0] }
            Write-Host "INFO: Test targets $facadeName (correct layer)" -ForegroundColor Green
        }
    }

    return $true
}

function Invoke-LayerValidationGate {
    param(
        [string]$ReplayRoot,
        [string]$Worktree
    )

    $charterPath = Join-Path $ReplayRoot 'TEST_CHARTER.md'
    $planPath = Join-Path $ReplayRoot 'REPLAY_PLAN.md'
    $resultPath = Join-Path $ReplayRoot 'LAYER_VALIDATION_RESULT.json'

    $result = [ordered]@{
        gate = 'layer_validation'
        charter_path = $charterPath
        can_proceed = $true
        validation_status = 'PASS'
        issues = @()
        warnings = @()
        validated_at = (Get-Date).ToString('s')
    }

    # v432: Check 1 - Run charter content validation (v431 logic)
    $layerValid = Test-CharterLayer -CharterPath $charterPath -WorktreePath $Worktree

    if (-not $layerValid) {
        $result.can_proceed = $false
        $result.validation_status = 'FAIL'
        $result.issues += @{
            code = 'WRONG_TEST_SURFACE_CHARTER'
            message = 'Test charter targets Service layer instead of Facade/Controller layer'
            remediation = 'Change test to target Facade layer. Use @Remote/@CatfishRemote entry point.'
        }
    }

    # v432: Check 2 - Validate actual carrier file paths (NEW)
    if ((Test-Path -LiteralPath $planPath) -and (Test-Path -LiteralPath $Worktree)) {
        $planContent = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8

        # Extract carrier references (patterns like "Target: ServiceName" or "Carrier: ClassName")
        $carrierPattern = '(?:Target|Carrier|Entry|测试载体|入口):\s*([A-Z][a-zA-Z0-9]*)'
        $carriers = [regex]::Matches($planContent, $carrierPattern) |
                     ForEach-Object { $_.Groups[1].Value } |
                     Select-Object -Unique

        $invalidCarriers = @()

        foreach ($carrierName in $carriers) {
            # Search for carrier files in worktree
            Push-Location $Worktree
            try {
                $searchResult = rg "class\s+$carrierName" --type java -l 2>$null
                if ($searchResult) {
                    $carrierPaths = $searchResult -split "`n"
                    foreach ($carrierPath in $carrierPaths) {
                        if (-not [string]::IsNullOrWhiteSpace($carrierPath)) {
                            if (-not (Test-CarrierLayer $carrierPath)) {
                                $invalidCarriers += [ordered]@{
                                    name = $carrierName
                                    path = $carrierPath
                                    reason = 'Carrier is not in an executable layer (Facade/Controller)'
                                }
                                Write-Host "ERROR: Carrier $carrierName at $carrierPath is not in Facade/Controller layer" -ForegroundColor Red
                            } else {
                                Write-Host "OK: Carrier $carrierName at $carrierPath is in executable layer" -ForegroundColor Green
                            }
                        }
                    }
                }
            } finally {
                Pop-Location
            }
        }

        if ($invalidCarriers.Count -gt 0) {
            $result.can_proceed = $false
            $result.validation_status = 'FAIL'
            $result.issues += @{
                code = 'WRONG_TEST_SURFACE_FILEPATH'
                message = "$($invalidCarriers.Count) carrier(s) not in executable layer (Facade/Controller)"
                carriers = $invalidCarriers
                remediation = 'Select a Facade or Controller layer carrier as the test entry point.'
            }
        }
    }

    # Write result
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    if ($result.can_proceed) {
        Write-Host "Layer validation: PASSED" -ForegroundColor Green
    } else {
        Write-Host "Layer validation: FAILED" -ForegroundColor Red
        foreach ($issue in $result.issues) {
            Write-Host "  [$($issue.code)] $($issue.message)" -ForegroundColor Red
        }
    }

    return $result
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'Test-CharterLayer: Validates Facade/Controller layer selection',
            'Prevents wrong_test_surface before execution'
        )
    }
    $result | Format-List
    exit 0
}

# Main execution
$result = Invoke-LayerValidationGate -ReplayRoot $ReplayRoot -Worktree $Worktree

exit $(if ($result.can_proceed) { 0 } else { 1 })
