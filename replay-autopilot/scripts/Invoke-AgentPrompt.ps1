param(
    [Parameter(Mandatory = $true)]
    [string]$PromptPath,
    [Parameter(Mandatory = $true)]
    [string]$WorkDir,
    [Parameter(Mandatory = $true)]
    [string]$LogDir,
    [ValidateSet('codex', 'claude', 'manual')]
    [string]$Executor = 'claude',
    [string]$Model = '',
    [string]$ReasoningEffort = '',
    [string]$Sandbox = 'danger-full-access',
    [string]$Approval = 'never',
    [int]$TimeoutMinutes = 240,
    [string]$CompletionPath = '',
    [int]$CompletionQuietSeconds = 90,
    [string]$Name = 'agent',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

# v432 Experiment 1: Architectural Layer Pre-Flight Gate
function Test-CarrierLayer {
    <#
    .SYNOPSIS
    Validates that a carrier path is in an executable architectural layer.

    .DESCRIPTION
    Checks if the carrier is in example-api (Facade), example-web (Controller),
    or example-core/facade (Facade implementation). Returns $false for
    Service layer (example-core without /facade/) and other internal layers.

    .PARAMETER CarrierPath
    The file path to the carrier class.

    .EXAMPLE
    Test-CarrierLayer "example-core/src/main/java/com/example/project/core/ai/service/ExampleFlowService.java"
    Returns $false (Service layer)

    .EXAMPLE
    Test-CarrierLayer "example-api/src/main/java/com/example/project/api/facade/ExampleFacade.java"
    Returns $true (Facade layer)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$CarrierPath
    )

    # Normalize path
    $CarrierPath = $CarrierPath -replace '\\', '/'

    # Check for Facade layer (example-api)
    if ($CarrierPath -match 'example-api/.*Facade\.java') {
        return $true
    }

    # Check for Controller layer (example-web)
    if ($CarrierPath -match 'example-web/.*Controller\.java') {
        return $true
    }

    # Check for Facade implementation in example-core
    if ($CarrierPath -match 'example-core/.*facade/.*FacadeImpl\.java') {
        return $true
    }

    # All other layers are non-executable for entry points
    return $false
}

function Invoke-PreFlightCarrierCheck {
    <#
    .SYNOPSIS
    Pre-flights all carriers in a plan before execution.

    .DESCRIPTION
    Reads the plan file, extracts all carrier references, and validates
    that each is in an executable layer. Throws if any carrier fails.

    .PARAMETER PlanPath
    Path to the plan file (e.g., REPLAY_PLAN.md or PLAN_CANDIDATE_*.md)

    .EXAMPLE
    Invoke-PreFlightCarrierCheck "REPLAY_PLAN.md"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PlanPath
    )

    if (-not (Test-Path $PlanPath)) {
        Write-Warning "Plan file not found: $PlanPath"
        return
    }

    $planContent = Get-Content $PlanPath -Raw

    # Extract carrier references (patterns like "Target: ServiceName" or "Carrier: ClassName")
    $carrierPattern = '(?:Target|Carrier|Entry):\s*([A-Z][a-zA-Z0-9]*)'
    $carriers = [regex]::Matches($planContent, $carrierPattern) |
                 ForEach-Object { $_.Groups[1].Value }

    if ($carriers.Count -eq 0) {
        Write-Warning "No carriers found in plan: $PlanPath"
        return
    }

    # Search for carrier files
    foreach ($carrierName in $carriers) {
        $searchResult = rg "class\s+$carrierName" --type java -l 2>$null

        if ($searchResult) {
            $carrierPath = ($searchResult -split "`n" | Select-Object -First 1) -replace '\\', '/'
            if (-not (Test-CarrierLayer $carrierPath)) {
                throw "CARRIER LAYER VIOLATION: $carrierName ($carrierPath) is not in an executable layer (Facade/Controller). Please select a Facade or Controller layer carrier."
            }
            Write-Host "✓ $carrierName ($carrierPath) - valid executable layer" -ForegroundColor Green
        } else {
            Write-Warning "Carrier $carrierName not found in codebase (may be new service)"
        }
    }
}

# v432 Experiment 3: RED Phase TODO Ban
function Test-TodoPlaceholder {
    <#
    .SYNOPSIS
    Checks for TODO placeholders in production code.

    .PARAMETER WorkDir
    The working directory to check.

    .PARAMETER ForbiddenPaths
    Array of paths to check for TODO placeholders.

    .EXAMPLE
    Test-TodoPlaceholder "D:\worktree"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WorkDir,

        [string[]]$ForbiddenPaths = @(
            "example-core/src/main/java",
            "example-api/src/main/java",
            "example-web/src/main/java"
        )
    )

    $results = @()

    foreach ($path in $ForbiddenPaths) {
        $targetPath = Join-Path $WorkDir $path -replace '\\', '/'
        if (Test-Path $targetPath) {
            $matches = rg "\b(TODO|FIXME|XXX)\b" $targetPath -n 2>$null
            if ($matches) {
                $results += $matches
            }
        }
    }

    if ($results.Count -gt 0) {
        $errorMsg = "TODO placeholders detected in production code:`n"
        $errorMsg += ($results | Select-Object -First 5) -join "`n"
        if ($results.Count -gt 5) {
            $errorMsg += "`n... and $($results.Count - 5) more"
        }
        throw $errorMsg
    }

    Write-Host "✓ No TODO placeholders in production code" -ForegroundColor Green
}

function Resolve-RequiredPath {
    param([string]$Path, [string]$Label)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full)) {
        throw "$Label not found: $full"
    }
    return $full
}

function Get-ConfigProjectRoot {
    $configPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\config.yaml'))
    if (-not (Test-Path -LiteralPath $configPath)) {
        return ''
    }
    foreach ($line in (Get-Content -LiteralPath $configPath -Encoding UTF8)) {
        if ($line -match '^\s*project_root\s*:\s*(.+?)\s*$') {
            return [System.IO.Path]::GetFullPath($matches[1].Trim().Trim('"').Trim("'"))
        }
    }
    return ''
}

function Get-GitStatusText {
    param([string]$Repo)
    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Test-Path -LiteralPath $Repo)) {
        return ''
    }
    $status = & git -C $Repo status --short 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ''
    }
    return (($status | Sort-Object) -join "`n")
}

function Resolve-ExecutorCommand {
    param([string]$Name)
    $cmd = Get-Command "$Name.cmd" -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command $Name -ErrorAction Stop
    }
    return $cmd.Source
}

function Test-AgentCompletionFileReady {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $true
    }
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full)) {
        if ([string]::IsNullOrWhiteSpace($script:workDirFull)) {
            return $false
        }
        $fallback = Join-Path $script:workDirFull (Split-Path -Leaf $full)
        if ($fallback -eq $full -or -not (Test-Path -LiteralPath $fallback)) {
            return $false
        }
        $fallbackItem = Get-Item -LiteralPath $fallback
        if ($fallbackItem.PSIsContainer -or $fallbackItem.Length -le 0) {
            return $false
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
        Copy-Item -LiteralPath $fallback -Destination $full -Force
    }
    $item = Get-Item -LiteralPath $full
    return (-not $item.PSIsContainer -and $item.Length -gt 0)
}

function Receive-JobWithTimeout {
    param(
        [System.Management.Automation.Job]$Job,
        [int]$TimeoutSeconds,
        [string]$TimeoutMessage,
        [string]$CompletionPath = '',
        [int]$CompletionQuietSeconds = 90,
        [string]$ProcessMatchText = ''
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $completionFull = ''
    if (-not [string]::IsNullOrWhiteSpace($CompletionPath)) {
        $completionFull = [System.IO.Path]::GetFullPath($CompletionPath)
    }
    $lastCompletionSignature = ''
    $completionStableSince = $null
    $quietSeconds = [Math]::Max(15, $CompletionQuietSeconds)

    function Test-CompletionFileReady {
        param([string]$Path)
        return (Test-AgentCompletionFileReady -Path $Path)
    }

    function Get-ResultExitCode {
        param($Result)
        if ($null -eq $Result) {
            return $null
        }
        $candidate = $Result | Select-Object -Last 1
        if ($null -ne $candidate.PSObject.Properties['ExitCode']) {
            return $candidate.ExitCode
        }
        return $null
    }

    function Stop-ExecutorProcessesByCommandLine {
        param([string]$MatchText)
        if ([string]::IsNullOrWhiteSpace($MatchText)) {
            return
        }

        $escaped = [regex]::Escape($MatchText)
        $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
        $byParent = @{}
        foreach ($process in $allProcesses) {
            $parentId = [int]$process.ParentProcessId
            if (-not $byParent.ContainsKey($parentId)) {
                $byParent[$parentId] = New-Object System.Collections.ArrayList
            }
            [void]$byParent[$parentId].Add($process)
        }

        $descendants = New-Object System.Collections.ArrayList
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([int]$PID)
        while ($queue.Count -gt 0) {
            $parentId = [int]$queue.Dequeue()
            if (-not $byParent.ContainsKey($parentId)) {
                continue
            }
            foreach ($child in $byParent[$parentId]) {
                [void]$descendants.Add($child)
                $queue.Enqueue([int]$child.ProcessId)
            }
        }

        $descendantIds = @{}
        foreach ($descendant in $descendants) {
            $descendantIds[[int]$descendant.ProcessId] = $descendant
        }

        $seedIds = @{}
        foreach ($descendant in $descendants) {
            if (-not [string]::IsNullOrWhiteSpace($descendant.CommandLine) -and $descendant.CommandLine -match $escaped) {
                $seedIds[[int]$descendant.ProcessId] = $true
            }
        }

        $targetIds = @{}
        foreach ($seedId in @($seedIds.Keys)) {
            $queue.Enqueue([int]$seedId)
            while ($queue.Count -gt 0) {
                $currentId = [int]$queue.Dequeue()
                $targetIds[$currentId] = $true
                if ($byParent.ContainsKey($currentId)) {
                    foreach ($child in $byParent[$currentId]) {
                        if ($descendantIds.ContainsKey([int]$child.ProcessId)) {
                            $queue.Enqueue([int]$child.ProcessId)
                        }
                    }
                }
            }
        }

        $candidates = @($descendants |
            Where-Object { $targetIds.ContainsKey([int]$_.ProcessId) } |
            Sort-Object CreationDate -Descending)

        foreach ($candidate in $candidates) {
            try {
                Stop-Process -Id ([int]$candidate.ProcessId) -Force -ErrorAction Stop
            } catch {
                # Best effort cleanup. The process may have exited between WMI enumeration and Stop-Process.
            }
        }
    }

    while ($true) {
        $remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($remaining -le 0) {
            Stop-ExecutorProcessesByCommandLine -MatchText $ProcessMatchText
            Stop-Job -Job $Job | Out-Null
            Remove-Job -Job $Job -Force | Out-Null
            throw $TimeoutMessage
        }

        $done = Wait-Job -Job $Job -Timeout ([Math]::Min(5, $remaining))
        if ($done) {
            break
        }

        if (-not [string]::IsNullOrWhiteSpace($completionFull) -and (Test-Path -LiteralPath $completionFull)) {
            $completionItem = Get-Item -LiteralPath $completionFull
            $signature = '{0}|{1}' -f $completionItem.Length, $completionItem.LastWriteTimeUtc.Ticks
            if ($signature -ne $lastCompletionSignature) {
                $lastCompletionSignature = $signature
                $completionStableSince = Get-Date
            } elseif ($null -ne $completionStableSince -and ((Get-Date) - $completionStableSince).TotalSeconds -ge $quietSeconds) {
                Stop-ExecutorProcessesByCommandLine -MatchText $ProcessMatchText
                Stop-Job -Job $Job | Out-Null
                Remove-Job -Job $Job -Force | Out-Null
                return [pscustomobject]@{
                    ExitCode = 0
                    CompletionMode = 'completion_file'
                    CompletionPath = $completionFull
                }
            }
        }
    }

    $completionReadyAfterExit = Test-CompletionFileReady $completionFull
    $result = Receive-Job -Job $Job
    $state = $Job.State
    Remove-Job -Job $Job -Force | Out-Null
    if ($state -ne 'Completed') {
        throw "Agent command job ended with state: $state"
    }
    if ($completionReadyAfterExit) {
        return [pscustomobject]@{
            ExitCode = 0
            CompletionMode = 'completion_file_after_process_exit'
            CompletionPath = $completionFull
            ExecutorExitCode = (Get-ResultExitCode $result)
        }
    }
    if ($null -ne $result -and $null -eq $result.CompletionMode) {
        $result | Add-Member -NotePropertyName CompletionMode -NotePropertyValue 'process_exit' -Force
    }
    return $result
}

$promptPathFull = Resolve-RequiredPath $PromptPath 'Prompt'
$workDirFull = Resolve-RequiredPath $WorkDir 'WorkDir'
$logDirFull = [System.IO.Path]::GetFullPath($LogDir)
New-Item -ItemType Directory -Force -Path $logDirFull | Out-Null
$protectedRoot = Get-ConfigProjectRoot
$protectedRootStatusBefore = ''
if (-not [string]::IsNullOrWhiteSpace($protectedRoot) -and (Resolve-RequiredPath $protectedRoot 'ProtectedRoot') -ine $workDirFull) {
    $protectedRootStatusBefore = Get-GitStatusText -Repo $protectedRoot
}

$stdoutLog = Join-Path $logDirFull "$Name.stdout.log"
$stderrLog = Join-Path $logDirFull "$Name.stderr.log"
$lastMessage = Join-Path $logDirFull "$Name.last-message.md"
$metaPath = Join-Path $logDirFull "$Name.exec.json"
$rgConfigPath = Join-Path $PSScriptRoot 'ripgrep-autopilot.config'
$toolPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\tools'))
$commandSource = ''

if ($Executor -ne 'manual') {
    $commandSource = Resolve-ExecutorCommand $Executor
}

if ($ValidateOnly -or $Executor -eq 'manual') {
    [pscustomobject]@{
        Executor = $Executor
        Command = $commandSource
        PromptPath = $promptPathFull
        WorkDir = $workDirFull
        LogDir = $logDirFull
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        CompletionPath = $CompletionPath
        CompletionQuietSeconds = $CompletionQuietSeconds
        Status = if ($Executor -eq 'manual') { 'MANUAL_PROMPT_READY' } else { 'VALID' }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metaPath -Encoding UTF8
    Get-Content -LiteralPath $metaPath -Encoding UTF8
    exit 0
}

$timeoutSeconds = [Math]::Max(60, $TimeoutMinutes * 60)
$started = Get-Date
$reasoningEffortActual = if ([string]::IsNullOrWhiteSpace($ReasoningEffort)) { 'medium' } else { $ReasoningEffort.Trim() }
$automationGuard = @(
    'AUTOMATION HARD RULES:',
    '- Do not launch GUI editors or desktop applications such as Cursor, VS Code, Notepad, Explorer, browser windows, or IDE helpers.',
    '- Use shell, ripgrep, git, Maven, and direct file edits only; every result must be written to the required files.',
    '- This is unattended execution. Do not ask clarification questions. If a required completion file is requested, write that exact file before your final response.',
    '- If you genuinely cannot proceed, write the requested completion file with BLOCKED status and concrete evidence instead of replying conversationally.',
    ''
) -join "`n"

if ($Executor -eq 'codex') {
    $codexExecHelp = (& $commandSource exec --help 2>&1 | Out-String)
    $supportsApproval = $codexExecHelp -match '--ask-for-approval'
    $supportsBypass = $codexExecHelp -match '--dangerously-bypass-approvals-and-sandbox'

    $args = @(
        'exec',
        '-c', 'model_context_window=1000000',
        '-c', 'model_auto_compact_token_limit=900000',
        '-c', ('model_reasoning_effort="{0}"' -f $reasoningEffortActual),
        '-c', 'features.hooks=false',
        '--cd', $workDirFull,
        '--output-last-message', $lastMessage
    )
    if ($supportsBypass -and $Approval -eq 'never' -and $Sandbox -eq 'danger-full-access') {
        $args += '--dangerously-bypass-approvals-and-sandbox'
    } else {
        $args += @('--sandbox', $Sandbox)
        if ($supportsApproval -and -not [string]::IsNullOrWhiteSpace($Approval)) {
            $args += @('--ask-for-approval', $Approval)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $args += @('--model', $Model)
    }
    $args += '-'

    $job = Start-Job -ArgumentList $promptPathFull, $commandSource, $args, $stdoutLog, $stderrLog, $rgConfigPath, $toolPath, $automationGuard, $Name -ScriptBlock {
        param($PromptPathInner, $CommandSource, $ArgsInner, $StdoutLogInner, $StderrLogInner, $RgConfigPathInner, $ToolPathInner, $AutomationGuardInner, $NameInner)
        $stdoutText = ''
        $stderrText = ''
        $exit = 1
        try {
            if (Test-Path -LiteralPath $ToolPathInner) {
                $env:PATH = "$ToolPathInner;$env:PATH"
            }
            if (Test-Path -LiteralPath $RgConfigPathInner) {
                $env:RIPGREP_CONFIG_PATH = $RgConfigPathInner
            }
            $env:RG_AUTOPILOT_LIMIT = '80'
            $promptBody = Get-Content -LiteralPath $PromptPathInner -Raw -Encoding UTF8
            $env:REPLAY_AGENT_STAGE = $NameInner
            $env:REPLAY_ORACLE_ISOLATION = if ($NameInner -match '^(?i:phase2)$') { '0' } else { '1' }
            $env:REPLAY_FORBIDDEN_ORACLE_BRANCH = if ($promptBody -match '(?mi)oracle branch\s*[:=]\s*`?([^`\r\n]+)') { $Matches[1].Trim() } else { '' }
            $env:REPLAY_FORBIDDEN_ORACLE_COMMIT = if ($promptBody -match '(?mi)oracle commit\s*[:=]\s*`?([0-9a-f]{7,40})') { $Matches[1].Trim() } else { '' }
            $prompt = $AutomationGuardInner + $promptBody
            $output = $prompt | & $CommandSource @ArgsInner 2>&1
            $exit = $LASTEXITCODE
            $stdoutText = ($output | Out-String)
        } catch {
            $stderrText = ($_ | Out-String)
            if ($null -ne $_.Exception) {
                $stderrText += "`n$($_.Exception.ToString())"
            }
            $exit = 1
        } finally {
            $stdoutText | Set-Content -LiteralPath $StdoutLogInner -Encoding UTF8
            $stderrText | Set-Content -LiteralPath $StderrLogInner -Encoding UTF8
        }
        [pscustomobject]@{ ExitCode = $exit }
    }
    $result = Receive-JobWithTimeout -Job $job -TimeoutSeconds $timeoutSeconds -TimeoutMessage "Codex executor timed out after $TimeoutMinutes minutes" -CompletionPath $CompletionPath -CompletionQuietSeconds $CompletionQuietSeconds -ProcessMatchText $workDirFull
    $exitCode = $result.ExitCode
} elseif ($Executor -eq 'claude') {
    $args = @('--print', '--permission-mode', 'bypassPermissions', '--output-format', 'text', '--max-turns', '200')
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $args += @('--model', $Model)
    }
    $args += @('--add-dir', $workDirFull)

    $job = Start-Job -ArgumentList $promptPathFull, $commandSource, $args, $stdoutLog, $stderrLog, $workDirFull, $rgConfigPath, $toolPath, $automationGuard, $Name -ScriptBlock {
        param($PromptPathInner, $CommandSource, $ArgsInner, $StdoutLogInner, $StderrLogInner, $WorkDirInner, $RgConfigPathInner, $ToolPathInner, $AutomationGuardInner, $NameInner)
        $stdoutText = ''
        $stderrText = ''
        $exit = 1
        $pushed = $false
        try {
            if (Test-Path -LiteralPath $ToolPathInner) {
                $env:PATH = "$ToolPathInner;$env:PATH"
            }
            if (Test-Path -LiteralPath $RgConfigPathInner) {
                $env:RIPGREP_CONFIG_PATH = $RgConfigPathInner
            }
            $env:RG_AUTOPILOT_LIMIT = '80'
            Push-Location $WorkDirInner
            $pushed = $true
            $promptBody = Get-Content -LiteralPath $PromptPathInner -Raw -Encoding UTF8
            $env:REPLAY_AGENT_STAGE = $NameInner
            $env:REPLAY_ORACLE_ISOLATION = if ($NameInner -match '^(?i:phase2)$') { '0' } else { '1' }
            $env:REPLAY_FORBIDDEN_ORACLE_BRANCH = if ($promptBody -match '(?mi)oracle branch\s*[:=]\s*`?([^`\r\n]+)') { $Matches[1].Trim() } else { '' }
            $env:REPLAY_FORBIDDEN_ORACLE_COMMIT = if ($promptBody -match '(?mi)oracle commit\s*[:=]\s*`?([0-9a-f]{7,40})') { $Matches[1].Trim() } else { '' }
            $prompt = $AutomationGuardInner + $promptBody
            $output = $prompt | & $CommandSource @ArgsInner 2>&1
            $exit = $LASTEXITCODE
            $stdoutText = ($output | Out-String)
        } catch {
            $stderrText = ($_ | Out-String)
            if ($null -ne $_.Exception) {
                $stderrText += "`n$($_.Exception.ToString())"
            }
            $exit = 1
        } finally {
            if ($pushed) {
                Pop-Location
            }
            $stdoutText | Set-Content -LiteralPath $StdoutLogInner -Encoding UTF8
            $stderrText | Set-Content -LiteralPath $StderrLogInner -Encoding UTF8
        }
        [pscustomobject]@{ ExitCode = $exit }
    }
    $result = Receive-JobWithTimeout -Job $job -TimeoutSeconds $timeoutSeconds -TimeoutMessage "Claude executor timed out after $TimeoutMinutes minutes" -CompletionPath $CompletionPath -CompletionQuietSeconds $CompletionQuietSeconds -ProcessMatchText $workDirFull
    $exitCode = $result.ExitCode
} else {
    throw "Unsupported executor: $Executor"
}

$ended = Get-Date
$failureCategory = ''
if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($CompletionPath) -and -not (Test-AgentCompletionFileReady $CompletionPath)) {
    $exitCode = 88
    $failureCategory = 'missing_completion'
}
if ($exitCode -ne 0 -and [string]::IsNullOrWhiteSpace($failureCategory)) {
    $failureText = ''
    if (Test-Path -LiteralPath $stdoutLog) {
        $failureText += Get-Content -LiteralPath $stdoutLog -Raw -Encoding UTF8
    }
    if (Test-Path -LiteralPath $stderrLog) {
        $failureText += "`n"
        $failureText += Get-Content -LiteralPath $stderrLog -Raw -Encoding UTF8
    }
    if ($failureText -match '(?i)usage limit|hit your usage limit|purchase more credits|try again at') {
        $failureCategory = 'usage_limit'
    } elseif ($failureText -match '(?i)not logged in|login required|authentication|unauthorized') {
        $failureCategory = 'auth'
    } else {
        $failureCategory = 'executor'
    }
}

if (-not [string]::IsNullOrWhiteSpace($protectedRoot) -and $protectedRoot -ine $workDirFull) {
    $protectedRootStatusAfter = Get-GitStatusText -Repo $protectedRoot
    if ($protectedRootStatusAfter -ne $protectedRootStatusBefore) {
        $violationPath = Join-Path $logDirFull "$Name.protected-root-violation.md"
        @(
            '# Protected Root Status Violation',
            '',
            "stage: $Name",
            "executor: $Executor",
            "protected_root: $protectedRoot",
            "work_dir: $workDirFull",
            '',
            '## Before',
            '```',
            $protectedRootStatusBefore,
            '```',
            '',
            '## After',
            '```',
            $protectedRootStatusAfter,
            '```'
        ) | Set-Content -LiteralPath $violationPath -Encoding UTF8
        $exitCode = 92
        $failureCategory = 'protected_root_modified'
    }
}

$meta = [ordered]@{
    executor = $Executor
    prompt_path = $promptPathFull
    work_dir = $workDirFull
    log_dir = $logDirFull
    stdout_log = $stdoutLog
    stderr_log = $stderrLog
    last_message = $lastMessage
    model = $Model
    reasoning_effort = $reasoningEffortActual
    started_at = $started.ToString('s')
    ended_at = $ended.ToString('s')
    timeout_minutes = $TimeoutMinutes
    completion_path = $CompletionPath
    completion_quiet_seconds = $CompletionQuietSeconds
    completion_mode = $result.CompletionMode
    exit_code = $exitCode
    executor_exit_code = if ($null -ne $result.PSObject.Properties['ExecutorExitCode']) { $result.ExecutorExitCode } else { $exitCode }
    failure_category = $failureCategory
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metaPath -Encoding UTF8

if ($exitCode -ne 0) {
    if ($failureCategory -eq 'protected_root_modified') {
        Write-Host "$Executor modified protected project root. See $logDirFull"
        exit 92
    }
    if ($failureCategory -eq 'usage_limit') {
        Write-Host "$Executor usage limit reached. See $stdoutLog"
        exit 86
    }
    if ($failureCategory -eq 'auth') {
        Write-Host "$Executor authentication failed. See $stdoutLog"
        exit 87
    }
    if ($failureCategory -eq 'missing_completion') {
        Write-Host "$Executor exited successfully but did not write required completion file: $CompletionPath. See $stdoutLog"
        exit 88
    }
    throw "$Executor exited with code $exitCode. See $stdoutLog"
}

Write-Host "$Executor completed: $Name"
Write-Host "Log: $stdoutLog"
Write-Host "Last message: $lastMessage"
