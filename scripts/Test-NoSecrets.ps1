$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = New-Object System.Collections.Generic.List[string]

$forbiddenNames = @(
    'auth.json',
    'settings.local.json',
    'history.jsonl',
    'session_index.jsonl'
)

$allowedEnvFiles = @(
    'agents\skills\log-investigator\.env'
)

Get-ChildItem -LiteralPath $root -Recurse -Force -File | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length).TrimStart('\')
    $normalizedRel = $rel -replace '/', '\'
    if ($normalizedRel -eq '.git' -or $normalizedRel.StartsWith('.git\')) {
        return
    }
    if ($_.Name -eq '.env' -and $allowedEnvFiles -notcontains $normalizedRel) {
        $failures.Add("forbidden file: $rel") | Out-Null
        return
    }
    if ($forbiddenNames -contains $_.Name) {
        $failures.Add("forbidden file: $rel") | Out-Null
        return
    }
    if ($_.Extension -in @('.sqlite', '.db', '.log')) {
        $failures.Add("forbidden extension: $rel") | Out-Null
        return
    }
    if ($_.Length -gt 5MB) {
        $failures.Add("large file >5MB: $rel") | Out-Null
        return
    }
    $text = ''
    try {
        $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 -ErrorAction Stop
    } catch {
        return
    }
    $secretPattern = "(?i)(ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|GITHUB_TOKEN|GH_TOKEN|GITHUB_PERSONAL_ACCESS_TOKEN)\s*[:=]\s*[`"']?(?!<SET_ON_NEW_MACHINE>|$)[A-Za-z0-9_\.\-]{16,}"
    if ($text -match $secretPattern) {
        $failures.Add("secret-like token: $rel") | Out-Null
    }
    $concreteUserPathPattern = '(?i)C:[\\/]+Users[\\/]+(?!<USER>|<USERPROFILE>|%USERPROFILE%|%USERNAME%|\$HOME|\$env:USERPROFILE)[A-Za-z0-9._-]+'
    if ($text -match $concreteUserPathPattern) {
        $failures.Add("concrete Windows user path: $rel") | Out-Null
    }
    if ($_.Name -in @('.env', '.env.example')) {
        $text -split "\r?\n" | ForEach-Object {
            $line = $_
            if ($line -match '^\s*#' -or $line -notmatch '=') { return }
            $parts = $line -split '=', 2
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            if ($key -match '(?i)(PASSWORD|TOKEN|SECRET|AUTH|CREDENTIAL|API_KEY|USERNAME)' -and
                $value -ne '' -and
                $value -ne '<SET_ON_NEW_MACHINE>') {
                $failures.Add("credential value must be placeholder: $rel") | Out-Null
            }
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Secret scan failed:'
    foreach ($f in $failures) { Write-Host " - $f" }
    exit 1
}

Write-Host 'PASS: no forbidden secrets or runtime state files found'
