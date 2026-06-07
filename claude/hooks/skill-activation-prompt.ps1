param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

function Write-HookLog {
    param(
        [string]$Platform,
        [string]$Message
    )

    try {
        $logDir = Join-Path $env:USERPROFILE ".agents\logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        }
        $logPath = Join-Path $logDir "skill-hooks.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $logPath -Value "[$timestamp][$Platform] $Message" -Encoding UTF8 -ErrorAction Stop
    } catch {
    }
}

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-HookLog -Platform "claude" -Message "skip empty hook input"
    exit 0
}

try {
    $data = $rawInput | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-HookLog -Platform "claude" -Message "skip invalid hook json"
    exit 0
}

if ($null -eq $data) {
    Write-HookLog -Platform "claude" -Message "skip null hook payload"
    exit 0
}

$promptText = ""
if ($data.PSObject.Properties["prompt"]) {
    $promptText = $data.prompt
}

if ([string]::IsNullOrWhiteSpace($promptText)) {
    Write-HookLog -Platform "claude" -Message "skip empty prompt"
    exit 0
}

$guardScript = Join-Path $env:USERPROFILE ".agents\hooks\workflow-guard-core.ps1"
if (Test-Path $guardScript) {
    & $guardScript -PromptText $promptText -ProjectDir $env:CLAUDE_PROJECT_DIR -AdvisoryOnly
    if ($LASTEXITCODE -ne 0) {
        Write-HookLog -Platform "claude" -Message "workflow guard returned exit code $LASTEXITCODE; continuing as advisory"
    }
}

$coreScript = Join-Path $env:USERPROFILE ".agents\hooks\skill-activation-core.ps1"
if (Test-Path $coreScript) {
    & $coreScript -PromptText $promptText -ProjectDir $env:CLAUDE_PROJECT_DIR
    Write-HookLog -Platform "claude" -Message "skill suggestion processed"
} else {
    Write-HookLog -Platform "claude" -Message "missing core script: $coreScript"
}

exit 0
