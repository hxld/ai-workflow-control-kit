param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [string]$ProjectRoot = '',
    [string]$MavenCommand = 'mvn',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Read-YamlField {
    param(
        [string]$YamlContent,
        [string]$FieldName
    )
    if ([string]::IsNullOrWhiteSpace($YamlContent)) {
        return $null
    }

    # Simple YAML parser for specific fields
    # Matches: field_name: value
    # Split into lines and check each line
    $lines = $YamlContent -split "`n"
    foreach ($line in $lines) {
        # Check if this line contains the field we're looking for
        if ($line -match "^\s*" + [regex]::Escape($FieldName) + "\s*:\s*(.+)$") {
            $value = $matches[1].Trim()
            # Remove quotes if present
            $value = $value -replace '^["'']|["'']$', ''
            return $value
        }
    }
    return $null
}

function Convert-ToWorktreeEquivalentPath {
    param(
        [string]$PathValue,
        [string]$ProjectRootFull,
        [string]$WorktreeFull
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

    $pathFull = Resolve-AbsolutePath $PathValue
    $projectPrefix = (Resolve-AbsolutePath $ProjectRootFull).TrimEnd('\', '/')
    $worktreePrefix = (Resolve-AbsolutePath $WorktreeFull).TrimEnd('\', '/')

    if ($pathFull.Equals($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $worktreePrefix
    }

    $prefixWithSlash = $projectPrefix + [System.IO.Path]::DirectorySeparatorChar
    if ($pathFull.StartsWith($prefixWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $pathFull.Substring($prefixWithSlash.Length)
        $candidate = Join-Path $worktreePrefix $relative
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $pathFull
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    # Try to infer project root from worktree
    $pomXml = Join-Path $worktreeFull 'pom.xml'
    if (Test-Path -LiteralPath $pomXml) {
        $ProjectRoot = $worktreeFull
    } else {
        # Check if worktree is a subdirectory of project root
        $parent = Split-Path -Parent $worktreeFull
        while (-not [string]::IsNullOrWhiteSpace($parent)) {
            if (Test-Path -LiteralPath (Join-Path $parent 'pom.xml')) {
                $ProjectRoot = $parent
                break
            }
            $nextParent = Split-Path -Parent $parent
            if ($nextParent -eq $parent) { break }
            $parent = $nextParent
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    throw "ProjectRoot could not be inferred. Please provide -ProjectRoot or ensure pom.xml exists in worktree or ancestor directory."
}

$projectRootFull = Resolve-AbsolutePath $ProjectRoot
$preflightResultPath = Join-Path $replayRootFull 'PREFLIGHT_TEST_COMPILATION.json'
$preflightLogPath = Join-Path $replayRootFull 'PREFLIGHT_TEST_COMPILATION.log'

$startTime = Get-Date
$result = [ordered]@{
    stage = 'preflight_test_compilation'
    replay_root = $replayRootFull
    worktree = $worktreeFull
    project_root = $projectRootFull
    status = 'PENDING'
    decision = 'ALLOW'
    issues = @()
    warnings = @()
    started_at = $startTime.ToString('s')
    completed_at = ''
    duration_seconds = 0
    maven_settings_used = ''
    root_pom_used = ''
    maven_command_args = ''
}

Write-Host "Preflight: Validating baseline test compilation health..."
Write-Host "  Project root: $projectRootFull"
Write-Host "  Worktree: $worktreeFull"

# Check for pom.xml
$pomPath = Join-Path $projectRootFull 'pom.xml'
if (-not (Test-Path -LiteralPath $pomPath)) {
    $result.status = 'SKIP'
    $result.decision = 'ALLOW'
    $result.warnings += 'pom.xml not found - skipping preflight validation'
    $result.completed_at = (Get-Date).ToString('s')
    $result.duration_seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $preflightResultPath -Encoding UTF8
    Write-Host "Preflight: SKIP - pom.xml not found"
    exit 0
}

# Try to compile test sources only
# Check for build-test-profile.yaml to get Maven settings and root pom
$buildTestProfilePath = Join-Path $projectRootFull '.memory\build-test-profile.yaml'
$mavenSettings = $null
$rootPom = $null

if (Test-Path -LiteralPath $buildTestProfilePath) {
    Write-Host "Preflight: Found build-test-profile.yaml at $buildTestProfilePath"
    $yamlContent = Get-Content -LiteralPath $buildTestProfilePath -Raw -Encoding UTF8
    $mavenSettings = Read-YamlField -YamlContent $yamlContent -FieldName 'maven_settings'
    $rootPom = Read-YamlField -YamlContent $yamlContent -FieldName 'root_pom'

    if (-not [string]::IsNullOrWhiteSpace($mavenSettings)) {
        Write-Host "Preflight: Using Maven settings: $mavenSettings"
    }
    if (-not [string]::IsNullOrWhiteSpace($rootPom)) {
        Write-Host "Preflight: Using root POM: $rootPom"
    }
}

if (-not [string]::IsNullOrWhiteSpace($rootPom)) {
    $originalRootPom = Resolve-AbsolutePath $rootPom
    $mappedRootPom = Convert-ToWorktreeEquivalentPath -PathValue $rootPom -ProjectRootFull $projectRootFull -WorktreeFull $worktreeFull
    if (-not $mappedRootPom.Equals($originalRootPom, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Preflight: Remapped profile root POM to isolated worktree: $mappedRootPom"
        $result.warnings += "profile_root_pom_remapped_to_worktree: $originalRootPom -> $mappedRootPom"
        $rootPom = $mappedRootPom
    }
}

# Build Maven argument list
$mavenArgs = @('test-compile', '-q', '-DskipTests')

if (-not [string]::IsNullOrWhiteSpace($mavenSettings)) {
    $mavenArgs = @('-s', $mavenSettings) + $mavenArgs
}

# Determine working directory and POM file
$mavenWorkDir = if (-not [string]::IsNullOrWhiteSpace($rootPom) -and (Test-Path -LiteralPath $rootPom)) {
    Write-Host "Preflight: Using POM file: $rootPom"
    $mavenArgs = @('-f', $rootPom) + $mavenArgs
    Split-Path -Parent $rootPom
} else {
    $projectRootFull
}

$testCompileCmd = @($MavenCommand) + $mavenArgs
$testCompileLog = Join-Path $replayRootFull 'PREFLIGHT_MAVEN_TEST_COMPILE.log'
$testCompileErrorLog = Join-Path $replayRootFull 'PREFLIGHT_MAVEN_TEST_COMPILE_ERROR.log'

Write-Host "Preflight: Running: $($MavenCommand) $($mavenArgs -join ' ')"
Write-Host "  Working directory: $mavenWorkDir"
Write-Host "  Log: $testCompileLog"
Write-Host "  Error Log: $testCompileErrorLog"

# Record the actual Maven arguments used in the result
$result.maven_settings_used = if ($mavenSettings) { $mavenSettings } else { '(not specified)' }
$result.root_pom_used = if ($rootPom) { $rootPom } else { '(default)' }
$result.maven_command_args = $mavenArgs -join ' '

# Resolve Maven command path
$mavenCmdPath = $null
try {
    $cmdInfo = Get-Command -Name $MavenCommand -ErrorAction Stop
    $mavenCmdPath = $cmdInfo.Source
    Write-Host "Preflight: Resolved Maven path: $mavenCmdPath"
} catch {
    $errorMsg = "Failed to resolve Maven command '$MavenCommand': $_"
    $result.status = 'LAUNCH_FAILED'
    $result.decision = 'BLOCKED'
    $result.issues += $errorMsg
    $result.completed_at = (Get-Date).ToString('s')
    $result.duration_seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

    # Add exit_code field
    $result | Add-Member -NotePropertyName 'exit_code' -NotePropertyValue -1

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $preflightResultPath -Encoding UTF8

    $blockerPath = Join-Path $replayRootFull 'PREFLIGHT_BLOCKER.md'
    @"
# Preflight Blocker: Maven Launch Failed

Could not locate or launch Maven executable.

- Project: $projectRootFull
- Command: $MavenCommand

## Error

$errorMsg

**Decision**: BLOCKED - Maven must be installed and accessible.

**Recovery**:
1. Verify Maven is installed: `mvn -version`
2. Check PATH environment variable includes Maven bin directory.
3. Re-run replay after fixing Maven installation.
"@ | Set-Content -LiteralPath $blockerPath -Encoding UTF8

    Write-Host "Preflight: BLOCKED - $errorMsg"
    exit 1
}

# Use .NET ProcessStartInfo for reliable process execution
$processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
$processStartInfo.FileName = $mavenCmdPath
# Build arguments as a single string (compatible with all .NET versions)
$processStartInfo.Arguments = $mavenArgs -join ' '
$processStartInfo.WorkingDirectory = $mavenWorkDir
$processStartInfo.UseShellExecute = $false
$processStartInfo.RedirectStandardOutput = $true
$processStartInfo.RedirectStandardError = $true
$processStartInfo.CreateNoWindow = $true

# Create process object
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processStartInfo

# Prepare output streams
$outputLogLines = [System.Collections.Generic.List[string]]::new()
$errorLogLines = [System.Collections.Generic.List[string]]::new()

# Start the process
try {
    $started = $process.Start()
    if (-not $started) {
        throw "Process.Start() returned false"
    }
} catch {
    $errorMsg = "Failed to launch Maven process: $_"
    $result.status = 'LAUNCH_FAILED'
    $result.decision = 'BLOCKED'
    $result.issues += $errorMsg
    $result.completed_at = (Get-Date).ToString('s')
    $result.duration_seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

    # Add exit_code field
    $result | Add-Member -NotePropertyName 'exit_code' -NotePropertyValue -1

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $preflightResultPath -Encoding UTF8

    $blockerPath = Join-Path $replayRootFull 'PREFLIGHT_BLOCKER.md'
    @"
# Preflight Blocker: Maven Process Launch Failed

Could not start Maven process.

- Project: $projectRootFull
- Maven path: $mavenCmdPath

## Error

$errorMsg

**Decision**: BLOCKED - Maven process failed to start.

**Recovery**:
1. Verify Maven executable exists at: $mavenCmdPath
2. Check file permissions and antivirus settings.
3. Try running Maven manually to diagnose the issue.
"@ | Set-Content -LiteralPath $blockerPath -Encoding UTF8

    Write-Host "Preflight: BLOCKED - $errorMsg"
    exit 1
}

# Wait for process with timeout
$completed = $process.WaitForExit($TimeoutSeconds * 1000)

if (-not $completed) {
    try {
        $process.Kill()
    } catch { }

    $result.status = 'TIMEOUT'
    $result.decision = 'BLOCKED'
    $result.issues += "preflight_timeout: test-compile did not complete within ${TimeoutSeconds}s"
    $result.completed_at = (Get-Date).ToString('s')
    $result.duration_seconds = $TimeoutSeconds

    # Add exit_code field (use -1 for timeout)
    $result | Add-Member -NotePropertyName 'exit_code' -NotePropertyValue -1

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $preflightResultPath -Encoding UTF8

    $blockerPath = Join-Path $replayRootFull 'PREFLIGHT_BLOCKER.md'
    @"
# Preflight Blocker: Test Compilation Timeout

Test compilation validation did not complete within ${TimeoutSeconds}s.

- Project: $projectRootFull
- Maven path: $mavenCmdPath
- Log: $testCompileLog

**Decision**: BLOCKED - Phase 1 implementation must not start until baseline test compilation is verified.

**Recovery**:
- Check if the Maven build is hanging on dependency downloads or network issues.
- Try running `$MavenCommand test-compile -q -DskipTests` manually to diagnose the issue.
- If the issue is environment-related, fix the environment before running replay.
- If the issue is a genuine compilation blocker, fix it before Phase 1 implementation.
"@ | Set-Content -LiteralPath $blockerPath -Encoding UTF8

    Write-Host "Preflight: BLOCKED - timeout after ${TimeoutSeconds}s"
    exit 1
}

# Read output streams (safe since process has exited)
$stdoutContent = $process.StandardOutput.ReadToEnd()
$stderrContent = $process.StandardError.ReadToEnd()

# Write logs
$stdoutContent | Out-File -LiteralPath $testCompileLog -Encoding UTF8 -NoNewline
$stderrContent | Out-File -LiteralPath $testCompileErrorLog -Encoding UTF8 -NoNewline

$exitCode = $process.ExitCode
$result.completed_at = (Get-Date).ToString('s')
$result.duration_seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

# Read log for analysis
$logContent = $stdoutContent
$errorContent = $stderrContent
$combinedLogContent = $stdoutContent + "`n" + $stderrContent

# Add exit_code to result (always present)
$result | Add-Member -NotePropertyName 'exit_code' -NotePropertyValue $exitCode

# Analyze exit code and log
if ($exitCode -eq 0) {
    $result.status = 'PASS'
    $result.decision = 'ALLOW'
    Write-Host "Preflight: PASS - test compilation succeeded"
} else {
    $result.status = 'FAIL'
    $result.decision = 'BLOCKED'

    # Try to categorize the failure
    if ($combinedLogContent -match '[Bb]uild failure') {
        $result.issues += 'build_failure'
    }
    if ($combinedLogContent -match '[Cc]ompilation failure') {
        $result.issues += 'compilation_failure'
    }
    if ($combinedLogContent -match '[Dd]ependency.*error|[Rr]esolution.*error') {
        $result.issues += 'dependency_resolution_failure'
    }
    if ($combinedLogContent -match '[Pp]lugin.*error|[Gg]oal.*error') {
        $result.issues += 'maven_plugin_error'
    }
    if ($combinedLogContent -match 'OutOfMemory|memory') {
        $result.issues += 'out_of_memory'
    }

    if ($result.issues.Count -eq 0) {
        $result.issues += "unknown_failure: exit_code=$exitCode"
    }

    Write-Host "Preflight: BLOCKED - test compilation failed with exit code $exitCode"
    Write-Host "  Issues: $($result.issues -join ', ')"

    # Write human-readable blocker
    $blockerPath = Join-Path $replayRootFull 'PREFLIGHT_BLOCKER.md'
    $issueList = ($result.issues | ForEach-Object { "- $_" }) -join "`n"
    @"
# Preflight Blocker: Test Compilation Failed

Baseline test compilation failed. Phase 1 implementation must not start until baseline test health is verified.

- Project: $projectRootFull
- Maven path: $mavenCmdPath
- Exit code: $exitCode
- Duration: $($result.duration_seconds)s
- Log: $testCompileLog

## Detected Issues

$issueList

**Decision**: BLOCKED - Do not start Phase 1 implementation.

**Recovery**:
1. Review the compilation log: `$testCompileLog`
2. Fix the compilation errors in the test source code.
3. Verify the fix by running: `$MavenCommand test-compile -DskipTests` manually.
4. Once baseline tests compile, re-run the replay.

**Note**: This prevents `implementation_after_blocked_red` by ensuring the test framework can compile before any RED phase execution.
"@ | Set-Content -LiteralPath $blockerPath -Encoding UTF8

    # Write log summary to preflight log
    $logHead = if ($combinedLogContent.Length -gt 2000) { $combinedLogContent.Substring(0, 2000) + "`n... (truncated)" } else { $combinedLogContent }
    @"
Preflight Test Compilation Result
==================================

Status: $($result.status)
Decision: $($result.decision)
Exit Code: $exitCode
Duration: $($result.duration_seconds)s
Issues: $($result.issues -join ', ')

Compilation Log (last 2000 chars):
-----------------------------------
$logHead
"@ | Set-Content -LiteralPath $preflightLogPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $preflightResultPath -Encoding UTF8

if ($result.decision -eq 'BLOCKED') {
    exit 1
}

exit 0
