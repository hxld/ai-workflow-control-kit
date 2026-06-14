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
    function Convert-RgClassMatch {
        param(
            [Parameter(Mandatory=$true)]
            [string]$Line
        )
        if ($Line -notmatch '^(.+?\.java):(\d+):.*\b(?:interface|class)\s+([A-Za-z_][A-Za-z0-9_]*)') {
            return $null
        }
        $path = $matches[1] -replace '\\', '/'
        if ($path -match '/src/test/') {
            return $null
        }
        [PSCustomObject]@{
            Path = $path
            Line = $matches[2]
            Name = $matches[3]
        }
    }

    $output = @()
    $output += "# Surface Carrier Scan"
    $output += ""
    $output += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $output += "Project Root: $ProjectRoot"
    $output += ""
    $output += "## Facade Layer (example-api / example-api-open)"
    $output += ""

    # Find all Facade interfaces
    $facades = @(rg "public interface.*Facade" --type java -n 2>$null |
                ForEach-Object { Convert-RgClassMatch $_ } |
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
    $controllers = @(rg "public class.*Controller" --type java -n 2>$null |
                    ForEach-Object { Convert-RgClassMatch $_ } |
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
    $facadeImpls = @(rg "public class.*FacadeImpl" --type java -n 2>$null |
                   ForEach-Object { Convert-RgClassMatch $_ } |
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
