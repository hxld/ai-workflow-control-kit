param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$recomputeScript = Join-Path $scriptRoot 'recompute_round_coverage.py'
$enforcerScript = Join-Path $scriptRoot 'Enforce-RoundCoverageCap.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v693-round-coverage-recompute-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'ROUND_RESULT.md') @'
# ROUND_RESULT

## Coverage

- blind_self_assessed_coverage: 25
- verification_capped_coverage: 25
- final_status: PARTIAL
'@
    Write-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json') ([ordered]@{
        coverage_cap_from_ledger = 25
        final_pass_allowed = $false
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 3
        closed_requirement_families = @('core_entry')
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        slice_index = 2
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 3
        closed_requirement_families = @('stateful_side_effect')
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_03.json') ([ordered]@{
        slice_index = 3
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 3
        closed_requirement_families = @('generated_artifact_template_upload')
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_04.json') ([ordered]@{
        slice_index = 4
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 3
        closed_requirement_families = @('deploy_export_page')
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
    })

    $initialOutput = & python $recomputeScript --root $replayRoot --require-closed-family --fail-on-positive-without-synthesis 2>&1
    Assert-True 'recompute fails when reported coverage exceeds verifier-adjusted coverage' ($LASTEXITCODE -ne 0) $initialOutput
    $initialJson = $initialOutput | ConvertFrom-Json
    Assert-True 'recompute preserves verifier-adjusted sum despite non-authorizing synthesis' ([int]$initialJson.recomputed_adjusted_coverage -eq 12) ($initialJson | ConvertTo-Json -Depth 12)
    Assert-True 'recompute reports verifier capped coverage' ([int]$initialJson.recomputed_verification_capped_coverage -eq 12) ($initialJson | ConvertTo-Json -Depth 12)
    Assert-True 'recompute flags only reported overstatement' (@($initialJson.issues) -contains 'reported_coverage_exceeds_verifier_adjusted') ($initialJson | ConvertTo-Json -Depth 12)
    Assert-True 'recompute does not emit legacy positive coverage blocker' (-not (@($initialJson.issues) -contains 'positive_coverage_without_synthesis_authorization')) ($initialJson | ConvertTo-Json -Depth 12)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $enforcerScript `
        -RoundResultPath (Join-Path $replayRoot 'ROUND_RESULT.md') `
        -RouterCapPath (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json') `
        -ReplayRoot $replayRoot
    Assert-True 'enforcer exits zero' ($LASTEXITCODE -eq 0)
    $roundText = Get-Content -LiteralPath (Join-Path $replayRoot 'ROUND_RESULT.md') -Raw -Encoding UTF8
    Assert-True 'enforcer caps round result to verifier-adjusted coverage' ($roundText -match '(?m)^\s*-\s*verification_capped_coverage:\s*12\s*$') $roundText
    Assert-True 'enforcer records verifier adjusted coverage in enforcement block' ($roundText -match '(?m)^\s*-\s*verifier_adjusted_coverage:\s*12\s*$') $roundText

    $afterOutput = & python $recomputeScript --root $replayRoot --require-closed-family --fail-on-positive-without-synthesis 2>&1
    Assert-True 'recompute passes after enforcer aligns reported coverage with verifier' ($LASTEXITCODE -eq 0) $afterOutput
    $afterJson = $afterOutput | ConvertFrom-Json
    Assert-True 'recompute after enforcer remains partial progress mode' ([string]$afterJson.coverage_counting_mode -eq 'verifier_adjusted_partial_progress') ($afterJson | ConvertTo-Json -Depth 12)

    Write-Host ''
    Write-Host 'v693 Round Coverage Recompute Preserves Partial Progress: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
