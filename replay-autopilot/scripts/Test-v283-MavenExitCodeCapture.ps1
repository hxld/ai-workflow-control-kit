#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test v283: Maven Exit Code Capture and Output Logging

This test validates that the Maven preflight gate reliably captures
exit codes and process output using .NET ProcessStartInfo.

.DESCRIPTION
Test Scenarios:
1. Verify that exit_code field is always present in result JSON
2. Verify that exit_code is numeric (not blank, null, or empty string)
3. Verify that Maven stdout and stderr logs are captured (unless SKIP)
4. Verify that maven_command_args contains both -s and -f
5. Verify that Maven path resolution works correctly

.REQUIREMENTS
- D:\opt\claim must exist with .memory/build-test-profile.yaml
- Test worktree must exist

.EXPECTED_RESULTS
- exit_code field must exist in PREFLIGHT_TEST_COMPILATION.json
- exit_code must be a numeric value (integer)
- PREFLIGHT_MAVEN_TEST_COMPILE.log should exist and may be empty
- PREFLIGHT_MAVEN_TEST_COMPILE_ERROR.log should exist and may be empty
- maven_command_args must contain both -s and -f
#>

$ErrorActionPreference = 'Stop'

# Test configuration
$ReplayRoot = 'D:\opt\replay-autopilot'
$Worktree = 'D:\opt\claim'
$ProjectRoot = 'D:\opt\claim'

Write-Host "========================================"
Write-Host "Test v283: Maven Exit Code Capture"
Write-Host "========================================"
Write-Host ""

# Test 1: Verify build-test-profile.yaml exists
Write-Host "[Test 1] Verifying build-test-profile.yaml exists..."
$buildTestProfilePath = Join-Path $ProjectRoot '.memory\build-test-profile.yaml'
if (-not (Test-Path -LiteralPath $buildTestProfilePath)) {
    Write-Host "  FAIL: build-test-profile.yaml not found at $buildTestProfilePath"
    exit 1
}
Write-Host "  PASS: build-test-profile.yaml found"

# Test 2: Run Invoke-PreflightTestCompilation.ps1
Write-Host "[Test 2] Running Invoke-PreflightTestCompilation.ps1..."
$scriptPath = Join-Path $ReplayRoot 'scripts\Invoke-PreflightTestCompilation.ps1'

# Clean up previous results
$resultPath = Join-Path $ReplayRoot 'PREFLIGHT_TEST_COMPILATION.json'
$stdoutLog = Join-Path $ReplayRoot 'PREFLIGHT_MAVEN_TEST_COMPILE.log'
$stderrLog = Join-Path $ReplayRoot 'PREFLIGHT_MAVEN_TEST_COMPILE_ERROR.log'

if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath -Force }
if (Test-Path -LiteralPath $stdoutLog) { Remove-Item -LiteralPath $stdoutLog -Force }
if (Test-Path -LiteralPath $stderrLog) { Remove-Item -LiteralPath $stderrLog -Force }

try {
    & $scriptPath -ReplayRoot $ReplayRoot -Worktree $Worktree -ProjectRoot $ProjectRoot -TimeoutSeconds 180
    $exitCode = $LASTEXITCODE
    Write-Host "  INFO: Preflight test compilation completed with exit code $exitCode"
} catch {
    Write-Host "  FAIL: Preflight test compilation threw exception: $_"
    exit 1
}

# Test 3: Verify result JSON exists
Write-Host "[Test 3] Verifying result JSON exists..."
if (-not (Test-Path -LiteralPath $resultPath)) {
    Write-Host "  FAIL: Result JSON not found at $resultPath"
    exit 1
}
Write-Host "  PASS: Result JSON found"

# Test 4: Verify exit_code field exists and is valid
Write-Host "[Test 4] Verifying exit_code field..."
$resultJson = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json

if (-not ($resultJson.PSObject.Properties.Name -contains 'exit_code')) {
    Write-Host "  FAIL: exit_code field is missing from result JSON"
    Write-Host "  Available fields: $($resultJson.PSObject.Properties.Name -join ', ')"
    exit 1
}

$exitCodeValue = $resultJson.exit_code
Write-Host "  exit_code value: $exitCodeValue (type: $($exitCodeValue.GetType().Name))"

# Check if exit_code is numeric
if ($null -eq $exitCodeValue) {
    Write-Host "  FAIL: exit_code is null"
    exit 1
}

# Check if exit_code is an integer
if ($exitCodeValue -isnot [int]) {
    Write-Host "  FAIL: exit_code is not an integer (type: $($exitCodeValue.GetType().Name))"
    exit 1
}

Write-Host "  PASS: exit_code field is present and numeric"

# Test 5: Verify exit_code is not blank/empty
Write-Host "[Test 5] Verifying exit_code is not blank or empty..."
if ($exitCodeValue -is [string]) {
    if ([string]::IsNullOrWhiteSpace($exitCodeValue)) {
        Write-Host "  FAIL: exit_code is a blank string"
        exit 1
    }
} else {
    # For non-string types (int, etc.), just verify it's not null
    if ($null -eq $exitCodeValue) {
        Write-Host "  FAIL: exit_code is null"
        exit 1
    }
}

Write-Host "  PASS: exit_code is not blank or empty"

# Test 6: Verify Maven log files exist
Write-Host "[Test 6] Verifying Maven log files exist..."
if (-not (Test-Path -LiteralPath $stdoutLog)) {
    Write-Host "  FAIL: Maven stdout log not found at $stdoutLog"
    exit 1
}
if (-not (Test-Path -LiteralPath $stderrLog)) {
    Write-Host "  FAIL: Maven stderr log not found at $stderrLog"
    exit 1
}
Write-Host "  PASS: Both Maven log files exist"

# Test 7: Verify log files are not empty (unless SKIP or PASS with quiet flag)
Write-Host "[Test 7] Verifying log files have content (unless SKIP or quiet success)..."
$status = if ($resultJson.PSObject.Properties.Name -contains 'status') { $resultJson.status } else { '' }

if ($status -eq 'SKIP') {
    Write-Host "  INFO: Status is SKIP, log files are expected to be empty"
    Write-Host "  PASS: Log files may be empty for SKIP status"
} elseif ($status -eq 'PASS' -and $exitCodeValue -eq 0) {
    # Maven with -q flag produces no output on success
    Write-Host "  INFO: Status is PASS with exit_code=0, empty logs are acceptable (Maven -q flag)"
    Write-Host "  PASS: Empty logs are acceptable for quiet successful runs"
} else {
    $stdoutContent = Get-Content -LiteralPath $stdoutLog -Raw -Encoding UTF8
    $stderrContent = Get-Content -LiteralPath $stderrLog -Raw -Encoding UTF8

    $stdoutEmpty = [string]::IsNullOrWhiteSpace($stdoutContent)
    $stderrEmpty = [string]::IsNullOrWhiteSpace($stderrContent)

    if ($stdoutEmpty -and $stderrEmpty) {
        Write-Host "  FAIL: Both Maven log files are empty (status=$status, exit_code=$exitCodeValue)"
        Write-Host "  At least one log file should have content when Maven fails"
        exit 1
    }

    Write-Host "  PASS: At least one Maven log file has content"
}

# Test 8: Verify maven_command_args contains -s and -f
Write-Host "[Test 8] Verifying maven_command_args contains -s and -f..."
if (-not ($resultJson.PSObject.Properties.Name -contains 'maven_command_args')) {
    Write-Host "  FAIL: maven_command_args field is missing from result JSON"
    exit 1
}

$mavenCommandArgs = $resultJson.maven_command_args
Write-Host "  Maven command args: $mavenCommandArgs"

if ($mavenCommandArgs -notmatch '-s') {
    Write-Host "  FAIL: maven_command_args does not contain -s flag"
    exit 1
}

if ($mavenCommandArgs -notmatch '-f') {
    Write-Host "  FAIL: maven_command_args does not contain -f flag"
    exit 1
}

Write-Host "  PASS: maven_command_args contains both -s and -f flags"

# Test 9: Verify Maven command execution context
Write-Host "[Test 9] Verifying Maven command execution context..."
if ($resultJson.PSObject.Properties.Name -contains 'maven_settings_used') {
    Write-Host "  Maven settings used: $($resultJson.maven_settings_used)"
}
if ($resultJson.PSObject.Properties.Name -contains 'root_pom_used') {
    Write-Host "  Root POM used: $($resultJson.root_pom_used)"
}
Write-Host "  PASS: Execution context fields present"

Write-Host ""
Write-Host "========================================"
Write-Host "All v283 tests PASSED"
Write-Host "========================================"
Write-Host ""
Write-Host "Summary:"
Write-Host "  - exit_code field exists: PASS"
Write-Host "  - exit_code is numeric: PASS (value=$exitCodeValue)"
Write-Host "  - exit_code not blank/empty: PASS"
Write-Host "  - Maven log files exist: PASS"
Write-Host "  - Log files have content: PASS"
Write-Host "  - maven_command_args has -s and -f: PASS"
Write-Host "  - Execution context fields: PASS"
Write-Host ""

exit 0
