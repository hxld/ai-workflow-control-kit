param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = $PSScriptRoot
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($verifier, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True ($parseErrors.Count -eq 0) ("Verify-PlanContract.ps1 must parse. Errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
Write-Host 'PASS: Verify-PlanContract.ps1 parses'

$verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
Assert-True ($verifierText -match "v399/v400: Domain-to-directory mapping") 'Domain mapping block should be v400 guarded'
Assert-True ($verifierText -match "\$domainKey -match 'ai\|claim\|auto'") 'Domain mapping should use $domainKey, not an empty expression'
Assert-True ($verifierText -match '\[regex\]::Escape') 'Domain mapping should escape regex patterns'
Assert-True ($verifierText -notmatch "(?m)^\s*'[^'\r\n]*\s+=\s*'[^']+'\s*$") 'Domain mapping should not contain malformed hash literal entries'
Write-Host 'PASS: Domain mapping block is syntactically guarded'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v400-verify-smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $tempRoot -Stage Phase0 | Out-Null
    $exitCode = $LASTEXITCODE
    Assert-True ($exitCode -ne 0) 'Empty replay root should fail verification'
    $verifyPath = Join-Path $tempRoot 'PHASE0_CONTRACT_VERIFY.json'
    Assert-True (Test-Path -LiteralPath $verifyPath) 'Verifier must write PHASE0_CONTRACT_VERIFY.json even on failure'
    $verify = Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$verify.verification_status -eq 'FAIL') 'Smoke verify status should be FAIL'
    Assert-True (@($verify.issues).Count -gt 0) 'Smoke verify should include concrete issues'
    Write-Host 'PASS: Failure path writes concrete verify JSON'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: v400 Verify-PlanContract parse smoke tests passed'
[ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4
