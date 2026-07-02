param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$invokeAgent = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
$mvnShim = Join-Path $repoRoot 'tools\mvn.cmd'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v613-' + [guid]::NewGuid().ToString('N'))

$oldStage = $env:REPLAY_AGENT_STAGE
$oldProtectedRoot = $env:REPLAY_PROTECTED_ROOT
$oldWorktreeRoot = $env:REPLAY_WORKTREE_ROOT
$oldMavenCmd = $env:MAVEN_CMD

try {
    Assert-True 'maven_shim_exists' (Test-Path -LiteralPath $mvnShim -PathType Leaf)

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($invokeAgent, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True 'invoke_agent_parse_clean' (-not $parseErrors -or $parseErrors.Count -eq 0) (($parseErrors | ForEach-Object { $_.Message }) -join '; ')

    $invokeText = Get-Content -LiteralPath $invokeAgent -Raw -Encoding UTF8
    Assert-True 'invoke_agent_exports_protected_root_to_jobs' (
        $invokeText.Contains('$env:REPLAY_PROTECTED_ROOT = $ProtectedRootInner') -and
        $invokeText.Contains('$env:REPLAY_WORKTREE_ROOT = $WorkDirInner')
    )
    Assert-True 'invoke_agent_prepends_tool_path' ($invokeText.Contains('$env:PATH = "$ToolPathInner;$env:PATH"'))

    $protectedRoot = Join-Path $tempRoot 'protected-root'
    $worktree = Join-Path $tempRoot 'replay\worktree'
    New-Item -ItemType Directory -Force -Path $protectedRoot, $worktree | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $protectedRoot 'pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Encoding UTF8

    $env:REPLAY_AGENT_STAGE = 'phase0-command-guard-repair'
    $env:REPLAY_PROTECTED_ROOT = $protectedRoot
    $env:REPLAY_WORKTREE_ROOT = $worktree
    $env:MAVEN_CMD = ''
    $phase0Command = '"' + $mvnShim + '" -f "' + (Join-Path $worktree 'pom.xml') + '" -pl example-core -am compile'
    $phase0Output = & cmd.exe /d /s /c "$phase0Command 2>&1" | Out-String
    $phase0Exit = $LASTEXITCODE
    Assert-True 'phase0_maven_blocked_before_real_maven' ($phase0Exit -eq 84) "exit=$phase0Exit output=$phase0Output"
    Assert-True 'phase0_maven_block_message' ($phase0Output -match 'phase0 command guard blocked Maven') $phase0Output

    $env:REPLAY_AGENT_STAGE = 'phase1'
    $protectedCommand = '"' + $mvnShim + '" -f "' + (Join-Path $protectedRoot 'pom.xml') + '" -pl example-core -am compile'
    $protectedOutput = & cmd.exe /d /s /c "$protectedCommand 2>&1" | Out-String
    $protectedExit = $LASTEXITCODE
    Assert-True 'protected_root_maven_blocked' ($protectedExit -eq 85) "exit=$protectedExit output=$protectedOutput"
    Assert-True 'protected_root_maven_block_message' ($protectedOutput -match 'protected root guard blocked Maven') $protectedOutput

    [ordered]@{
        status = 'PASS'
        version = 'v613'
        assertions = @(
            'Phase0 Maven is blocked by tool shim before real Maven lookup',
            'Protected-root Maven POM is blocked outside Phase0',
            'Invoke-AgentPrompt exports protected/worktree roots into executor jobs'
        )
    } | ConvertTo-Json -Depth 4
}
finally {
    $env:REPLAY_AGENT_STAGE = $oldStage
    $env:REPLAY_PROTECTED_ROOT = $oldProtectedRoot
    $env:REPLAY_WORKTREE_ROOT = $oldWorktreeRoot
    $env:MAVEN_CMD = $oldMavenCmd
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
