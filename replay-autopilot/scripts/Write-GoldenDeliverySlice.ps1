param(
    [string]$EvidenceRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT",
    [string]$OutputRoot = '',
    [string]$ControlSummaryPath = '',
    [string]$GoldenLedgerPath = '',
    [switch]$ValidateOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonRequired {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required json not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Value
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Get-StringArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-RuleForFingerprint {
    param([string]$Fingerprint)

    switch -Regex ($Fingerprint) {
        '^wrong_test_surface$' {
            return [ordered]@{
                focus = 'real_entry_behavior_test'
                first_carrier_selection = 'Select the public controller/facade/processor or the production service method that owns the user-visible behavior; test through that route, not through helpers or DTOs.'
                required_red_test_shape = 'RED fails because the real entry does not produce the required business output/state/payload.'
                side_effect_evidence = 'Assert the visible output or state transition reached through the real entry.'
                coverage_credit_rule = 'No credit for helper-only, DTO-only, mapper-only, or static/file-presence tests.'
                forbidden_first_slice = 'helper-only, mock-only, DTO-only, static-only, file-presence-only'
            }
        }
        '^core_entry_unclosed$' {
            return [ordered]@{
                focus = 'core_entry_closure'
                first_carrier_selection = 'Name one real production entry and one downstream owning carrier before writing tests; if no entry can be named, stop as BLOCKED.'
                required_red_test_shape = 'RED calls the selected entry or its direct service boundary and fails on missing orchestration.'
                side_effect_evidence = 'Show that the selected entry invokes the owning carrier and changes the required business result.'
                coverage_credit_rule = 'Core entry remains open until production wiring is exercised by a behavioral test.'
                forbidden_first_slice = 'new standalone service, detached builder, constants-only, schema-only'
            }
        }
        '^side_effect_ledger_gap$' {
            return [ordered]@{
                focus = 'stateful_side_effect_slice'
                first_carrier_selection = 'Choose the carrier that writes or emits the required DB/state/file/API/payload/task/log side effect.'
                required_red_test_shape = 'RED observes missing side effect through a mapper/provider/client/file/export/log boundary.'
                side_effect_evidence = 'GREEN must assert persisted state, emitted payload, generated artifact, task/log row, or exported content.'
                coverage_credit_rule = 'No side-effect coverage without executable assertion; source existence only caps to partial.'
                forbidden_first_slice = 'mock-only collaborator verification, in-memory flag only, source scan only'
            }
        }
        '^executable_surface_slice_gap$' {
            return [ordered]@{
                focus = 'deploy_surface_first_slice'
                first_carrier_selection = 'Pick the deploy-facing surface named by the requirement: page, export, API payload, task, message, template, upload, or report.'
                required_red_test_shape = 'RED fails through the deploy-facing route or through the narrowest executable adapter for that route.'
                side_effect_evidence = 'Assert page/export/payload/template/upload/message output, not only lower-level data preparation.'
                coverage_credit_rule = 'Static file presence and compile-only checks do not close deploy-facing surface coverage.'
                forbidden_first_slice = 'backend-only helper when requirement exposes page/export/payload/artifact'
            }
        }
        '^exact_contract_gap$' {
            return [ordered]@{
                focus = 'literal_contract_slice'
                first_carrier_selection = 'Freeze literal field names, enum values, output text, ordering, and source-of-truth before implementation.'
                required_red_test_shape = 'RED asserts the exact literal contract from the requirement against the real output or persisted field.'
                side_effect_evidence = 'Assert exact field/value/order in DTO/API/export/page/log/persistence as applicable.'
                coverage_credit_rule = 'Close-enough names, inferred aliases, and manual interpretation do not earn exact-contract credit.'
                forbidden_first_slice = 'renamed approximation, local constant without consuming surface, generic mapper field'
            }
        }
        '^schema_contract_discovery_gap$' {
            return [ordered]@{
                focus = 'schema_exact_discovery_slice'
                first_carrier_selection = 'Search current code schema/signature/DTO/payload/entity/mapper evidence first; if one family is schema-blocked, cap that family and continue with the nearest executable business slice.'
                required_red_test_shape = 'RED must assert an executable contract that current code can prove: real entry behavior, persisted field, payload shape, export column, or schema-backed mapper call.'
                side_effect_evidence = 'Record search command, discovered source file/symbol, confirmed/inferred/blocked status, affected family, cap, and next executable proof.'
                coverage_credit_rule = 'Unknown schema or exact contract cannot earn coverage, but it also must not force global 0 when another real executable slice exists.'
                forbidden_first_slice = 'waiting for oracle/schema waiver, prose-only uncertainty ledger, global BLOCKED with a real entry available'
            }
        }
        '^phase0_carrier_evidence_gap$' {
            return [ordered]@{
                focus = 'phase0_real_carrier_discovery'
                first_carrier_selection = 'Before Plan, record reproducible source searches and select an existing production entry from the current worktree; do not proceed with placeholders or unverified carriers.'
                required_red_test_shape = 'The first RED must target the selected real entry or its nearest executable owning carrier named by Phase 0 evidence.'
                side_effect_evidence = 'Phase 0 must preserve search commands, matched files, selected class/method, and baseline-existing status so Phase 1 can prove behavior instead of guessing.'
                coverage_credit_rule = 'No coverage credit when Phase 0 cannot prove the selected carrier exists in the current worktree.'
                forbidden_first_slice = 'oracle-waiting entry, TBD carrier, prose-only search, hallucinated class, search results not written to Phase 0 artifacts'
            }
        }
        '^evolution_validation_fail$' {
            return [ordered]@{
                focus = 'validated_tooling_evolution'
                first_carrier_selection = 'Before another replay, implement one concrete runner/prompt/verifier/test change that is actually invoked.'
                required_red_test_shape = 'Tooling regression test fails before the fix or a fixture proves the missing enforcement.'
                side_effect_evidence = 'Show changed script/prompt is on the live runner path and regression test passes.'
                coverage_credit_rule = 'No-op docs or uninvoked helper scripts do not count as evolution.'
                forbidden_first_slice = 'plan-only evolution, report-only evolution, unattached script'
            }
        }
        '^low_verification_cap$' {
            return [ordered]@{
                focus = 'verification_cap_recovery'
                first_carrier_selection = 'Select the smallest executable business behavior that can raise verification-capped coverage.'
                required_red_test_shape = 'RED must be a business assertion, not a compilation or presence failure.'
                side_effect_evidence = 'GREEN must produce executable evidence that the verifier can credit.'
                coverage_credit_rule = 'Blind score cannot rise above verification evidence.'
                forbidden_first_slice = 'self-assessed scoring, static proof, prose-only rationale'
            }
        }
        default {
            return [ordered]@{
                focus = 'generic_executable_slice'
                first_carrier_selection = 'Select the highest-weight real production behavior and existing owner carrier.'
                required_red_test_shape = 'RED fails on business behavior through the selected carrier.'
                side_effect_evidence = 'GREEN proves the required output/state/payload/artifact.'
                coverage_credit_rule = 'Credit only executable evidence.'
                forbidden_first_slice = 'helper-only, mock-only, static-only'
            }
        }
    }
}

function Convert-RuleList {
    param([string[]]$Fingerprints)

    $rules = New-Object System.Collections.Generic.List[object]
    foreach ($fp in $Fingerprints) {
        $rule = Get-RuleForFingerprint -Fingerprint $fp
        $rule.fingerprint = $fp
        $rules.Add([pscustomobject]$rule) | Out-Null
    }
    return @($rules.ToArray())
}

$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $evidenceRootFull '_golden-samples'
}
$outputRootFull = Resolve-AbsolutePath $OutputRoot
if ([string]::IsNullOrWhiteSpace($ControlSummaryPath)) {
    $ControlSummaryPath = Join-Path $evidenceRootFull '_control\RUN_CONTROL_LATEST.json'
}
if ([string]::IsNullOrWhiteSpace($GoldenLedgerPath)) {
    $GoldenLedgerPath = Join-Path $outputRootFull 'GOLDEN_SAMPLE_LEDGER.json'
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        evidence_root = $evidenceRootFull
        output_root = $outputRootFull
        control_summary_path = (Resolve-AbsolutePath $ControlSummaryPath)
        golden_ledger_path = (Resolve-AbsolutePath $GoldenLedgerPath)
    } | ConvertTo-Json -Depth 6
    exit 0
}

New-Item -ItemType Directory -Force -Path $outputRootFull | Out-Null
$control = Read-JsonRequired (Resolve-AbsolutePath $ControlSummaryPath)
$ledger = if (Test-Path -LiteralPath $GoldenLedgerPath) { Read-JsonRequired (Resolve-AbsolutePath $GoldenLedgerPath) } else { $null }

$latest = $control.latest
$decision = $control.control_decision
$fingerprints = Get-StringArray $latest.fingerprints
$repeated = Get-StringArray $decision.repeated_blockers
if ($repeated.Count -gt 0) {
    $fingerprints = @($repeated)
}
if ($fingerprints.Count -eq 0) {
    $fingerprints = @('generic_executable_slice')
}

$rules = Convert-RuleList -Fingerprints $fingerprints
$candidateEvidence = @()
if ($null -ne $ledger) {
    $candidateEvidence = @($ledger.candidates | Select-Object -First 5)
}

$delivery = [ordered]@{
    schema = 'golden_delivery_slice.v1'
    generated_at = (Get-Date).ToString('s')
    evidence_root = $evidenceRootFull
    output_root = $outputRootFull
    latest_replay_root = [string]$latest.replay_root
    control_decision = [string]$decision.decision_kind
    repeated_blockers = @($fingerprints)
    recommended_next_step = [string]$decision.recommended_next_step
    rules = @($rules)
    candidate_evidence = @($candidateEvidence)
}

$jsonPath = Join-Path $outputRootFull 'GOLDEN_DELIVERY_SLICE.json'
$mdPath = Join-Path $outputRootFull 'GOLDEN_DELIVERY_SLICE.md'
$promptPath = Join-Path $outputRootFull 'GOLDEN_DELIVERY_SLICE_PROMPT.md'
$delivery | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Golden Delivery Slice') | Out-Null
$md.Add('') | Out-Null
$md.Add("- generated_at: $($delivery.generated_at)") | Out-Null
$md.Add("- control_decision: $($delivery.control_decision)") | Out-Null
$md.Add("- latest_replay_root: $($delivery.latest_replay_root)") | Out-Null
$md.Add("- recommended_next_step: $($delivery.recommended_next_step)") | Out-Null
$md.Add('') | Out-Null
$md.Add('## First Slice Contract') | Out-Null
$md.Add('') | Out-Null
$md.Add('The next replay must implement a positive first slice, not only avoid known anti-patterns. The first slice must bind requirement literal, real production carrier, failing behavioral RED, minimal GREEN production diff, and executable side-effect proof.') | Out-Null
$md.Add('') | Out-Null
foreach ($rule in $rules) {
    $md.Add("### $($rule.fingerprint) -> $($rule.focus)") | Out-Null
    $md.Add('') | Out-Null
    $md.Add("- first_carrier_selection: $($rule.first_carrier_selection)") | Out-Null
    $md.Add("- required_red_test_shape: $($rule.required_red_test_shape)") | Out-Null
    $md.Add("- side_effect_evidence: $($rule.side_effect_evidence)") | Out-Null
    $md.Add("- coverage_credit_rule: $($rule.coverage_credit_rule)") | Out-Null
    $md.Add("- forbidden_first_slice: $($rule.forbidden_first_slice)") | Out-Null
    $md.Add('') | Out-Null
}
$md.Add('## Candidate Positive Evidence') | Out-Null
if ($candidateEvidence.Count -eq 0) {
    $md.Add('- no mined positive candidate; use the rules above and stop if no executable carrier exists') | Out-Null
} else {
    foreach ($candidate in $candidateEvidence) {
        $md.Add(("- {0} | oracle={1} | verification={2} | root={3}" -f $candidate.feature, $candidate.oracle_adjusted_coverage, $candidate.verification_capped_coverage, $candidate.replay_root)) | Out-Null
    }
}
Write-TextFile -Path $mdPath -Value ($md -join "`n")

$prompt = @"
# Golden Delivery Slice Control

This is generic positive delivery guidance mined from replay evidence. It is not oracle evidence and must not leak feature-specific implementation facts.

Before Phase 0/Plan/Phase 1 proceeds, enforce this positive first-slice contract:

1. Choose the highest-weight real production carrier.
2. Write the first RED against that carrier or its real entry path.
3. GREEN must include the minimal production diff and executable side-effect/output proof.
4. Coverage credit is capped by executable verification evidence.
5. If this cannot be done, stop with BLOCKED and name the missing carrier/evidence. Do not fill with prose.

Required rules for this run:

$($md -join "`n")
"@
Write-TextFile -Path $promptPath -Value $prompt

if (-not [string]::IsNullOrWhiteSpace($latest.replay_root) -and (Test-Path -LiteralPath $latest.replay_root)) {
    Copy-Item -LiteralPath $jsonPath -Destination (Join-Path $latest.replay_root 'NEXT_GOLDEN_DELIVERY_SLICE.json') -Force
    Copy-Item -LiteralPath $mdPath -Destination (Join-Path $latest.replay_root 'NEXT_GOLDEN_DELIVERY_SLICE.md') -Force
}

if (-not $Quiet) {
    Write-Host "Golden delivery slice written: $mdPath"
    Write-Host "Golden delivery prompt written: $promptPath"
}
