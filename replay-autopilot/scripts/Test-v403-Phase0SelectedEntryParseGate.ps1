param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function New-WorktreeClass {
    param([string]$Root, [string]$ClassName)
    $dir = Join-Path $Root 'worktree\com\example'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Text -Path (Join-Path $dir "$ClassName.java") -Value @"
package com.example;

public class $ClassName {
    public void handle(Long id) {
    }
}
"@
}

function Invoke-CarrierVerify {
    param([string]$Root)
    $verifier = Join-Path $PSScriptRoot 'Verify-Phase0CarrierEvidence.ps1'
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $Root -Worktree (Join-Path $Root 'worktree') -ErrorAction SilentlyContinue
    return ($output | ConvertFrom-Json)
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v403-entry-parse-" + [guid]::NewGuid().ToString('N'))

try {
    $missingRoot = Join-Path $tempRoot 'missing'
    New-WorktreeClass -Root $missingRoot -ClassName 'ExistingEntry'
    Write-Text -Path (Join-Path $missingRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

## Search Commands Used

```
rg "class ExistingEntry" --type java
```
'@
    $missingVerify = Invoke-CarrierVerify -Root $missingRoot
    Assert-True -Name 'missing_selected_real_entry_fails' -Condition (@($missingVerify.issues) -contains 'phase0_selected_real_entry_missing')

    $carrierOnlyRoot = Join-Path $tempRoot 'carrier-only'
    New-WorktreeClass -Root $carrierOnlyRoot -ClassName 'ExistingEntry'
    Write-Text -Path (Join-Path $carrierOnlyRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

**selected_real_entry**:
- Carrier: `ExistingEntry`
- Status: EXISTING

## Search Commands Used

```
rg "class ExistingEntry" --type java
```
'@
    $carrierOnlyVerify = Invoke-CarrierVerify -Root $carrierOnlyRoot
    Assert-True -Name 'structured_carrier_only_is_parsed' -Condition ($carrierOnlyVerify.selected_real_entry -eq 'ExistingEntry')
    Assert-True -Name 'structured_carrier_only_fails_invalid_format' -Condition (@($carrierOnlyVerify.issues) -contains 'phase0_selected_real_entry_invalid_format')

    $validStructuredRoot = Join-Path $tempRoot 'valid-structured'
    New-WorktreeClass -Root $validStructuredRoot -ClassName 'ExistingEntry'
    Write-Text -Path (Join-Path $validStructuredRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

**selected_real_entry**:
- Entry: `ExistingEntry.handle(Long id)`
- Status: EXISTING

## Verified from Current Worktree

- `ExistingEntry.java` exists

## Search Commands Used

```
rg "class ExistingEntry" --type java
```
'@
    $validStructuredVerify = Invoke-CarrierVerify -Root $validStructuredRoot
    Assert-True -Name 'structured_method_entry_passes' -Condition ($validStructuredVerify.verification_status -eq 'PASS')
    Assert-True -Name 'structured_method_entry_extracted' -Condition ($validStructuredVerify.selected_real_entry -eq 'ExistingEntry.handle(Long id)')

    Write-Host 'PASS: v403 Phase0 selected entry parse gate'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
