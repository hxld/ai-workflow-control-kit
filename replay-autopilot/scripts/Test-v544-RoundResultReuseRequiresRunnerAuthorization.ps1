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

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 12)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-TextFile {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

function Import-RunReplayLoopFunctions {
    $runLoop = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-ReplayLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }
    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v544-round-reuse-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Write-TextFile (Join-Path $replayRoot 'ROUND_RESULT.md') '# stale round result'
    Write-TextFile (Join-Path $replayRoot 'FINAL_REPLAY_REPORT.md') '# stale final report'
    Write-TextFile (Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md') '# stale summary'
    Write-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json') ([ordered]@{
        validation_status = 'PASS'
        final_pass_allowed = $false
        coverage_cap_from_ledger = 0
        open_required_family_count = 1
        selected_family = 'wire_payload_api_contract'
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        verification_status = 'BLOCKED'
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        authorization_blockers = @('verification_failed_or_blocked', 'behavior_evidence_missing')
    })

    Import-RunReplayLoopFunctions

    $decision = Get-Phase1RoundReuseDecision -ReplayRoot $replayRoot
    Assert-True 'non-authorizing round result with open family must rerun Phase1' ([bool]$decision.rerun_phase1 -and -not [bool]$decision.can_reuse) ($decision | ConvertTo-Json -Depth 10)
    $decisionPath = Archive-Phase1RoundArtifactsForRerun -ReplayRoot $replayRoot -Decision $decision
    Assert-True 'stale ROUND_RESULT archived out of active root' (-not (Test-Path -LiteralPath (Join-Path $replayRoot 'ROUND_RESULT.md')))
    Assert-True 'stale FINAL_REPLAY_REPORT archived out of active root' (-not (Test-Path -LiteralPath (Join-Path $replayRoot 'FINAL_REPLAY_REPORT.md')))
    $decisionJson = Get-Content -LiteralPath $decisionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'reuse decision records rerun reason' ([string]$decisionJson.reason -eq 'round_result_non_authorizing_with_open_required_family') ($decisionJson | ConvertTo-Json -Depth 10)

    Write-TextFile (Join-Path $replayRoot 'ROUND_RESULT.md') '# reusable round result'
    Write-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json') ([ordered]@{
        validation_status = 'PASS'
        final_pass_allowed = $true
        coverage_cap_from_ledger = 100
        open_required_family_count = 0
        selected_family = ''
    })
    Remove-Item -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_02.json') -Force -ErrorAction SilentlyContinue
    $reuseDecision = Get-Phase1RoundReuseDecision -ReplayRoot $replayRoot
    Assert-True 'authorized round result remains reusable' ([bool]$reuseDecision.can_reuse -and -not [bool]$reuseDecision.rerun_phase1) ($reuseDecision | ConvertTo-Json -Depth 10)

    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_03.json') ([ordered]@{
        verification_status = 'BLOCKED'
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        authorization_blockers = @('selected_carrier_missing')
    })
    $closedButDirtyDecision = Get-Phase1RoundReuseDecision -ReplayRoot $replayRoot
    Assert-True 'non-authorizing slice artifact prevents round reuse even after router closure' `
        ([bool]$closedButDirtyDecision.rerun_phase1 -and -not [bool]$closedButDirtyDecision.can_reuse -and [string]$closedButDirtyDecision.reason -eq 'round_result_non_authorizing_slice_artifact') `
        ($closedButDirtyDecision | ConvertTo-Json -Depth 10)

    Write-Host 'v544 round result reuse authorization regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
