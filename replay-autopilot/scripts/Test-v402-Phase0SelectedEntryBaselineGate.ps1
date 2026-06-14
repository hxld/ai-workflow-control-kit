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

function Invoke-CarrierVerify {
    param([string]$Root)
    $verifier = Join-Path $PSScriptRoot 'Verify-Phase0CarrierEvidence.ps1'
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $Root -Worktree (Join-Path $Root 'worktree') -ErrorAction SilentlyContinue
    return ($output | ConvertFrom-Json)
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v402-entry-gate-" + [guid]::NewGuid().ToString('N'))

try {
    $newCarrierRoot = Join-Path $tempRoot 'new-carrier'
    New-WorktreeClass -Root $newCarrierRoot -ClassName 'ExistingEntry'
    Write-Text -Path (Join-Path $newCarrierRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

- selected_real_entry: ExampleFlowService (planned_new_carrier per oracle)

## Verified from Current Worktree

- `ExistingEntry.java` exists

## Search Commands Used

```
rg "class ExistingEntry" --type java
```
'@

    $newCarrierVerify = Invoke-CarrierVerify -Root $newCarrierRoot
    Assert-True -Name 'planned_new_carrier_is_not_baseline_entry' -Condition (@($newCarrierVerify.issues) -contains 'phase0_selected_real_entry_not_baseline_existing')
    Assert-True -Name 'planned_new_carrier_class_only_is_invalid_format' -Condition (@($newCarrierVerify.issues) -contains 'phase0_selected_real_entry_invalid_format')

    $classOnlyRoot = Join-Path $tempRoot 'class-only'
    New-WorktreeClass -Root $classOnlyRoot -ClassName 'ExistingEntry'
    Write-Text -Path (Join-Path $classOnlyRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

- selected_real_entry: ExistingEntry

## Verified from Current Worktree

- `ExistingEntry.java` exists

## Search Commands Used

```
rg "class ExistingEntry" --type java
```
'@

    $classOnlyVerify = Invoke-CarrierVerify -Root $classOnlyRoot
    Assert-True -Name 'class_only_entry_is_invalid_format' -Condition (@($classOnlyVerify.issues) -contains 'phase0_selected_real_entry_invalid_format')

    $validRoot = Join-Path $tempRoot 'valid'
    New-WorktreeClass -Root $validRoot -ClassName 'ExistingEntry'
    Write-Text -Path (Join-Path $validRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

- selected_real_entry: ExistingEntry.handle(Long id)
- carrier_class: com.example.ExistingEntry
- carrier_status: EXISTING

## Verified from Current Worktree

- `ExistingEntry.java` exists

## Search Commands Used

```
rg "class ExistingEntry" --type java
```
'@

    $validVerify = Invoke-CarrierVerify -Root $validRoot
    Assert-True -Name 'valid_existing_method_entry_passes' -Condition ($validVerify.verification_status -eq 'PASS')

    Write-Host 'PASS: v402 Phase0 selected entry baseline gate'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
