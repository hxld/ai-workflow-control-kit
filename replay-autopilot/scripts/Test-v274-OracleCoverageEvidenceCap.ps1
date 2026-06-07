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
$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$parsePath = Join-Path $scriptRoot 'Parse-ReplayReport.ps1'
$phase2PromptPath = Join-Path $repoRoot 'prompts\phase2-oracle-posthoc.prompt.md'
$deepReviewPromptPath = Join-Path $repoRoot 'prompts\deep-replay-review.prompt.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        runner = $runnerPath
        parser = $parsePath
        phase2_prompt = $phase2PromptPath
        deep_review_prompt = $deepReviewPromptPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$parser = Get-Content -LiteralPath $parsePath -Raw -Encoding UTF8
$phase2Prompt = Get-Content -LiteralPath $phase2PromptPath -Raw -Encoding UTF8
$deepReviewPrompt = Get-Content -LiteralPath $deepReviewPromptPath -Raw -Encoding UTF8

Assert-True ($runner -match 'verification_capped_zero_blocks_oracle_credit') `
    'Run-ReplayLoop must enforce oracle credit when verification capped coverage is zero'
Assert-True ($runner -match 'ORACLE_COVERAGE_ENFORCEMENT\.md') `
    'Run-ReplayLoop must write an explicit oracle coverage enforcement artifact'
Assert-True ($parser -match 'verification_capped_zero_blocks_oracle_credit') `
    'Parse-ReplayReport must enforce the same oracle credit cap before writing AUTOPILOT_SUMMARY'
Assert-True ($parser -match 'reported_oracle_adjusted_coverage') `
    'Parse-ReplayReport must preserve the original reported oracle score for audit'
Assert-True ($parser -match 'Normalize-StatusOrNull') `
    'Parse-ReplayReport must normalize status fields instead of accepting arbitrary heading text'
Assert-True ($parser.Contains('^##\s*Decision\s*[:=]\s*')) `
    'Parse-ReplayReport must not treat headings like Decision Rationale as status declarations'
Assert-True ($phase2Prompt -match 'not oracle completeness') `
    'Phase2 prompt must define oracle coverage as replay overlap, not oracle completeness'
Assert-True ($phase2Prompt -match 'verification_capped_coverage: 0.*oracle_adjusted_coverage.*0') `
    'Phase2 prompt must force oracle_adjusted_coverage to zero when verification capped coverage is zero'
Assert-True ($runner -match 'WORKTREE_HEAD_AUDIT\.json') `
    'Run-ReplayLoop must capture worktree head audit evidence'
Assert-True ($deepReviewPrompt -match 'WORKTREE_HEAD_AUDIT\.json') `
    'Deep review prompt must allow WORKTREE_HEAD_AUDIT.json'
Assert-True ($deepReviewPrompt -match 'Do not infer the replay''s initial baseline from the worktree''s current HEAD after Phase 2') `
    'Deep review prompt must forbid initial baseline inference from final HEAD'

[ordered]@{
    status = 'PASS'
    assertions = 11
    cases = @(
        'runner_oracle_credit_cap',
        'runner_enforcement_artifact',
        'parser_oracle_credit_cap',
        'parser_reported_oracle_audit',
        'parser_status_normalization',
        'parser_decision_heading_guard',
        'phase2_overlap_definition',
        'phase2_zero_cap_rule',
        'runner_worktree_head_audit',
        'deep_review_head_audit_allowed',
        'deep_review_final_head_inference_forbidden'
    )
} | ConvertTo-Json -Depth 6
