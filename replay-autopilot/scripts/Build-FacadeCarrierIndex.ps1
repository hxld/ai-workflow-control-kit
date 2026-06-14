# Valid Facade Carrier Pre-Index (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)
# Scans the project for Facade interfaces and outputs VALID_FACADE_CARRIERS.json

param(
    [Parameter(Mandatory = $true)]
    [string]$BaselineRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$BaselineCommit = '',
    [string[]]$Modules = @('claim-api', 'claim-api-open', 'claim-core')
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$baselineRootFull = Resolve-AbsolutePath $BaselineRoot
$outputPathFull = Resolve-AbsolutePath $OutputPath

if (-not (Test-Path -LiteralPath $baselineRootFull)) {
    throw "Baseline root not found: $baselineRootFull"
}

# Get baseline commit if not provided
if ([string]::IsNullOrWhiteSpace($BaselineCommit)) {
    pushd $baselineRootFull
    try {
        $BaselineCommit = git rev-parse HEAD 2>$null
    } finally {
        popd
    }
}

$carriers = @{}
$totalCount = 0

foreach ($module in $Modules) {
    $modulePath = Join-Path $baselineRootFull $module
    if (-not (Test-Path -LiteralPath $modulePath)) {
        Write-Host "Module not found: $modulePath" -ForegroundColor Yellow
        continue
    }

    $srcPath = Join-Path $modulePath 'src\main\java'
    if (-not (Test-Path -LiteralPath $srcPath)) {
        Write-Host "Source path not found: $srcPath" -ForegroundColor Yellow
        continue
    }

    Write-Host "Scanning $module for Facade interfaces..." -ForegroundColor Cyan

    $javaFiles = @(Get-ChildItem -LiteralPath $srcPath -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue)
    foreach ($file in $javaFiles) {
        $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8
        $currentFacade = ''
        $facadeLineNumber = 0

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = [string]$lines[$i]
            if ([string]::IsNullOrWhiteSpace($currentFacade) -and $line -match '\binterface\s+(\w*Facade\w*)\b') {
                $currentFacade = $matches[1]
                $facadeLineNumber = $i + 1
                continue
            }

            if ([string]::IsNullOrWhiteSpace($currentFacade)) { continue }
            if ($line -match '^\s*(?:public\s+)?(?:<[^>]+>\s*)?[\w<>\[\], ?\.]+\s+(\w+)\s*\(([^)]*)\)\s*(?:throws\s+[^;]+)?;') {
                $method = $matches[1]
                $parameters = $matches[2]
                $key = "$currentFacade.$method"
                if ($carriers.Contains($key)) {
                    $key = "$key#$($i + 1)"
                }
                $carriers[$key] = [ordered]@{
                    facade_name = $currentFacade
                    method_name = $method
                    parameters = $parameters
                    file_path = $file.FullName
                    line_number = $i + 1
                    facade_line_number = $facadeLineNumber
                    module = $module
                    layer = 'Facade'
                    type = 'interface'
                }
                $totalCount++
            }
        }
    }
}

# Build output index
$index = [ordered]@{
    schema_version = 'v465-experiment2'
    baseline_commit = $BaselineCommit
    generated_at = (Get-Date -Format 'o')
    baseline_root = $baselineRootFull
    modules_scanned = @($Modules)
    total_carriers = $totalCount
    carriers = $carriers
}

# Write output
$index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPathFull -Encoding UTF8

Write-Host "Built facade carrier index: $outputPathFull" -ForegroundColor Green
Write-Host "Total carriers: $totalCount" -ForegroundColor Green

exit 0
