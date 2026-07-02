param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "ASSERT FAILED: $Name" }
        throw "ASSERT FAILED: $Name - $Details"
    }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$prevalidator = Join-Path $scriptRoot 'Invoke-TestCharterPrevalidator.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("test-v609-charter-underscore-entry-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    Write-Host "`n=== Scenario 1: entry_point: (underscore machine format) ==="

    Write-Text (Join-Path $tempRoot 'TEST_CHARTER.md') @'
# Test Charter

## Overview
- test_surface: example-server test harness (JUnit + Mockito, no Spring)
- entry_point: AbstractSampleProcessor.handleTaskResponse -> SampleProcessor.handleTaskResponse
- test_class: SampleProcessorTest (NEW)
- test_method: shouldTriggerAutoFlow_whenConditionsMet

## RED Phase

### Test 1: shouldTriggerAutoFlow_whenConditionsMet
| Field | Value |
|-------|-------|
| Given: | SampleTask with caseId=12345, createUserId=null |
| When: | handleTaskResponse is called |
| Then: | sampleService.processAutoFlow is invoked once |
| Expected assertion: | `verify(sampleService, times(1)).processAutoFlow(...)` |

## GREEN Phase

### Test 2: shouldHandleAutoFlowExceptionGracefully
| Field | Value |
|-------|-------|
| Given: | sampleService.processAutoFlow throws RuntimeException |
| When: | handleTaskResponse is called |
| Then: | Exception caught; main flow continues |

## DB/Transaction Tests
- S1 tests are unit-level with mocked dependencies
- Full DB transaction tests are in S2

## Side Effects
- verify: assertEquals expected state
'@

    $result1 = & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $tempRoot -PassThru
    $exit1 = $LASTEXITCODE
    $parsed1 = ($result1 | Out-String) | ConvertFrom-Json

    Write-Host "  exit_code: $exit1"
    $failureCodes = @($parsed1.failures | ForEach-Object { $_.code })
    Write-Host "  failure_codes: $($failureCodes -join ', ')"

    Assert-True 'entry_point_underscore_prevalidator_passes' ($exit1 -eq 0) "Prevalidator rejected entry_point: format -- exit code $exit1"
    Assert-True 'entry_point_no_missing_entry_point_failure' (-not ($failureCodes -contains 'MISSING_ENTRY_POINT')) "Got MISSING_ENTRY_POINT failure despite entry_point: field"

    Write-Host "`n=== Scenario 2: Legacy Entry Point: (space format) still accepted ==="

    Remove-Item -LiteralPath (Join-Path $tempRoot 'TEST_CHARTER.md') -Force
    Write-Text (Join-Path $tempRoot 'TEST_CHARTER.md') @'
# Test Charter

## RED Phase

### S1-RED: SampleCarrier.execute returns missing source values
- **Test Class**: SampleCarrierTest
- **Test method**: shouldPreserveSourceValuesAfterRebuild
- **Entry Point**: `SampleCarrier.execute(Long id)` via reflection

**DB Verification**: AtomicReference capture verifies request source values.

**Side Effects**:
- verify: assertEquals expected state after execute
'@

    $result2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $tempRoot -PassThru
    Assert-True 'legacy_entry_point_still_accepted' ($LASTEXITCODE -eq 0) "Prevalidator rejected legacy Entry Point: format -- exit code $LASTEXITCODE"

    Write-Host "`n=== Scenario 3: entry_point: present but no RED/GREEN sections ==="

    Remove-Item -LiteralPath (Join-Path $tempRoot 'TEST_CHARTER.md') -Force
    Write-Text (Join-Path $tempRoot 'TEST_CHARTER.md') @'
# Test Charter
- entry_point: SampleProcessor.handleTaskResponse
- test_class: SampleProcessorTest

This charter has no RED or GREEN phase sections.
'@

    $result3 = & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $tempRoot -PassThru
    $exit3 = $LASTEXITCODE
    $parsed3 = ($result3 | Out-String) | ConvertFrom-Json
    $failureCodes3 = @($parsed3.failures | ForEach-Object { $_.code })
    $warningCodes3 = @($parsed3.warnings | ForEach-Object { $_.code })

    Write-Host "  exit_code: $exit3"
    Write-Host "  failures: $($failureCodes3 -join ', ')"
    Write-Host "  warnings: $($warningCodes3 -join ', ')"

    Assert-True 'entry_only_no_red_still_passes_prevalidator' ($exit3 -eq 0) "Prevalidator rejected charter with only entry_point: -- exit code $exit3"

    Write-Host "`n=== All Scenarios Passed ==="
    $result = [ordered]@{
        status = 'PASS'
        script = $PSCommandPath
        version = 'v609'
        evolution_type = 'test_charter_entry_point_underscore'
        scenarios = @(
            'entry_point_underscore_accepted',
            'legacy_entry_point_still_accepted',
            'no_regression_on_other_validations'
        )
    }
    $result | ConvertTo-Json -Depth 6
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
