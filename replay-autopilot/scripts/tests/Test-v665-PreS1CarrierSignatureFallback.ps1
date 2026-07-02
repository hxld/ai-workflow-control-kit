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
$runLoopScript = Join-Path $scriptsRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v665-pres1-carrier-fallback-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    $sourceDir = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task'
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

    Write-Utf8 (Join-Path $sourceDir 'TExampleApiTask.java') @'
package com.example.project.core.ai.task;

public class TExampleApiTask {
}
'@

    Write-Utf8 (Join-Path $sourceDir 'TaskResponse.java') @'
package com.example.project.core.ai.task;

public class TaskResponse {
}
'@

    Write-Utf8 (Join-Path $sourceDir 'ExampleApplyClaimApiTask.java') @'
package com.example.project.core.ai.task;

public class ExampleApplyClaimApiTask {
}
'@

    Write-Utf8 (Join-Path $sourceDir 'ExampleApplyClaimApiTaskResponse.java') @'
package com.example.project.core.ai.task;

public class ExampleApplyClaimApiTaskResponse {
}
'@

    Write-Utf8 (Join-Path $sourceDir 'AbstractExampleApiTaskProcessor.java') @'
package com.example.project.core.ai.task;

public abstract class AbstractExampleApiTaskProcessor {
    public final TaskResponse execute(TExampleApiTask task) {
        return null;
    }
}
'@

    Write-Utf8 (Join-Path $sourceDir 'ExampleApplyClaimApiTaskProcessor.java') @'
package com.example.project.core.ai.task;

public class ExampleApplyClaimApiTaskProcessor extends AbstractExampleApiTaskProcessor {
    public void handleTaskResponse(ExampleApplyClaimApiTask task, ExampleApplyClaimApiTaskResponse response) {
    }
}
'@

    Write-Utf8 (Join-Path $replayRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md') @'
# Requirement

AI claim auto flow should write AI handling logs and compensation side effects.
'@

    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
selected_real_entry: com.example.project.core.ai.task.AbstractExampleApiTaskProcessor.execute
selected_carrier: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimAutoFlowBehaviorTest.java#handleTaskResponse_freeReviewAmountWithinThreshold_triggersAutoFlowSideEffects
minimum_side_effect_or_blocker: selected carrier must produce exact AI handling log or compensation/status mapper-boundary write
expected_test_class: com.example.project.core.ai.task.ExampleApplyClaimAutoFlowBehaviorTest
expected_test_method: handleTaskResponse_freeReviewAmountWithinThreshold_triggersAutoFlowSideEffects
expected_side_effects: ["AI handling log insert","compensation mapper-boundary write"]
'@

    @{
        expected_test_class = 'com.example.project.core.ai.task.ExampleApplyClaimAutoFlowBehaviorTest'
        expected_test_method = 'handleTaskResponse_freeReviewAmountWithinThreshold_triggersAutoFlowSideEffects'
        expected_side_effects = @('AI handling log insert', 'compensation mapper-boundary write')
        side_effects = @('AI handling log insert', 'compensation mapper-boundary write')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'PLAN_RESULT.json') -Encoding UTF8

    $runLoopText = Get-Content -LiteralPath $runLoopScript -Raw -Encoding UTF8
    $startIndex = $runLoopText.IndexOf('$ErrorActionPreference = ''Stop''')
    $endIndex = $runLoopText.IndexOf("`nfunction Get-MetricNumber", $startIndex)
    Assert-True ($startIndex -ge 0 -and $endIndex -gt $startIndex) 'test helper should extract Run-ReplayLoop function definitions'
    $helperText = $runLoopText.Substring($startIndex, $endIndex - $startIndex)
    $helperText = $helperText.Replace('$PSScriptRoot', "'" + $scriptsRoot.Replace("'", "''") + "'")
    $helperScript = Join-Path $tempRoot 'runloop-functions-under-test.ps1'
    Write-Utf8 $helperScript $helperText

    $command = @"
. '$helperScript'
Invoke-V348PreS1CarrierVerification -ReplayRoot '$replayRoot' -Worktree '$worktree' -RequirementSource '$replayRoot\REQUIREMENT_SOURCE_SNAPSHOT.md'
"@
    powershell -NoProfile -ExecutionPolicy Bypass -Command $command | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-S1 carrier verification helper should run without aborting the caller'

    $gatePath = Join-Path $replayRoot 'PRE_S1_CARRIER_VERIFY.json'
    $signaturePath = Join-Path $replayRoot 'PRE_S1_CARRIER_SIGNATURE_AUTHORIZATION.json'
    Assert-True (Test-Path -LiteralPath $gatePath) 'PRE_S1_CARRIER_VERIFY.json must be written'
    Assert-True (Test-Path -LiteralPath $signaturePath) 'PRE_S1_CARRIER_SIGNATURE_AUTHORIZATION.json must be written'

    $gate = Get-Content -LiteralPath $gatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $signature = Get-Content -LiteralPath $signaturePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$gate.signature_authorized) 'gate should authorize signature after fallback fields are derived'
    Assert-True ([bool]$signature.authorized) 'signature authorization should be true'
    Assert-True ([string]$gate.test_invocation_path -match 'ExampleApplyClaimAutoFlowBehaviorTest#handleTaskResponse') 'test invocation path should fall back from expected test class/method'
    Assert-True ([string]$gate.proof_observation_point -match 'AI handling log') 'proof observation point should fall back from side-effect fields'

    Write-Host ''
    Write-Host '=== v665 PRE-S1 CARRIER SIGNATURE FALLBACK: PASS ===' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
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
