# Test-V447TriggerPointValidation.ps1
# Tests for V447 Experiment 1: Correct Trigger Point Selection

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$ValidatorScript = Join-Path $ScriptRoot "trigger_point_validator.py"

function Test-PythonScriptExists {
    Write-Host "TEST: Check if trigger_point_validator.py exists" -ForegroundColor Cyan
    if (-not (Test-Path $ValidatorScript)) {
        Write-Host "FAIL: trigger_point_validator.py not found at $ValidatorScript" -ForegroundColor Red
        return $false
    }
    Write-Host "PASS: trigger_point_validator.py found" -ForegroundColor Green
    return $true
}

function Test-TriggerPointExtraction {
    Write-Host "TEST: Extract trigger point from requirement text" -ForegroundColor Cyan

    $testCases = @(
        @{
            Requirement = "AI核赔结果获取成功后，自动流转到审核环节"
            Expected = "AI核赔结果获取成功后"
        },
        @{
            Requirement = "赔款计算成功后，生成理算明细"
            Expected = "赔款计算成功后"
        },
        @{
            Requirement = "案件受理后进行核赔"
            Expected = $null
        }
    )

    $allPassed = $true
    foreach ($testCase in $testCases) {
        $result = python $ValidatorScript extract $testCase.Requirement 2>&1 | ConvertFrom-Json
        if ($result.trigger_point -eq $testCase.Expected) {
            Write-Host "  PASS: '$($testCase.Requirement)' -> '$($result.trigger_point)'" -ForegroundColor Green
        } else {
            Write-Host "  FAIL: Expected '$($testCase.Expected)', got '$($result.trigger_point)'" -ForegroundColor Red
            $allPassed = $false
        }
    }

    return $allPassed
}

function Test-TriggerPointValidation {
    Write-Host "TEST: Validate trigger point against selected carrier" -ForegroundColor Cyan

    $testCases = @(
        @{
            Requirement = "AI核赔结果获取成功后，自动流转"
            Carrier = "ExampleCalculatorApiTaskProcessor"
            ShouldPass = $false
            Reason = "Wrong: AI核赔 should use ExampleApplyClaimApiTaskProcessor"
        },
        @{
            Requirement = "AI核赔结果获取成功后，自动流转"
            Carrier = "ExampleApplyClaimApiTaskProcessor"
            ShouldPass = $true
            Reason = "Correct: AI核赔 maps to ExampleApplyClaimApiTaskProcessor"
        },
        @{
            Requirement = "赔款计算成功后"
            Carrier = "ExampleCalculatorApiTaskProcessor"
            ShouldPass = $true
            Reason = "Correct: 赔款计算 maps to ExampleCalculatorApiTaskProcessor"
        },
        @{
            Requirement = "赔款计算成功后"
            Carrier = "ExampleApplyClaimApiTaskProcessor"
            ShouldPass = $false
            Reason = "Wrong: 赔款计算 should use ExampleCalculatorApiTaskProcessor"
        }
    )

    $allPassed = $true
    foreach ($testCase in $testCases) {
        $result = python $ValidatorScript validate $testCase.Requirement $testCase.Carrier 2>&1 | ConvertFrom-Json

        if ($testCase.ShouldPass) {
            if ($result.valid -eq $true) {
                Write-Host "  PASS: $($testCase.Reason)" -ForegroundColor Green
            } else {
                Write-Host "  FAIL: Expected to pass but failed: $($testCase.Reason)" -ForegroundColor Red
                Write-Host "    Error: $($result.error)" -ForegroundColor Red
                $allPassed = $false
            }
        } else {
            if ($result.valid -eq $false) {
                Write-Host "  PASS: Correctly rejected - $($testCase.Reason)" -ForegroundColor Green
            } else {
                Write-Host "  FAIL: Should have failed but passed: $($testCase.Reason)" -ForegroundColor Red
                $allPassed = $false
            }
        }
    }

    return $allPassed
}

function Test-CarrierSuggestion {
    Write-Host "TEST: Suggest correct carrier based on trigger point" -ForegroundColor Cyan

    $requirement = "AI核赔结果获取成功后"
    $availableCarriers = @(
        "ExampleCalculatorApiTaskProcessor",
        "ExampleApplyClaimApiTaskProcessor",
        "CaseFlowStatusService"
    ) | ConvertTo-Json

    $result = python $ValidatorScript suggest $requirement $availableCarriers 2>&1 | ConvertFrom-Json

    if ($result.suggested_carrier -eq "ExampleApplyClaimApiTaskProcessor") {
        Write-Host "  PASS: Correctly suggested ExampleApplyClaimApiTaskProcessor" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  FAIL: Expected ExampleApplyClaimApiTaskProcessor, got $($result.suggested_carrier)" -ForegroundColor Red
        return $false
    }
}

function Test-V446BugReproduction {
    Write-Host "TEST: Reproduce v446 bug (wrong carrier selection)" -ForegroundColor Cyan

    # This is the exact bug from v446
    $requirement = "AI核赔结果获取成功后，自动流转到保险公司理算"
    $wrongCarrier = "ExampleCalculatorApiTaskProcessor"

    $result = python $ValidatorScript validate $requirement $wrongCarrier 2>&1 | ConvertFrom-Json

    if ($result.valid -eq $false) {
        Write-Host "  PASS: v446 bug detected - ExampleCalculatorApiTaskProcessor correctly rejected for AI核赔 trigger" -ForegroundColor Green
        Write-Host "    Error message: $($result.error)" -ForegroundColor Cyan
        return $true
    } else {
        Write-Host "  FAIL: v446 bug NOT detected - wrong carrier incorrectly accepted" -ForegroundColor Red
        return $false
    }
}

function Test-PromptExists {
    Write-Host "TEST: Check if V447_TRIGGER_POINT_VALIDATION.md prompt exists" -ForegroundColor Cyan

    $promptPath = Join-Path $RepoRoot "prompts\V447_TRIGGER_POINT_VALIDATION.md"
    if (Test-Path $promptPath) {
        Write-Host "PASS: V447_TRIGGER_POINT_VALIDATION.md found" -ForegroundColor Green
        return $true
    } else {
        Write-Host "FAIL: V447_TRIGGER_POINT_VALIDATION.md not found" -ForegroundColor Red
        return $false
    }
}

# Run all tests
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "V447 Trigger Point Validation Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$results = @()
$results += Test-PythonScriptExists
$results += Test-PromptExists
$results += Test-TriggerPointExtraction
$results += Test-TriggerPointValidation
$results += Test-CarrierSuggestion
$results += Test-V446BugReproduction

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passed = ($results | Where-Object { $_ -eq $true }).Count
$total = $results.Count

Write-Host "Passed: $passed / $total" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })

if ($passed -eq $total) {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests FAILED" -ForegroundColor Red
    exit 1
}
