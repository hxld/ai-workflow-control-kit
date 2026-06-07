param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

$root = Join-Path $env:TEMP ('replay-sync-test-' + [guid]::NewGuid().ToString('N'))
$tempRoot = [System.IO.Path]::GetFullPath($root)
if (-not $tempRoot.StartsWith([System.IO.Path]::GetFullPath($env:TEMP), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe temp root: $tempRoot"
}

try {
    $source = Join-Path $tempRoot 'replay-autopilot'
    $evidence = Join-Path $tempRoot 'replay-evidence'
    $gitRoot = Join-Path $tempRoot 'vault'
    $sourcesRoot = Join-Path $gitRoot 'learning\raw\sources'
    $knowledge = Join-Path $sourcesRoot 'ai-knowledge'

    New-Item -ItemType Directory -Force -Path (Join-Path $source 'scripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $source 'logs') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $source '.tmp') | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'README.md') -Value '# source' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source 'scripts\tool.ps1') -Value 'Write-Output ok' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source 'logs\skip.log') -Value 'skip' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source '.tmp\skip.txt') -Value 'skip' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source 'cache.pyc') -Value 'skip' -Encoding UTF8

    New-Item -ItemType Directory -Force -Path (Join-Path $evidence 'feature\round\worktree') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $evidence 'feature\round\logs') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $evidence '_reports') | Out-Null
    Set-Content -LiteralPath (Join-Path $evidence 'REPLAY_AUTOPILOT_SESSION_SUMMARY.md') -Value '# summary' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $evidence 'feature\round\ROUND_RESULT.md') -Value '# round' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $evidence 'feature\round\worktree\Bad.java') -Value 'class Bad {}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $evidence 'feature\round\logs\bad.log') -Value 'bad' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $evidence '_reports\weekly.md') -Value '# report' -Encoding UTF8

    New-Item -ItemType Directory -Force -Path $knowledge | Out-Null
    Push-Location $gitRoot
    try {
        git init | Out-Null
        git config user.email test@example.invalid
        git config user.name replay-sync-test
        Set-Content -LiteralPath (Join-Path $knowledge 'CURRENT_VERSION.md') -Value '# v1' -Encoding UTF8
        git add -- learning/raw/sources/ai-knowledge
        git commit -m 'test: initial knowledge' | Out-Null
    } finally {
        Pop-Location
    }

    $config = Join-Path $tempRoot 'config.yaml'
    @"
knowledge_repo: $knowledge
replay_root_base: $evidence\feature\claim-codex-replay-v000
"@ | Set-Content -LiteralPath $config -Encoding UTF8

    $script = Join-Path $PSScriptRoot 'Sync-KnowledgeBackup.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script `
        -ConfigPath $config `
        -ReplayAutopilotRoot $source `
        -KnowledgeRepo $knowledge `
        -EvidenceRoot $evidence `
        -IncludeAutopilot `
        -IncludeKnowledge `
        -EvidenceMode Milestone `
        -CommitMessage 'test: sync replay backups' | Out-Null

    $autopilotBackup = Join-Path $sourcesRoot 'replay-autopilot'
    $evidenceBackup = Join-Path $sourcesRoot 'replay-evidence-lite'
    Assert-True (Test-Path -LiteralPath (Join-Path $autopilotBackup 'README.md')) 'autopilot README was not copied'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $autopilotBackup 'logs\skip.log'))) 'autopilot logs were copied'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $autopilotBackup '.tmp\skip.txt'))) 'autopilot tmp files were copied'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $autopilotBackup 'cache.pyc'))) 'autopilot pyc was copied'
    Assert-True (Test-Path -LiteralPath (Join-Path $evidenceBackup 'REPLAY_AUTOPILOT_SESSION_SUMMARY.md')) 'session summary was not copied'
    Assert-True (Test-Path -LiteralPath (Join-Path $evidenceBackup 'feature\round\ROUND_RESULT.md')) 'round result was not copied'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $evidenceBackup 'feature\round\worktree\Bad.java'))) 'worktree source was copied'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $evidenceBackup 'feature\round\logs\bad.log'))) 'evidence logs were copied'
    Assert-True (Test-Path -LiteralPath (Join-Path $evidenceBackup '_reports\weekly.md')) 'report asset was not copied'

    $subject = (& git -C $gitRoot log -1 --pretty=%s).Trim()
    Assert-True ($subject -eq 'test: sync replay backups') "unexpected commit subject: $subject"

    'PASS'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
                break
            } catch {
                if ($attempt -eq 5) {
                    Write-Warning "Unable to remove temp test directory: $tempRoot"
                    break
                }
                Start-Sleep -Milliseconds 500
            }
        }
    }
}
