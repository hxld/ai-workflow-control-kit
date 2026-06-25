#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$autopilotRoot = Split-Path -Parent $scriptsRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v656-named-experiment-gates-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'demo-harness') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'

    $command = "mvn --% -f $(Join-Path $worktree 'pom.xml') -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"
    @{
        families = @(@{ id = 'core_entry'; required = $true; required_proof_type = 'real_entry_behavior' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    @{
        callable_carriers = @(@{ signature = 'demo.RealEntry.handle(String): String' })
        failed_carrier_authorizations = @(@{ signature = 'demo.BadEntry.handle()'; reason = 'synthetic_carrier' })
        test_harness_modules = @('demo-harness')
        valid_maven_command_templates = @(@{ module = 'demo-harness'; command = $command })
        forbidden_proof_types_by_family = @{ core_entry = @('mock_only', 'static_only', 'helper_only', 'file_presence') }
        side_effect_probe_examples = @(@{ family = 'core_entry'; probe = 'returned payload value' })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'replay-context-index.json') -Encoding UTF8
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        production_boundary = 'demo.RealEntry.handle(String): String'
        downstream_side_effect_or_output = 'returned payload value'
        red_expectation = 'assertEquals("mapped", result) fails before mapping is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.RealEntry.handle(String): String'
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        resolved_signature = @{ selected_carrier = @{ class_name = 'demo.RealEntry'; visibility = 'public'; formatted = 'String demo.RealEntry.handle(String)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- first_red_test: RealEntryContractTest#returnsMappedPayload
- red_command: $command
- green_command: $command
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through the existing entry
- red_assertion: assertEquals("mapped", result)
- downstream_output_or_side_effect: returned payload value
- production_boundary: demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only or mock-only closure
- green_change_boundary: RealEntry.handle return mapping
- validation_command: $command
- entry_invocation_method: new RealEntry().handle("input")
- required_proof_type: real_entry_behavior
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType real_entry_behavior | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'aggregate pre-slice gate should pass valid v656 named experiment inputs'

    foreach ($artifact in @('PRE_SLICE_AUTHORIZATION_GATE.json', 'PROOF_TYPE_POLICY_GATE.json', 'REPLAY_CONTEXT_INDEX_CONTRACT_CHECK.json')) {
        $path = Join-Path $replayRoot $artifact
        Assert-True (Test-Path -LiteralPath $path) "$artifact must be generated"
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ([string]$json.status -eq 'PASS') "$artifact must pass for valid contract"
    }

    $badReplayRoot = Join-Path $tempRoot 'bad-replay'
    $badWorktree = Join-Path $badReplayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $badWorktree | Out-Null
    Write-Utf8 (Join-Path $badWorktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    @{
        schema_version = 1
        family_id = 'core_entry'
        real_entry_fqn = 'helper_only'
        production_entry_qn = 'helper_only'
        test_harness_module = 'demo-harness'
        test_class = 'RealEntryContractTest'
        test_method = 'returnsMappedPayload'
        red_command = "mvn --% -f $(Join-Path $badWorktree 'pom.xml') -pl demo-harness -Dtest=RealEntryContractTest#returnsMappedPayload test"
        green_command = 'mvn install'
        isolated_pom_path = (Join-Path $badWorktree 'pom.xml')
        maven_settings_arg = '-Dfile.encoding=UTF-8'
        required_proof_type = 'mock_only'
        side_effect_or_output_probe = 'static_only'
        must_not_assertion = ''
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $badReplayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') -Encoding UTF8
    @{
        families = @(@{ id = 'core_entry'; required = $true; required_proof_type = 'real_entry_behavior' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $badReplayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    @{
        proof_type = 'mock_only'
        production_entry = 'helper_only'
        business_assertion = 'static_only'
        state_or_output_surface = 'file_presence'
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $badReplayRoot 'TEST_CHARTER_01.json') -Encoding UTF8
    @{
        callable_carriers = @()
        failed_carrier_authorizations = @(@{ signature = 'helper_only'; reason = 'synthetic_carrier' })
        test_harness_modules = @('other-harness')
        valid_maven_command_templates = @('mvn deploy')
        forbidden_proof_types_by_family = @{ core_entry = @('mock_only') }
        side_effect_probe_examples = @(@{ family = 'core_entry'; probe = 'returned payload value' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $badReplayRoot 'REPLAY_CONTEXT_INDEX.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'pre_slice_authorization_gate.ps1') `
        -ReplayRoot $badReplayRoot `
        -Worktree $badWorktree `
        -Contract (Join-Path $badReplayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') `
        -FamilyLedger (Join-Path $badReplayRoot 'REQUIREMENT_FAMILY_LEDGER.json') 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'pre-slice authorization gate must fail closed on helper/static and Maven command violations'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'proof_type_policy_gate.ps1') `
        -ReplayRoot $badReplayRoot `
        -TestCharter (Join-Path $badReplayRoot 'TEST_CHARTER_01.json') `
        -FamilyLedger (Join-Path $badReplayRoot 'REQUIREMENT_FAMILY_LEDGER.json') `
        -Contract (Join-Path $badReplayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'proof-type policy gate must reject mock/static/helper proof'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'replay_context_index_contract_check.ps1') `
        -ReplayRoot $badReplayRoot `
        -Index (Join-Path $badReplayRoot 'REPLAY_CONTEXT_INDEX.json') `
        -Contract (Join-Path $badReplayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'replay context index contract check must reject missing reuse and invalid command template'

    $aggregateText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    Assert-True ($aggregateText -match 'pre_slice_authorization_gate\.ps1') 'aggregate gate must invoke pre_slice_authorization_gate.ps1'
    Assert-True ($aggregateText -match 'proof_type_policy_gate\.ps1') 'aggregate gate must invoke proof_type_policy_gate.ps1'
    Assert-True ($aggregateText -match 'replay_context_index_contract_check\.ps1') 'aggregate gate must invoke replay_context_index_contract_check.ps1'
    Assert-True ($promptText -match 'PRE_SLICE_AUTHORIZATION_GATE\.json') 'executor prompt must name pre-slice authorization gate artifact'
    Assert-True ($promptText -match 'PROOF_TYPE_POLICY_GATE\.json') 'executor prompt must name proof-type policy artifact'
    Assert-True ($promptText -match 'REPLAY_CONTEXT_INDEX_CONTRACT_CHECK\.json') 'executor prompt must name replay context index contract artifact'

    Write-Host 'v656 Stop-And-Evolve Named Experiment Gates: PASS'
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
