# Regression test for v444 Phase0 Entry Markdown Format fix
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw $Name }
        throw "$Name :: $Details"
    }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('v444-entry-markdown-{0}' -f ([Guid]::NewGuid().ToString('N')))
$worktree = Join-Path $root 'worktree'
New-Item -ItemType Directory -Force -Path $worktree | Out-Null
& git -C $worktree init | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src') | Out-Null
Set-Content -LiteralPath (Join-Path $worktree 'src\Entry.java') -Encoding UTF8 -Value 'class Entry { public void handle() {} }'

# Test PHASE0_RESULT.md with **Entry**: format (markdown bold)
Set-Content -LiteralPath (Join-Path $root 'PHASE0_RESULT.md') -Encoding UTF8 -Value @'
# Phase 0 Result

## Selected Real Entry

**Entry**: `Entry.handle()` (EXISTING)

**Carrier**: `Entry`

**Method**: `handle`

**Location**: `src/Entry.java:1'

---

## Search Commands Used

```powershell
rg "class Entry" --type java
```
'@

$verify = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-Phase0CarrierEvidence.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree | ConvertFrom-Json

Assert-True -Name 'verification_status is PASS' -Condition ([string]$verify.verification_status -eq 'PASS') -Details ($verify | ConvertTo-Json -Depth 8)
Assert-True -Name 'selected_real_entry is Entry.handle()' -Condition ([string]$verify.selected_real_entry -eq 'Entry.handle()')
Assert-True -Name 'selected_entry_carrier is Entry' -Condition ([string]$verify.selected_entry_carrier -eq 'Entry')
Assert-True -Name 'selected_entry_method is handle' -Condition ([string]$verify.selected_entry_method -eq 'handle')
Assert-True -Name 'no issues' -Condition ($verify.issues.Count -eq 0)

Remove-Item -LiteralPath $root -Recurse -Force
Write-Host 'PASS Test-v444-Phase0EntryMarkdownFormat'
