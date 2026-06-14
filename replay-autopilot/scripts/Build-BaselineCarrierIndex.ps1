<#
.SYNOPSIS
    Experiment 1: Build Baseline Carrier Index (v457)

.DESCRIPTION
    Pre-indexes baseline carriers by architectural layer to reduce Phase0 carrier selection failures.
    Scans baseline for potential carriers and outputs BASELINE_CARRIER_INDEX.json.

.PARAMETER BaselineRoot
    Path to the baseline repository root (default: <PROJECT_ROOT>).

.PARAMETER OutputPath
    Path to output JSON file (default: .\BASELINE_CARRIER_INDEX.json).

.PARAMETER BaselineCommit
    Git commit hash for baseline verification (default: <your baseline commit>).

.EXAMPLE
    .\Build-BaselineCarrierIndex.ps1 -BaselineRoot "$env:AI_WORKFLOW_PROJECT_ROOT" -OutputPath "BASELINE_CARRIER_INDEX.json"
#>

[CmdletBinding()]
param(
    [string]$BaselineRoot = "$env:AI_WORKFLOW_PROJECT_ROOT",
    [string]$OutputPath = ".\BASELINE_CARRIER_INDEX.json",
    [string]$BaselineCommit = ""
)

$ErrorActionPreference = 'Stop'

# Resolve absolute paths
$BaselineRoot = (Resolve-Path $BaselineRoot -ErrorAction SilentlyContinue).Path
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

Write-Host "Building Baseline Carrier Index..."
Write-Host "Baseline Root: $BaselineRoot"
Write-Host "Output Path: $OutputPath"
Write-Host "Baseline Commit: $BaselineCommit"

$carriers = @{}
$rgWrapper = Join-Path $PSScriptRoot '..\tools\rg-wrapper.ps1'

if (-not (Test-Path -LiteralPath $rgWrapper)) {
    Write-Warning "rg-wrapper.ps1 not found, using direct rg commands"
}

function Test-RgAvailable {
    try {
        $null = Get-Command rg -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

$rgAvailable = Test-RgAvailable

if (-not $rgAvailable) {
    Write-Error "ripgrep (rg) is not found. Please install it first."
    exit 1
}

# Scan example-core for Task processors and @Remote/@CatfishRemote annotations
Write-Host "Scanning example-core..."
$corePath = Join-Path $BaselineRoot "example-core\src\main\java"

if (Test-Path -LiteralPath $corePath) {
    $rgResult = rg "@CatfishRemote|@Remote" --type java --files-with-matching $corePath 2>&1
    foreach ($file in $rgResult) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $relativeFile = $file -replace [regex]::Escape($BaselineRoot), '' -replace '^\\+', '' -replace '^/+', ''
        $className = [System.IO.Path]::GetFileNameWithoutExtension($file)

        $layer = if ($file -match "(\\|/)example-api(\\|/)|Facade") { "Facade" }
                  elseif ($file -match "(\\|/)example-web(\\|/)|Controller") { "Controller" }
                  elseif ($file -match "TaskProcessor|\.task\.|Task\.java") { "Task" }
                  elseif ($file -match "Service") { "Service" }
                  else { "Service" }

        $carriers[$className] = @{
            layer = $layer
            module = "example-core"
            file = $relativeFile
            baseline_commit = $BaselineCommit
            type = "Task"
        }
    }
}

# Scan example-api for Facade implementations
Write-Host "Scanning example-api..."
$apiPath = Join-Path $BaselineRoot "example-api\src\main\java"

if (Test-Path -LiteralPath $apiPath) {
    $rgResult = rg "class.*Facade|class.*Controller" --type java --files-with-matching $apiPath 2>&1
    foreach ($file in $rgResult) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $relativeFile = $file -replace [regex]::Escape($BaselineRoot), '' -replace '^\\+', '' -replace '^/+', ''
        $className = [System.IO.Path]::GetFileNameWithoutExtension($file)

        $layer = if ($file -match "Facade") { "Facade" }
                  elseif ($file -match "Controller") { "Controller" }
                  else { "Service" }

        $carriers[$className] = @{
            layer = $layer
            module = "example-api"
            file = $relativeFile
            baseline_commit = $BaselineCommit
            type = "Facade"
        }
    }
}

# Scan example-web for Controller implementations
Write-Host "Scanning example-web..."
$webPath = Join-Path $BaselineRoot "example-web\src\main\java"

if (Test-Path -LiteralPath $webPath) {
    $rgResult = rg "@Controller|@RestController|@RequestMapping" --type java --files-with-matching $webPath 2>&1
    foreach ($file in $rgResult) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $relativeFile = $file -replace [regex]::Escape($BaselineRoot), '' -replace '^\\+', '' -replace '^/+', ''
        $className = [System.IO.Path]::GetFileNameWithoutExtension($file)

        $carriers[$className] = @{
            layer = "Controller"
            module = "example-web"
            file = $relativeFile
            baseline_commit = $BaselineCommit
            type = "Controller"
        }
    }
}

# Output JSON
$output = @{
    schema_version = "v457"
    baseline_commit = $BaselineCommit
    generated_at = (Get-Date -Format "o")
    total_carriers = $carriers.Count
    carriers = $carriers
}

$outputJson = $output | ConvertTo-Json -Depth 4
$outputJson | Out-File -LiteralPath $OutputPath -Encoding UTF8

Write-Host "`nIndex complete!"
Write-Host "- Total carriers indexed: $($carriers.Count)"
Write-Host "- Output: $OutputPath"

# Summary by layer
$layerSummary = $carriers.Values | Group-Object -Property layer | Select-Object Name, Count
Write-Host "`nCarriers by layer:"
foreach ($layer in $layerSummary) {
    Write-Host "  - $($layer.Name): $($layer.Count)"
}

return $output
