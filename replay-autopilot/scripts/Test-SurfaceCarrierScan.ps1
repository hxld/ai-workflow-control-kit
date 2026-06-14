param(
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Text
}

function Import-StartReplayRoundFunctions {
    $script = Join-Path $PSScriptRoot 'Start-ReplayRound.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Start-ReplayRound.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $needed = @(
        'Read-TextIfExists',
        'Get-SurfaceCarrierSpecs',
        'Get-RequirementAwareSurfaceScore',
        'Write-SurfaceCarrierScan'
    )
    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $needed -contains $node.Name
    }, $true)
    if (@($functionAsts).Count -lt $needed.Count) {
        throw 'Required Start-ReplayRound functions were not found.'
    }
    $order = @{
        'Read-TextIfExists' = 0
        'Get-SurfaceCarrierSpecs' = 1
        'Get-RequirementAwareSurfaceScore' = 2
        'Write-SurfaceCarrierScan' = 3
    }
    foreach ($functionAst in @($functionAsts | Sort-Object { $order[$_.Name] })) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\surface-scan-{0}' -f $PID)
$repo = Join-Path $tempRoot 'repo'
New-Item -ItemType Directory -Force -Path $repo | Out-Null

try {
    Import-StartReplayRoundFunctions

    Write-Text (Join-Path $repo 'claim-core/src/main/java/com/acme/ai/facade/AiApplyFacadeImpl.java') 'class AiApplyFacadeImpl {}'
    Write-Text (Join-Path $repo 'claim-core/src/main/java/com/acme/dock/service/PartnerCallbackPushService.java') 'class PartnerCallbackPushService {}'
    Write-Text (Join-Path $repo 'claim-core/src/main/java/com/acme/caseinfo/service/ClaimNotifyEvent.java') 'class ClaimNotifyEvent {}'
    1..50 | ForEach-Object {
        Write-Text (Join-Path $repo ("claim-core/src/main/java/com/acme/ai/service/AiNoiseService{0}.java" -f $_)) "class AiNoiseService$_ {}"
    }
    & git -C $repo init | Out-Null
    & git -C $repo add . | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git add failed in surface scan test repo' }

    $requirement = Join-Path $tempRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md'
    Write-Text $requirement 'Partner callback should publish MQ notification through existing producer and carry wxId/openid payload.'
    $out = Join-Path $tempRoot 'SURFACE_CARRIER_SCAN.md'
    Write-SurfaceCarrierScan -Worktree $repo -OutPath $out -RequirementSnapshot $requirement
    $scan = Get-Content -LiteralPath $out -Raw -Encoding UTF8

    if ($scan -notmatch 'PartnerCallbackPushService\.java') {
        throw 'Expected requirement-aware external callback carrier in surface scan'
    }
    if ($scan -notmatch 'ClaimNotifyEvent\.java') {
        throw 'Expected requirement-aware MQ/notify carrier in surface scan'
    }

    [ordered]@{
        status = 'PASS'
        cases = @(
            'requirement_aware_callback_carrier_boost',
            'requirement_aware_mq_notify_carrier_boost'
        )
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
} finally {
    if (-not $KeepTemp) {
        $tmpRootFull = Resolve-AbsolutePath $tempRoot
        $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
        if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tmpRootFull -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
