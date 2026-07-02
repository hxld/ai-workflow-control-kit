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

function Get-StringArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    return @([string]$Value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-PropertyValue {
    param($Object, [string[]]$Names)

    if ($null -eq $Object) { return $null }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }
    return $null
}

function Get-NullableIntProperty {
    param($Object, [string]$Name)

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $null
    }
    $raw = $Object.$Name
    if ($null -eq $raw -or [string]::IsNullOrWhiteSpace([string]$raw)) {
        return $null
    }
    try {
        return [int]$raw
    } catch {
        return $null
    }
}

function Test-PathUnderRoot {
    param([string]$Root, [string]$Path)

    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        $rootFull = [System.IO.Path]::GetFullPath($Root)
        if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $rootFull += [System.IO.Path]::DirectorySeparatorChar
        }
        $pathFull = [System.IO.Path]::GetFullPath($Path)
        return $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Get-LatestSliceResultPath {
    param([string]$ReplayRoot)

    if ([string]::IsNullOrWhiteSpace($ReplayRoot) -or -not (Test-Path -LiteralPath $ReplayRoot)) {
        return $null
    }
    $slice = Get-ChildItem -LiteralPath $ReplayRoot -Filter 'SLICE_RESULT_*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^SLICE_RESULT_(\d+)\.json$' } |
        ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName
                Index = [int]([regex]::Match($_.Name, '^SLICE_RESULT_(\d+)\.json$').Groups[1].Value)
            }
        } |
        Sort-Object Index -Descending |
        Select-Object -First 1
    if ($null -eq $slice) { return $null }
    return $slice.Path
}

function Test-SliceResultAuthorizesTaskProcessorEntry {
    param([string]$ReplayRoot, [string]$WorktreePath)

    $slicePath = Get-LatestSliceResultPath -ReplayRoot $ReplayRoot
    if ([string]::IsNullOrWhiteSpace($slicePath)) { return $false }
    $result = Read-JsonIfExists $slicePath
    if ($null -eq $result) { return $false }

    $charter = Get-PropertyValue -Object $result -Names @('behavior_test_charter', 'test_charter')
    $entryText = @(
        (Get-PropertyValue -Object $charter -Names @('production_entry', 'real_entry', 'selected_real_entry', 'selected_carrier', 'production_boundary')),
        (Get-PropertyValue -Object $result -Names @('production_entry', 'real_entry', 'selected_real_entry', 'selected_carrier', 'target_subsurface_or_carrier', 'production_boundary'))
    ) -join ' '
    if ($entryText -notmatch '(?i)\bTaskProcessor\b|[\\/]task[\\/]|\.task\.|\bhandleTaskResponse\b') {
        return $false
    }

    $proofKind = [string](Get-PropertyValue -Object $charter -Names @('proof_kind', 'proof_type'))
    if ($proofKind -notmatch '(?i)real_entry|behavior|stateful|side_effect') {
        return $false
    }

    $matchedTestCount = Get-NullableIntProperty -Object $result -Name 'matched_test_count'
    if ($null -eq $matchedTestCount -or $matchedTestCount -le 0) {
        return $false
    }
    if (-not [bool](Get-PropertyValue -Object $result -Names @('real_entry_invoked'))) {
        return $false
    }

    $declaredExitCodes = @(
        Get-NullableIntProperty -Object $result -Name 'green_exit_code'
        Get-NullableIntProperty -Object $result -Name 'test_execution_exit_code'
    ) | Where-Object { $null -ne $_ }
    if ($declaredExitCodes.Count -eq 0 -or ($declaredExitCodes | Where-Object { $_ -ne 0 }).Count -gt 0) {
        return $false
    }

    $assertions = @()
    $assertions += @(Get-StringArray (Get-PropertyValue -Object $result -Names @('side_effect_assertions')))
    $assertions += @(Get-StringArray (Get-PropertyValue -Object $result -Names @('exact_output_assertions')))
    $assertions += @(Get-StringArray (Get-PropertyValue -Object $result -Names @('closed_assertions')))
    if ($assertions.Count -eq 0) {
        return $false
    }

    $evidenceFiles = @()
    $evidenceFiles += @(Get-StringArray (Get-PropertyValue -Object $charter -Names @('evidence_file', 'evidence_files')))
    $evidenceFiles += @(Get-StringArray (Get-PropertyValue -Object $result -Names @('evidence_file', 'evidence_files', 'implemented_tests')))
    $evidenceFiles = @($evidenceFiles | Select-Object -Unique)
    foreach ($rawEvidence in $evidenceFiles) {
        $evidence = ([string]$rawEvidence).Split('#')[0].Trim()
        if ([string]::IsNullOrWhiteSpace($evidence)) { continue }
        $candidate = if ([System.IO.Path]::IsPathRooted($evidence)) { $evidence } else { Join-Path $WorktreePath $evidence }
        $normalizedEvidence = $candidate -replace '\\', '/'
        if ((Test-Path -LiteralPath $candidate) -and
            (Test-PathUnderRoot -Root $WorktreePath -Path $candidate) -and
            $normalizedEvidence -match '(?i)/src/test/') {
            return $true
        }
    }

    return $false
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
        $isPublic = $path -match '(?i)/(controller|facade)/|example-api/|example-web/'
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
            if (Test-SliceResultAuthorizesTaskProcessorEntry -ReplayRoot $ReplayRoot -WorktreePath $WorktreePath) {
                Write-Host "WARNING: Service collaborator mention allowed because slice result proves a real TaskProcessor entry was executed." -ForegroundColor Yellow
                return $true
            }
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

        if ($invalidCarriers.Count -gt 0 -and (Test-SliceResultAuthorizesTaskProcessorEntry -ReplayRoot $ReplayRoot -WorktreePath $Worktree)) {
            $result.warnings += @{
                code = 'TASK_PROCESSOR_REAL_ENTRY_SLICE_EXCEPTION'
                message = "$($invalidCarriers.Count) non-Facade carrier(s) allowed because slice result proves real TaskProcessor entry execution"
                carriers = $invalidCarriers
            }
            Write-Host "WARNING: Non-Facade carriers allowed by real TaskProcessor slice evidence" -ForegroundColor Yellow
        } elseif ($invalidCarriers.Count -gt 0 -and (Test-BackendTaskProcessorOracleReplay -ReplayRoot $ReplayRoot -EvidenceText $planContent)) {
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
