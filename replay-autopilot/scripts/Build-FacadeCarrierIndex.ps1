# Valid Facade Carrier Pre-Index (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)
# Scans the project for Facade interfaces and outputs VALID_FACADE_CARRIERS.json

param(
    [Parameter(Mandatory = $true)]
    [string]$BaselineRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$BaselineCommit = '',
    [string]$Modules = @('example-api', 'example-api-open', 'example-core')
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

    # Search for Facade interfaces
    Write-Host "Scanning $module for Facade interfaces..." -ForegroundColor Cyan

    $rgPattern = '(?s)interface\s+(\w*Facade\w*)\s*(?:extends\s+\w+\s*)?\{'

    $rgArgs = @(
        '--type=java',
        '--no-heading',
        '--line-number',
        '-U', '5',
        $rgPattern,
        $srcPath
    )

    $rgOutput = rg @rgArgs 2>$null

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rgOutput)) {
        $lines = $rgOutput -split "`n"
        $currentFile = $null
        $currentLineNumber = 0
        $currentFacade = $null

        foreach ($line in $lines) {
            if ($line -match '^([^\d]+)[:-](\d+):(.*)$') {
                $currentFile = $matches[1]
                $currentLineNumber = [int]$matches[2]
                $content = $matches[3]

                if ($content -match 'interface\s+(\w*Facade\w*)') {
                    $currentFacade = $matches[1]
                }
            } elseif ($currentFacade -and $currentFile) {
                # Look for method signatures in next lines
                if ($line -match '^\s*([^\s].*)?(\w+)\s*\(([^)]*)\)(?:\s*throws\s+[^;]+)?;') {
                    $method = $matches[2]
                    $parameters = $matches[3]

                    $fullPath = if ($currentFile -match '^[A-Za-z]:') { $currentFile } else { Join-Path $baselineRootFull $currentFile }

                    $key = "$currentFacade.$method"
                    $carriers[$key] = [ordered]@{
                        facade_name = $currentFacade
                        method_name = $method
                        parameters = $parameters
                        file_path = $fullPath
                        line_number = $currentLineNumber
                        module = $module
                        layer = 'Facade'
                        type = 'interface'
                    }
                    $totalCount++
                }
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
