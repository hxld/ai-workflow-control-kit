# Replay-ControlPlane.psm1 — Shared control-plane helper functions
#
# Modular extraction of the most-used utilities from Verify-PlanContract.ps1
# and other replay-autopilot scripts. New scripts should dot-source this module
# instead of redefining these functions.
#
# To use in a script:
#   $modulePath = Join-Path $PSScriptRoot 'modules\Replay-ControlPlane.psm1'
#   if (Test-Path $modulePath) { Import-Module $modulePath -Force }
#
# NOTE: This module is SAFE to import in scripts that also define local copies
# of the same functions — the ones in the module take precedence on import.

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

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-Json {
    param([string]$Path, [object]$Object, [int]$Depth = 6)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Object | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-FirstText {
    param([string]$Text, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ''
}

function Get-KeyValueField {
    param([string]$Text, [string]$Field)
    $escapedField = [regex]::Escape($Field)
    foreach ($line in ($Text -split "\r?\n")) {
        $lineMatch = [regex]::Match($line.Trim(), '^(?:\*{0,2}\s*)?(?:[-*]\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*(.+?)\s*$')
        if ($lineMatch.Success) {
            return $lineMatch.Groups[1].Value.Trim()
        }
    }
    $patterns = @(
        ('(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*([^\r\n]+?)\s*$'),
        ('(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*\r?\n\s*:\s*([^\r\n]+?)\s*$'),
        ('(?im)\|\s*\*{0,2}' + $escapedField + '\*{0,2}\s*\|\s*`?([^\r\n|]+?)`?\s*\|')
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ''
}

function Add-MissingFileIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Root,
        [string]$Name
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Name))) {
        $Issues.Add("missing_file:$Name") | Out-Null
    }
}

function Add-MissingTokenIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Text,
        [string]$Token,
        [string]$Issue
    )
    if ($Text.IndexOf($Token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        $Issues.Add($Issue) | Out-Null
    }
}

function Add-MissingAnyTokenIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Text,
        [string[]]$Tokens,
        [string]$Issue
    )
    foreach ($token in $Tokens) {
        if ($Text.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return
        }
    }
    $Issues.Add($Issue) | Out-Null
}

Export-ModuleMember -Function Resolve-AbsolutePath, Read-TextIfExists, Write-Text, Write-Json,
    Get-FirstText, Get-KeyValueField,
    Add-MissingFileIssue, Add-MissingTokenIssue, Add-MissingAnyTokenIssue
