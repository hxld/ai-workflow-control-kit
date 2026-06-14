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
    Checks if the carrier is in claim-api (Facade), claim-web (Controller),
    or claim-core/facade (Facade implementation). Returns $false for
    Service layer (claim-core without /facade/) and other internal layers.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$CarrierPath
    )

    # Normalize path
    $CarrierPath = $CarrierPath -replace '\\', '/'

    # Check for Facade layer (claim-api)
    if ($CarrierPath -match 'claim-api/.*Facade\.java') {
        return $true
    }

    # Check for Controller layer (claim-web)
    if ($CarrierPath -match 'claim-web/.*Controller\.java') {
        return $true
    }

    # Check for Facade implementation in claim-core
    if ($CarrierPath -match 'claim-core/.*facade/.*FacadeImpl\.java') {
        return $true
    }

    # All other layers are non-executable for entry points
    return $false
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-OracleFilePath {
    param($Row)
    if ($null -eq $Row) { return '' }
    if ($Row.PSObject.Properties.Name -contains 'path') { return [string]$Row.path }
    if ($Row.PSObject.Properties.Name -contains 'file') { return [string]$Row.file }
    return ''
}

function Test-BackendTaskProcessorOracleReplay {
    param([string]$ReplayRoot, [string]$EvidenceText = '')

    $oracle = Read-JsonIfExists (Join-Path $ReplayRoot 'ORACLE_DIFF_ANALYSIS.json')
    if ($null -eq $oracle) { return $false }

    $rows = @()
    if ($null -ne $oracle.files) {
        $rows = @($oracle.files)
    } elseif ($null -ne $oracle.production_changes) {
        $rows = @($oracle.production_changes)
    }
    $productionRows = @($rows | Where-Object {
        $path = Get-OracleFilePath -Row $_
        $isProduction = if ($_.PSObject.Properties.Name -contains 'is_production') { [bool]$_.is_production } else { ($path -match '/src/main/java/|\\src\\main\\java\\') }
        $isProduction -and -not [string]::IsNullOrWhiteSpace($path)
    })
    if ($productionRows.Count -eq 0) { return $false }

    $highRows = @($productionRows | Where-Object {
        if ($_.PSObject.Properties.Name -contains 'weight') { [string]$_.weight -eq 'HIGH' } else { $true }
    })
    if ($highRows.Count -eq 0) { return $false }

    $allBackend = $true
    $hasTaskProcessor = $false
    foreach ($row in $highRows) {
        $path = (Get-OracleFilePath -Row $row) -replace '\\', '/'
        $className = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $layer = if ($row.PSObject.Properties.Name -contains 'layer') { [string]$row.layer } else { '' }
        $isBackend = $layer -eq 'Service' -or $path -match '(?i)/(service|task|helper)/' -or $className -match '(?i)(Service|TaskProcessor|Processor)$'
        $isPublic = $path -match '(?i)/(controller|facade)/|claim-api/|claim-web/'
        if ($className -match '(?i)TaskProcessor') { $hasTaskProcessor = $true }
        if (-not $isBackend -or $isPublic) {
            $allBackend = $false
            break
        }
    }

    return ($allBackend -and ($hasTaskProcessor -or $EvidenceText -match '(?i)\bTaskProcessor\b|\brebuildTaskData\b'))
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
        [string]$WorktreePath,
        [string]$ReplayRoot
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
            if (Test-BackendTaskProcessorOracleReplay -ReplayRoot $ReplayRoot -EvidenceText $charter) {
                Write-Host "WARNING: Service-layer charter allowed by backend TaskProcessor oracle exception." -ForegroundColor Yellow
                return $true
            }

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
    $layerValid = Test-CharterLayer -CharterPath $charterPath -WorktreePath $Worktree -ReplayRoot $ReplayRoot

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

        if ($invalidCarriers.Count -gt 0 -and (Test-BackendTaskProcessorOracleReplay -ReplayRoot $ReplayRoot -EvidenceText $planContent)) {
            $result.warnings += @{
                code = 'BACKEND_TASK_PROCESSOR_ORACLE_EXCEPTION'
                message = "$($invalidCarriers.Count) non-Facade carrier(s) allowed because archived oracle high-weight files are backend TaskProcessor/Service carriers"
                carriers = $invalidCarriers
            }
            Write-Host "WARNING: Non-Facade carriers allowed by backend TaskProcessor oracle exception" -ForegroundColor Yellow
        } elseif ($invalidCarriers.Count -gt 0) {
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
