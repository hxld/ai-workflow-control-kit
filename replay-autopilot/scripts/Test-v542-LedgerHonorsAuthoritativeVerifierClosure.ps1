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

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 16)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-TextFile {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Import-RunSliceLoopFunctions {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v542-ledger-authoritative-closure-" + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Write-JsonFile (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        classification = 'narrow_backend_read_only_fix'
        base_classification = 'narrow_backend_fix'
        read_only = $true
        verifier_adjustments = [ordered]@{
            non_applicable_families = @('stateful_side_effect', 'deploy_export_page', 'config_policy_threshold', 'generated_artifact_template_upload', 'external_integration', 'lifecycle_cleanup_retention')
        }
    })
    Write-JsonFile (Join-Path $replayRoot 'AUTOPILOT_RUN.json') ([ordered]@{
        replay_root = $replayRoot
        requirement_source = (Join-Path $replayRoot 'REQUIREMENT.md')
    })
    Write-TextFile (Join-Path $replayRoot 'REQUIREMENT.md') 'backend task processor rebuild should propagate policyNum and insureNum into request payload'

    $ledgerPath = Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json'
    Write-JsonFile $ledgerPath ([ordered]@{
        schema_version = 1
        replay_root = $replayRoot
        max_slices = 3
        created_at = '2026-06-14T00:00:00'
        updated_at = '2026-06-14T00:00:00'
        coverage_cap = 100
        no_progress_slices = @()
        open_required_after_max = @()
        families = @(
            [ordered]@{
                id = 'core_entry'
                title = 'Core real entry'
                weight = 100
                recommended_slice_type = 'exact_contract_slice'
                required = $true
                status = 'OPEN'
                touched_count = 0
                first_slice = $null
                last_slice = $null
                slices = @()
                first_executable_carrier = 'AiApplyClaimApiTaskProcessor.rebuildTaskData'
                planned_slice = 'S1'
                proof_required = @('behavior_test', 'code_inspection')
                forbidden_proof = @('helper_only')
                coverage_cap_if_open = 0
                open_sibling_surfaces = @('TaskProcessor rebuildTaskData -> AiClaimBaseTaskData.policyNum/insureNum -> InputData.policy_num/InputData.insure_num')
                open_sibling_count = 1
                last_next_recommended_slice_type = ''
                last_gap_flags = @()
                evidence_keywords = @('processor', 'task', 'core_entry', 'entry', 'real entry')
                last_reason = 'fixture'
            },
            [ordered]@{
                id = 'wire_payload_api_contract'
                title = 'Wire/API exact contract'
                weight = 88
                recommended_slice_type = 'exact_contract_slice'
                required = $true
                status = 'OPEN'
                touched_count = 0
                first_slice = $null
                last_slice = $null
                slices = @()
                first_executable_carrier = 'AiApplyClaimApiTaskProcessor.doIt'
                planned_slice = 'S1'
                proof_required = @('code_inspection', 'payload_assertion')
                forbidden_proof = @('helper_only')
                coverage_cap_if_open = 0
                open_sibling_surfaces = @('AiApplyClaimApiTaskProcessor.doIt')
                open_sibling_count = 1
                last_next_recommended_slice_type = ''
                last_gap_flags = @()
                evidence_keywords = @('payload', 'request', 'api', 'wire')
                last_reason = 'fixture'
            }
        )
    })

    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'exact_contract_slice'
        coverage_delta = 100
        target_subsurface_or_carrier = 'private rebuildTaskData(Long caseId) method in both processors'
        required_sibling_surfaces = @('AiClaimDataAssemblyHelper.buildRequestCommon', 'RequestBuildContext.policyNum', 'RequestBuildContext.insureNum')
        production_boundary = 'AiApplyClaimApiTaskProcessor.rebuildTaskData, AiCalculateLossApiTaskProcessor.rebuildTaskData'
        proof_kind = 'real_entry_behavior'
        red_expectation = 'policyNum and insureNum missing before fix'
        implemented_files = @(
            'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java',
            'claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java',
            'claim-server/src/test/java/com/huize/claim/core/ai/task/PolicyNumRebuildPathTest.java'
        )
        closed_assertions = @('policyNum source-chain propagation', 'insureNum source-chain propagation')
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        gap_flags = @()
        next_recommended_slice_type = 'deploy_surface_first_slice'
        tests = @([ordered]@{ phase = 'GREEN'; result = 'pass'; command = 'mvn test'; evidence = 'BUILD SUCCESS' })
    })

    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PASS'
        slice_status = 'DONE'
        adjusted_coverage_delta = 100
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $true
        authorization_blockers = @()
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        proof_type_mismatch_families = @()
        gap_flags = @()
        warnings = @(
            'red_phase_passed_before_fix',
            'family_sibling_surface_not_applicable_by_feature_classification',
            'side_effect_evidence_not_applicable_by_feature_classification'
        )
    })

    Import-RunSliceLoopFunctions
    Update-FamilyLedgerFromSlice -Path $ledgerPath -SliceResultPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceVerifyPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -SliceIndex 1 -MaxSlices 3

    $ledger = Read-JsonFile $ledgerPath
    $core = @($ledger.families | Where-Object { [string]$_.id -eq 'core_entry' } | Select-Object -First 1)[0]
    Assert-True 'authoritative verifier closure overrides non-blocking warnings' ([string]$core.status -eq 'EXECUTABLE_CLOSED') ($ledger | ConvertTo-Json -Depth 16)
    Assert-True 'closed core family has no open sibling surfaces' ([int]$core.open_sibling_count -eq 0 -and @($core.open_sibling_surfaces).Count -eq 0) ($core | ConvertTo-Json -Depth 10)
    Assert-True 'ledger audit records closed family absorption' (Test-Path -LiteralPath (Join-Path $replayRoot 'LEDGER_AUDIT_TRAIL.jsonl'))

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'FamilyRouterAndCap.ps1') -ReplayRoot $replayRoot -Ledger $ledgerPath -ValidateOnly | Out-Null
    Assert-True 'router no longer reports stale ledger for authoritative closure' ($LASTEXITCODE -eq 0)
    $router = Read-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json')
    Assert-True 'router selects remaining wire family after core closure' ([string]$router.selected_family -eq 'wire_payload_api_contract') ($router | ConvertTo-Json -Depth 16)

    Write-Host 'v542 ledger authoritative verifier closure regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
