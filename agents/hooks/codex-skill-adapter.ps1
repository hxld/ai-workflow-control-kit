param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

function Write-CodexAdapterLog {
    param([string]$Message)

    try {
        $logDir = Join-Path $env:USERPROFILE ".agents\logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir "skill-hooks.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $logPath -Value "[$timestamp][codex-adapter] $Message" -Encoding UTF8
    } catch {
    }
}

function ConvertFrom-CodexHookJson {
    param([string]$RawJson)

    try {
        return $RawJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $directError = $_.Exception.Message
    }

    # Some Codex hook payloads have Windows paths with odd-length backslash runs.
    # Normalize only invalid JSON escapes; valid escapes like \n, \t, \u1234, \\/ stay unchanged.
    $fixedJson = [regex]::Replace($RawJson, '\\+([^"\\/bfnrtu])', '\\$1')
    if ($fixedJson -eq $RawJson) {
        Write-CodexAdapterLog -Message "JSON parse skipped: $directError; rawLength=$($RawJson.Length)"
        return $null
    }

    try {
        return $fixedJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-CodexAdapterLog -Message "JSON parse skipped after fallback: $($_.Exception.Message); firstError=$directError; rawLength=$($RawJson.Length)"
        return $null
    }
}

# Read all input from stdin
$inputJson = ""
$stdin = [Console]::In
while ($null -ne ($line = $stdin.ReadLine())) {
    $inputJson += $line
}

# If no input, exit
if ([string]::IsNullOrEmpty($inputJson)) {
    exit 0
}

# Parse JSON. Invalid payloads should never block Codex, but they should be visible in hook logs.
$payload = ConvertFrom-CodexHookJson -RawJson $inputJson
if ($null -eq $payload) {
    exit 0
}

$prompt = $payload.prompt
$cwd = $payload.cwd

if ([string]::IsNullOrEmpty($prompt)) {
    exit 0
}

# Call the original skill activation script
$scriptPath = Join-Path $PSScriptRoot "skill-activation-core.ps1"

try {
    & $scriptPath -PromptText $prompt -ProjectDir $cwd
} catch {
    Write-CodexAdapterLog -Message "Error: $_"
}

exit 0
