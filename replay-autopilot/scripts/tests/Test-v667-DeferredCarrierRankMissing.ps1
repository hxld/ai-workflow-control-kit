#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Json {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v667-deferred-carrier-rank-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
first_red_test: sample-harness/src/test/java/com/example/workflow/CoreEntryBehaviorTest.java#shouldInvokeRealEntry
selected_real_entry: com.example.workflow.TaskProcessor.handleTaskResponse
selected_carrier: com.example.workflow.TaskProcessor.handleTaskResponse
proof_kind: real_entry_behavior
'@
    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') ''
    Write-Utf8 (Join-Path $replayRoot 'BASELINE_INDEX.md') ''
    Write-Json (Join-Path $replayRoot 'FAMILY_CONTRACT.json') ([ordered]@{
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true },
            [ordered]@{ id = 'generated_artifact_template_upload'; required = $true }
        )
    })
    Write-Json (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $false
    })
    Write-Json (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        selected_carrier = 'com.example.workflow.TaskProcessor.handleTaskResponse'
        real_entry = 'com.example.workflow.TaskProcessor.handleTaskResponse'
        production_boundary = 'com.example.workflow.TaskProcessor.handleTaskResponse'
        downstream_side_effect_or_output = 'real_entry_invocation; business_behavior_RED; minimal_GREEN_production_diff'
        red_expectation = 'business assertion should fail before production change'
        requires_side_effect_evidence = $false
        requires_exact_contract_assertions = $false
        forbidden_synthetic_carrier = $false
    })
    Write-Json (Join-Path $replayRoot 'SIDE_EFFECT_EVIDENCE_01.json') ([ordered]@{
        status = 'NOT_REQUIRED'
        red_result = 'PENDING_BUSINESS_ASSERTION'
        green_result = 'PENDING'
        test_name = 'sample-harness/src/test/java/com/example/workflow/CoreEntryBehaviorTest.java#shouldInvokeRealEntry'
        entry_call = 'com.example.workflow.TaskProcessor.handleTaskResponse'
        expected_writes_or_outputs = @('real entry behavior assertion')
    })
    Write-Json (Join-Path $replayRoot 'NEXT_SLICE_EXACT_CONTRACT_01.json') ([ordered]@{
        decision = 'ALLOW'
        rows = @(
            [ordered]@{
                literal = 'real entry behavior'
                symbol_or_field = 'TaskProcessor.handleTaskResponse'
                test_assertion = 'shouldInvokeRealEntry'
            }
        )
        issues = @()
    })
    Write-Json (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json') ([ordered]@{
        rows = @(
            [ordered]@{
                literal = 'real entry behavior'
                symbol_or_field = 'TaskProcessor.handleTaskResponse'
                test_assertion = 'shouldInvokeRealEntry'
            }
        )
    })
    Write-Json (Join-Path $replayRoot 'CARRIER_RANK_01.json') ([ordered]@{
        schema_version = 1
        slice_index = 1
        families = @(
            [ordered]@{
                family = 'core_entry'
                required = $true
                status = 'OPEN'
                rank = 1
                production_carrier = 'com.example.workflow.TaskProcessor.handleTaskResponse'
            },
            [ordered]@{
                family = 'generated_artifact_template_upload'
                required = $true
                status = 'OPEN'
                rank = 2
                production_carrier = ''
            }
        )
        missing_required_rank1 = @('generated_artifact_template_upload')
        gate = 'carrier_ranking_hard_stop'
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Authorize-PreSliceEvidence.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType tracer_bullet `
        -ForcedSiblingSurface 'com.example.workflow.TaskProcessor.handleTaskResponse' | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice authorization script should run'

    $auth = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$auth.decision -eq 'ALLOW') 'missing carrier for deferred generated-artifact family must not block executable core_entry slice'
    Assert-True (-not ((@($auth.issues) -join ',') -match 'carrier_rank_missing:generated_artifact_template_upload')) 'deferred family carrier gap must not be a hard issue'
    Assert-True (((@($auth.warnings) -join ',') -match 'carrier_rank_missing_deferred:generated_artifact_template_upload')) 'deferred family carrier gap must be disclosed as warning'

    $auth.carrier_rank.families[0].production_carrier = ''
    $auth.carrier_rank.missing_required_rank1 = @('core_entry', 'generated_artifact_template_upload')
    Write-Json (Join-Path $replayRoot 'CARRIER_RANK_01.json') $auth.carrier_rank

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Authorize-PreSliceEvidence.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType tracer_bullet `
        -ForcedSiblingSurface 'com.example.workflow.TaskProcessor.handleTaskResponse' | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice authorization script should run with missing forced carrier'

    $blocked = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$blocked.decision -eq 'STOP') 'missing carrier for current forced family must still block'
    Assert-True (((@($blocked.issues) -join ',') -match 'carrier_rank_missing:core_entry')) 'current family missing carrier must remain a hard issue'

    Write-Host 'v667 deferred carrier-rank missing: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
