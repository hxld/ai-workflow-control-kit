param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
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
$prevalidatorPython = Join-Path $scriptRoot 'test_charter_prevalidator.py'
$prevalidatorPythonText = Get-Content -LiteralPath $prevalidatorPython -Raw -Encoding UTF8
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("test-charter-synthetic-source-chain-v505-" + [guid]::NewGuid().ToString('N'))

try {
    Assert-True 'prevalidator_has_synthetic_source_chain_gate' ($prevalidatorPythonText.Contains('SYNTHETIC_SOURCE_CHAIN_CHARTER') -and $prevalidatorPythonText.Contains('SYNTHETIC_SOURCE_CHAIN_PATTERNS'))

    $badRoot = Join-Path $tempRoot 'bad'
    New-Item -ItemType Directory -Force -Path $badRoot | Out-Null
    Write-Text (Join-Path $badRoot 'TEST_CHARTER.md') @'
# Test Charter

## Test Class: SampleCarrierTest

**Entry Point**: `SampleCarrier.rebuildTaskData(Long caseId)`

**DB Verification**: AtomicReference capture verifies output state.

**Side Effects**:
- verify: assertEquals expected state after execute

**Transaction Test**: transaction rollback not required for this in-memory behavior proof.

```java
when(helper.buildRequestCommon(anyLong(), any(), any(), any(), any(), any(), any(), any(), any()))
    .thenAnswer(invocation -> {
        return new SampleRequest();
    });
```
'@

    $badOut = Join-Path $badRoot 'prevalidator-output.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $badRoot -PassThru > $badOut
    $badExit = $LASTEXITCODE
    $badResult = Get-Content -LiteralPath $badOut -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'synthetic_source_chain_charter_blocks' ($badExit -ne 0 -and -not [bool]$badResult.can_proceed)
    Assert-True 'synthetic_source_chain_failure_code_reported' ((@($badResult.failures | ForEach-Object { $_.code }) -contains 'SYNTHETIC_SOURCE_CHAIN_CHARTER'))

    $goodRoot = Join-Path $tempRoot 'good'
    New-Item -ItemType Directory -Force -Path $goodRoot | Out-Null
    Write-Text (Join-Path $goodRoot 'TEST_CHARTER.md') @'
# Test Charter

## Test Class: SampleCarrierTest

**Entry Point**: `SampleCarrier.rebuildTaskData(Long caseId)`

**DB Verification**: AtomicReference capture verifies output state.

**Side Effects**:
- verify: assertEquals expected state after execute

**Transaction Test**: transaction rollback not required for this in-memory behavior proof.

Plan: mock helper inputs, let the real production builder/carrier derive the request, then assert output state.
'@

    $goodOut = Join-Path $goodRoot 'prevalidator-output.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $goodRoot -PassThru > $goodOut
    $goodExit = $LASTEXITCODE
    $goodResult = Get-Content -LiteralPath $goodOut -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'real_source_chain_charter_passes' ($goodExit -eq 0 -and [bool]$goodResult.can_proceed)

    Write-Host 'PASS: v505 test charter synthetic source-chain gate'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
