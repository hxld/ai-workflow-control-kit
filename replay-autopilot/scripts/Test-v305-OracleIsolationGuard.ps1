param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$toolsRoot = Join-Path $autopilotRoot 'tools'
$cases = New-Object System.Collections.Generic.List[string]

$guard = Get-Content -LiteralPath (Join-Path $toolsRoot 'git-guard.ps1') -Raw -Encoding UTF8
$invoke = Get-Content -LiteralPath (Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1') -Raw -Encoding UTF8
$cases.Add((Assert-True -Name 'git_guard_exists' -Condition ($guard -match 'REPLAY_ORACLE_ISOLATION' -and $guard -match 'replay-autopilot oracle isolation blocked'))) | Out-Null
$cases.Add((Assert-True -Name 'invoke_sets_oracle_isolation_env' -Condition ($invoke -match 'REPLAY_AGENT_STAGE' -and $invoke -match 'REPLAY_FORBIDDEN_ORACLE_BRANCH' -and $invoke -match 'REPLAY_FORBIDDEN_ORACLE_COMMIT'))) | Out-Null

$nonPhase2Prompts = @(
    'phase0-contract-gate.prompt.md',
    'phase-plan-tournament.prompt.md',
    'phase1-slice-executor.prompt.md',
    'phase1-round-synthesis.prompt.md',
    'phase1-strict-blind.prompt.md'
)
foreach ($promptName in $nonPhase2Prompts) {
    $text = Get-Content -LiteralPath (Join-Path $autopilotRoot "prompts\$promptName") -Raw -Encoding UTF8
    $cases.Add((Assert-True -Name "oracle_ref_redacted_$promptName" -Condition ($text -notmatch 'oracle branch:\s*\{\{ORACLE_BRANCH\}\}' -and $text -notmatch 'oracle commit:\s*\{\{ORACLE_COMMIT\}\}'))) | Out-Null
}

$oldIsolation = $env:REPLAY_ORACLE_ISOLATION
$oldBranch = $env:REPLAY_FORBIDDEN_ORACLE_BRANCH
$oldCommit = $env:REPLAY_FORBIDDEN_ORACLE_COMMIT
$oldStage = $env:REPLAY_AGENT_STAGE
try {
    $env:REPLAY_ORACLE_ISOLATION = '1'
    $env:REPLAY_FORBIDDEN_ORACLE_BRANCH = 'ai_claim_V2'
    $env:REPLAY_FORBIDDEN_ORACLE_COMMIT = '07d37b6c30d42f0737a2629f051b9d7b76baf78e'
    $env:REPLAY_AGENT_STAGE = 'phase0'
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & (Join-Path $toolsRoot 'rtk.cmd') git diff --name-only ai_claim_V2 e19c16c5a 2>$null | Out-Null
    $rtkExit = $LASTEXITCODE

    & (Join-Path $toolsRoot 'git.cmd') show 07d37b6c30d42f0737a2629f051b9d7b76baf78e 2>$null | Out-Null
    $gitExit = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference

    $cases.Add((Assert-True -Name 'rtk_git_diff_oracle_blocked' -Condition ($rtkExit -eq 82))) | Out-Null
    $cases.Add((Assert-True -Name 'git_show_oracle_commit_blocked' -Condition ($gitExit -eq 82))) | Out-Null
} finally {
    if ($null -ne $oldErrorActionPreference) {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    $env:REPLAY_ORACLE_ISOLATION = $oldIsolation
    $env:REPLAY_FORBIDDEN_ORACLE_BRANCH = $oldBranch
    $env:REPLAY_FORBIDDEN_ORACLE_COMMIT = $oldCommit
    $env:REPLAY_AGENT_STAGE = $oldStage
}

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
