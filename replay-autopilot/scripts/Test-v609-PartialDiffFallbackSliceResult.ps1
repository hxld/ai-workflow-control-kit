param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Import-RunSliceLoopFunctions {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v609-partial-diff-" + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'
$worktree = Join-Path $tempRoot 'worktree'
$logDir = Join-Path $replayRoot 'logs\phase1-slices\slice01'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree, $logDir | Out-Null
    & git -C $worktree init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }

    $prodFile = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\service\AiAutoClaimFlowService.java'
    $testFile = Join-Path $worktree 'claim-server\src\test\java\com\huize\claim\core\ai\task\AiApplyClaimAutoFlowTriggerTest.java'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $prodFile), (Split-Path -Parent $testFile) | Out-Null
    'class AiAutoClaimFlowService {}' | Set-Content -LiteralPath $prodFile -Encoding UTF8
    'class AiApplyClaimAutoFlowTriggerTest {}' | Set-Content -LiteralPath $testFile -Encoding UTF8

    Import-RunSliceLoopFunctions

    $audit = Write-PartialWorktreeDiffAudit `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -Stage 'after_retry' `
        -SliceLogDir $logDir `
        -ExitCode 88

    Assert-True ([bool]$audit.HasDiff) 'partial diff audit must detect untracked worktree files'
    Assert-True (Test-Path -LiteralPath $audit.JsonPath -PathType Leaf) 'partial diff audit JSON must be written'
    Assert-True (Test-Path -LiteralPath $audit.MdPath -PathType Leaf) 'partial diff audit Markdown must be written'

    $auditJson = Get-Content -LiteralPath $audit.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($auditJson.schema -eq 'partial_worktree_diff_audit.v1') 'audit schema mismatch'
    Assert-True ($auditJson.status -eq 'PARTIAL_DIFF_DETECTED') 'audit status must detect partial diff'
    Assert-True (@($auditJson.production_files) -contains 'claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java') 'audit must include production file'
    Assert-True (@($auditJson.test_files) -contains 'claim-server/src/test/java/com/huize/claim/core/ai/task/AiApplyClaimAutoFlowTriggerTest.java') 'audit must include test file'

    $sliceResult = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $forced = [pscustomobject]@{
        family_id = 'core_entry'
        slice_type = 'stateful_success_slice'
    }

    Write-ExecutorBlockedSliceResult `
        -Path $sliceResult `
        -SliceIndex 1 `
        -ForcedDecision $forced `
        -SliceLogDir $logDir `
        -ExitCode 88 `
        -Reason 'executor completed without writing required SLICE_RESULT after retry' `
        -FailureCategory 'executor_silent_no_output' `
        -PartialDiffAudit $audit

    Assert-True (Test-Path -LiteralPath $sliceResult -PathType Leaf) 'fallback SLICE_RESULT must be written'
    $slice = Get-Content -LiteralPath $sliceResult -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($slice.slice_status -eq 'BLOCKED') 'fallback slice must be BLOCKED'
    Assert-True ([bool]$slice.partial_worktree_diff_detected) 'fallback slice must disclose partial worktree diff'
    Assert-True (@($slice.gap_flags) -contains 'partial_worktree_diff_detected') 'fallback slice must include partial diff gap flag'
    Assert-True (@($slice.gap_flags) -contains 'executor_silent_no_output') 'fallback slice must retain executor failure category'
    Assert-True ($slice.proof_kind -eq 'partial_worktree_diff_audit') 'fallback slice must use partial diff proof kind'
    Assert-True (@($slice.current_slice_changed_files) -contains 'claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java') 'fallback slice must keep production changed file'
    Assert-True (@($slice.current_slice_changed_files) -contains 'claim-server/src/test/java/com/huize/claim/core/ai/task/AiApplyClaimAutoFlowTriggerTest.java') 'fallback slice must keep test changed file'
    Assert-True ([string]$slice.partial_worktree_diff_audit -eq [string]$audit.JsonPath) 'fallback slice must point to audit JSON'

    $sliceLoopText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($sliceLoopText.Contains('Partial worktree diff detected before retry')) 'retry prompt must surface partial diff before retry'
    Assert-True ($sliceLoopText.Contains('partial_worktree_diff_detected')) 'runner must use stable partial diff gap flag'

    Write-Host 'Test-v609-PartialDiffFallbackSliceResult PASS'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
