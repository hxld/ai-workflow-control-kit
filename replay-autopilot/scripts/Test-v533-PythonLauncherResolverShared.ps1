param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "ASSERT FAILED: $Name" }
        throw "ASSERT FAILED: $Name - $Details"
    }
    Write-Host "PASS: $Name"
}

function Write-TextFile {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$resolver = Join-Path $PSScriptRoot 'Resolve-PythonLauncher.ps1'
$contract = Join-Path $PSScriptRoot 'Invoke-ContractVerification.ps1'
$incremental = Join-Path $PSScriptRoot 'Invoke-IncrementalVerification.ps1'
$todo = Join-Path $PSScriptRoot 'Invoke-TodoDetector.ps1'
$carrier = Join-Path $PSScriptRoot 'Invoke-CarrierSearch.ps1'
$reconcile = Join-Path $PSScriptRoot 'Invoke-Phase0ContractReconciliation.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v533-" + [guid]::NewGuid().ToString('N'))

try {
    . $resolver
    $python = Resolve-PythonLauncher
    Assert-True 'shared resolver finds executable Python 3' (-not [string]::IsNullOrWhiteSpace([string]$python.Command) -and [string]$python.Version -match '^Python\s+3\.') ($python | ConvertTo-Json -Depth 6)

    foreach ($file in @($contract, $incremental, $todo, $carrier, $reconcile)) {
        $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        Assert-True "wrapper imports shared resolver: $(Split-Path -Leaf $file)" ($text.Contains('Resolve-PythonLauncher.ps1') -and $text.Contains('Resolve-PythonLauncher'))
    }

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-TextFile (Join-Path $tempRoot 'TEST_CHARTER.md') '# Test Charter'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $contract -WorkDir $tempRoot | Out-Null
    Assert-True 'contract wrapper runs without python3 alias failure' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $incremental -WorkDir $tempRoot -Phase RED | Out-Null
    Assert-True 'incremental wrapper runs with shared resolver' ($LASTEXITCODE -ne 9009)

    Write-Host 'v533 shared Python launcher resolver regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
