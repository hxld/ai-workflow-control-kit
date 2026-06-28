$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..\..')
$summaryScript = Join-Path $repoRoot 'replay-autopilot\scripts\Write-ControlPlaneSummary.ps1'
$controlScript = Join-Path $repoRoot 'replay-autopilot\scripts\Run-UnattendedReplayControl.ps1'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$summaryText = Get-Content -LiteralPath $summaryScript -Raw -Encoding UTF8
$controlText = Get-Content -LiteralPath $controlScript -Raw -Encoding UTF8

Assert-True ($summaryText -match 'AuxiliaryTimeoutSeconds') 'control summary exposes auxiliary timeout parameter'
Assert-True ($summaryText -match 'SkipAuxiliaryArtifacts') 'control summary exposes skip auxiliary parameter'
Assert-True ($summaryText -match 'WaitForExit') 'control summary auxiliary execution is time bounded'
Assert-True ($summaryText -match 'AUXILIARY_TIMEOUT') 'control summary writes timeout marker evidence'
Assert-True ($summaryText -match 'continuing control loop') 'auxiliary failures do not block the control loop'
Assert-True ($summaryText -notmatch 'throw "Failure audit pack generation failed') 'failure audit auxiliary is nonblocking'
Assert-True ($summaryText -notmatch 'throw "Golden delivery slice generation failed') 'golden slice auxiliary is nonblocking'

Assert-True ($controlText -match 'control_summary_auxiliary_timeout_seconds') 'unattended controller reads auxiliary timeout config'
Assert-True ($controlText -match 'control_summary_skip_auxiliary_artifacts') 'unattended controller reads skip auxiliary config'
Assert-True ($controlText -match "'-AuxiliaryTimeoutSeconds'") 'unattended controller passes auxiliary timeout to summary'
Assert-True ($controlText -match "'-SkipAuxiliaryArtifacts'") 'unattended controller can skip auxiliary artifacts'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-control-summary-validate-{0}' -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    $jsonText = & powershell -NoProfile -ExecutionPolicy Bypass -File $summaryScript `
        -EvidenceRoot $tempRoot `
        -AuxiliaryTimeoutSeconds 7 `
        -SkipAuxiliaryArtifacts `
        -ValidateOnly
    if ($LASTEXITCODE -ne 0) {
        throw "Write-ControlPlaneSummary validate-only failed with exit code $LASTEXITCODE"
    }
    $json = $jsonText | ConvertFrom-Json
    Assert-True ([int]$json.auxiliary_timeout_seconds -eq 7) 'validate-only reports auxiliary timeout'
    Assert-True ([bool]$json.skip_auxiliary_artifacts) 'validate-only reports skip auxiliary artifacts'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS Test-v645-ControlSummaryAuxiliaryTimeout'
