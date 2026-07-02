param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runReplayLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$planSchemaFailFast = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'

$replayText = Get-Content -LiteralPath $runReplayLoop -Raw -Encoding UTF8
$sliceText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
$schemaText = Get-Content -LiteralPath $planSchemaFailFast -Raw -Encoding UTF8

Assert-True ($replayText.Contains('$hasPolicyNum = $PlanText -match')) 'Run-ReplayLoop policy rebuild detector must require policyNum.'
Assert-True ($replayText.Contains('$hasInsureNum = $PlanText -match')) 'Run-ReplayLoop policy rebuild detector must require insureNum.'
Assert-True ($replayText.Contains('$hasRebuildBoundary = $PlanText -match')) 'Run-ReplayLoop policy rebuild detector must require a rebuild/source-chain boundary.'
Assert-True ($replayText.Contains('return ($hasPolicyNum -and $hasInsureNum -and $hasRebuildBoundary)')) 'Run-ReplayLoop policy rebuild detector must use conjunctive matching.'
Assert-True ($replayText -notmatch 'return \(\$PlanText -match ''\(\?i\)policyNum\|insureNum\|rebuildTaskData\|ExampleApplyClaimApiTaskProcessor') 'Run-ReplayLoop must not use broad OR matching for policy rebuild detection.'

Assert-True ($schemaText.Contains('$hasPolicyNum = $PlanText -match')) 'Plan schema fail-fast policy rebuild detector must require policyNum.'
Assert-True ($schemaText.Contains('$hasInsureNum = $PlanText -match')) 'Plan schema fail-fast policy rebuild detector must require insureNum.'
Assert-True ($schemaText.Contains('$hasRebuildBoundary = $PlanText -match')) 'Plan schema fail-fast policy rebuild detector must require a rebuild/source-chain boundary.'
Assert-True ($schemaText.Contains('return ($hasPolicyNum -and $hasInsureNum -and $hasRebuildBoundary)')) 'Plan schema fail-fast policy rebuild detector must use conjunctive matching.'

Assert-True ($sliceText.Contains('$phase0Args = @(')) 'Run-SliceLoop must build phase0-precheck args explicitly.'
Assert-True ($sliceText.Contains('if (-not [string]::IsNullOrWhiteSpace($MavenSettings))')) 'Run-SliceLoop must pass -MavenSettings only when non-empty.'
Assert-True ($sliceText -notmatch '-MavenSettings \$MavenSettings -SliceIndex') 'Run-SliceLoop must not pass an empty MavenSettings value positionally.'
Assert-True ($sliceText.Contains('$oldPreference = $ErrorActionPreference')) 'Run-SliceLoop must isolate phase0-precheck native stderr capture.'
Assert-True ($sliceText.Contains('$ErrorActionPreference = $oldPreference')) 'Run-SliceLoop must restore ErrorActionPreference after phase0-precheck.'

Assert-True ($sliceText.Contains('if ($blockedBeforeExecutor)')) 'Run-SliceLoop must classify local gate blocks before downstream implementation gates.'
Assert-True ($sliceText.Contains('local_gate_blocked_before_executor')) 'Run-SliceLoop must write runner contract evidence for blocked-before-executor stops.'
Assert-True ($sliceText.Contains('blocked_before_executor:')) 'Run-SliceLoop must mark slice progress with blocked_before_executor.'

$blockedIndex = $sliceText.IndexOf('if ($blockedBeforeExecutor)')
$layerIndex = $sliceText.IndexOf('# v431: Layer validation gate (pre-flight check)', $blockedIndex)
Assert-True ($blockedIndex -ge 0 -and $layerIndex -gt $blockedIndex) 'Blocked-before-executor handling must run before layer validation gate.'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runReplayLoop, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True (-not $parseErrors -or $parseErrors.Count -eq 0) ('Run-ReplayLoop parse errors: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True (-not $parseErrors -or $parseErrors.Count -eq 0) ('Run-SliceLoop parse errors: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($planSchemaFailFast, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True (-not $parseErrors -or $parseErrors.Count -eq 0) ('Invoke-PlanSchemaFailFast parse errors: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))

Write-Host 'Test-v603-PolicyRebuildDetectorAndBlockedSliceGate PASS'
