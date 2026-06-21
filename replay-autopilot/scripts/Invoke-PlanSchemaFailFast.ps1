# Plan Schema Fail-Fast Checker (Experiment 3 from NEXT_EXPERIMENT_PLAN.md)
# Validates plan schema completeness and rejects plans with missing required fields

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$PlanResultPath = '',
    [string]$Worktree = '',
    [string]$FeatureClassificationPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        return $text | ConvertFrom-Json
    } catch {
        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        if ($start -ge 0 -and $end -gt $start) {
            return $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
        }
        throw
    }
}

function Get-PlanProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-BooleanTrue {
    param($Value)
    if ($Value -is [bool]) { return [bool]$Value }
    return ([string]$Value).Trim().ToLowerInvariant() -eq 'true'
}

function Test-MavenFailureSignal {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }
    if ($Text -match '(?i)\bBUILD FAILURE\b' -or
        $Text -match '(?i)\bCompilation failure\b' -or
        $Text -match '(?i)\bFailed to execute goal\b' -or
        $Text -match '(?i)\bMojoFailureException\b' -or
        $Text -match '(?i)\bMojoExecutionException\b') {
        return $true
    }
    if ($Text -match '(?i)\bBUILD SUCCESS\b') {
        return $false
    }
    return ($Text -match '(?im)^\s*\[ERROR\]')
}

function Test-RequiredValuePresent {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($Value)
    }
    if ($Value -is [System.Array]) {
        return $Value.Count -gt 0
    }
    return $true
}

function Read-FeatureClassification {
    param(
        [string]$ReplayRoot,
        [string]$Path
    )

    $candidate = $Path
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = Join-Path $ReplayRoot 'FEATURE_CLASSIFICATION.json'
    }
    return Read-JsonObject -Path $candidate
}

function Test-NarrowBackendReadOnlyFeature {
    param($FeatureClassification)

    if ($null -eq $FeatureClassification) { return $false }
    $classification = [string](Get-PlanProperty -Object $FeatureClassification -Name 'classification')
    $baseClassification = [string](Get-PlanProperty -Object $FeatureClassification -Name 'base_classification')
    $readOnlyValue = Get-PlanProperty -Object $FeatureClassification -Name 'read_only'
    $readOnly = $false
    if ($readOnlyValue -is [bool]) {
        $readOnly = [bool]$readOnlyValue
    } elseif ($null -ne $readOnlyValue) {
        $readOnly = ([string]$readOnlyValue).Trim().ToLowerInvariant() -eq 'true'
    }

    $statefulRequired = $true
    $adjustments = Get-PlanProperty -Object $FeatureClassification -Name 'verifier_adjustments'
    if ($null -ne $adjustments) {
        $statefulValue = Get-PlanProperty -Object $adjustments -Name 'stateful_side_effect_required'
        if ($statefulValue -is [bool]) {
            $statefulRequired = [bool]$statefulValue
        } elseif ($null -ne $statefulValue) {
            $statefulRequired = ([string]$statefulValue).Trim().ToLowerInvariant() -eq 'true'
        }
    }

    return (
        $readOnly -and
        -not $statefulRequired -and
        ($classification -eq 'narrow_backend_read_only_fix' -or $baseClassification -eq 'narrow_backend_fix')
    )
}

function Get-SideEffectSchemaIssues {
    param(
        $Value,
        [switch]$AllowReadOnlyMemoryShape,
        [switch]$StatefulSideEffectNotRequired
    )

    if ($StatefulSideEffectNotRequired -and $null -eq $Value) {
        return @()
    }

    $issues = @()
    if ($null -eq $Value) {
        return @('side_effects missing')
    }

    $items = @($Value)
    if ($items.Count -eq 0) {
        return @('side_effects empty')
    }

    $index = 0
    foreach ($item in $items) {
        $index++
        if ($null -eq $item) {
            $issues += "side_effects[$index] null"
            continue
        }
        if ($item -is [string]) {
            if ([string]::IsNullOrWhiteSpace($item)) {
                $issues += "side_effects[$index] blank"
            }
            continue
        }

        $effect = [string](Get-PlanProperty -Object $item -Name 'side_effect')
        $state = [string](Get-PlanProperty -Object $item -Name 'state')
        $proof = [string](Get-PlanProperty -Object $item -Name 'proof')
        $description = [string](Get-PlanProperty -Object $item -Name 'description')
        $type = [string](Get-PlanProperty -Object $item -Name 'type')
        $memory = [string](Get-PlanProperty -Object $item -Name 'memory')
        $source = [string](Get-PlanProperty -Object $item -Name 'source')
        $target = [string](Get-PlanProperty -Object $item -Name 'target')
        $operation = [string](Get-PlanProperty -Object $item -Name 'operation')
        $value = [string](Get-PlanProperty -Object $item -Name 'value')
        $hasStrictShape = (-not [string]::IsNullOrWhiteSpace($effect) -and -not [string]::IsNullOrWhiteSpace($state) -and -not [string]::IsNullOrWhiteSpace($proof))
        $hasCompactShape = (-not [string]::IsNullOrWhiteSpace($description) -and -not [string]::IsNullOrWhiteSpace($type))
        $hasReadOnlyMemoryShape = (
            [bool]$AllowReadOnlyMemoryShape -and
            -not [string]::IsNullOrWhiteSpace($operation) -and
            (
                -not [string]::IsNullOrWhiteSpace($memory) -or
                -not [string]::IsNullOrWhiteSpace($target)
            ) -and
            (
                -not [string]::IsNullOrWhiteSpace($value) -or
                -not [string]::IsNullOrWhiteSpace($source)
            )
        )
        if (-not ($hasStrictShape -or $hasCompactShape -or $hasReadOnlyMemoryShape)) {
            $issues += "side_effects[$index] object must include non-empty side_effect/state/proof or type/description"
        }
    }
    return @($issues)
}

function Test-PolicyRebuildPlan {
    param([string]$PlanText)
    if ([string]::IsNullOrWhiteSpace($PlanText)) { return $false }
    $hasPolicyNum = $PlanText -match '(?i)(policyNum|policy_num)'
    $hasInsureNum = $PlanText -match '(?i)(insureNum|insure_num)'
    $hasRebuildBoundary = $PlanText -match '(?i)(rebuildTaskData|RequestBuildFunction|RequestBuildContext|AiClaimDataAssemblyHelper)'
    return ($hasPolicyNum -and $hasInsureNum -and $hasRebuildBoundary)
}

function Test-PathInsideRoot {
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $rootFull += [System.IO.Path]::DirectorySeparatorChar
    }
    return $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ReplayEvidencePath {
    param([string]$Path, [string]$ReplayRoot)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $cleanPath = $Path.Trim().Trim('`').Trim('"').Trim("'")
    if ([System.IO.Path]::IsPathRooted($cleanPath)) {
        return [System.IO.Path]::GetFullPath($cleanPath)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $ReplayRoot $cleanPath))
}

function Get-TestInfrastructureRealityIssues {
    param(
        $Infra,
        [string]$Worktree,
        [string]$ReplayRoot
    )

    $issues = @()
    $moduleName = [string](Get-PlanProperty -Object $Infra -Name 'test_module_for_target')
    $dryRunCommand = [string](Get-PlanProperty -Object $Infra -Name 'compilation_dry_run_command')
    $evidenceFile = [string](Get-PlanProperty -Object $Infra -Name 'compilation_dry_run_evidence_file')

    if ([string]::IsNullOrWhiteSpace($moduleName)) {
        $issues += 'test_infrastructure_check.test_module_for_target empty'
    }

    if ([string]::IsNullOrWhiteSpace($dryRunCommand)) {
        $issues += 'test_infrastructure_check.compilation_dry_run_command missing'
    } else {
        $commandText = $dryRunCommand.Trim().ToLowerInvariant()
        if ($commandText -notmatch '(^|\s)mvn(\.cmd|\.bat)?(\s|$)') {
            $issues += 'test_infrastructure_check.compilation_dry_run_command must invoke mvn'
        }
        if (-not $commandText.Contains('test-compile')) {
            $issues += 'test_infrastructure_check.compilation_dry_run_command must run test-compile'
        }
        if (-not $commandText.Contains('-am')) {
            $issues += 'test_infrastructure_check.compilation_dry_run_command must include -am'
        }
        if (-not $commandText.Contains('-pl')) {
            $issues += 'test_infrastructure_check.compilation_dry_run_command must include -pl'
        }
        if (-not [string]::IsNullOrWhiteSpace($moduleName) -and -not $commandText.Contains($moduleName.ToLowerInvariant())) {
            $issues += "test_infrastructure_check.compilation_dry_run_command must target module $moduleName"
        }
        $normalizedCommand = $commandText.Replace('/', '\')
        if ($normalizedCommand.Contains('d:\opt\lipei\claim\pom.xml')) {
            $issues += 'test_infrastructure_check.compilation_dry_run_command must not target protected project root pom'
        }
        if (-not [string]::IsNullOrWhiteSpace($Worktree)) {
            $worktreePom = ([System.IO.Path]::GetFullPath((Join-Path $Worktree 'pom.xml'))).ToLowerInvariant().Replace('/', '\')
            $usesWorktreePlaceholder = ($normalizedCommand.Contains('<worktree>\pom.xml') -or $normalizedCommand.Contains('{{worktree}}\pom.xml') -or $normalizedCommand.Contains('$worktree\pom.xml'))
            if (-not ($normalizedCommand.Contains($worktreePom) -or $usesWorktreePlaceholder)) {
                $issues += 'test_infrastructure_check.compilation_dry_run_command must target isolated worktree root pom'
            }
        }
    }

    $worktreeExists = -not [string]::IsNullOrWhiteSpace($Worktree) -and (Test-Path -LiteralPath $Worktree)
    if ($worktreeExists -and -not [string]::IsNullOrWhiteSpace($moduleName)) {
        $modulePath = Join-Path $Worktree $moduleName
        if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
            $issues += "test_module_missing:$moduleName"
        } else {
            if (-not (Test-Path -LiteralPath (Join-Path $modulePath 'pom.xml') -PathType Leaf)) {
                $issues += "test_module_pom_missing:$moduleName"
            }
            $srcTestPath = Join-Path $modulePath 'src\test'
            if (-not (Test-Path -LiteralPath $srcTestPath -PathType Container)) {
                $issues += "test_module_missing_src_test:$moduleName"
            } else {
                $testSource = Get-ChildItem -LiteralPath $srcTestPath -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $testSource) {
                    $issues += "test_module_has_no_test_sources:$moduleName"
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($evidenceFile)) {
        $issues += 'test_infrastructure_check.compilation_dry_run_evidence_file missing'
    } else {
        $evidencePath = Resolve-ReplayEvidencePath -Path $evidenceFile -ReplayRoot $ReplayRoot
        if (-not (Test-PathInsideRoot -Path $evidencePath -Root $ReplayRoot)) {
            $issues += 'test_infrastructure_check.compilation_dry_run_evidence_file must be under replay root'
        } elseif (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            $issues += "compilation_dry_run_evidence_file_not_found:$evidenceFile"
        } else {
            $evidenceText = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8
            $evidenceExitCode = $null
            $evidenceCommand = ''
            try {
                $evidenceJson = $evidenceText | ConvertFrom-Json
                $exitProperty = $evidenceJson.PSObject.Properties['exit_code']
                if ($null -ne $exitProperty) {
                    $evidenceExitCode = [string]$exitProperty.Value
                }
                $commandProperty = $evidenceJson.PSObject.Properties['command']
                if ($null -ne $commandProperty) {
                    $evidenceCommand = [string]$commandProperty.Value
                }
            } catch { }

            if ($null -ne $evidenceExitCode -and $evidenceExitCode.Trim() -match '^-?\d+$' -and [int]$evidenceExitCode -ne 0) {
                $issues += "compilation_dry_run_evidence_exit_code:$evidenceExitCode"
            }
            if (-not [string]::IsNullOrWhiteSpace($evidenceCommand)) {
                $evidenceCommandText = $evidenceCommand.ToLowerInvariant()
                if (-not [string]::IsNullOrWhiteSpace($moduleName) -and -not $evidenceCommandText.Contains($moduleName.ToLowerInvariant())) {
                    $issues += "compilation_dry_run_evidence_command_wrong_module:$moduleName"
                }
                if (-not $evidenceCommandText.Contains('-am') -or -not $evidenceCommandText.Contains('-pl') -or -not $evidenceCommandText.Contains('test-compile')) {
                    $issues += 'compilation_dry_run_evidence_command_incomplete'
                }
                if ($evidenceCommandText.Replace('/', '\').Contains('d:\opt\lipei\claim\pom.xml')) {
                    $issues += 'compilation_dry_run_evidence_command_must_not_target_protected_root_pom'
                }
            }
            if (Test-MavenFailureSignal -Text $evidenceText) {
                $issues += 'compilation_dry_run_evidence_contains_failure_signal'
            }
            if ($evidenceText -notmatch '(?i)BUILD SUCCESS' -and $evidenceText -notmatch '"exit_code"\s*:\s*0') {
                $issues += 'compilation_dry_run_evidence_missing_success_signal'
            }
        }
    }

    return @($issues)
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = ''
if (-not [string]::IsNullOrWhiteSpace($Worktree)) {
    $worktreeFull = Resolve-AbsolutePath $Worktree
} else {
    $candidateWorktree = Join-Path $replayRootFull 'worktree'
    if (Test-Path -LiteralPath $candidateWorktree) {
        $worktreeFull = Resolve-AbsolutePath $candidateWorktree
    }
}

# Determine plan result path
if ([string]::IsNullOrWhiteSpace($PlanResultPath)) {
    $possiblePaths = @(
        (Join-Path $replayRootFull 'PLAN_RESULT.json'),
        (Join-Path $replayRootFull 'PLAN.json'),
        (Join-Path $replayRootFull 'REPLAY_PLAN.md')
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path -LiteralPath $path) {
            $PlanResultPath = $path
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($PlanResultPath) -or -not (Test-Path -LiteralPath $PlanResultPath)) {
    $result = [ordered]@{
        stage = 'PlanSchemaFailFast'
        status = 'FAIL'
        error = 'Plan file not found'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'PLAN_SCHEMA_FAILFAST.json') -Encoding UTF8
    exit 1
}

$planTextRaw = Get-Content -LiteralPath $PlanResultPath -Raw -Encoding UTF8
$plan = Read-JsonObject -Path $PlanResultPath
$featureClassification = Read-FeatureClassification -ReplayRoot $replayRootFull -Path $FeatureClassificationPath
$narrowBackendReadOnlyFeature = Test-NarrowBackendReadOnlyFeature -FeatureClassification $featureClassification

if ($null -eq $plan) {
    $result = [ordered]@{
        stage = 'PlanSchemaFailFast'
        status = 'FAIL'
        error = 'Plan is null or invalid JSON'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'PLAN_SCHEMA_FAILFAST.json') -Encoding UTF8
    exit 1
}

$missingFields = @()
$placeholderFields = @()
$emptyArrayFields = @()
$testInfrastructureIssues = @()
$sideEffectIssues = @()

$planStatus = ''
if ($plan.PSObject.Properties.Name -contains 'plan_status') {
    $planStatus = ([string]$plan.plan_status).Trim().ToUpperInvariant()
} elseif ($plan.PSObject.Properties.Name -contains 'status') {
    $planStatus = ([string]$plan.status).Trim().ToUpperInvariant()
}

if ([string]::IsNullOrWhiteSpace($planStatus)) {
    $missingFields += 'plan_status'
}

# Required fields with no placeholders allowed. PROCEED plans must be executable;
# blocked plans must explain the blocker instead of inventing carriers.
$requiredFields = [ordered]@{}
$arrayFields = @()
if ($planStatus -eq 'PROCEED') {
    $requiredFields = [ordered]@{
        'plan_status' = $true
        'target_carrier_file_path' = $true
        'target_carrier_line_number' = $true
        'expected_test_class' = $true
        'expected_test_method' = $true
        'test_infrastructure_check' = $true
    }
    if (-not $narrowBackendReadOnlyFeature) {
        $requiredFields['side_effects'] = $true
        $arrayFields = @('side_effects', 'expected_assertions')
    } else {
        $arrayFields = @('expected_assertions')
    }
} elseif (@('BLOCKED', 'INVALID_PLAN') -contains $planStatus) {
    $requiredFields = [ordered]@{
        'plan_status' = $true
    }
    if ($planStatus -eq 'BLOCKED') {
        $requiredFields['blocker'] = $true
    } else {
        $requiredFields['invalid_reason'] = $true
    }
} elseif (-not [string]::IsNullOrWhiteSpace($planStatus)) {
    $missingFields += "valid_plan_status:$planStatus"
}

foreach ($field in $requiredFields.Keys) {
    if (-not ($plan.PSObject.Properties.Name -contains $field)) {
        $missingFields += $field
    } else {
        $value = $plan.$field
        if (-not (Test-RequiredValuePresent $value)) {
            $missingFields += $field
        } elseif ($value -is [string] -and ($value -eq 'TBD' -or $value -eq 'NEW' -or $value -eq 'unknown' -or $value -eq 'UNKNOWN')) {
            $placeholderFields += "$field (value: $value)"
        }
    }
}

foreach ($field in $arrayFields) {
    if ($plan.PSObject.Properties.Name -contains $field) {
        $value = $plan.$field
        if ($null -ne $value -and $value -is [System.Array]) {
            if ($value.Count -eq 0) {
                $emptyArrayFields += $field
            }
        } elseif ($null -eq $value) {
            $emptyArrayFields += $field
        }
    }
}

if ($planStatus -eq 'PROCEED') {
    $sideEffectIssues += Get-SideEffectSchemaIssues `
        -Value (Get-PlanProperty -Object $plan -Name 'side_effects') `
        -AllowReadOnlyMemoryShape:$narrowBackendReadOnlyFeature `
        -StatefulSideEffectNotRequired:$narrowBackendReadOnlyFeature

    $infra = Get-PlanProperty -Object $plan -Name 'test_infrastructure_check'
    if ($null -eq $infra) {
        $testInfrastructureIssues += 'test_infrastructure_check_missing'
    } else {
        foreach ($field in @(
                'test_module_for_target',
                'test_module_has_dependencies',
                'test_harness_available',
                'can_import_production_classes',
                'compilation_dry_run_exit_code',
                'compilation_dry_run_command',
                'compilation_dry_run_evidence_file',
                'blocker_reason'
            )) {
            if ($null -eq (Get-PlanProperty -Object $infra -Name $field)) {
                $testInfrastructureIssues += "test_infrastructure_check.$field missing"
            }
        }

        foreach ($booleanField in @('test_module_has_dependencies', 'test_harness_available', 'can_import_production_classes')) {
            $value = Get-PlanProperty -Object $infra -Name $booleanField
            if ($null -ne $value -and -not (Test-BooleanTrue $value)) {
                $testInfrastructureIssues += "test_infrastructure_check.$booleanField must be true for PROCEED"
            }
        }

        $exitValue = Get-PlanProperty -Object $infra -Name 'compilation_dry_run_exit_code'
        if ($null -ne $exitValue) {
            $exitText = ([string]$exitValue).Trim()
            if ($exitText -notmatch '^-?\d+$') {
                $testInfrastructureIssues += 'test_infrastructure_check.compilation_dry_run_exit_code must be integer'
            } elseif ([int]$exitText -ne 0) {
                $testInfrastructureIssues += "test_infrastructure_check.compilation_dry_run_exit_code must be 0 for PROCEED (actual: $exitText)"
            }
        }

        $blockerReason = [string](Get-PlanProperty -Object $infra -Name 'blocker_reason')
        if (-not [string]::IsNullOrWhiteSpace($blockerReason) -and $blockerReason.Trim() -notmatch '^(?i:none|no_blocker|not_blocked)$') {
            $testInfrastructureIssues += "test_infrastructure_check.blocker_reason must be empty/none for PROCEED (actual: $blockerReason)"
        }

        $testInfrastructureIssues += Get-TestInfrastructureRealityIssues -Infra $infra -Worktree $worktreeFull -ReplayRoot $replayRootFull

        if (Test-PolicyRebuildPlan -PlanText $planTextRaw) {
            $policyModule = [string](Get-PlanProperty -Object $infra -Name 'test_module_for_target')
            $policyDryRunCommand = [string](Get-PlanProperty -Object $infra -Name 'compilation_dry_run_command')
            $policyExpectedTestClass = [string](Get-PlanProperty -Object $plan -Name 'expected_test_class')
            $policyBlockerReason = [string](Get-PlanProperty -Object $infra -Name 'blocker_reason')

            if ($policyModule.Trim().ToLowerInvariant() -ne 'claim-server') {
                $testInfrastructureIssues += 'policy_rebuild_test_module_must_be_claim_server'
            }
            if ($policyExpectedTestClass -match '(?i)claim-core[\\/]+src[\\/]+test' -or ($policyModule.Trim().ToLowerInvariant() -ne 'claim-server' -and $policyExpectedTestClass -notmatch '(?i)(claim-server[\\/]+src[\\/]+test|com\.huize\.claim\.test)')) {
                $testInfrastructureIssues += 'policy_rebuild_expected_test_class_must_use_claim_server_harness'
            }
            $policyCommandText = $policyDryRunCommand.ToLowerInvariant()
            if (-not ($policyCommandText.Contains('-pl claim-server') -and $policyCommandText.Contains('-am') -and $policyCommandText.Contains('test-compile'))) {
                $testInfrastructureIssues += 'policy_rebuild_compile_dry_run_must_use_claim_server_am_test_compile'
            }
            if ($planTextRaw -match '(?i)\b(manual\s+(verification|check|inspection|code\s+inspection)|code\s+inspection)\b' -or $policyBlockerReason -match '(?i)manual|inspection') {
                $testInfrastructureIssues += 'manual_verification_not_allowed_for_proceed'
            }
        }
    }
}

$overallStatus = 'PASS'
$issues = @()

if ($missingFields.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Missing required fields: $($missingFields -join ', ')"
}

if ($placeholderFields.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Placeholder values found: $($placeholderFields -join ', ')"
}

if ($emptyArrayFields.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Empty arrays found: $($emptyArrayFields -join ', ')"
}

if ($testInfrastructureIssues.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Test infrastructure check failed: $($testInfrastructureIssues -join ', ')"
}

if ($sideEffectIssues.Count -gt 0) {
    $overallStatus = 'FAIL'
    $issues += "Side effects schema failed: $($sideEffectIssues -join ', ')"
}

# Build result
$result = [ordered]@{
    stage = 'PlanSchemaFailFast'
    status = $overallStatus
    required = $true
    can_proceed = ($overallStatus -eq 'PASS')
    checks = [ordered]@{
        plan_status = $planStatus
        valid_plan_status = (@('PROCEED', 'BLOCKED', 'INVALID_PLAN') -contains $planStatus)
        all_required_fields_present = ($missingFields.Count -eq 0)
        missing_fields = @($missingFields)
        no_placeholder_values = ($placeholderFields.Count -eq 0)
        placeholder_fields = @($placeholderFields)
        required_arrays_populated = ($emptyArrayFields.Count -eq 0)
        empty_array_fields = @($emptyArrayFields)
        test_infrastructure_check_present = ($null -ne (Get-PlanProperty -Object $plan -Name 'test_infrastructure_check'))
        test_infrastructure_check_valid = ($testInfrastructureIssues.Count -eq 0)
        test_infrastructure_issues = @($testInfrastructureIssues)
        side_effects_valid = ($sideEffectIssues.Count -eq 0)
        side_effect_issues = @($sideEffectIssues)
        feature_classification = if ($featureClassification) { [string](Get-PlanProperty -Object $featureClassification -Name 'classification') } else { '' }
        stateful_side_effect_required = (-not $narrowBackendReadOnlyFeature)
        side_effect_schema_mode = if ($narrowBackendReadOnlyFeature) { 'read_only_memory_or_not_required' } else { 'stateful_required' }
        worktree = $worktreeFull
    }
    issues = @($issues)
    timestamp = (Get-Date -Format 'o')
}

$outputPath = Join-Path $replayRootFull 'PLAN_SCHEMA_FAILFAST.json'
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

if ($overallStatus -ne 'PASS') {
    Write-Host "PLAN_SCHEMA_INCOMPLETE: $($issues -join '; ')" -ForegroundColor Red
    exit 1
}

Write-Host "PLAN_SCHEMA_COMPLETE: All required fields present with valid values" -ForegroundColor Green
exit 0
