param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot '..\..'))
$sut = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-goal-proof-' + [guid]::NewGuid().ToString('N'))
$fakeBin = Join-Path $tempRoot 'bin'
$workDir = Join-Path $tempRoot 'work'
$logDir = Join-Path $tempRoot 'logs'
$promptPath = Join-Path $tempRoot 'prompt.md'
$completionPath = Join-Path $logDir 'completion.md'

New-Item -ItemType Directory -Force -Path $fakeBin, $workDir, $logDir | Out-Null
Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value @(
    '# Fake replay stage',
    '',
    "Write completion to: $completionPath"
)

$fakeClaude = Join-Path $fakeBin 'claude.cmd'
Set-Content -LiteralPath $fakeClaude -Encoding ASCII -Value @(
    '@echo off',
    'echo fake claude stage output',
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Content -LiteralPath $env:FAKE_REPLAY_COMPLETION_PATH -Encoding UTF8 -Value ''stage_status: PASS''"',
    'exit /b 0'
)

$oldPath = $env:PATH
$oldCompletion = $env:FAKE_REPLAY_COMPLETION_PATH
try {
    $env:PATH = "$fakeBin;$env:PATH"
    $env:FAKE_REPLAY_COMPLETION_PATH = $completionPath
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut `
        -PromptPath $promptPath `
        -WorkDir $workDir `
        -LogDir $logDir `
        -Executor claude `
        -Name phase0 `
        -CompletionPath $completionPath `
        -TimeoutMinutes 1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Invoke-AgentPrompt exited with $LASTEXITCODE"
    }

    $goalSpecPath = Join-Path $logDir 'phase0.goalspec.json'
    $proofSpecPath = Join-Path $logDir 'phase0.proofspec.json'
    $execPath = Join-Path $logDir 'phase0.exec.json'

    Assert-True (Test-Path -LiteralPath $goalSpecPath -PathType Leaf) 'GoalSpec was not written.'
    Assert-True (Test-Path -LiteralPath $proofSpecPath -PathType Leaf) 'ProofSpec was not written.'
    Assert-True (Test-Path -LiteralPath $execPath -PathType Leaf) 'Exec metadata was not written.'

    $goalSpec = Get-Content -LiteralPath $goalSpecPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $proofSpec = Get-Content -LiteralPath $proofSpecPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $exec = Get-Content -LiteralPath $execPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True ($goalSpec.schema -eq 'replay_agent_goal_spec.v1') 'GoalSpec schema mismatch.'
    Assert-True ($goalSpec.stage -eq 'phase0') 'GoalSpec stage mismatch.'
    Assert-True ($goalSpec.proof_obligations.name -contains 'completion_artifact') 'GoalSpec missing completion obligation.'
    Assert-True ($proofSpec.schema -eq 'replay_agent_proof_spec.v1') 'ProofSpec schema mismatch.'
    Assert-True ($proofSpec.status -eq 'PASS') 'ProofSpec did not pass.'
    Assert-True ([bool]$proofSpec.completion_ready) 'ProofSpec completion_ready was false.'
    Assert-True ($proofSpec.validated_obligations.name -contains 'executor_exit') 'ProofSpec missing executor_exit obligation.'
    Assert-True ($exec.goal_spec_path -eq $goalSpecPath) 'Exec metadata missing GoalSpec path.'
    Assert-True ($exec.proof_spec_path -eq $proofSpecPath) 'Exec metadata missing ProofSpec path.'

    Write-Host 'Test-v596-AgentGoalProofSpec PASS'
} finally {
    $env:PATH = $oldPath
    if ($null -eq $oldCompletion) {
        Remove-Item Env:\FAKE_REPLAY_COMPLETION_PATH -ErrorAction SilentlyContinue
    } else {
        $env:FAKE_REPLAY_COMPLETION_PATH = $oldCompletion
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
