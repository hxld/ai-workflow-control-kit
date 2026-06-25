param(
    [string]$EvidenceRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT",
    [string]$ReplayRoot = '',
    [string]$ControlSummaryPath = '',
    [string]$BlockerRegistryPath = '',
    [switch]$ValidateOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

function Read-TextIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Get-StringArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Add-UniqueString {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Get-BlockerRule {
    param([string]$Fingerprint)

    switch -Regex ($Fingerprint) {
        '^policy_rebuild_claim_core_harness$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'plan_authorization'
                root_cause = 'Policy rebuild planning confuses the claim-core production carrier with the claim-server executable test harness.'
                required_fix = 'Add a pre-Maven policy gate and Plan authorization rule: policyNum/insureNum rebuild may target claim-core production files, but tests and dry-run evidence must use claim-server with -pl claim-server -am test-compile.'
                prevention_gate = 'Do not materialize Maven evidence for claim-core when policy rebuild keywords are present; stop or deterministically repair before Maven.'
                regression_test = 'r17-shaped Plan fixture emits policy_rebuild_claim_core_harness and proves no claim-core Maven evidence is generated.'
                next_validation = 'Next replay either uses claim-server harness and passes Plan authorization, or stops immediately with this fingerprint before Maven.'
                machine_gate = 'policy_rebuild_claim_server_harness_required'
                severity = 'P0'
            }
        }
        '^low_verification_cap$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'verification_strategy'
                root_cause = 'Replay keeps producing blind or prose evidence that the verifier cannot credit.'
                required_fix = 'Force the next first slice to close one executable business behavior with RED/GREEN and side-effect/output proof.'
                prevention_gate = 'Coverage cannot improve unless verification-capped evidence improves; otherwise stop and evolve instead of replaying.'
                regression_test = 'Test failure audit marks low verification cap as requiring golden first slice and executable evidence.'
                next_validation = 'Next replay must either raise verification_capped_coverage above zero or stop with a concrete missing executable carrier.'
                machine_gate = 'golden_first_slice_required'
                severity = 'P0'
            }
        }
        '^evolution_validation_fail$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'evolution_control'
                root_cause = 'Evolution is being accepted without proving the changed runner/prompt/verifier is on the live execution path.'
                required_fix = 'Require changed files, invoked path, regression result, pushed backup commit, and blocker-addressing proof.'
                prevention_gate = 'Reflection gate rejects no-op, report-only, or uninvoked tooling evolution.'
                regression_test = 'Validate-EvolutionResult and ReflectionSufficiencyGate reject unrelated evolution.'
                next_validation = 'EVOLUTION_RESULT_VERIFY=PASS and REFLECTION_GATE=PASS before the next cycle may continue.'
                machine_gate = 'evolution_effectiveness_required'
                severity = 'P0'
            }
        }
        '^plan_format_drift$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'plan_schema'
                root_cause = 'Plan artifacts are still interpreted from unstable Markdown and aliases.'
                required_fix = 'Use machine-readable PLAN_RESULT.json and fail fast before Phase 1 when required keys are missing.'
                prevention_gate = 'Markdown-only or prose-only plans must not enter the slice executor.'
                regression_test = 'Plan schema fail-fast rejects incomplete PROCEED contracts.'
                next_validation = 'PLAN_SCHEMA_FAILFAST=PASS with target carrier, test method, side effects, and assertions.'
                machine_gate = 'plan_machine_contract_required'
                severity = 'P0'
            }
        }
        '^side_effect_ledger_gap$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'behavioral_test_design'
                root_cause = 'Implementation stops at code presence or mock collaborator checks, without proving DB/state/file/API/log/task side effects.'
                required_fix = 'First slice must name side effects and assert at least one executable side effect through the owning carrier.'
                prevention_gate = 'No side-effect proof means the family stays open and coverage is capped.'
                regression_test = 'Test charter or dry-run gate rejects side-effect ledger without executable proof.'
                next_validation = 'ROUND_RESULT cites concrete side-effect assertion, not source scan or helper-only proof.'
                machine_gate = 'side_effect_proof_required'
                severity = 'P0'
            }
        }
        '^exact_contract_gap$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'requirement_contract'
                root_cause = 'Exact literals, fields, enum values, payload keys, or display/export contracts are inferred instead of frozen.'
                required_fix = 'Extract exact contract ledger before coding and assert exact values on the real output or persisted carrier.'
                prevention_gate = 'Close-enough aliases and inferred names earn no exact-contract credit.'
                regression_test = 'Verifier or test fixture rejects missing literal/field/payload assertion.'
                next_validation = 'Next first slice contains requirement literal -> code location -> assertion mapping.'
                machine_gate = 'exact_contract_ledger_required'
                severity = 'P0'
            }
        }
        '^wrong_test_surface$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'test_surface'
                root_cause = 'Tests validate helpers, DTOs, mappers, or static files instead of the requirement-visible entry or owning carrier.'
                required_fix = 'Select one real entry and require the RED test to call that entry or the nearest executable production boundary.'
                prevention_gate = 'Helper-only/mock-only/static-only tests cannot close a behavior family.'
                regression_test = 'Dry-run gate rejects selected entry and selected carrier mismatch.'
                next_validation = 'FIRST_SLICE_PROOF_PLAN binds first_red_test to the selected real entry/carrier.'
                machine_gate = 'real_entry_test_surface_required'
                severity = 'P0'
            }
        }
        '^core_entry_unclosed$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'implementation_slice'
                root_cause = 'Planning names a concept but does not wire or test the actual production entry that triggers the behavior.'
                required_fix = 'Close the highest-weight real entry first; do not start from detached services or constants.'
                prevention_gate = 'Core entry remains open until executable evidence proves the entry path.'
                regression_test = 'Plan/dry-run gate rejects first slice that does not bind to selected real entry.'
                next_validation = 'Diff and test evidence show the selected entry path is touched and asserted.'
                machine_gate = 'core_entry_closure_required'
                severity = 'P0'
            }
        }
        '^executable_surface_slice_gap$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'deploy_surface'
                root_cause = 'Deploy-facing surfaces are left at compile/static evidence instead of executable API/page/export/payload/artifact proof.'
                required_fix = 'Pick the smallest deploy-facing surface and assert its executable output.'
                prevention_gate = 'Compile-only or source-existence evidence cannot close deploy-facing surface coverage.'
                regression_test = 'Surface slice gate rejects static-only proof for deploy-facing families.'
                next_validation = 'Next report has executable proof for the named surface or an explicit blocked carrier.'
                machine_gate = 'executable_surface_proof_required'
                severity = 'P0'
            }
        }
        '^phase0_carrier_evidence_gap$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'phase0_discovery'
                root_cause = 'Phase 0 selects or implies carriers without preserving reproducible source evidence.'
                required_fix = 'Require search commands, matched files, selected class/method, and baseline-existing status.'
                prevention_gate = 'No verified carrier means Plan must block, not guess.'
                regression_test = 'Phase0 carrier evidence verifier rejects placeholder or hallucinated entries.'
                next_validation = 'PHASE0 carrier evidence files prove selected_real_entry exists in the current worktree.'
                machine_gate = 'phase0_carrier_evidence_required'
                severity = 'P1'
            }
        }
        '^phase0_oracle_contamination$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'source_isolation'
                root_cause = 'Blind discovery is mixing oracle/post-hoc clues into Phase 0 selection.'
                required_fix = 'Separate blind source-of-truth from oracle post-hoc and fail closed on oracle-derived carrier claims.'
                prevention_gate = 'Phase 0 cannot use oracle, old replay, or target diff evidence.'
                regression_test = 'Phase0 verifier rejects oracle-inferred selected entry.'
                next_validation = 'Phase0 artifacts disclose oracle_used=false and cite only allowed sources.'
                machine_gate = 'blind_source_isolation_required'
                severity = 'P1'
            }
        }
        '^phase0_format_drift$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'phase0_schema'
                root_cause = 'Phase 0 required fields are still emitted in unstable headings or prose.'
                required_fix = 'Use exact headings plus machine-readable status fields; reject placeholders and aliases.'
                prevention_gate = 'Phase0 parse failure stops before Plan.'
                regression_test = 'Phase0 format fixture covers allowed headings and rejects missing status.'
                next_validation = 'PHASE0 contract verify passes with real selected entry and required headings.'
                machine_gate = 'phase0_machine_contract_required'
                severity = 'P1'
            }
        }
        '^executor_resource_or_crash$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'executor_reliability'
                root_cause = 'Executor exits, model capacity, rate limits, or transient API failures interrupt the pipeline.'
                required_fix = 'Use bounded retry/fallback and record executor failure class without consuming it as coverage failure.'
                prevention_gate = 'Transient executor errors retry; persistent executor errors stop with evidence.'
                regression_test = 'Executor retry fixture treats 429 and model capacity as transient and bounded.'
                next_validation = 'Run status distinguishes infrastructure stop from implementation blocker.'
                machine_gate = 'executor_retry_and_classification_required'
                severity = 'P1'
            }
        }
        '^executor_credit_required$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'executor_resource'
                root_cause = 'Primary executor cannot run because the account has no required credit or positive balance.'
                required_fix = 'Restore Claude/executor account credit, or intentionally change executor policy with audit disclosure before replay resumes.'
                prevention_gate = 'Credit-required errors stop as resource blockers and are not scored as evaluation or implementation failures.'
                regression_test = 'Invoke-AgentPrompt fixture classifies Claude 402 Credit required as executor_credit_required and exits with resource code 86.'
                next_validation = 'Next run either reaches slice execution after credit is restored or stops before replay with executor_credit_required.'
                machine_gate = 'executor_credit_required_stopline'
                severity = 'P0'
            }
        }
        '^protected_root_isolation_violation$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'runner_isolation'
                root_cause = 'Replay executor attempted forbidden commands or writes against the protected main project root.'
                required_fix = 'Kill the offending process tree, preserve command-guard evidence, audit protected-root git status, and stop before another replay round.'
                prevention_gate = 'Any protected-root POM command or protected-root status mutation exits with an isolation blocker.'
                regression_test = 'Invoke-AgentPrompt command-guard fixture proves forbidden protected-root commands produce exit 92/93 and blocker classification.'
                next_validation = 'FAILURE_AUDIT_PACK classifies protected_root_isolation_violation instead of unknown.'
                machine_gate = 'protected_root_isolation_required'
                severity = 'P0'
            }
        }
        '^maven_pl_without_am_command_guard$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'runner_command_policy'
                root_cause = 'Slice executor ran a Maven command with -pl for compile/test goals without -am, so dependent modules may be skipped and replay evidence becomes unreliable.'
                required_fix = 'Inject command-guard feedback into the retry prompt and keep a machine gate requiring -am for every Maven compile/test command that uses -pl.'
                prevention_gate = 'Phase1 retry prompt must name maven_pl_without_am_forbidden and show the valid -pl <module> -am command shape before retrying.'
                regression_test = 'Command-guard retry fixture proves PHASE1_SLICE retry prompt contains maven_pl_without_am_forbidden and -pl <test-module> -am guidance.'
                next_validation = 'Next Phase1 retry either uses -am with -pl or writes BLOCKED SLICE_RESULT without running a forbidden command.'
                machine_gate = 'maven_project_list_also_make_required'
                severity = 'P0'
            }
        }
        '^schema_contract_discovery_gap$' {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'schema_discovery'
                root_cause = 'Schema or payload contracts are unknown, but the system either guesses or globally blocks instead of selecting an executable slice.'
                required_fix = 'Classify confirmed/inferred/blocked schema items and continue only on executable confirmed carriers.'
                prevention_gate = 'Unknown exact schema caps that family but cannot justify fake completion.'
                regression_test = 'Schema discovery ledger fixture rejects prose-only uncertainty.'
                next_validation = 'Next Plan records schema status and chooses a confirmed executable carrier.'
                machine_gate = 'schema_discovery_ledger_required'
                severity = 'P1'
            }
        }
        default {
            return [ordered]@{
                blocker = $Fingerprint
                root_cause_layer = 'unknown'
                root_cause = 'Unclassified blocker; replay control must classify before more unattended runs.'
                required_fix = 'Add a blocker rule, owner layer, regression fixture, and next validation metric.'
                prevention_gate = 'Unknown repeated blocker requires deep review.'
                regression_test = 'Failure audit includes unknown blocker classification test.'
                next_validation = 'Blocker appears in FAILURE_AUDIT_PACK with owner and fix path.'
                machine_gate = 'blocker_classification_required'
                severity = 'P1'
            }
        }
    }
}

function Convert-ToMarkdownCell {
    param([object]$Value)
    if ($null -eq $Value) { return '-' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '-' }
    return $text.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot
if ([string]::IsNullOrWhiteSpace($ControlSummaryPath)) {
    $ControlSummaryPath = Join-Path $evidenceRootFull '_control\RUN_CONTROL_LATEST.json'
}
if ([string]::IsNullOrWhiteSpace($BlockerRegistryPath)) {
    $BlockerRegistryPath = Join-Path $evidenceRootFull '_control\BLOCKER_REGISTRY.json'
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        schema = 'failure_audit_pack_writer.v1'
        evidence_root = $evidenceRootFull
        control_summary_path = Resolve-AbsolutePath $ControlSummaryPath
        blocker_registry_path = Resolve-AbsolutePath $BlockerRegistryPath
        emits_verifiable_rules = $true
        verifiable_rules_schema = 'replay_verifiable_rule_pack.v1'
    } | ConvertTo-Json -Depth 6
    exit 0
}

$control = Read-JsonIfExists (Resolve-AbsolutePath $ControlSummaryPath)
if ([string]::IsNullOrWhiteSpace($ReplayRoot)) {
    if ($null -eq $control -or $null -eq $control.latest -or [string]::IsNullOrWhiteSpace([string]$control.latest.replay_root)) {
        throw "ReplayRoot was not provided and control summary does not expose latest.replay_root"
    }
    $ReplayRoot = [string]$control.latest.replay_root
}

$root = Resolve-AbsolutePath $ReplayRoot
if (-not (Test-Path -LiteralPath $root)) {
    throw "Replay root not found: $root"
}

$registry = Read-JsonIfExists (Resolve-AbsolutePath $BlockerRegistryPath)
$fingerprintJson = Read-JsonIfExists (Join-Path $root 'BLOCKER_FINGERPRINTS.json')
$stagnation = Read-JsonIfExists (Join-Path $root 'STAGNATION_DECISION.json')
$summary = Read-JsonIfExists (Join-Path $root 'RUN_CONTROL_SUMMARY.json')

$fingerprints = New-Object System.Collections.Generic.List[string]
foreach ($fp in @(Get-StringArray $fingerprintJson.fingerprints)) { Add-UniqueString $fingerprints $fp }
foreach ($fp in @(Get-StringArray $fingerprintJson.repeated_blockers)) { Add-UniqueString $fingerprints $fp }
foreach ($fp in @(Get-StringArray $stagnation.repeated_blockers)) { Add-UniqueString $fingerprints $fp }
if ($null -ne $summary -and $null -ne $summary.latest) {
    foreach ($fp in @(Get-StringArray $summary.latest.fingerprints)) { Add-UniqueString $fingerprints $fp }
}
if ($fingerprints.Count -eq 0 -and $null -ne $control -and $null -ne $control.latest) {
    foreach ($fp in @(Get-StringArray $control.latest.fingerprints)) { Add-UniqueString $fingerprints $fp }
}
if ($fingerprints.Count -eq 0) {
    Add-UniqueString $fingerprints 'unknown'
}

$commandGuardSignals = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.exec.json' -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $exec = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $category = [string]$exec.failure_category
        $reasons = [string]$exec.command_guard_reasons
        if ($category -eq 'command_guard_violation' -and $reasons -match 'maven_pl_without_am_forbidden') {
            $commandGuardSignals.Add($_.FullName) | Out-Null
        }
    } catch {
        continue
    }
}
if ($commandGuardSignals.Count -gt 0) {
    Add-UniqueString $fingerprints 'maven_pl_without_am_command_guard'
}

$repeated = New-Object System.Collections.Generic.List[string]
foreach ($fp in @(Get-StringArray $stagnation.repeated_blockers)) { Add-UniqueString $repeated $fp }
if ($null -ne $control -and $null -ne $control.control_decision) {
    foreach ($fp in @(Get-StringArray $control.control_decision.repeated_blockers)) { Add-UniqueString $repeated $fp }
}

$diagnoses = New-Object System.Collections.Generic.List[object]
$mustFix = New-Object System.Collections.Generic.List[string]
$goldenBlockers = @(
    'policy_rebuild_claim_core_harness',
    'low_verification_cap',
    'wrong_test_surface',
    'core_entry_unclosed',
    'side_effect_ledger_gap',
    'exact_contract_gap',
    'executable_surface_slice_gap'
)

foreach ($fp in @($fingerprints.ToArray())) {
    $rule = Get-BlockerRule -Fingerprint $fp
    $count = 0
    if ($null -ne $registry -and $null -ne $registry.blockers -and $registry.blockers.PSObject.Properties.Name -contains $fp) {
        $count = [int]$registry.blockers.$fp.count
    }
    $isRepeated = $repeated.Contains($fp) -or $count -ge 2
    $rule.replay_count = $count
    $rule.repeated = $isRepeated
    $diagnoses.Add([pscustomobject]$rule) | Out-Null
    if ($isRepeated -or $rule.severity -eq 'P0') {
        Add-UniqueString $mustFix $fp
    }
}

$goldenRequired = $false
foreach ($fp in @($mustFix.ToArray())) {
    if ($goldenBlockers -contains $fp) {
        $goldenRequired = $true
        break
    }
}

$latestCap = $null
$latestOracle = $null
$feature = ''
if ($null -ne $control -and $null -ne $control.latest) {
    $latestCap = $control.latest.verification_capped_coverage
    $latestOracle = $control.latest.oracle_adjusted_coverage
    $feature = [string]$control.latest.feature
}

$jsonPath = Join-Path $root 'FAILURE_AUDIT_PACK.json'
$mdPath = Join-Path $root 'FAILURE_AUDIT_PACK.md'
$verifiableRulesPath = Join-Path $root 'VERIFIABLE_RULES.json'
$verifiableRulesMdPath = Join-Path $root 'VERIFIABLE_RULES.md'
$generatedAt = (Get-Date).ToString('s')

$verifiableRuleItems = New-Object System.Collections.Generic.List[object]
foreach ($diagnosis in @($diagnoses.ToArray())) {
    $machineGate = [string]$diagnosis.machine_gate
    if ([string]::IsNullOrWhiteSpace($machineGate)) {
        $machineGate = 'blocker_classification_required'
    }
    $safeGate = $machineGate -replace '[^a-zA-Z0-9_\-]', '_'
    $fingerprint = [string]$diagnosis.blocker
    $verifiableRuleItems.Add([pscustomobject][ordered]@{
        id = "rule_$safeGate"
        fingerprint = $fingerprint
        severity = [string]$diagnosis.severity
        owner_layer = [string]$diagnosis.root_cause_layer
        trigger = [ordered]@{
            fingerprint = $fingerprint
            repeated = [bool]$diagnosis.repeated
            replay_count = [int]$diagnosis.replay_count
        }
        must_fix = @($mustFix.ToArray()) -contains $fingerprint
        prevention_gate = [string]$diagnosis.prevention_gate
        required_fix = [string]$diagnosis.required_fix
        regression_test = [string]$diagnosis.regression_test
        next_validation = [string]$diagnosis.next_validation
        machine_gate = $machineGate
        acceptance = @(
            "Invoked runner, prompt, verifier, schema, or gate change addresses machine_gate=$machineGate.",
            "Regression evidence is present and PASS for: $($diagnosis.regression_test)",
            "Next validation evidence is present and PASS for: $($diagnosis.next_validation)"
        )
        verification_status = 'PENDING'
    }) | Out-Null
}

$verifiableRulePack = [ordered]@{
    schema = 'replay_verifiable_rule_pack.v1'
    generated_at = $generatedAt
    replay_root = $root
    evidence_root = $evidenceRootFull
    source_audit_pack = $jsonPath
    rules = @($verifiableRuleItems.ToArray())
}

$audit = [ordered]@{
    schema = 'failure_audit_pack.v1'
    generated_at = $generatedAt
    replay_root = $root
    evidence_root = $evidenceRootFull
    feature = $feature
    verification_capped_coverage = $latestCap
    oracle_adjusted_coverage = $latestOracle
    fingerprints = @($fingerprints.ToArray())
    repeated_blockers = @($repeated.ToArray())
    must_fix_before_next_replay = @($mustFix.ToArray())
    golden_first_slice_required = $goldenRequired
    diagnoses = @($diagnoses.ToArray())
    verifiable_rules_path = $verifiableRulesPath
    verifiable_rules_md_path = $verifiableRulesMdPath
    verifiable_rule_count = $verifiableRuleItems.Count
    operating_rule = 'If must_fix_before_next_replay is non-empty, the next unattended cycle must not continue until evolution addresses these blockers with invoked tooling/prompt/verifier changes and regression evidence.'
}

$audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$verifiableRulePack | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $verifiableRulesPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Failure Audit Pack') | Out-Null
$md.Add('') | Out-Null
$md.Add("- generated_at: $($audit.generated_at)") | Out-Null
$md.Add("- replay_root: $root") | Out-Null
$md.Add("- feature: $(Convert-ToMarkdownCell $feature)") | Out-Null
$md.Add("- verification_capped_coverage: $(Convert-ToMarkdownCell $latestCap)") | Out-Null
$md.Add("- oracle_adjusted_coverage: $(Convert-ToMarkdownCell $latestOracle)") | Out-Null
$md.Add("- golden_first_slice_required: $goldenRequired") | Out-Null
$md.Add("- must_fix_before_next_replay: $(@($mustFix.ToArray()) -join ', ')") | Out-Null
$md.Add('') | Out-Null
$md.Add('## Diagnosis Table') | Out-Null
$md.Add('') | Out-Null
$md.Add('| Blocker | Count | Layer | Root Cause | Required Fix | Next Validation |') | Out-Null
$md.Add('| --- | ---: | --- | --- | --- | --- |') | Out-Null
foreach ($diagnosis in @($diagnoses.ToArray())) {
    $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f `
        (Convert-ToMarkdownCell $diagnosis.blocker),
        (Convert-ToMarkdownCell $diagnosis.replay_count),
        (Convert-ToMarkdownCell $diagnosis.root_cause_layer),
        (Convert-ToMarkdownCell $diagnosis.root_cause),
        (Convert-ToMarkdownCell $diagnosis.required_fix),
        (Convert-ToMarkdownCell $diagnosis.next_validation))) | Out-Null
}
$md.Add('') | Out-Null
$md.Add('## Verifiable Rule Pack') | Out-Null
$md.Add('') | Out-Null
$md.Add("- json: $verifiableRulesPath") | Out-Null
$md.Add("- md: $verifiableRulesMdPath") | Out-Null
$md.Add('') | Out-Null
$md.Add('| Rule | Machine Gate | Status | Regression Test | Next Validation |') | Out-Null
$md.Add('| --- | --- | --- | --- | --- |') | Out-Null
foreach ($ruleItem in @($verifiableRuleItems.ToArray())) {
    $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f `
        (Convert-ToMarkdownCell $ruleItem.id),
        (Convert-ToMarkdownCell $ruleItem.machine_gate),
        (Convert-ToMarkdownCell $ruleItem.verification_status),
        (Convert-ToMarkdownCell $ruleItem.regression_test),
        (Convert-ToMarkdownCell $ruleItem.next_validation))) | Out-Null
}
$md.Add('') | Out-Null
$md.Add('## Hard Rule') | Out-Null
$md.Add('') | Out-Null
$md.Add('Do not run another blind replay only to rediscover these blockers. First produce a validated evolution that changes an invoked runner, prompt, verifier, schema, or golden-slice gate and proves it with regression evidence.') | Out-Null
Set-Content -LiteralPath $mdPath -Encoding UTF8 -Value ($md -join "`n")

$rulesMd = New-Object System.Collections.Generic.List[string]
$rulesMd.Add('# Verifiable Replay Rules') | Out-Null
$rulesMd.Add('') | Out-Null
$rulesMd.Add("- generated_at: $generatedAt") | Out-Null
$rulesMd.Add("- source_audit_pack: $jsonPath") | Out-Null
$rulesMd.Add('') | Out-Null
$rulesMd.Add('| Rule | Fingerprint | Severity | Machine Gate | Verification Status |') | Out-Null
$rulesMd.Add('| --- | --- | --- | --- | --- |') | Out-Null
foreach ($ruleItem in @($verifiableRuleItems.ToArray())) {
    $rulesMd.Add(('| {0} | {1} | {2} | {3} | {4} |' -f `
        (Convert-ToMarkdownCell $ruleItem.id),
        (Convert-ToMarkdownCell $ruleItem.fingerprint),
        (Convert-ToMarkdownCell $ruleItem.severity),
        (Convert-ToMarkdownCell $ruleItem.machine_gate),
        (Convert-ToMarkdownCell $ruleItem.verification_status))) | Out-Null
}
Set-Content -LiteralPath $verifiableRulesMdPath -Encoding UTF8 -Value ($rulesMd -join "`n")

$controlDir = Join-Path $evidenceRootFull '_control'
if (Test-Path -LiteralPath $controlDir) {
    Copy-Item -LiteralPath $jsonPath -Destination (Join-Path $controlDir 'FAILURE_AUDIT_PACK_LATEST.json') -Force
    Copy-Item -LiteralPath $mdPath -Destination (Join-Path $controlDir 'FAILURE_AUDIT_PACK_LATEST.md') -Force
    Copy-Item -LiteralPath $verifiableRulesPath -Destination (Join-Path $controlDir 'VERIFIABLE_RULES_LATEST.json') -Force
    Copy-Item -LiteralPath $verifiableRulesMdPath -Destination (Join-Path $controlDir 'VERIFIABLE_RULES_LATEST.md') -Force
}

if (-not $Quiet) {
    Write-Host "Failure audit pack written: $mdPath"
}
