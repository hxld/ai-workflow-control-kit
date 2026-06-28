param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Message - $Detail"
    }
    Write-Host "PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v714-blocked-plan-rules-' + [guid]::NewGuid().ToString('N'))

try {
    $runnerText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    Assert-True ($runnerText.Contains("Join-Path `$PSScriptRoot 'New-EvolutionProposal.ps1'")) 'blocked plan branch invokes shared evolution proposal generator'
    Assert-True ($runnerText.Contains('-File $proposalScript -ReplayRoot $replayRoot')) 'blocked plan branch calls generator with current replay root'

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-Utf8 (Join-Path $tempRoot 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: BLOCKED
- blocker: carrier_search_unproven
'@
    Write-Utf8 (Join-Path $tempRoot 'PLAN_CONTRACT_VERIFY.json') @'
{
  "stage": "Plan",
  "verification_status": "FAIL",
  "issues": [
    "carrier_search_selected_carrier_not_in_results",
    "plan_status_not_proceed:BLOCKED"
  ],
  "issue_evidence": [
    {
      "issue": "plan_status_not_proceed:BLOCKED",
      "artifact": "PLAN_RESULT.md",
      "machine_gate": "blocked_plan_status_stops_replay",
      "snippet": "plan_status=BLOCKED; blocker=carrier_search_unproven",
      "expected_action": "Stop before implementation and route to evolution with closeable machine-gate evidence."
    }
  ]
}
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'New-EvolutionProposal.ps1') -ReplayRoot $tempRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'shared proposal generator exits successfully for blocked plan fixture'
    $rulesPath = Join-Path $tempRoot 'VERIFIABLE_RULES.json'
    Assert-True (Test-Path -LiteralPath $rulesPath) 'blocked plan fixture writes VERIFIABLE_RULES.json'
    $rules = Get-Content -LiteralPath $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $gates = @($rules.rules | ForEach-Object { [string]$_.machine_gate })
    Assert-True ($gates -contains 'blocked_plan_status_stops_replay') 'blocked plan verifiable rules include closeable machine gate' (($gates -join ';'))

    Write-Host ''
    Write-Host 'v714 Blocked Plan Writes Verifiable Rules: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
