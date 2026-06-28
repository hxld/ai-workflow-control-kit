param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Import-RunReplayLoopFunctions {
    $runReplayLoop = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runReplayLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-ReplayLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$manualOracleWaitPattern = '(?is)((?<!without\s)Oracle\s+Post-Hoc\s*(->|required|pending|(before|after)\s+implementation)|(?<!cannot\sverify\.)\s*Oracle\s+commit\s+(pending|required|needed|before\s+(implementation|planning))|next (step|action):\s*(await|wait|pending).*\bOracle\b|awaiting\s+Oracle\s+(verification|access|branch)\s+(to\s+(provide|verify)|before\s+(implementation|planning)|required|pending)|waiting\s+for\s+Oracle\s+(to\s+(provide|verify)|verification\s+(required|needed))|AWAIT_ORACLE_VERIFICATION_OR_WAIVER|Provide\s+oracle\s+branch\s+access|Coverage\s+Cap\s+Waiver|waive\s+coverage\s+caps|(?<!no\s)manual\s+oracle\s+verification\s+(required|needed|pending)|(?<!constraint\s)awaiting\s+oracle\s+verification|wait(?:ing)?\s+for\s+oracle\s+verification)'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v615-oracle-wait-repair-" + [guid]::NewGuid().ToString('N'))

try {
    Import-RunReplayLoopFunctions
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $before = @'
# Phase 0 Artifact

- Oracle Post-Hoc required before implementation
- Oracle commit pending
- next step: await Oracle branch access
- awaiting Oracle access required
- waiting for Oracle to provide exact signatures
- AWAIT_ORACLE_VERIFICATION_OR_WAIVER
- Provide oracle branch access
- Coverage Cap Waiver: Not required
- waive coverage caps
- manual oracle verification needed
- awaiting oracle verification
- waiting for oracle verification
- verify after oracle
- not verified against oracle
'@

    foreach ($artifactName in @('PHASE0_RESULT.md', 'EXPLORATION_REPORT.md', 'ROUND_CONTRACT.md', 'IMPLEMENTATION_CONTRACT.md')) {
        Set-Content -LiteralPath (Join-Path $tempRoot $artifactName) -Value $before -Encoding UTF8
    }

    $combinedBefore = (Get-ChildItem -LiteralPath $tempRoot -File | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    }) -join "`n"
    Assert-True ($combinedBefore -match $manualOracleWaitPattern) 'fixture must contain verifier oracle-wait patterns before repair'

    Repair-Phase0ManualOracleWaitText -ReplayRoot $tempRoot

    $combinedAfter = (Get-ChildItem -LiteralPath $tempRoot -File | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    }) -join "`n"
    Assert-True (-not ($combinedAfter -match $manualOracleWaitPattern)) 'repair must remove verifier oracle-wait patterns from all Phase0 artifacts'

    $runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    foreach ($token in @(
        'Coverage\s+Cap\s+Waiver',
        'Oracle\s+commit\s+(pending|required|needed)',
        'Oracle\s+Post-Hoc\s*(->|required|pending|(before|after)\s+implementation)',
        'AWAIT_ORACLE_VERIFICATION_OR_WAIVER',
        'Provide\s+oracle\s+branch\s+access',
        'waive\s+coverage\s+caps'
    )) {
        Assert-True ($runnerText.Contains($token)) "runner repair must include pattern token $token"
    }

    Write-Host 'Test-v615-Phase0ManualOracleWaitRepairCoverage PASS'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
