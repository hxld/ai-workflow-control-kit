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
    param(
        [string]$Root,
        [string]$ClassName,
        [string]$MethodName = 'handle'
    )

    $dir = Join-Path $Root 'worktree\example-core\src\main\java\com\example'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Text -Path (Join-Path $dir "$ClassName.java") -Value @"
package com.example;

public class $ClassName {
    public void $MethodName(Long id) {
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v404-entry-path-" + [guid]::NewGuid().ToString('N'))

try {
    $pathRoot = Join-Path $tempRoot 'path-entry'
    New-WorktreeClass -Root $pathRoot -ClassName 'ExistingEntry' -MethodName 'handle'
    Write-Text -Path (Join-Path $pathRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

**selected_real_entry**: `example-core/src/main/java/com/example/ExistingEntry.handle`

## Search Commands Used

```
rg "class ExistingEntry|public void handle" --type java
```
'@
    $pathVerify = Invoke-CarrierVerify -Root $pathRoot
    Assert-True -Name 'path_style_class_method_passes' -Condition ($pathVerify.verification_status -eq 'PASS')
    Assert-True -Name 'path_style_entry_is_normalized' -Condition ($pathVerify.selected_real_entry -eq 'ExistingEntry.handle')
    Assert-True -Name 'path_style_method_extracted' -Condition ($pathVerify.selected_entry_method -eq 'handle')

    $packageRoot = Join-Path $tempRoot 'package-entry'
    New-WorktreeClass -Root $packageRoot -ClassName 'ExistingEntry' -MethodName 'handle'
    Write-Text -Path (Join-Path $packageRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

**selected_real_entry**: `com.example.ExistingEntry.handle(Long id)`

## Search Commands Used

```
rg "class ExistingEntry|handle" --type java
```
'@
    $packageVerify = Invoke-CarrierVerify -Root $packageRoot
    Assert-True -Name 'package_style_class_method_passes' -Condition ($packageVerify.verification_status -eq 'PASS')
    Assert-True -Name 'package_style_entry_is_normalized' -Condition ($packageVerify.selected_real_entry -eq 'ExistingEntry.handle(Long id)')

    $missingMethodRoot = Join-Path $tempRoot 'missing-method'
    New-WorktreeClass -Root $missingMethodRoot -ClassName 'ExistingEntry' -MethodName 'handle'
    Write-Text -Path (Join-Path $missingMethodRoot 'PHASE0_RESULT.md') -Value @'
# Phase 0 Result

**selected_real_entry**: `example-core/src/main/java/com/example/ExistingEntry.notRealMethod`

## Search Commands Used

```
rg "class ExistingEntry|notRealMethod" --type java
```
'@
    $missingMethodVerify = Invoke-CarrierVerify -Root $missingMethodRoot
    Assert-True -Name 'missing_method_fails' -Condition (@($missingMethodVerify.issues) -contains 'phase0_selected_real_entry_method_not_found')

    Write-Host 'PASS: v404 selected entry path and method gate'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
