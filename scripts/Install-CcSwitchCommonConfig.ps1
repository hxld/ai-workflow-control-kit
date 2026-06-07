param(
    [string]$CcSwitchHome = (Join-Path $HOME '.cc-switch'),
    [string]$ClaimProjectRoot = 'D:\opt\claim',
    [switch]$BackupExisting,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-Root {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Write-Step {
    param([string]$Message)
    Write-Host "[cc-switch-config] $Message"
}

function Convert-ToSlashPath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

function Expand-Template {
    param([string]$Text)
    $map = @{
        '<USERPROFILE>' = $HOME
        '<USERPROFILE_SLASH>' = Convert-ToSlashPath $HOME
        '<CODEX_HOME>' = (Join-Path $HOME '.codex')
        '<CODEX_HOME_SLASH>' = Convert-ToSlashPath (Join-Path $HOME '.codex')
        '<CLAIM_PROJECT_ROOT>' = $ClaimProjectRoot
        '<CLAIM_PROJECT_ROOT_SLASH>' = Convert-ToSlashPath $ClaimProjectRoot
    }
    $expanded = $Text
    foreach ($entry in $map.GetEnumerator()) {
        $expanded = $expanded.Replace($entry.Key, $entry.Value)
    }
    return $expanded
}

function Read-RenderedTemplate {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Template not found: $Path"
    }
    return Expand-Template -Text (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Text
    )
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

$repo = Resolve-Root
$dbPath = Join-Path $CcSwitchHome 'cc-switch.db'
$codexTemplate = Join-Path $repo 'cc-switch\common_config_codex.toml.template'
$claudeTemplate = Join-Path $repo 'cc-switch\common_config_claude.json.template'

if (-not (Test-Path -LiteralPath $dbPath)) {
    Write-Step "Skip; cc-switch database not found: $dbPath"
    return
}

$codexConfig = Read-RenderedTemplate -Path $codexTemplate
$claudeConfig = Read-RenderedTemplate -Path $claudeTemplate

if ($DryRun) {
    Write-Step "DryRun: would update common_config_codex and common_config_claude in $dbPath"
    Write-Step 'DryRun: would enable commonConfigEnabled for current codex and claude providers.'
    return
}

$python = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python) {
    throw 'Python is required to update cc-switch sqlite config. Install Python or update cc-switch common_config_* manually from cc-switch/*.template.'
}

if ($BackupExisting) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$dbPath.backup-$stamp"
    Write-Step "Backup $dbPath -> $backup"
    Copy-Item -LiteralPath $dbPath -Destination $backup -Force
} else {
    Write-Step 'No -BackupExisting supplied; updating cc-switch.db without creating a backup.'
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-switch-common-config-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$codexFile = Join-Path $tmpDir 'common_config_codex.toml'
$claudeFile = Join-Path $tmpDir 'common_config_claude.json'
Write-Utf8NoBom -Path $codexFile -Text $codexConfig
Write-Utf8NoBom -Path $claudeFile -Text $claudeConfig

$env:CC_SWITCH_DB = $dbPath
$env:CC_SWITCH_COMMON_CODEX = $codexFile
$env:CC_SWITCH_COMMON_CLAUDE = $claudeFile

try {
    @'
import json
import os
import sqlite3

db_path = os.environ["CC_SWITCH_DB"]
with open(os.environ["CC_SWITCH_COMMON_CODEX"], "r", encoding="utf-8") as fh:
    codex_config = fh.read()
with open(os.environ["CC_SWITCH_COMMON_CLAUDE"], "r", encoding="utf-8") as fh:
    claude_config = fh.read()

try:
    import tomllib
    tomllib.loads(codex_config)
except ModuleNotFoundError:
    pass

json.loads(claude_config)

con = sqlite3.connect(db_path)
try:
    con.execute(
        "insert or replace into settings(key, value) values(?, ?)",
        ("common_config_codex", codex_config),
    )
    con.execute(
        "insert or replace into settings(key, value) values(?, ?)",
        ("common_config_claude", claude_config),
    )

    for app_type in ("codex", "claude"):
        rows = con.execute(
            "select id, meta from providers where app_type = ? and is_current = 1",
            (app_type,),
        ).fetchall()
        for provider_id, meta_text in rows:
            try:
                meta = json.loads(meta_text or "{}")
            except json.JSONDecodeError:
                meta = {}
            meta["commonConfigEnabled"] = True
            con.execute(
                "update providers set meta = ? where app_type = ? and id = ?",
                (json.dumps(meta, ensure_ascii=False, separators=(",", ":")), app_type, provider_id),
            )

    con.commit()
finally:
    con.close()
'@ | python -
    Write-Step 'Updated cc-switch common_config_codex/common_config_claude and enabled current providers.'
} finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:CC_SWITCH_DB,Env:CC_SWITCH_COMMON_CODEX,Env:CC_SWITCH_COMMON_CLAUDE -ErrorAction SilentlyContinue
}
