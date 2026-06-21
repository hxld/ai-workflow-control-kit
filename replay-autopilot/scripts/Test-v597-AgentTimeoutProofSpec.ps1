param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-timeout-proof-' + [guid]::NewGuid().ToString('N'))
$fakeBin = Join-Path $tempRoot 'bin'
$workDir = Join-Path $tempRoot 'work'
$logDir = Join-Path $tempRoot 'logs'
$promptPath = Join-Path $tempRoot 'prompt.md'
$completionPath = Join-Path $logDir 'completion.md'

New-Item -ItemType Directory -Force -Path $fakeBin, $workDir, $logDir | Out-Null
Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value 'Never write completion.'

$fakeClaude = Join-Path $fakeBin 'claude.cmd'
Set-Content -LiteralPath $fakeClaude -Encoding ASCII -Value @(
    '@echo off',
    'ping 127.0.0.1 -n 80 >nul',
    'exit /b 0'
)

$oldPath = $env:PATH
try {
    $env:PATH = "$fakeBin;$env:PATH"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut `
        -PromptPath $promptPath `
        -WorkDir $workDir `
        -LogDir $logDir `
        -Executor claude `
        -Name timeoutstage `
        -CompletionPath $completionPath `
        -TimeoutMinutes 1 *> (Join-Path $tempRoot 'invoke.out')
    $exit = $LASTEXITCODE

    Assert-True ($exit -eq 89) "Expected timeout exit 89, got $exit."

    $goalSpecPath = Join-Path $logDir 'timeoutstage.goalspec.json'
    $proofSpecPath = Join-Path $logDir 'timeoutstage.proofspec.json'
    $execPath = Join-Path $logDir 'timeoutstage.exec.json'

    Assert-True (Test-Path -LiteralPath $goalSpecPath -PathType Leaf) 'GoalSpec missing after timeout.'
    Assert-True (Test-Path -LiteralPath $proofSpecPath -PathType Leaf) 'ProofSpec missing after timeout.'
    Assert-True (Test-Path -LiteralPath $execPath -PathType Leaf) 'Exec metadata missing after timeout.'

    $proofSpec = Get-Content -LiteralPath $proofSpecPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $exec = Get-Content -LiteralPath $execPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True ($proofSpec.status -eq 'FAIL') 'Timeout ProofSpec should fail.'
    Assert-True ($proofSpec.failure_category -eq 'executor_timeout') 'Timeout ProofSpec category mismatch.'
    Assert-True ([int]$proofSpec.exit_code -eq 89) 'Timeout ProofSpec exit code mismatch.'
    Assert-True ($exec.failure_category -eq 'executor_timeout') 'Timeout exec category mismatch.'
    Assert-True ([int]$exec.exit_code -eq 89) 'Timeout exec exit code mismatch.'

    Write-Host 'Test-v597-AgentTimeoutProofSpec PASS'
} finally {
    $env:PATH = $oldPath
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
