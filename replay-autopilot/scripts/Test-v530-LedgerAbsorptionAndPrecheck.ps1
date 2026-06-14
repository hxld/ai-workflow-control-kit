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
    param([string]$Path, $Value, [int]$Depth = 12)
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
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
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

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v530-" + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'
$worktree = Join-Path $replayRoot 'worktree'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    Write-TextFile (Join-Path $worktree 'pom.xml') '<project />'

    Write-JsonFile (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        classification = 'narrow_backend_read_only_fix'
        base_classification = 'narrow_backend_fix'
        read_only = $true
        backend_only = $true
        verifier_adjustments = [ordered]@{
            non_applicable_families = @('stateful_side_effect', 'deploy_export_page', 'config_policy_threshold', 'generated_artifact_template_upload', 'external_integration', 'lifecycle_cleanup_retention')
        }
    })
    Write-JsonFile (Join-Path $replayRoot 'AUTOPILOT_RUN.json') ([ordered]@{
        replay_root = $replayRoot
        worktree = $worktree
        requirement_source = (Join-Path $replayRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md')
    })
    Write-TextFile (Join-Path $replayRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md') 'backend task processor rebuild should propagate policyNum and insureNum into request payload'
    Write-TextFile (Join-Path $replayRoot 'EXPECTED_DIFF_MATRIX.md') 'payload request processor policyNum insureNum'
    Write-TextFile (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') 'core_entry wire_payload_api_contract'
    Write-TextFile (Join-Path $replayRoot 'REPLAY_PLAN.md') 'core_entry wire_payload_api_contract'

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
                id = 'core_entry'; title = 'Core real entry'; weight = 100; recommended_slice_type = 'exact_contract_slice'; required = $true; status = 'OPEN'; touched_count = 0; first_slice = $null; last_slice = $null; slices = @(); first_executable_carrier = 'TaskProcessor.rebuildTaskData'; planned_slice = 'S1'; proof_required = @('behavior_test'); forbidden_proof = @('helper_only'); coverage_cap_if_open = 0; open_sibling_surfaces = @('TaskProcessor.rebuildTaskData'); open_sibling_count = 1; last_next_recommended_slice_type = ''; last_gap_flags = @(); evidence_keywords = @('processor', 'task', 'core_entry', 'entry'); last_reason = 'fixture'
            },
            [ordered]@{
                id = 'wire_payload_api_contract'; title = 'Wire/API exact contract'; weight = 88; recommended_slice_type = 'exact_contract_slice'; required = $true; status = 'OPEN'; touched_count = 0; first_slice = $null; last_slice = $null; slices = @(); first_executable_carrier = 'TaskProcessor.doIt'; planned_slice = 'S1'; proof_required = @('wire_payload'); forbidden_proof = @('helper_only'); coverage_cap_if_open = 0; open_sibling_surfaces = @('TaskProcessor.doIt'); open_sibling_count = 1; last_next_recommended_slice_type = ''; last_gap_flags = @(); evidence_keywords = @('payload', 'request', 'api', 'wire'); last_reason = 'fixture'
            }
        )
    })

    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'exact_contract_slice'
        coverage_delta = 100
        target_subsurface_or_carrier = 'TaskProcessor.rebuildTaskData'
        production_boundary = 'TaskProcessor.rebuildTaskData'
        proof_kind = 'real_entry_behavior'
        red_expectation = 'policyNum and insureNum missing before fix'
        implemented_files = @('claim-core/src/main/java/acme/TaskProcessor.java', 'claim-server/src/test/java/acme/TaskProcessorTest.java')
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        gap_flags = @()
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
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry', 'wire_payload_api_contract')
        gap_flags = @()
        warnings = @()
        proof_type_mismatch_families = @()
    })

    $routerScript = Join-Path $scriptRoot 'FamilyRouterAndCap.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $routerScript -ReplayRoot $replayRoot -Ledger $ledgerPath | Out-Null
    Assert-True 'router detects stale ledger before absorption' ($LASTEXITCODE -ne 0)
    $consistencyError = Read-JsonFile (Join-Path $replayRoot 'LEDGER_CONSISTENCY_ERROR.json')
    Assert-True 'router writes metadata inconsistency artifact' ([string]$consistencyError.status -eq 'METADATA_INCONSISTENCY') ($consistencyError | ConvertTo-Json -Depth 12)

    Import-RunSliceLoopFunctions
    Update-FamilyLedgerFromSlice -Path $ledgerPath -SliceResultPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceVerifyPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -SliceIndex 1 -MaxSlices 3
    $ledger = Read-JsonFile $ledgerPath
    $core = @($ledger.families | Where-Object { [string]$_.id -eq 'core_entry' } | Select-Object -First 1)[0]
    $wire = @($ledger.families | Where-Object { [string]$_.id -eq 'wire_payload_api_contract' } | Select-Object -First 1)[0]
    Assert-True 'ledger absorbs verifier closed core family' ([string]$core.status -eq 'EXECUTABLE_CLOSED' -and [int]$core.touched_count -eq 1) ($ledger | ConvertTo-Json -Depth 12)
    Assert-True 'ledger absorbs verifier closed wire family even when slice result omitted it' ([string]$wire.status -eq 'EXECUTABLE_CLOSED' -and [int]$wire.touched_count -eq 1) ($ledger | ConvertTo-Json -Depth 12)
    Assert-True 'ledger audit trail written' (Test-Path -LiteralPath (Join-Path $replayRoot 'LEDGER_AUDIT_TRAIL.jsonl'))

    & powershell -NoProfile -ExecutionPolicy Bypass -File $routerScript -ReplayRoot $replayRoot -Ledger $ledgerPath | Out-Null
    Assert-True 'router allows final pass after absorption' ($LASTEXITCODE -eq 0)
    $router = Read-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json')
    Assert-True 'router cap uses updated ledger' ([int]$router.coverage_cap_from_ledger -eq 100 -and [bool]$router.final_pass_allowed) ($router | ConvertTo-Json -Depth 12)

    $precheckRoot = Join-Path $tempRoot 'precheck'
    New-Item -ItemType Directory -Force -Path $precheckRoot | Out-Null
    Write-JsonFile (Join-Path $precheckRoot 'SLICE_RESULT_01.json') ([ordered]@{
        tests = @([ordered]@{ phase = 'RED'; result = 'pass'; evidence = 'old stale red pass' })
    })
    Write-JsonFile (Join-Path $precheckRoot 'SLICE_RESULT_02.json') ([ordered]@{
        tests = @([ordered]@{ phase = 'RED'; result = 'fail'; evidence = 'business assertion failed before fix' })
    })
    Write-JsonFile (Join-Path $precheckRoot 'SLICE_RESULT_03.json') ([ordered]@{
        tests = @(
            [ordered]@{ phase = 'RED'; command = 'test-compile'; result = 'pass'; evidence = 'Test class compiled successfully' },
            [ordered]@{ phase = 'RED'; command = 'test execution with fixed argument index'; result = 'pass'; evidence = 'Tests ran but with failures indicating missing source-chain assignments' },
            [ordered]@{ phase = 'GREEN'; command = 'test execution'; result = 'pass'; evidence = 'Tests run: 5, Failures: 0, Errors: 0, Skipped: 0' }
        )
    })
    $phase0Precheck = Join-Path $scriptRoot 'phase0-precheck.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $phase0Precheck -ReplayRoot $precheckRoot -SliceIndex 2 | Out-Null
    Assert-True 'phase0 precheck uses requested slice index' ($LASTEXITCODE -eq 0)
    $precheckResult = Read-JsonFile (Join-Path $precheckRoot 'PHASE0_PRECHECK_RESULT.json')
    Assert-True 'phase0 precheck ignored stale first slice red pass' ([string]$precheckResult.checks.red_phase_authorized.Reason -eq 'red_phase_authorized') ($precheckResult | ConvertTo-Json -Depth 12)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $phase0Precheck -ReplayRoot $precheckRoot -SliceIndex 3 | Out-Null
    Assert-True 'phase0 precheck ignores RED test-compile pass when later RED business evidence exists' ($LASTEXITCODE -eq 0)
    $precheckResult = Read-JsonFile (Join-Path $precheckRoot 'PHASE0_PRECHECK_RESULT.json')
    Assert-True 'phase0 precheck selected business RED evidence instead of compile pass' ([string]$precheckResult.checks.red_phase_authorized.Reason -eq 'red_phase_authorized') ($precheckResult | ConvertTo-Json -Depth 12)

    Write-Host 'v530 ledger absorption and precheck regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
