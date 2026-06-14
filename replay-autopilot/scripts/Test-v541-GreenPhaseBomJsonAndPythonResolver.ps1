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
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$verifier = Join-Path $scriptRoot 'verify_green_phase.py'
$runSlice = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v541-green-bom-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    $implFile = Join-Path $worktree 'claim-core\src\main\java\Example.java'
    Write-TextFile -Path $implFile -Value @"
class Example {
    void rebuild() {
        req.setPolicyNum(buildContext.getPolicyNum());
    }
}
"@

    $implementedJson = Join-Path $tempRoot 'implemented.json'
    $familiesJson = Join-Path $tempRoot 'families.json'
    ConvertTo-Json -InputObject @('claim-core/src/main/java/Example.java') -Depth 6 |
        Set-Content -LiteralPath $implementedJson -Encoding UTF8
    '"core_entry"' | Set-Content -LiteralPath $familiesJson -Encoding UTF8

    $output = & python $verifier verify $worktree $implementedJson $familiesJson 2>&1
    $exitCode = $LASTEXITCODE
    Assert-True 'verify_green_phase accepts PowerShell UTF8 BOM JSON' ($exitCode -eq 0) (($output | Out-String).Trim())
    $result = ($output | Out-String) | ConvertFrom-Json
    Assert-True 'singleton touched family JSON is normalized' ([bool]$result.stateful_family_detected) ($result | ConvertTo-Json -Depth 10)
    Assert-True 'real implementation is not blocked' ([bool]$result.can_proceed -and -not [bool]$result.block_green) ($result | ConvertTo-Json -Depth 10)

    $runSliceText = Get-Content -LiteralPath $runSlice -Raw -Encoding UTF8
    $greenStart = $runSliceText.IndexOf('function Invoke-GreenPhaseNoMockGate')
    $greenEnd = $runSliceText.IndexOf('function Get-RequiredFamilyCountFromContract')
    Assert-True 'green gate function block found' ($greenStart -ge 0 -and $greenEnd -gt $greenStart)
    $greenBlock = $runSliceText.Substring($greenStart, $greenEnd - $greenStart)
    Assert-True 'green gate imports shared python resolver' ($greenBlock.Contains('Resolve-PythonLauncher.ps1') -and $greenBlock.Contains('Resolve-PythonLauncher'))
    Assert-True 'green gate no longer hardcodes python executable' (-not $greenBlock.Contains('& python $gateScript verify'))
    Assert-True 'green gate preserves singleton arrays in JSON evidence' ($greenBlock.Contains('ConvertTo-Json -InputObject @($touchedFamilies)'))
    Assert-True 'green gate keeps structured parse failure evidence' ($greenBlock.Contains('green_phase_gate_unparseable') -and $greenBlock.Contains('GREEN_PHASE_VERIFY_{0:D2}.json'))

    $verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
    Assert-True 'python verifier reads utf-8-sig JSON' ($verifierText.Contains("encoding='utf-8-sig'"))
    Assert-True 'python verifier normalizes scalar JSON values' ($verifierText.Contains('normalize_string_list'))

    Write-Host 'v541 green phase BOM JSON and resolver regression passed.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
