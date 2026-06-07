param(
    [Parameter(Mandatory=$true)]
    [string]$PromptText,
    [string]$ProjectDir,
    [switch]$AdvisoryOnly
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-HookLog {
    param([string]$Message)

    try {
        $logDir = Join-Path $env:USERPROFILE ".agents\logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        }
        $logPath = Join-Path $logDir "skill-hooks.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $logPath -Value "[$timestamp][guard] $Message" -Encoding UTF8 -ErrorAction Stop
    } catch {
    }
}

function Test-ContainsAny {
    param(
        [string]$Text,
        [string[]]$Keywords
    )

    foreach ($keyword in $Keywords) {
        if ($Text.Contains($keyword.ToLower())) {
            return $true
        }
    }

    return $false
}

function New-Keyword {
    param([int[]]$Codes)

    return (-join ($Codes | ForEach-Object { [char]$_ }))
}

function Get-CanonicalProjectDir {
    param([string]$RawPath)

    if (-not [string]::IsNullOrWhiteSpace($RawPath) -and (Test-Path $RawPath)) {
        return (Resolve-Path $RawPath).Path
    }

    $cwd = (Get-Location).Path
    if (Test-Path $cwd) {
        return $cwd
    }

    return $null
}

function Get-LatestChildDirectory {
    param([string]$ParentPath)

    if (-not (Test-Path $ParentPath)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $ParentPath -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-WorkflowSyncStatePath {
    param([string]$ProjectRoot)

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        return $null
    }

    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($ProjectRoot.ToLowerInvariant())
        $hashBytes = $md5.ComputeHash($bytes)
        $hash = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
        $stateDir = Join-Path $env:USERPROFILE ".cursor\hooks\state\workflow-sync"
        return Join-Path $stateDir ($hash + ".json")
    } finally {
        $md5.Dispose()
    }
}

function Get-WorkflowSyncState {
    param([string]$ProjectRoot)

    $statePath = Get-WorkflowSyncStatePath -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($statePath) -or -not (Test-Path $statePath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $statePath -Encoding UTF8 -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-DateValue {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return [datetime]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        return $null
    }
}

function Get-LastWriteTimeOrNull {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        return (Get-Item -LiteralPath $Path).LastWriteTime
    } catch {
        return $null
    }
}

function Get-LatestWriteTimeInDirectory {
    param([string]$DirectoryPath)

    if (-not (Test-Path $DirectoryPath)) {
        return $null
    }

    try {
        $latest = Get-ChildItem -LiteralPath $DirectoryPath -Recurse -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $latest) {
            return $null
        }
        return $latest.LastWriteTime
    } catch {
        return $null
    }
}

function Get-GitDirtyPaths {
    param([string]$ProjectRoot)

    if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path (Join-Path $ProjectRoot ".git"))) {
        return @()
    }

    try {
        $output = & git -C $ProjectRoot status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
            return @()
        }

        $paths = @()
        foreach ($line in $output) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
                continue
            }

            $pathPart = $line.Substring(3).Trim()
            if ($pathPart.Contains("->")) {
                $pathPart = ($pathPart -split "->")[-1].Trim()
            }
            if (-not [string]::IsNullOrWhiteSpace($pathPart)) {
                $paths += $pathPart
            }
        }

        return $paths
    } catch {
        return @()
    }
}

function Get-LatestDirtyCodeWriteTime {
    param([string]$ProjectRoot)

    $latest = $null
    foreach ($relativePath in (Get-GitDirtyPaths -ProjectRoot $ProjectRoot)) {
        $normalized = $relativePath.Replace('/', '\')
        $lower = $normalized.ToLowerInvariant()

        if (
            $lower.StartsWith(".doc\") -or
            $lower.StartsWith("openspec\") -or
            $lower.StartsWith(".memory\") -or
            $lower.StartsWith(".cursor\") -or
            $lower.StartsWith(".claude\") -or
            $lower.StartsWith(".agents\") -or
            $lower.StartsWith("target\") -or
            $lower.StartsWith("node_modules\")
        ) {
            continue
        }

        $fullPath = Join-Path $ProjectRoot $normalized
        if (-not (Test-Path $fullPath)) {
            continue
        }

        $writeTime = Get-LastWriteTimeOrNull -Path $fullPath
        if ($null -ne $writeTime -and ($null -eq $latest -or $writeTime -gt $latest)) {
            $latest = $writeTime
        }
    }

    return $latest
}

function Write-BlockMessage {
    param(
        [string]$Title,
        [string[]]$Lines,
        [string]$ActionLine = "ACTION: Run deep-plan first, generate .doc/ and openspec, then continue."
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("=========================================")
    [void]$sb.AppendLine($Title)
    [void]$sb.AppendLine("=========================================")
    [void]$sb.AppendLine("")
    foreach ($line in $Lines) {
        [void]$sb.AppendLine($line)
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($ActionLine)
    [Console]::Write($sb.ToString())
}

function Exit-GuardDecision {
    param(
        [string]$LogMessage,
        [string]$BlockTitle,
        [string]$NoticeTitle,
        [string[]]$Lines,
        [string]$ActionLine = ""
    )

    if ($AdvisoryOnly) {
        Write-HookLog -Message ("advisory: " + $LogMessage)
    } else {
        Write-HookLog -Message $LogMessage
    }

    $title = $BlockTitle
    if ($AdvisoryOnly -and -not [string]::IsNullOrWhiteSpace($NoticeTitle)) {
        $title = $NoticeTitle
    }

    if ([string]::IsNullOrWhiteSpace($ActionLine)) {
        Write-BlockMessage -Title $title -Lines $Lines
    } else {
        Write-BlockMessage -Title $title -Lines $Lines -ActionLine $ActionLine
    }

    if ($AdvisoryOnly) {
        exit 0
    }

    exit 2
}

$promptLower = $PromptText.ToLower()
$projectRoot = Get-CanonicalProjectDir -RawPath $ProjectDir

if ([string]::IsNullOrWhiteSpace($projectRoot)) {
    Write-HookLog -Message "skip because project root is empty"
    exit 0
}

$planningKeywords = @(
    (New-Keyword @(28145,24230,35268,21010)),
    (New-Keyword @(25216,26415,35774,35745)),
    (New-Keyword @(25216,26415,26041,26696)),
    (New-Keyword @(38656,27714,36716,25216,26415,25991,26723)),
    "generate technical doc",
    "deep plan"
)
$implementationKeywords = @(
    (New-Keyword @(24320,21457)),
    (New-Keyword @(23454,29616)),
    (New-Keyword @(20889,20195,30721)),
    (New-Keyword @(32534,30721)),
    (New-Keyword @(24320,22987,24320,21457)),
    (New-Keyword @(32487,32493,24320,21457)),
    (New-Keyword @(23436,25972,24320,21457)),
    (New-Keyword @(19968,38190,24320,21457)),
    "auto-complete", "dev-workflow", "implement", "implementation", "code this", "fix this",
    (New-Keyword @(20462,22797,36825,20010))
)
$syncKeywords = @(
    (New-Keyword @(21516,27493,36827,24230)),
    (New-Keyword @(25552,20132,20195,30721)),
    (New-Keyword @(21457,24067)),
    "ship", "release", "push", "create pr", "merge",
    (New-Keyword @(21457,29256))
)
$completionKeywords = @(
    (New-Keyword @(24635,32467)),
    (New-Keyword @(25910,23614)),
    (New-Keyword @(24635,32467,20102)),
    (New-Keyword @(21487,26463)),
    (New-Keyword @(32467,26463)),
    (New-Keyword @(32467,26463,19968,19979)),
    (New-Keyword @(32467,26463,19968,19979,32467,26524)),
    (New-Keyword @(32467,26463,19979)),
    "wrap up", "done", "finished", "final answer", "finalize", "summary"
)

$isPlanningIntent = Test-ContainsAny -Text $promptLower -Keywords $planningKeywords
$isImplementationIntent = Test-ContainsAny -Text $promptLower -Keywords $implementationKeywords
$isSyncIntent = Test-ContainsAny -Text $promptLower -Keywords $syncKeywords
$isCompletionIntent = Test-ContainsAny -Text $promptLower -Keywords $completionKeywords

if (-not ($isPlanningIntent -or $isImplementationIntent -or $isSyncIntent -or $isCompletionIntent)) {
    exit 0
}

$rootDocDir = Join-Path $projectRoot "doc"
$rootDotDocDir = Join-Path $projectRoot ".doc"
$openSpecDir = Join-Path $projectRoot "openspec"
$openSpecChangesDir = Join-Path $openSpecDir "changes"

if ((Test-Path $rootDocDir) -and (-not (Test-Path $rootDotDocDir))) {
    Exit-GuardDecision -LogMessage "blocked because doc/ exists without .doc/ at $projectRoot" -BlockTitle "WORKFLOW BLOCKED" -NoticeTitle "WORKFLOW GUARD NOTICE" -Lines @(
        "Detected root doc/ directory but no .doc/ directory.",
        "The workflow standard requires .doc/; doc/ is not allowed."
    )
}

if ($isPlanningIntent) {
    Write-HookLog -Message "allow planning intent for $projectRoot"
    exit 0
}

$featureDir = Get-LatestChildDirectory -ParentPath $rootDotDocDir
$activeChangeDir = $null
if (Test-Path $openSpecChangesDir) {
    $activeChangeDir = Get-ChildItem -LiteralPath $openSpecChangesDir -Directory |
        Where-Object { $_.Name -ne "archive" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

$missing = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path $rootDotDocDir)) {
    [void]$missing.Add("Missing root .doc/ directory.")
} elseif ($null -eq $featureDir) {
    [void]$missing.Add("No feature directory found under .doc/.")
} else {
    $requirementsPath = Join-Path $featureDir.FullName "requirements.md"
    $techDesignPath = Join-Path $featureDir.FullName "tech-design.md"
    $taskPlanPath = Join-Path $featureDir.FullName "task_plan.md"
    $codeChangePath = Join-Path $featureDir.FullName "code-change.md"

    if (-not (Test-Path $requirementsPath)) {
        [void]$missing.Add("Missing requirements.md.")
    }
    if (-not (Test-Path $techDesignPath)) {
        [void]$missing.Add("Missing .doc/$($featureDir.Name)/tech-design.md.")
    }
    if (-not (Test-Path $taskPlanPath)) {
        [void]$missing.Add("Missing .doc/$($featureDir.Name)/task_plan.md.")
    }
    if ($isSyncIntent -and (-not (Test-Path $codeChangePath))) {
        [void]$missing.Add("Missing .doc/$($featureDir.Name)/code-change.md.")
    }
}

if (-not (Test-Path $openSpecDir)) {
    [void]$missing.Add("Missing openspec/.")
} elseif (-not (Test-Path $openSpecChangesDir)) {
    [void]$missing.Add("Missing openspec/changes/.")
} elseif ($null -eq $activeChangeDir) {
    [void]$missing.Add("No active openspec change found.")
} else {
    $proposalPath = Join-Path $activeChangeDir.FullName "proposal.md"
    $tasksPath = Join-Path $activeChangeDir.FullName "tasks.md"

    if (-not (Test-Path $proposalPath)) {
        [void]$missing.Add("Missing openspec/changes/$($activeChangeDir.Name)/proposal.md.")
    }
    if (-not (Test-Path $tasksPath)) {
        [void]$missing.Add("Missing openspec/changes/$($activeChangeDir.Name)/tasks.md.")
    }
}

if ($missing.Count -gt 0) {
    $contextLines = @()
    if ($featureDir -ne $null) {
        $contextLines += "Active .doc directory: .doc/$($featureDir.Name)"
    }
    if ($activeChangeDir -ne $null) {
        $contextLines += "Active openspec change: openspec/changes/$($activeChangeDir.Name)"
    }
    $contextLines += ""
    $contextLines += "Missing items:"
    foreach ($item in $missing) {
        $contextLines += "- $item"
    }

    Exit-GuardDecision -LogMessage ("blocked because missing artifacts: " + ($missing -join "; ")) -BlockTitle "WORKFLOW BLOCKED" -NoticeTitle "WORKFLOW GUARD NOTICE" -Lines $contextLines
}

if ($isCompletionIntent -and -not $isSyncIntent) {
    $syncState = Get-WorkflowSyncState -ProjectRoot $projectRoot
    $lastCodeEditAt = Get-DateValue -Value $syncState.lastCodeEditAt
    $dirtyCodeWriteAt = Get-LatestDirtyCodeWriteTime -ProjectRoot $projectRoot

    if ($null -eq $lastCodeEditAt -or ($null -ne $dirtyCodeWriteAt -and $dirtyCodeWriteAt -gt $lastCodeEditAt)) {
        $lastCodeEditAt = $dirtyCodeWriteAt
    }

    if ($null -ne $lastCodeEditAt) {
        $staleTargets = New-Object System.Collections.Generic.List[string]

        if ($featureDir -ne $null) {
            $docChecks = @(
                @{ Label = ".doc/$($featureDir.Name)/tech-design.md"; Path = (Join-Path $featureDir.FullName "tech-design.md") },
                @{ Label = ".doc/$($featureDir.Name)/task_plan.md"; Path = (Join-Path $featureDir.FullName "task_plan.md") },
                @{ Label = ".doc/$($featureDir.Name)/code-change.md"; Path = (Join-Path $featureDir.FullName "code-change.md") }
            )

            foreach ($docCheck in $docChecks) {
                $lastWrite = Get-LastWriteTimeOrNull -Path $docCheck.Path
                if ($null -eq $lastWrite -or $lastWrite -lt $lastCodeEditAt) {
                    [void]$staleTargets.Add($docCheck.Label)
                }
            }
        }

        if ($activeChangeDir -ne $null) {
            $openSpecLastWrite = Get-LatestWriteTimeInDirectory -DirectoryPath $activeChangeDir.FullName
            if ($null -eq $openSpecLastWrite -or $openSpecLastWrite -lt $lastCodeEditAt) {
                [void]$staleTargets.Add("openspec/changes/$($activeChangeDir.Name)/")
            }
        }

        $progressPath = Join-Path $projectRoot ".memory\progress.md"
        $findingsPath = Join-Path $projectRoot ".memory\findings.md"
        $progressWrite = Get-LastWriteTimeOrNull -Path $progressPath
        $findingsWrite = Get-LastWriteTimeOrNull -Path $findingsPath
        if ($null -eq $progressWrite -or $progressWrite -lt $lastCodeEditAt) {
            [void]$staleTargets.Add(".memory/progress.md")
        }
        if ($null -eq $findingsWrite -or $findingsWrite -lt $lastCodeEditAt) {
            [void]$staleTargets.Add(".memory/findings.md")
        }

        if ($staleTargets.Count -gt 0) {
            $syncLines = @(
                "Detected code edits in this session that are newer than the tracked project-level documents.",
                "Last code edit: " + $lastCodeEditAt.ToString("yyyy-MM-dd HH:mm:ss"),
                "",
                "Please sync these targets before summarizing or ending the task:"
            )
            foreach ($target in $staleTargets) {
                $syncLines += "- $target"
            }

            Exit-GuardDecision -LogMessage ("blocked completion because sync targets are stale after code edit at " + $lastCodeEditAt.ToString("s")) -BlockTitle "SYNC-PROGRESS REQUIRED" -NoticeTitle "SYNC-PROGRESS NOTICE" -Lines $syncLines -ActionLine "ACTION: Run sync-progress (or manually update .doc / openspec / .memory) before finishing this task."
        }
    }
}

Write-HookLog -Message "allow request for $projectRoot"
exit 0
