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
    [int]$SilentNoOutputTimeoutSeconds = 0,
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
    Checks if the carrier is in claim-api (Facade), claim-web (Controller),
    or claim-core/facade (Facade implementation). Returns $false for
    Service layer (claim-core without /facade/) and other internal layers.

    .PARAMETER CarrierPath
    The file path to the carrier class.

    .EXAMPLE
    Test-CarrierLayer "claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java"
    Returns $false (Service layer)

    .EXAMPLE
    Test-CarrierLayer "claim-api/src/main/java/com/huize/claim/api/facade/AiClaimFacade.java"
    Returns $true (Facade layer)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$CarrierPath
    )

    # Normalize path
    $CarrierPath = $CarrierPath -replace '\\', '/'

    # Check for Facade layer (claim-api)
    if ($CarrierPath -match 'claim-api/.*Facade\.java') {
        return $true
    }

    # Check for Controller layer (claim-web)
    if ($CarrierPath -match 'claim-web/.*Controller\.java') {
        return $true
    }

    # Check for Facade implementation in claim-core
    if ($CarrierPath -match 'claim-core/.*facade/.*FacadeImpl\.java') {
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
            "claim-core/src/main/java",
            "claim-api/src/main/java",
            "claim-web/src/main/java"
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

function ConvertTo-NormalizedPathText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value -replace '\\', '/') -replace '"', '').ToLowerInvariant()
}

function Test-CommandLineContainsPath {
    param([string]$CommandLine, [string]$Path)
    $commandText = ConvertTo-NormalizedPathText $CommandLine
    $pathText = ConvertTo-NormalizedPathText $Path
    return (-not [string]::IsNullOrWhiteSpace($pathText) -and $commandText.Contains($pathText))
}

function Get-ReplayCommandGuardViolations {
    param(
        [string]$WorkDir,
        [string]$ProtectedRoot
    )

    $violations = New-Object System.Collections.Generic.List[object]
    $protectedPom = ''
    if (-not [string]::IsNullOrWhiteSpace($ProtectedRoot)) {
        try {
            $protectedPom = [System.IO.Path]::GetFullPath((Join-Path $ProtectedRoot 'pom.xml'))
        } catch {
            $protectedPom = ''
        }
    }

    $processes = @()
    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    } catch {
        return @()
    }

    foreach ($process in $processes) {
        $commandLine = [string]$process.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }

        $name = [string]$process.Name
        $mavenLikeProcess = $name -match '(?i)^(mvn|mvn\.cmd|mvn\.bat|java|cmd|powershell|pwsh)(\.exe)?$'
        $mavenLikeCommand = $commandLine -match '(?i)(^|[\s"''\\/])(mvn|mvn\.cmd|mvn\.bat)([\s"'']|$)' -or
            $commandLine -match '(?i)org\.codehaus\.plexus\.classworlds|maven\.home|maven\.multiModuleProjectDirectory'
        if (-not ($mavenLikeProcess -and $mavenLikeCommand)) { continue }

        $reason = ''
        $isReplayWorktreeCommand = -not [string]::IsNullOrWhiteSpace($WorkDir) -and (Test-CommandLineContainsPath -CommandLine $commandLine -Path $WorkDir)
        $hasProjectList = $commandLine -match '(?i)(^|[\s"''])-pl($|[\s"''=])'
        $hasAlsoMake = $commandLine -match '(?i)(^|[\s"''])-am($|[\s"''])'
        $hasBuildOrTestGoal = $commandLine -match '(?i)(^|[\s"''])(compile|test-compile|test)([\s"'']|$)'

        if ($commandLine -match '(?i)(^|[\s"''])(deploy)([\s"'']|$)') {
            $reason = 'maven_deploy_forbidden'
        } elseif (-not [string]::IsNullOrWhiteSpace($protectedPom) -and (Test-CommandLineContainsPath -CommandLine $commandLine -Path $protectedPom)) {
            $reason = 'protected_root_pom_forbidden'
        } elseif ($isReplayWorktreeCommand -and $hasProjectList -and $hasBuildOrTestGoal -and -not $hasAlsoMake) {
            $reason = 'maven_pl_without_am_forbidden'
        }

        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            $violations.Add([pscustomobject][ordered]@{
                process_id = [int]$process.ProcessId
                parent_process_id = [int]$process.ParentProcessId
                name = $name
                reason = $reason
                work_dir = $WorkDir
                protected_root = $ProtectedRoot
                command_line = $commandLine
                detected_at = (Get-Date).ToString('s')
            }) | Out-Null
        }
    }

    return @($violations.ToArray())
}

function Stop-ReplayCommandGuardViolations {
    param(
        [object[]]$Violations,
        [string]$GuardLogPath = ''
    )

    if ($null -eq $Violations -or $Violations.Count -eq 0) { return }

    if (-not [string]::IsNullOrWhiteSpace($GuardLogPath)) {
        $guardDir = Split-Path -Parent $GuardLogPath
        if (-not [string]::IsNullOrWhiteSpace($guardDir)) {
            New-Item -ItemType Directory -Force -Path $guardDir | Out-Null
        }
        foreach ($violation in $Violations) {
            ($violation | ConvertTo-Json -Depth 6 -Compress) | Add-Content -LiteralPath $GuardLogPath -Encoding UTF8
        }
    }

    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $byParent = @{}
    foreach ($process in $allProcesses) {
        $parentId = [int]$process.ParentProcessId
        if (-not $byParent.ContainsKey($parentId)) {
            $byParent[$parentId] = New-Object System.Collections.ArrayList
        }
        [void]$byParent[$parentId].Add($process)
    }

    $targetIds = @{}
    foreach ($violation in $Violations) {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([int]$violation.process_id)
        while ($queue.Count -gt 0) {
            $currentId = [int]$queue.Dequeue()
            if ($targetIds.ContainsKey($currentId)) { continue }
            $targetIds[$currentId] = $true
            if ($byParent.ContainsKey($currentId)) {
                foreach ($child in $byParent[$currentId]) {
                    $queue.Enqueue([int]$child.ProcessId)
                }
            }
        }
    }

    foreach ($targetId in @($targetIds.Keys | Sort-Object -Descending)) {
        try {
            Stop-Process -Id ([int]$targetId) -Force -ErrorAction Stop
        } catch {
            # Best effort cleanup. The process may have exited between WMI enumeration and Stop-Process.
        }
    }
}

function Invoke-ReplayCommandGuard {
    param(
        [string]$WorkDir,
        [string]$ProtectedRoot,
        [string]$GuardLogPath = ''
    )

    $violations = @(Get-ReplayCommandGuardViolations -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot)
    if ($violations.Count -gt 0) {
        Stop-ReplayCommandGuardViolations -Violations $violations -GuardLogPath $GuardLogPath
    }
    return $violations
}

function Invoke-ReplayCommandGuardCleanup {
    param(
        [string]$WorkDir,
        [string]$ProtectedRoot,
        [string]$GuardLogPath = '',
        [int]$Attempts = 6
    )

    $allViolations = New-Object System.Collections.Generic.List[object]
    for ($attempt = 0; $attempt -lt [Math]::Max(1, $Attempts); $attempt++) {
        $violations = @(Invoke-ReplayCommandGuard -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot -GuardLogPath $GuardLogPath)
        if ($violations.Count -eq 0) {
            break
        }
        foreach ($violation in $violations) {
            $allViolations.Add($violation) | Out-Null
        }
        Start-Sleep -Milliseconds 750
    }
    return @($allViolations.ToArray())
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
        [string]$ProcessMatchText = '',
        [string]$WorkDir = '',
        [string]$ProtectedRoot = '',
        [string]$ProtectedRootStatusBefore = '',
        [string]$StdoutLogPath = '',
        [string]$StderrLogPath = '',
        [string]$LastMessagePath = '',
        [int]$SilentNoOutputTimeoutSeconds = 0,
        [string]$GuardLogPath = ''
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $watchStartedUtc = (Get-Date).ToUniversalTime()
    $completionFull = ''
    if (-not [string]::IsNullOrWhiteSpace($CompletionPath)) {
        $completionFull = [System.IO.Path]::GetFullPath($CompletionPath)
    }
    $lastCompletionSignature = ''
    $completionStableSince = $null
    $quietSeconds = [Math]::Max(15, $CompletionQuietSeconds)
    $silentTimeout = [Math]::Max(0, $SilentNoOutputTimeoutSeconds)

    function Test-CompletionFileReady {
        param([string]$Path)
        return (Test-AgentCompletionFileReady -Path $Path)
    }

    function Get-OutputActivitySignature {
        $parts = New-Object System.Collections.ArrayList
        foreach ($path in @($StdoutLogPath, $StderrLogPath, $LastMessagePath, $completionFull)) {
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }
            $fullPath = [System.IO.Path]::GetFullPath($path)
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                $item = Get-Item -LiteralPath $fullPath
                if ($item.Length -gt 8) {
                    [void]$parts.Add(('{0}|{1}|{2}' -f $item.FullName, $item.Length, $item.LastWriteTimeUtc.Ticks))
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($completionFull)) {
            $completionParent = Split-Path -Parent $completionFull
            if (-not [string]::IsNullOrWhiteSpace($completionParent) -and (Test-Path -LiteralPath $completionParent -PathType Container)) {
                $recentArtifacts = @(Get-ChildItem -LiteralPath $completionParent -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -gt 0 -and $_.LastWriteTimeUtc -gt $watchStartedUtc } |
                    Sort-Object FullName)
                foreach ($artifact in $recentArtifacts) {
                    [void]$parts.Add(('{0}|{1}|{2}' -f $artifact.FullName, $artifact.Length, $artifact.LastWriteTimeUtc.Ticks))
                }
            }
        }

        return (@($parts) -join "`n")
    }

    $lastOutputActivitySignature = ''
    $lastOutputActivityAt = Get-Date
    if ($silentTimeout -gt 0) {
        $lastOutputActivitySignature = Get-OutputActivitySignature
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
        $guardViolations = @(Invoke-ReplayCommandGuardCleanup -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot -GuardLogPath $GuardLogPath)
        if ($guardViolations.Count -gt 0) {
            Stop-ExecutorProcessesByCommandLine -MatchText $ProcessMatchText
            Stop-Job -Job $Job | Out-Null
            Remove-Job -Job $Job -Force | Out-Null
            [void](Invoke-ReplayCommandGuardCleanup -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot -GuardLogPath $GuardLogPath)
            $reasons = @($guardViolations | ForEach-Object { "$($_.reason):pid=$($_.process_id)" }) -join '; '
            return [pscustomobject]@{
                ExitCode = 93
                CompletionMode = 'command_guard_violation'
                GuardReasons = $reasons
                GuardLogPath = $GuardLogPath
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($ProtectedRoot) -and $ProtectedRoot -ine $WorkDir) {
            $protectedRootStatusCurrent = Get-GitStatusText -Repo $ProtectedRoot
            if ($protectedRootStatusCurrent -ne $ProtectedRootStatusBefore) {
                Stop-ExecutorProcessesByCommandLine -MatchText $ProcessMatchText
                Stop-Job -Job $Job | Out-Null
                Remove-Job -Job $Job -Force | Out-Null
                [void](Invoke-ReplayCommandGuardCleanup -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot -GuardLogPath $GuardLogPath)
                return [pscustomobject]@{
                    ExitCode = 92
                    CompletionMode = 'protected_root_modified_during_execution'
                    GuardReasons = 'protected_root_status_changed'
                    GuardLogPath = $GuardLogPath
                }
            }
        }

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
                $completionGuardViolations = @(Invoke-ReplayCommandGuardCleanup -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot -GuardLogPath $GuardLogPath)
                if ($completionGuardViolations.Count -gt 0) {
                    $reasons = @($completionGuardViolations | ForEach-Object { "$($_.reason):pid=$($_.process_id)" }) -join '; '
                    return [pscustomobject]@{
                        ExitCode = 93
                        CompletionMode = 'command_guard_violation'
                        GuardReasons = $reasons
                        GuardLogPath = $GuardLogPath
                    }
                }
                return [pscustomobject]@{
                    ExitCode = 0
                    CompletionMode = 'completion_file'
                    CompletionPath = $completionFull
                }
            }
        }

        if ($silentTimeout -gt 0 -and -not (Test-CompletionFileReady $completionFull)) {
            $currentOutputActivitySignature = Get-OutputActivitySignature
            if ($currentOutputActivitySignature -ne $lastOutputActivitySignature) {
                $lastOutputActivitySignature = $currentOutputActivitySignature
                $lastOutputActivityAt = Get-Date
            } elseif (((Get-Date) - $lastOutputActivityAt).TotalSeconds -ge $silentTimeout) {
                Stop-ExecutorProcessesByCommandLine -MatchText $ProcessMatchText
                Stop-Job -Job $Job | Out-Null
                Remove-Job -Job $Job -Force | Out-Null
                [void](Invoke-ReplayCommandGuardCleanup -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot -GuardLogPath $GuardLogPath)
                return [pscustomobject]@{
                    ExitCode = 88
                    CompletionMode = 'silent_no_output_timeout'
                    SilentNoOutputTimeoutSeconds = $silentTimeout
                    CompletionPath = $completionFull
                }
            }
        }
    }

    $completionReadyAfterExit = Test-CompletionFileReady $completionFull
    $result = Receive-Job -Job $Job
    $state = $Job.State
    Remove-Job -Job $Job -Force | Out-Null
    $guardViolationsAfterExit = @(Invoke-ReplayCommandGuardCleanup -WorkDir $WorkDir -ProtectedRoot $ProtectedRoot -GuardLogPath $GuardLogPath)
    if ($guardViolationsAfterExit.Count -gt 0) {
        $reasons = @($guardViolationsAfterExit | ForEach-Object { "$($_.reason):pid=$($_.process_id)" }) -join '; '
        return [pscustomobject]@{
            ExitCode = 93
            CompletionMode = 'command_guard_violation_after_exit'
            GuardReasons = $reasons
            GuardLogPath = $GuardLogPath
            ExecutorExitCode = (Get-ResultExitCode $result)
        }
    }
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
$commandGuardLog = Join-Path $logDirFull "$Name.command-guard.jsonl"
$rgConfigPath = Join-Path $PSScriptRoot 'ripgrep-autopilot.config'
$toolPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\tools'))
$commandSource = ''

if ($Executor -ne 'manual') {
    $commandSource = Resolve-ExecutorCommand $Executor
}

$timeoutSeconds = [Math]::Max(60, $TimeoutMinutes * 60)
$effectiveSilentNoOutputTimeoutSeconds = [Math]::Max(0, $SilentNoOutputTimeoutSeconds)
if ($effectiveSilentNoOutputTimeoutSeconds -le 0 -and $env:REPLAY_AGENT_SILENT_NO_OUTPUT_TIMEOUT_SECONDS -match '^\d+$') {
    $effectiveSilentNoOutputTimeoutSeconds = [int]$env:REPLAY_AGENT_SILENT_NO_OUTPUT_TIMEOUT_SECONDS
}
if ($effectiveSilentNoOutputTimeoutSeconds -le 0 -and -not [string]::IsNullOrWhiteSpace($CompletionPath) -and $timeoutSeconds -gt 1200) {
    $effectiveSilentNoOutputTimeoutSeconds = 900
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
        SilentNoOutputTimeoutSeconds = $effectiveSilentNoOutputTimeoutSeconds
        Status = if ($Executor -eq 'manual') { 'MANUAL_PROMPT_READY' } else { 'VALID' }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metaPath -Encoding UTF8
    Get-Content -LiteralPath $metaPath -Encoding UTF8
    exit 0
}

$started = Get-Date
$reasoningEffortActual = if ([string]::IsNullOrWhiteSpace($ReasoningEffort)) { 'medium' } else { $ReasoningEffort.Trim() }
$allowedPom = Join-Path $workDirFull 'pom.xml'
$protectedPomForPrompt = if (-not [string]::IsNullOrWhiteSpace($protectedRoot)) { Join-Path $protectedRoot 'pom.xml' } else { '<protected project root pom>' }
$automationGuard = @(
    'AUTOMATION HARD RULES:',
    '- Do not launch GUI editors or desktop applications such as Cursor, VS Code, Notepad, Explorer, browser windows, or IDE helpers.',
    '- Use shell, ripgrep, git, Maven, and direct file edits only; every result must be written to the required files.',
    '- This is unattended execution. Do not ask clarification questions. If a required completion file is requested, write that exact file before your final response.',
    '- If you genuinely cannot proceed, write the requested completion file with BLOCKED status and concrete evidence instead of replying conversationally.',
    "- Maven project boundary: the only allowed project POM is $allowedPom; never run Maven with -f $protectedPomForPrompt or any POM under the protected project root.",
    '- Forbidden Maven goals in replay agent execution: never run `mvn deploy`; do not run `mvn install` unless the prompt explicitly authorizes install for an isolated replay worktree.',
    '- Maven commands that run tests must include `-f <isolated replay worktree>\pom.xml`; include `-s <settings.xml>` only when the replay config defines `maven_settings`.',
    '- Maven commands with `-pl <module>` must also include `-am` so reactor source modules are used instead of drifted local/remote SNAPSHOT artifacts.',
    '- In PowerShell, Maven commands containing `-Dtest`, `#`, or `-Dsurefire.failIfNoSpecifiedTests=false` should use `mvn --% ...` to avoid argument parsing false blockers.',
    '- If the target production carrier is in a module without test dependencies, place tests in an existing test-harness module; do not edit any `pom.xml` to add JUnit/Mockito/Spring Test.',
    '- For TaskProcessor/rebuildTaskData/source-chain tests, do not start a full Spring context: do not extend AbstractTestClass and do not add @SpringBootTest, @RunWith(SpringJUnit4ClassRunner.class), @ContextConfiguration, or @Resource injection. Use no-Spring JUnit with Mockito/reflection and deterministic inputs.',
    '- For policyNum/insureNum rebuild slices, mock AiClaimDataAssemblyHelper.buildRequestCommon and invoke the real RequestBuildFunction with a RequestBuildContext containing policyNum and insureNum. Do not directly return a hand-built request from thenAnswer. Do not rely on fixed database caseIds or allow taskData == null to pass.',
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
    $result = Receive-JobWithTimeout -Job $job -TimeoutSeconds $timeoutSeconds -TimeoutMessage "Codex executor timed out after $TimeoutMinutes minutes" -CompletionPath $CompletionPath -CompletionQuietSeconds $CompletionQuietSeconds -ProcessMatchText $workDirFull -WorkDir $workDirFull -ProtectedRoot $protectedRoot -ProtectedRootStatusBefore $protectedRootStatusBefore -StdoutLogPath $stdoutLog -StderrLogPath $stderrLog -LastMessagePath $lastMessage -SilentNoOutputTimeoutSeconds $effectiveSilentNoOutputTimeoutSeconds -GuardLogPath $commandGuardLog
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
    $result = Receive-JobWithTimeout -Job $job -TimeoutSeconds $timeoutSeconds -TimeoutMessage "Claude executor timed out after $TimeoutMinutes minutes" -CompletionPath $CompletionPath -CompletionQuietSeconds $CompletionQuietSeconds -ProcessMatchText $workDirFull -WorkDir $workDirFull -ProtectedRoot $protectedRoot -ProtectedRootStatusBefore $protectedRootStatusBefore -StdoutLogPath $stdoutLog -StderrLogPath $stderrLog -LastMessagePath $lastMessage -SilentNoOutputTimeoutSeconds $effectiveSilentNoOutputTimeoutSeconds -GuardLogPath $commandGuardLog
    $exitCode = $result.ExitCode
} else {
    throw "Unsupported executor: $Executor"
}

$ended = Get-Date
$stdoutLength = if (Test-Path -LiteralPath $stdoutLog -PathType Leaf) { (Get-Item -LiteralPath $stdoutLog).Length } else { 0 }
$stderrLength = if (Test-Path -LiteralPath $stderrLog -PathType Leaf) { (Get-Item -LiteralPath $stderrLog).Length } else { 0 }
$lastMessageExists = Test-Path -LiteralPath $lastMessage -PathType Leaf
$lastMessageLength = if ($lastMessageExists) { (Get-Item -LiteralPath $lastMessage).Length } else { 0 }
$executorProducedNoOutput = (
    $result.CompletionMode -eq 'silent_no_output_timeout' -or
    (
        $result.CompletionMode -eq 'process_exit' -and
        -not (Test-AgentCompletionFileReady $CompletionPath) -and
        $stdoutLength -le 8 -and
        $stderrLength -le 8 -and
        (-not $lastMessageExists -or $lastMessageLength -le 8)
    )
)
$failureCategory = ''
if ($result.CompletionMode -eq 'silent_no_output_timeout') {
    $exitCode = 88
    $failureCategory = 'executor_silent_no_output'
} elseif ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($CompletionPath) -and -not (Test-AgentCompletionFileReady $CompletionPath)) {
    $exitCode = 88
    $failureCategory = if ($executorProducedNoOutput) { 'executor_silent_no_output' } else { 'missing_completion' }
}
if ($exitCode -eq 93 -and [string]::IsNullOrWhiteSpace($failureCategory)) {
    $failureCategory = 'command_guard_violation'
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
    if ($failureText -match '(?i)\b402\b|credit required|positive balance|required for this model|insufficient credits|not enough credits') {
        $failureCategory = 'executor_credit_required'
    } elseif ($failureText -match '(?i)usage limit|hit your usage limit|purchase more credits|try again at') {
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
    command_guard_log = $commandGuardLog
    model = $Model
    reasoning_effort = $reasoningEffortActual
    started_at = $started.ToString('s')
    ended_at = $ended.ToString('s')
    timeout_minutes = $TimeoutMinutes
    completion_path = $CompletionPath
    completion_quiet_seconds = $CompletionQuietSeconds
    silent_no_output_timeout_seconds = $effectiveSilentNoOutputTimeoutSeconds
    completion_mode = $result.CompletionMode
    stdout_length = $stdoutLength
    stderr_length = $stderrLength
    last_message_exists = $lastMessageExists
    last_message_length = $lastMessageLength
    executor_produced_no_output = $executorProducedNoOutput
    command_guard_reasons = if ($null -ne $result.PSObject.Properties['GuardReasons']) { $result.GuardReasons } else { '' }
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
    if ($failureCategory -eq 'executor_credit_required') {
        Write-Host "$Executor credit or positive balance is required. See $stdoutLog"
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
    if ($failureCategory -eq 'executor_silent_no_output') {
        Write-Host "$Executor produced no output or stage artifacts before the silent watchdog expired: $CompletionPath. See $stdoutLog"
        exit 88
    }
    if ($failureCategory -eq 'command_guard_violation') {
        Write-Host "$Executor attempted a forbidden replay command. See $commandGuardLog"
        exit 93
    }
    throw "$Executor exited with code $exitCode. See $stdoutLog"
}

Write-Host "$Executor completed: $Name"
Write-Host "Log: $stdoutLog"
Write-Host "Last message: $lastMessage"
