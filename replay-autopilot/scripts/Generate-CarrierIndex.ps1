<#
.SYNOPSIS
Generates a comprehensive index of all executable carriers (Facade/Controller).

.DESCRIPTION
Scans the codebase for all Facade and Controller classes, writes them to
SURFACE_CARRIER_SCAN.md for use by planning prompts.

.PARAMETER ProjectRoot
Root directory of the project (e.g., <PROJECT_ROOT>)

.PARAMETER OutputPath
Output file path (default: {ProjectRoot}\SURFACE_CARRIER_SCAN.md)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $OutputPath = Join-Path $ProjectRoot "SURFACE_CARRIER_SCAN.md"
}

Push-Location $ProjectRoot

try {
    $rootFull = [System.IO.Path]::GetFullPath($ProjectRoot) -replace '[\\/]+$', ''

    function Convert-ToRepoPath {
        param(
            [Parameter(Mandatory=$true)]
            [string]$Path
        )

        $full = [System.IO.Path]::GetFullPath($Path)
        if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $full = $full.Substring($rootFull.Length) -replace '^[\\/]+', ''
        }
        return ($full -replace '\\', '/')
    }

    function Convert-JavaClassMatch {
        param(
            [Parameter(Mandatory=$true)]
            [string]$Path,
            [Parameter(Mandatory=$true)]
            [int]$LineNumber,
            [Parameter(Mandatory=$true)]
            [string]$Line
        )
        if ($Line -notmatch '\b(?:interface|class)\s+([A-Za-z_][A-Za-z0-9_]*)') {
            return $null
        }
        $path = Convert-ToRepoPath $Path
        if ($path -match '/src/test/') {
            return $null
        }
        [PSCustomObject]@{
            Path = $path
            Line = $LineNumber
            Name = $matches[1]
        }
    }

    function Find-JavaClassMatches {
        param(
            [Parameter(Mandatory=$true)]
            [string]$Pattern
        )

        $matchesOut = @()
        $javaFiles = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue)
        foreach ($file in $javaFiles) {
            $lineNumber = 0
            foreach ($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
                $lineNumber++
                if ($line -notmatch $Pattern) { continue }
                $match = Convert-JavaClassMatch -Path $file.FullName -LineNumber $lineNumber -Line $line
                if ($match) {
                    $matchesOut += $match
                }
            }
        }
        return @($matchesOut)
    }

    $output = @()
    $output += "# Surface Carrier Scan"
    $output += ""
    $output += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $output += "Project Root: $ProjectRoot"
    $output += ""
    $output += "## Facade Layer (example-api / example-api-open)"
    $output += ""

    # Find all Facade interfaces. Native enumeration keeps empty/non-Java repos from
    # turning ripgrep's "no files searched" diagnostic into a hard replay failure.
    $facades = @(Find-JavaClassMatches "public interface.*Facade" |
                Where-Object { $_ -and $_.Path -match '(^|/)(example-api|example-api-open)(/|$)' })

    foreach ($facade in ($facades | Sort-Object Name)) {
        if ($facade) {
            $output += "- $($facade.Name) - $($facade.Path)"
        }
    }

    $output += ""
    $output += "## Controller Layer (example-web)"
    $output += ""

    # Find all Controllers
    $controllers = @(Find-JavaClassMatches "public class.*Controller" |
                    Where-Object { $_ -and $_.Path -match '/src/main/java/' -and $_.Path -match 'Controller\.java$' })

    foreach ($controller in ($controllers | Sort-Object Name)) {
        if ($controller) {
            $output += "- $($controller.Name) - $($controller.Path)"
        }
    }

    $output += ""
    $output += "## Facade Implementation Layer (example-core/.../facade/)"
    $output += ""

    # Find all FacadeImpl classes
    $facadeImpls = @(Find-JavaClassMatches "public class.*FacadeImpl" |
                   Where-Object { $_ -and $_.Path -match '/src/main/java/' -and $_.Path -match '/facade/' -and $_.Path -match 'FacadeImpl\.java$' })

    foreach ($impl in ($facadeImpls | Sort-Object Name)) {
        if ($impl) {
            $output += "- $($impl.Name) - $($impl.Path)"
        }
    }

    $output += ""
    $output += "---"
    $output += ""
    $output += "## Summary"
    $output += ""
    $output += "- Total Facades: $($facades.Count)"
    $output += "- Total Controllers: $($controllers.Count)"
    $output += "- Total Facade Implementations: $($facadeImpls.Count)"
    $output += "- Total Executable Carriers: $($facades.Count + $controllers.Count + $facadeImpls.Count)"

    $output | Out-File -FilePath $OutputPath -Encoding UTF8

    Write-Host "Carrier index written to: $OutputPath" -ForegroundColor Green
    Write-Host "Facades: $($facades.Count), Controllers: $($controllers.Count), FacadeImpls: $($facadeImpls.Count)" -ForegroundColor Cyan

} finally {
    Pop-Location
}
