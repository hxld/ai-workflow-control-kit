<#
.SYNOPSIS
    Experiment 1: Build Baseline Carrier Index (v457)

.DESCRIPTION
    Pre-indexes baseline carriers by architectural layer to reduce Phase0 carrier selection failures.
    Scans baseline for potential carriers and outputs BASELINE_CARRIER_INDEX.json.

.PARAMETER BaselineRoot
    Path to the baseline repository root. Defaults to AI_WORKFLOW_PROJECT_ROOT.

.PARAMETER OutputPath
    Path to output JSON file (default: .\BASELINE_CARRIER_INDEX.json).

.PARAMETER BaselineCommit
    Optional Git commit hash for baseline verification.

.EXAMPLE
    .\Build-BaselineCarrierIndex.ps1 -BaselineRoot "<PROJECT_ROOT>" -OutputPath "BASELINE_CARRIER_INDEX.json"
#>

[CmdletBinding()]
param(
    [string]$BaselineRoot = "$env:AI_WORKFLOW_PROJECT_ROOT",
    [string]$OutputPath = ".\BASELINE_CARRIER_INDEX.json",
    [string]$BaselineCommit = ""
)

$ErrorActionPreference = 'Stop'

# Resolve absolute paths
if ([string]::IsNullOrWhiteSpace($BaselineRoot)) {
    throw "BaselineRoot is required. Pass -BaselineRoot or set AI_WORKFLOW_PROJECT_ROOT."
}
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

function Get-RelativePath {
    param([string]$Path)
    return ($Path -replace [regex]::Escape($BaselineRoot), '' -replace '^\\+', '' -replace '^/+', '')
}

function Get-ModuleNameForSourceRoot {
    param([string]$SourceRoot)
    $srcMain = Split-Path -Parent $SourceRoot
    $src = Split-Path -Parent $srcMain
    $modulePath = Split-Path -Parent $src
    if ($modulePath -eq $BaselineRoot) {
        return (Split-Path -Leaf $BaselineRoot)
    }
    return (Split-Path -Leaf $modulePath)
}

function Get-CarrierLayer {
    param([string]$File)
    if ($File -match "Facade") { return "Facade" }
    if ($File -match "Controller|Resource|Endpoint") { return "Controller" }
    if ($File -match "TaskProcessor|\.task\.|Task\.java") { return "Task" }
    if ($File -match "Service") { return "Service" }
    if ($File -match "Mapper|Repository|Dao") { return "Persistence" }
    return "Service"
}

function Get-JavaSourceRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $directRoot = Join-Path $BaselineRoot "src\main\java"
    if (Test-Path -LiteralPath $directRoot) {
        $roots.Add($directRoot) | Out-Null
    }
    Get-ChildItem -LiteralPath $BaselineRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $candidate = Join-Path $_.FullName "src\main\java"
        if (Test-Path -LiteralPath $candidate) {
            $roots.Add($candidate) | Out-Null
        }
    }
    return @($roots)
}

$sourceRoots = @(Get-JavaSourceRoots)
if ($sourceRoots.Count -eq 0) {
    Write-Warning "No Java source roots found under $BaselineRoot"
}

$carrierPattern = "@CatfishRemote|@Remote|@Controller|@RestController|@RequestMapping|class.*Facade|class.*Controller|class.*Service|class.*TaskProcessor|class.*Repository|class.*Mapper|class.*Dao"
foreach ($sourceRoot in $sourceRoots) {
    $moduleName = Get-ModuleNameForSourceRoot -SourceRoot $sourceRoot
    Write-Host "Scanning $moduleName..."
    $rgResult = rg $carrierPattern --type java --files-with-matching $sourceRoot 2>&1
    foreach ($file in $rgResult) {
        if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file)) { continue }
        $relativeFile = Get-RelativePath -Path $file
        $className = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $layer = Get-CarrierLayer -File $file

        $carriers[$className] = @{
            layer = $layer
            module = $moduleName
            file = $relativeFile
            baseline_commit = $BaselineCommit
            type = $layer
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
$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}
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
