# Test v357: STOP_AND_EVOLVE Experiments Validation
#
# Tests the three experiments from NEXT_EXPERIMENT_PLAN.md:
# 1. Entry Point Verification Gate (validate_entry_point_mapping.py)
# 2. Pre-Slice Test Charter Validation (validate_test_charter.py)
# 3. Horizontal Slice Pre-Check (validate_horizontal_coverage.py)

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $PSScriptRoot

# Summary tracking
$TotalTests = 0
$PassedTests = 0
$FailedTests = 0
$TestResults = @()

function Test-Experiment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedExitCode = '0'
    )

    $script:TotalTests++

    Write-Host "TEST $script:TotalTests`: $Name" -ForegroundColor Cyan

    $fullPath = Join-Path $ScriptRoot $ScriptPath

    if (-not (Test-Path $fullPath)) {
        Write-Host "  FAIL: Script not found: $fullPath" -ForegroundColor Red
        $script:FailedTests++
        $script:TestResults += @{
            Name = $Name
            Status = 'FAIL'
            Reason = 'Script not found'
        }
        return $false
    }

    try {
        # Run Python script
        $output = & python3 $fullPath $Arguments.Split(' ') 2>&1
        $exitCode = $LASTEXITCODE

        # Check exit code
        $exitCodeStr = $exitCode.ToString()
        if ($exitCodeStr -eq $ExpectedExitCode) {
            Write-Host "  PASS: Exit code $exitCode (expected $ExpectedExitCode)" -ForegroundColor Green
            $script:PassedTests++
            $script:TestResults += @{
                Name = $Name
                Status = 'PASS'
                ExitCode = $exitCode
            }
            return $true
        } else {
            Write-Host "  FAIL: Exit code $exitCode (expected $ExpectedExitCode)" -ForegroundColor Red
            Write-Host "  Output: $output" -ForegroundColor Gray
            $script:FailedTests++
            $script:TestResults += @{
                Name = $Name
                Status = 'FAIL'
                ExitCode = $exitCode
                ExpectedExitCode = $ExpectedExitCode
                Output = $output.Substring(0, [Math]::Min(200, $output.Length))
            }
            return $false
        }
    }
    catch {
        Write-Host "  FAIL: Exception: $($_.Exception.Message)" -ForegroundColor Red
        $script:FailedTests++
        $script:TestResults += @{
            Name = $Name
            Status = 'FAIL'
            Reason = $_.Exception.Message
        }
        return $false
    }
}

function Test-ScriptSyntax {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $script:TotalTests++
    $Name = "Syntax check: $ScriptPath"

    Write-Host "TEST $script:TotalTests`: $Name" -ForegroundColor Cyan

    $fullPath = Join-Path $ScriptRoot $ScriptPath

    if (-not (Test-Path $fullPath)) {
        Write-Host "  FAIL: Script not found" -ForegroundColor Red
        $script:FailedTests++
        return $false
    }

    # Check Python syntax
    $syntaxCheck = & python3 -m py_compile $fullPath 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  PASS: Python syntax valid" -ForegroundColor Green
        $script:PassedTests++
        $script:TestResults += @{
            Name = $Name
            Status = 'PASS'
        }
        return $true
    } else {
        Write-Host "  FAIL: Syntax error" -ForegroundColor Red
        Write-Host "  $syntaxCheck" -ForegroundColor Gray
        $script:FailedTests++
        $script:TestResults += @{
            Name = $Name
            Status = 'FAIL'
            Reason = $syntaxCheck
        }
        return $false
    }
}

function New-TempFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines,

        [Parameter(Mandatory = $false)]
        [string]$Extension = 'json'
    )

    $tempFile = [System.IO.Path]::GetTempFileName()
    $tempFile = $tempFile -replace '\.tmp$', ".$Extension"
    $Lines | Out-File -FilePath $tempFile -Encoding UTF8 -Force
    return $tempFile
}

# === BEGIN TESTS ===

Write-Host ""
Write-Host "=== v357 STOP_AND_EVOLVE Experiments Validation ===" -ForegroundColor Magenta
Write-Host ""

# Test 1-3: Script syntax checks
Write-Host "--- Syntax Checks ---" -ForegroundColor Yellow

Test-ScriptSyntax 'validate_horizontal_coverage.py'
Test-ScriptSyntax 'validate_test_charter.py'
Test-ScriptSyntax 'validate_entry_point_mapping.py'

# Test 4: Horizontal Coverage - Valid case
Write-Host "`n--- Experiment 3: Horizontal Coverage ---" -ForegroundColor Yellow

$validSliceLines = @(
    '{',
    '  "planned_files": [',
    '    "example-web/src/main/java/com/example/project/web/controller/ExampleController.java",',
    '    "example-core/src/main/java/com/example/project/service/ExampleService.java",',
    '    "example-provider/src/main/java/com/example/project/provider/ExampleMapper.java"',
    '  ]',
    '}'
)
$validSliceFile = New-TempFile -Lines $validSliceLines -Extension 'json'

Test-Experiment `
    -Name 'Horizontal Coverage: Valid 3-category slice' `
    -ScriptPath 'validate_horizontal_coverage.py' `
    -Arguments "--slice_plan $validSliceFile --min_categories 3" `
    -ExpectedExitCode '0'

Remove-Item $validSliceFile -Force

# Test 5: Horizontal Coverage - Invalid case (Backend only)
$invalidSliceLines = @(
    '{',
    '  "planned_files": [',
    '    "example-core/src/main/java/com/example/project/service/ExampleService.java",',
    '    "example-core/src/main/java/com/example/project/service/ExampleServiceImpl.java"',
    '  ]',
    '}'
)
$invalidSliceFile = New-TempFile -Lines $invalidSliceLines -Extension 'json'

Test-Experiment `
    -Name 'Horizontal Coverage: Invalid Backend-only slice (should FAIL)' `
    -ScriptPath 'validate_horizontal_coverage.py' `
    -Arguments "--slice_plan $invalidSliceFile --min_categories 3" `
    -ExpectedExitCode '1'

Remove-Item $invalidSliceFile -Force

# Test 6: Test Charter - Valid case
Write-Host "`n--- Experiment 2: Test Charter Validation ---" -ForegroundColor Yellow

$validTestLines = @(
    'import org.junit.Test;',
    'import static org.assertj.core.api.Assertions.assertThat;',
    '',
    'public class ExampleServiceTest {',
    '    @Test',
    '    public void testProcessClaim_Success_ReturnsExpectedResult() {',
    '        String result = service.processClaim("12345");',
    '        assertThat(result).isEqualTo("SUCCESS");',
    '    }',
    '}'
)
$validTestFile = New-TempFile -Lines $validTestLines -Extension 'java'

Test-Experiment `
    -Name 'Test Charter: Valid behavioral assertions' `
    -ScriptPath 'validate_test_charter.py' `
    -Arguments "--test_file $validTestFile --mode validate" `
    -ExpectedExitCode '0'

Remove-Item $validTestFile -Force

# Test 7: Test Charter - Invalid case (fail() anti-pattern)
$invalidTestLines = @(
    'import org.junit.Test;',
    '',
    'public class ExampleServiceTest {',
    '    @Test',
    '    public void testProcessClaim_NotYetImplemented() {',
    '        fail("Process claim should return success, but due to not implemented, this assertion fails");',
    '    }',
    '}'
)
$invalidTestFile = New-TempFile -Lines $invalidTestLines -Extension 'java'

Test-Experiment `
    -Name 'Test Charter: Invalid fail() anti-pattern (should FAIL)' `
    -ScriptPath 'validate_test_charter.py' `
    -Arguments "--test_file $invalidTestFile --mode validate" `
    -ExpectedExitCode '1'

Remove-Item $invalidTestFile -Force

# Test 8: Entry Point Mapping - Valid case
Write-Host "`n--- Experiment 1: Entry Point Verification ---" -ForegroundColor Yellow

$reqLines = @(
    '# Requirement: AI核赔申请',
    '',
    '当用户提交AI核赔申请成功后，系统触发核赔流程。',
    '申请成功后，通过ExampleApplyClaimApiTaskProcessor处理申请结果。'
)
$reqFile = New-TempFile -Lines $reqLines -Extension 'md'

$ledgerLines = @(
    '{',
    '  "families": [',
    '    {',
    '      "id": "core_entry",',
    '      "first_executable_carrier": "ExampleApplyClaimApiTaskProcessor.handleTaskResponse (verified in worktree)"',
    '    }',
    '  ]',
    '}'
)
$ledgerFile = New-TempFile -Lines $ledgerLines -Extension 'json'

Test-Experiment `
    -Name 'Entry Point: Valid carrier matches requirement (ExampleApplyClaim)' `
    -ScriptPath 'validate_entry_point_mapping.py' `
    -Arguments "--requirement $reqFile --ledger $ledgerFile" `
    -ExpectedExitCode '0'

Remove-Item $reqFile, $ledgerFile -Force

# Test 9: Entry Point Mapping - Invalid case (wrong carrier)
$reqLines2 = @(
    '# Requirement: AI核赔申请',
    '',
    '当用户提交AI核赔申请成功后，系统触发核赔流程。'
)
$reqFile2 = New-TempFile -Lines $reqLines2 -Extension 'md'

$invalidLedgerLines = @(
    '{',
    '  "families": [',
    '    {',
    '      "id": "core_entry",',
    '      "first_executable_carrier": "ExampleCalculatorApiTaskProcessor.handleTaskResponse (verified in worktree)"',
    '    }',
    '  ]',
    '}'
)
$invalidLedgerFile = New-TempFile -Lines $invalidLedgerLines -Extension 'json'

Test-Experiment `
    -Name 'Entry Point: Invalid carrier (ExampleCalculator instead of ExampleApplyClaim, should FAIL)' `
    -ScriptPath 'validate_entry_point_mapping.py' `
    -Arguments "--requirement $reqFile2 --ledger $invalidLedgerFile" `
    -ExpectedExitCode '1'

Remove-Item $reqFile2, $invalidLedgerFile -Force

# === SUMMARY ===

Write-Host "`n=== TEST SUMMARY ===" -ForegroundColor Magenta
Write-Host "Total: $TotalTests, Passed: $PassedTests, Failed: $FailedTests" -ForegroundColor White

if ($FailedTests -eq 0) {
    Write-Host "All tests PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$FailedTests test(s) FAILED" -ForegroundColor Red

    # Show failed test details
    Write-Host "`nFailed tests:" -ForegroundColor Red
    foreach ($result in $TestResults) {
        if ($result.Status -eq 'FAIL') {
            $reason = if ($result.Reason) { $result.Reason } elseif ($result.Output) { $result.Output } else { 'Unknown' }
            Write-Host "  - $($result.Name): $reason" -ForegroundColor Red
        }
    }

    exit 1
}
