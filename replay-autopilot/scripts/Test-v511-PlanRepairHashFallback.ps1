param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        throw "FAIL: $Name $Details"
    }
}

function Assert-Contains {
    param([string]$Name, [string]$Text, [string]$Pattern)
    if ($Text -notmatch $Pattern) {
        throw "FAIL: $Name missing pattern: $Pattern"
    }
}

function Assert-NotContains {
    param([string]$Name, [string]$Text, [string]$Pattern)
    if ($Text -match $Pattern) {
        throw "FAIL: $Name unexpectedly matched pattern: $Pattern"
    }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runner = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        runner = $runner
    } | ConvertTo-Json -Depth 4
    exit 0
}

if (-not (Test-Path -LiteralPath $runner)) {
    throw "Missing runner: $runner"
}

$runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
Assert-Contains 'runner defines sha256 fallback helper' $runnerText 'function\s+Get-Sha256Hex'
Assert-Contains 'runner probes get-filehash availability' $runnerText 'Get-Command\s+Get-FileHash\s+-ErrorAction\s+SilentlyContinue'
Assert-Contains 'runner has dotnet sha256 fallback' $runnerText '\[System\.Security\.Cryptography\.SHA256\]::Create\(\)'
Assert-Contains 'plan repair guard records before hash through fallback' $runnerText 'before_hash\s*=\s*Get-Sha256Hex\s+-Path\s+\$artifactPath'
Assert-Contains 'plan repair guard records after hash through fallback' $runnerText '\$afterHash\s*=\s*Get-Sha256Hex\s+-Path\s+\$artifactPath'

$planRepairBlockMatch = [regex]::Match(
    $runnerText,
    '(?s)Plan missing \$\(\$missingPlanArtifacts\.Count\) artifacts:.*?\$unauthorizedRepairChanges = @\(\).*?if \(\$unauthorizedRepairChanges\.Count -gt 0\)'
)
Assert-True 'test can isolate plan artifact repair guard block' $planRepairBlockMatch.Success
Assert-NotContains 'plan repair guard does not directly call Get-FileHash' $planRepairBlockMatch.Value 'Get-FileHash\s+-LiteralPath'

[ordered]@{
    status = 'PASS'
    assertions = 7
} | ConvertTo-Json -Depth 4
