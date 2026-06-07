param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$startRound = Join-Path $PSScriptRoot 'Start-ReplayRound.ps1'
$invokeAgent = Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'

$startText = Get-Content -LiteralPath $startRound -Raw -Encoding UTF8
$invokeText = Get-Content -LiteralPath $invokeAgent -Raw -Encoding UTF8

Assert-True ($startText -match "PROJECT_ROOT\s*=\s*'<protected-main-workspace-redacted; use isolated worktree only>'") 'Phase prompts should receive a redacted protected main workspace label'
Assert-True ($startText -match '\$systemContextSnapshotDir\s*=\s*Join-Path\s+\$replayRoot\s+''SYSTEM_CONTEXT_SNAPSHOT''') 'Start-ReplayRound should create a system context snapshot directory under replay root'
Assert-True ($startText -match 'Copy-Item\s+-LiteralPath\s+\$_\.FullName\s+-Destination\s+\(Join-Path\s+\$systemContextSnapshotDir\s+\$_\.Name\)') 'Start-ReplayRound should copy system context files into the replay snapshot'
Assert-True ($startText -match 'protected_root_status_changed_during_replay_prepare') 'Replay preparation should fail closed if protected root status changes'

Assert-True ($invokeText -match 'function\s+Get-ConfigProjectRoot') 'Invoke-AgentPrompt should discover the protected project root from config'
Assert-True ($invokeText -match '\$protectedRootStatusBefore\s*=\s*Get-GitStatusText\s+-Repo\s+\$protectedRoot') 'Invoke-AgentPrompt should record protected root status before agent execution'
Assert-True ($invokeText -match '\$protectedRootStatusAfter\s*=\s*Get-GitStatusText\s+-Repo\s+\$protectedRoot') 'Invoke-AgentPrompt should record protected root status after agent execution'
Assert-True ($invokeText -match 'protected_root_modified') 'Invoke-AgentPrompt should classify protected-root mutations explicitly'

Write-Host 'PASS: v422 protected root prompt isolation tests passed'
[ordered]@{ status = 'PASS'; assertions = 8 } | ConvertTo-Json -Depth 4
