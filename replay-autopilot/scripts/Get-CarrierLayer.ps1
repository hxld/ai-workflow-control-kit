<#
.SYNOPSIS
    Experiment 2: Get Carrier Layer (v457)

.DESCRIPTION
    Pre-validates carrier architectural layer before slice execution.
    Returns the layer (Facade/Controller/Service/Task/Unknown) and file path.

.PARAMETER Carrier
    The carrier class name to validate.

.PARAMETER BaselineRoot
    Path to the baseline repository root (default: <PROJECT_ROOT>).

.PARAMETER Worktree
    Path to the worktree (optional, overrides BaselineRoot).

.EXAMPLE
    .\Get-CarrierLayer.ps1 -Carrier "ExampleApplyClaimApiTaskProcessor" -BaselineRoot "$env:AI_WORKFLOW_PROJECT_ROOT"

.OUTPUTS
    System.Collections.Hashtable with layer, file, and reason fields.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Carrier,

    [string]$BaselineRoot = "$env:AI_WORKFLOW_PROJECT_ROOT",

    [string]$Worktree
)

$ErrorActionPreference = 'Stop'

$Carrier = $Carrier.Trim().Trim('`', '*', ',', ';', ':')

# Resolve worktree or baseline root
$SearchRoot = if ($Worktree) {
    (Resolve-Path $Worktree -ErrorAction SilentlyContinue).Path
} else {
    (Resolve-Path $BaselineRoot -ErrorAction SilentlyContinue).Path
}

if (-not $SearchRoot) {
    return @{
        layer = "Unknown"
        file = $null
        reason = "Search root not found: $BaselineRoot or $Worktree"
    }
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
    return @{
        layer = "Unknown"
        file = $null
        reason = "ripgrep (rg) is not available"
    }
}

# Search for carrier class definition
$javaPath = Join-Path $SearchRoot "src\main\java"
$definition = rg "class\s+$Carrier([\s<{]|$)" --type java --files-with-matching $SearchRoot 2>&1

if ([string]::IsNullOrWhiteSpace($definition) -or $definition -match "error|no matches") {
    return @{
        layer = "Unknown"
        file = $null
        reason = "Carrier '$Carrier' not found in baseline"
    }
}

# Parse the first matching file
$matchingFile = ($definition -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1).Trim()

if ([string]::IsNullOrWhiteSpace($matchingFile)) {
    return @{
        layer = "Unknown"
        file = $null
        reason = "No valid file found for carrier '$Carrier'"
    }
}

# Determine layer from file path
$layer = if ($matchingFile -match "(\\|/)example-api(\\|/)|Facade\b") {
    "Facade"
} elseif ($matchingFile -match "(\\|/)example-web(\\|/)|Controller\b") {
    "Controller"
} elseif ($matchingFile -match "(\\|/)provider(\\|/)|Mapper\b|Dao\b") {
    "Provider"
} elseif ($matchingFile -match "TaskProcessor|\.task\.|Task\.java") {
    "Task"
} elseif ($matchingFile -match "Service") {
    "Service"
} else {
    "Unknown"
}

$relativeFile = $matchingFile -replace [regex]::Escape($SearchRoot), '' -replace '^\\+', '' -replace '^/+', ''

return @{
    layer = $layer
    file = $relativeFile
    carrier = $Carrier
    baseline_commit = "e19c16c"
    reason = if ($layer -eq "Unknown") { "Cannot determine layer from file path" } else { $null }
}
