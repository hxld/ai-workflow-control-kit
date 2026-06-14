param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; suite = 'v441' } | ConvertTo-Json -Depth 4
    exit 0
}

$verifier = Join-Path $PSScriptRoot 'Verify-Phase0CarrierEvidence.ps1'
$runner = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v441-test-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $testRoot 'worktree'
    $taskDir = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task'
    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null

    Write-Text (Join-Path $taskDir 'AiApplyClaimApiTaskProcessor.java') @'
package com.huize.claim.core.ai.task;

public class AiApplyClaimApiTaskProcessor {
    public void handleTaskResponse(AiApplyClaimApiTask task, AiApplyClaimApiTaskResponse response) {
    }
}
class AiApplyClaimApiTask {}
class AiApplyClaimApiTaskResponse {}
'@

    Write-Text (Join-Path $testRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

`phase0_status`: PROCEED

**selected_real_entry**: `com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse`

**carrier_status**: EXISTING

## Search Commands Used

```powershell
rg -n "class\s+AiApplyClaimApiTaskProcessor" worktree --glob "*.java"
rg -n "handleTaskResponse" worktree --glob "*.java"
rg -n "AiApplyClaimApiTaskProcessor|handleTaskResponse" worktree --glob "*.java"
```

- result_summary: selected entry exists in baseline worktree.
'@

    $methodVerify = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree $worktree | ConvertFrom-Json
    Assert-True ($methodVerify.verification_status -eq 'PASS') 'Package-qualified Class.method should pass when class and method exist'
    Assert-True ([string]$methodVerify.selected_real_entry -eq 'AiApplyClaimApiTaskProcessor.handleTaskResponse') 'Package-qualified method should normalize to Class.method'
    Assert-True ([string]$methodVerify.selected_entry_carrier -eq 'AiApplyClaimApiTaskProcessor') 'Carrier should be terminal class, not package prefix'
    Assert-True ([string]$methodVerify.selected_entry_method -eq 'handleTaskResponse') 'Method should be parsed from package-qualified method'

    Write-Text (Join-Path $testRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

`phase0_status`: PROCEED

**selected_real_entry**: `com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor`

**carrier_status**: EXISTING

## Search Commands Used

```powershell
rg -n "class\s+AiApplyClaimApiTaskProcessor" worktree --glob "*.java"
rg -n "AiApplyClaimApiTaskProcessor" worktree --glob "*.java"
rg -n "claim.core.ai.task" worktree --glob "*.java"
```

- result_summary: selected class exists but method was not named.
'@

    $classOnlyVerify = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree $worktree | ConvertFrom-Json
    Assert-True ($classOnlyVerify.verification_status -eq 'FAIL') 'Package-qualified class-only entry should fail'
    Assert-True (@($classOnlyVerify.issues) -contains 'phase0_selected_real_entry_invalid_format') 'Class-only selected_real_entry should report invalid format'
    Assert-True (-not (@($classOnlyVerify.issues) -contains 'phase0_selected_real_entry_not_found')) 'Existing package-qualified class should not be misreported as not found'
    Assert-True ([string]$classOnlyVerify.selected_entry_carrier -eq 'AiApplyClaimApiTaskProcessor') 'Class-only carrier should still be terminal class for diagnostics'
    Assert-True ([string]::IsNullOrWhiteSpace([string]$classOnlyVerify.selected_entry_method)) 'Class-only entry should have no selected_entry_method'

    $runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
    Assert-True ($runnerText -match 'Phase0CarrierEvidence') 'Runner should expose a Phase0CarrierEvidence early-stop stage'
    Assert-True ($runnerText -match 'Phase 0 carrier evidence verification failed after repair') 'Runner should generate evolution artifacts for carrier evidence repair failures'

    Write-Host 'PASS: v441 Phase0 FQN carrier and evolution-stop tests passed'
    [ordered]@{ status = 'PASS'; assertions = 11 } | ConvertTo-Json -Depth 4
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
