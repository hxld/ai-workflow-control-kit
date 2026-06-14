# phase0-precheck.ps1
# RED Phase Hard Gate Pre-Validation (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)
# Discovery Mode Checkpoint System Integration

param(
    [Parameter(Mandatory = $false)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$Worktree,

    [Parameter(Mandatory = $false)]
    [string]$MavenSettings = '',

    [Parameter(Mandatory = $false)]
    [bool]$DiscoveryMode = $false,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Test-TestFramework {
    <#
    .SYNOPSIS
    Pre-validates test framework is working before RED phase.

    .DESCRIPTION
    Prevents RC5 (Test Framework Not Pre-Validated) by checking Maven can compile and run tests.

    Returns $true if test framework is valid.
    Returns $false if compilation or execution fails.
    #>
    param(
        [string]$WorktreePath,
        [string]$MavenSettingsPath
    )

    Write-Host "Pre-flight: Validating test framework..." -ForegroundColor Cyan

    $pomPath = Join-Path $WorktreePath 'pom.xml'
    if (-not (Test-Path -LiteralPath $pomPath)) {
        Write-Host "ERROR: pom.xml not found at $pomPath" -ForegroundColor Red
        return @{
            IsValid = $false
            Reason = 'pom_not_found'
        }
    }

    # Test 1: Verify test dependencies
    Write-Host "Checking test dependencies..." -ForegroundColor Gray
    $depArgs = @(
        '-s', $MavenSettingsPath,
        '-f', $pomPath,
        'dependency:tree',
        '-Dscope=test',
        '-q'
    )
    $depResult = & mvn @depArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Maven test dependency check failed" -ForegroundColor Red
        return @{
            IsValid = $false
            Reason = 'dependency_check_failed'
            ExitCode = $LASTEXITCODE
        }
    }

    # Test 2: Compile test sources
    Write-Host "Compiling test sources..." -ForegroundColor Gray
    $compileArgs = @(
        '-s', $MavenSettingsPath,
        '-f', $pomPath,
        'test-compile',
        '-pl', 'example-server',
        '-q'
    )
    $compileResult = & mvn @compileArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Test compilation failed" -ForegroundColor Red
        Write-Host "Fix required in example-server/pom.xml test dependencies" -ForegroundColor Yellow
        return @{
            IsValid = $false
            Reason = 'test_compile_failed'
            ExitCode = $LASTEXITCODE
        }
    }

    Write-Host "Test framework validation: PASSED" -ForegroundColor Green
    return @{
        IsValid = $true
        Reason = 'test_framework_valid'
    }
}

function Test-RedPhaseAuthorized {
    <#
    .SYNOPSIS
    Validates RED phase result meets authorization criteria.

    .DESCRIPTION
    Prevents RC3 (Implementation After Blocked RED) by checking:
    - RED phase executed
    - RED phase failed with business assertion (not compilation error)
    - RED phase did not pass (no implementation needed)

    Discovery mode (Experiment 1): For S1, if layer validation returns WARN,
    RED phase may proceed despite warnings.

    Returns $true if RED phase is authorized for GREEN.
    Returns $false if RED phase is blocked.
    #>
    param(
        [string]$SliceResultPath,
        [bool]$DiscoveryMode = $false
    )

    if (-not (Test-Path -LiteralPath $SliceResultPath)) {
        Write-Host "ERROR: Slice result not found at $SliceResultPath" -ForegroundColor Red
        return @{
            IsValid = $false
            Reason = 'slice_result_missing'
        }
    }

    $sliceResult = Get-Content -LiteralPath $SliceResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tests = @($sliceResult.tests)

    # Check 1: RED phase must have executed
    $redTest = $tests | Where-Object { $_.phase -eq 'RED' } | Select-Object -First 1
    if ($null -eq $redTest) {
        Write-Host "ERROR: RED phase not executed" -ForegroundColor Red
        return @{
            IsValid = $false
            Reason = 'red_phase_not_executed'
        }
    }

    # Check 2: RED phase must NOT have compilation errors
    $redResult = $redTest.result
    if ($redResult -match 'compil|error|COMPILATION ERROR') {
        Write-Host "ERROR: RED phase blocked by compilation error" -ForegroundColor Red
        Write-Host "Fix test dependencies before GREEN phase" -ForegroundColor Yellow
        return @{
            IsValid = $false
            Reason = 'red_phase_compilation_error'
            Result = $redResult
        }
    }

    # Check 3: RED phase must fail with business assertion (not pass)
    if ($redResult -match 'pass|success|PASS') {
        Write-Host "ERROR: RED phase passed - no implementation needed" -ForegroundColor Red
        Write-Host "This indicates either redundant test or tautology (assertTrue(true))" -ForegroundColor Yellow
        return @{
            IsValid = $false
            Reason = 'red_phase_passed'
            Result = $redResult
        }
    }

    # Check 4: RED phase failure must be business assertion, not runtime error only
    if ($redResult -match 'runtime.?error|NullPointerException|ClassNotFoundException') {
        # Discovery mode bypass for S1 (Experiment 1)
        if ($DiscoveryMode) {
            $layerFile = Join-Path (Split-Path $SliceResultPath) "LAYER_VALIDATION_RESULT.json"
            if (Test-Path -LiteralPath $layerFile) {
                $layerResult = Get-Content -LiteralPath $layerFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($layerResult.validation_status -eq "WARN" -or $layerResult.validation_status -eq "REVIEW") {
                    Write-Host "WARNING: Discovery mode: RED phase authorized despite runtime error (layer validation: WARN)" -ForegroundColor Yellow
                    return @{
                        IsValid = $true
                        Reason = 'red_phase_authorized_discovery_mode'
                        RedResult = $redResult
                        DiscoveryMode = $true
                        LayerStatus = $layerResult.validation_status
                    }
                }
            }
        }

        Write-Host "ERROR: RED phase failed with runtime error, not business assertion" -ForegroundColor Red
        Write-Host "Fix test setup (mocks, context) before GREEN phase" -ForegroundColor Yellow
        return @{
            IsValid = $false
            Reason = 'red_phase_runtime_error'
            Result = $redResult
        }
    }

    Write-Host "RED phase authorization: PASSED" -ForegroundColor Green
    return @{
        IsValid = $true
        Reason = 'red_phase_authorized'
        RedResult = $redResult
        DiscoveryMode = $DiscoveryMode
    }
}

function Invoke-Phase0Precheck {
    param(
        [string]$ReplayRoot,
        [string]$Worktree,
        [string]$MavenSettings,
        [bool]$DiscoveryMode
    )

    $resultPath = Join-Path $ReplayRoot 'PHASE0_PRECHECK_RESULT.json'

    $result = [ordered]@{
        gate = 'phase0_precheck'
        can_proceed = $true
        validation_status = 'PASS'
        discovery_mode = $DiscoveryMode
        checks = @{}
        issues = @()
        warnings = @()
        validated_at = (Get-Date).ToString('s')
    }

    # Run test framework validation (only if worktree provided)
    if (-not [string]::IsNullOrWhiteSpace($Worktree) -and (Test-Path -LiteralPath $Worktree)) {
        Write-Host "`n=== Phase0 Pre-Flight: Test Framework ===" -ForegroundColor Cyan
        $frameworkValid = Test-TestFramework -WorktreePath $Worktree -MavenSettingsPath $MavenSettings
        $result.checks.test_framework = $frameworkValid

        if (-not $frameworkValid.IsValid) {
            $result.can_proceed = $false
            $result.validation_status = 'FAIL'
            $result.issues += @{
                code = 'test_framework_invalid'
                message = 'Test framework validation failed'
                reason = $frameworkValid.Reason
            }
        }
    } else {
        $result.warnings += @{
            code = 'worktree_not_provided'
            message = 'Worktree not provided, skipping test framework check'
        }
    }

    # Run RED phase authorization check (if slice result exists)
    $sliceResult = Get-ChildItem -LiteralPath $ReplayRoot -Filter 'SLICE_RESULT_*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $sliceResult) {
        Write-Host "`n=== Phase0 Pre-Flight: RED Phase Authorization ===" -ForegroundColor Cyan
        $redAuthorized = Test-RedPhaseAuthorized -SliceResultPath $sliceResult.FullName -DiscoveryMode $DiscoveryMode
        $result.checks.red_phase_authorized = $redAuthorized

        if (-not $redAuthorized.IsValid) {
            $result.can_proceed = $false
            $result.validation_status = 'FAIL'
            $result.issues += @{
                code = 'red_phase_not_authorized'
                message = 'RED phase not authorized for GREEN'
                reason = $redAuthorized.Reason
            }
        }
    }

    # Write result
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    if ($result.can_proceed) {
        Write-Host "`nPhase0 pre-check: PASSED" -ForegroundColor Green
    } else {
        Write-Host "`nPhase0 pre-check: FAILED" -ForegroundColor Red
        foreach ($issue in $result.issues) {
            Write-Host "  [$($issue.code)] $($issue.message): $($issue.reason)" -ForegroundColor Red
        }
    }

    return $result
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'Test-TestFramework: Validates Maven test compilation',
            'Test-RedPhaseAuthorized: Validates RED phase result',
            'Prevents RC3 (implementation after blocked RED) and RC5 (test framework not pre-validated)',
            'Discovery Mode (Experiment 1): S1 may proceed with WARN layer validation'
        )
    }
    $result | Format-List
    exit 0
}

# Main execution
$result = Invoke-Phase0Precheck -ReplayRoot $ReplayRoot -Worktree $Worktree -MavenSettings $MavenSettings -DiscoveryMode $DiscoveryMode

exit $(if ($result.can_proceed) { 0 } else { 1 })
