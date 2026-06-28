param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$promptPath = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        prompt = $promptPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

Assert-True ($prompt -match 'IMPLEMENTATION_CONTRACT\.md[\s\S]{0,600}selected_real_entry:\s*<Phase0 selected_real_entry>') `
    'IMPLEMENTATION_CONTRACT prompt must require a machine-readable selected_real_entry line'
Assert-True ($prompt -match 'IMPLEMENTATION_CONTRACT\.md[\s\S]{0,700}first_slice:\s*<PLAN_RESULT first_slice>') `
    'IMPLEMENTATION_CONTRACT prompt must bind first_slice'
Assert-True ($prompt -match 'production_boundary:\s*<comma-separated production files/methods; same line, no bullet list>') `
    'FIRST_SLICE_PROOF_PLAN schema must require same-line production_boundary values'
Assert-True ($prompt -match 'production_boundary:[\s\S]{0,500}first_slice_proof_schema_empty') `
    'Prompt must explain that empty production_boundary plus bullet/list values fails schema validation'
Assert-True (($prompt -match 'oracle_production_file_overlap') -and ($prompt -match 'plan_status=BLOCKED') -and ($prompt -match 'oracle_overlap_below_threshold')) `
    'PLAN_RESULT prompt must require BLOCKED when oracle overlap remains below threshold'

Assert-True ($prompt -match 'TaskProcessor Policy Rebuild Source-Chain' -and $prompt -match 'Executable Evidence Gate') `
    'Prompt must contain policy_rebuild source-chain evidence section for TaskProcessor rebuild features'
Assert-True ($prompt -match 'buildRequestCommon' -and $prompt -match 'RequestBuildFunction' -and $prompt -match 'RequestBuildContext') `
    'Prompt must require buildRequestCommon, RequestBuildFunction, and RequestBuildContext tokens in policy_rebuild plan'
Assert-True ($prompt -match 'req\.setPolicyNum\(buildContext\.getPolicyNum\(\)\)' -and $prompt -match 'req\.setInsureNum\(buildContext\.getInsureNum\(\)\)') `
    'Prompt must require upstream assignment literals for policyNum and insureNum in policy_rebuild plans'
Assert-True ($prompt -match 'DTO-only' -and $prompt -match 'source-chain' -and $prompt -match 'taskData\.setXxx\(request\.getXxx\(\)\)') `
    'Prompt policy_rebuild section must prohibit DTO-only first-slice evidence and require source-chain assignment proof'

[ordered]@{
    status = 'PASS'
    assertions = 9
    cases = @(
        'implementation_contract_selected_real_entry_required',
        'implementation_contract_first_slice_binding_required',
        'production_boundary_same_line_schema_required',
        'schema_empty_failure_disclosed',
        'oracle_overlap_below_threshold_blocks_plan',
        'policy_rebuild_source_chain_evidence_section_exists',
        'policy_rebuild_machine_tokens_required',
        'policy_rebuild_upstream_assignment_literals_required',
        'policy_rebuild_no_dto_only_downstream_first'
    )
} | ConvertTo-Json -Depth 6
