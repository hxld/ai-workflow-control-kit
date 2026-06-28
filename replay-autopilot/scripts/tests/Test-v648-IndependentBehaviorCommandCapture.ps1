#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v648-command-capture-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $worktree = Join-Path $tempRoot 'worktree'
    $testDir = Join-Path $worktree 'demo-module\src\test\java\demo'
    $mainDir = Join-Path $worktree 'demo-module\src\main\java\demo'
    New-Item -ItemType Directory -Force -Path $testDir,$mainDir | Out-Null
    & git -C $tempRoot init | Out-Null
    & git -C $tempRoot config user.email test@example.invalid | Out-Null
    & git -C $tempRoot config user.name test | Out-Null
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    & git -C $worktree init | Out-Null
    & git -C $worktree config user.email test@example.invalid | Out-Null
    & git -C $worktree config user.name test | Out-Null
    Write-Utf8 (Join-Path $mainDir 'RealEntry.java') @'
package demo;

public class RealEntry {
    public String handle(String value) {
        return value;
    }
}
'@
    Write-Utf8 (Join-Path $testDir 'RealEntryTest.java') @'
package demo;

public class RealEntryTest {
    public void returnsMappedPayload() {
        new RealEntry().handle("x");
    }
}
'@
    & git -C $worktree add . | Out-Null
    & git -C $worktree commit -m baseline | Out-Null
    Write-Utf8 (Join-Path $mainDir 'RealEntry.java') @'
package demo;

public class RealEntry {
    public String handle(String value) {
        return "mapped:" + value;
    }
}
'@

    $sliceResult = Join-Path $tempRoot 'SLICE_RESULT_01.json'
    @{
        slice_index = 1
        slice_id = 'S1'
        slice_status = 'DONE'
        slice_type = 'stateful_success_slice'
        coverage_delta = 30
        target_subsurface_or_carrier = 'demo.RealEntry.handle(String)'
        production_boundary = 'demo.RealEntry.handle(String)'
        proof_kind = 'real_entry_behavior'
        red_expectation = 'RealEntryTest fails before mapping'
        implemented_files = @('demo-module/src/main/java/demo/RealEntry.java', 'demo-module/src/test/java/demo/RealEntryTest.java')
        current_slice_changed_files = @('demo-module/src/main/java/demo/RealEntry.java', 'demo-module/src/test/java/demo/RealEntryTest.java')
        round_changed_files_snapshot = @('demo-module/src/main/java/demo/RealEntry.java', 'demo-module/src/test/java/demo/RealEntryTest.java')
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        tests = @(
            @{ phase = 'GREEN'; result = 'pass'; evidence = 'BUILD SUCCESS' }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sliceResult -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $tempRoot `
        -Worktree $worktree `
        -SliceResult $sliceResult `
        -SliceIndex 1 | Out-Null

    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not [bool]$verify.authorized_for_next_slice) 'missing independent command must block next slice authorization'
    Assert-True ([int]$verify.adjusted_coverage_delta -eq 0) 'missing independent command must force adjusted coverage to zero'
    Assert-True (@($verify.gap_flags) -contains 'test_command_evidence_missing') 'missing independent command must emit test_command_evidence_missing'

    Write-Host 'v648 Independent Behavior Command Capture: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
