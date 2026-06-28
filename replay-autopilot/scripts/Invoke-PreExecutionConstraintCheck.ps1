# Pre-Execution Constraint Check (v466 enhanced)
# This script validates all constraints before Phase1 executor starts

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$PlanResultPath,
    [string]$BaselineRoot = '',
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

function Get-NonEmptyPlanValue {
    param(
        [object]$Plan,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Plan.PSObject.Properties.Name -contains $name) {
            $value = [string]$Plan.$name
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value.Trim()
            }
        }
    }
    return $null
}

function Get-ObjectPropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-KeyValueField {
    param([string]$Text, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Field)) {
        return ''
    }
    $escapedField = [regex]::Escape($Field)
    $patterns = @(
        ('(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'),
        ('(?im)^\s*\|\s*\*{0,2}\s*' + $escapedField + '\s*\*{0,2}\s*\|\s*`?([^|\r\n]+?)`?\s*\|')
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ''
}

function Get-TestCharterSurfaceDetection {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $labelPrefix = '(?im)^\s*(?:[-*]\s*)?(?:#{1,6}\s*)?(?:\*{0,2})\s*'
    $labelSuffix = '\s*(?:\*{0,2})\s*[:=]\s*\S'
    $patterns = [ordered]@{
        test_surface_label = $labelPrefix + 'test[_\s-]*surface' + $labelSuffix
        entry_point_label = $labelPrefix + 'entry[_\s-]*point' + $labelSuffix
        test_class_label = $labelPrefix + 'test[_\s-]*class' + $labelSuffix
        test_method_label = $labelPrefix + 'test[_\s-]*method' + $labelSuffix
        test_scenario_label = $labelPrefix + 'test[_\s-]*scenario' + $labelSuffix
        red_test_label = '(?im)^\s*(?:[-*]\s*)?(?:#{1,6}\s*)?(?:RED\s+)?Test\s*:\s*\S'
        class_label = '(?im)^\s*(?:[-*]\s*)?(?:#{1,6}\s*)?Class\s*:\s*\S'
    }

    foreach ($name in $patterns.Keys) {
        if ($Text -match $patterns[$name]) {
            return $name
        }
    }
    return ''
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
    $classification = [string](Get-ObjectPropertyValue -Object $FeatureClassification -Name 'classification')
    $baseClassification = [string](Get-ObjectPropertyValue -Object $FeatureClassification -Name 'base_classification')
    $readOnlyValue = Get-ObjectPropertyValue -Object $FeatureClassification -Name 'read_only'
    $readOnly = $false
    if ($readOnlyValue -is [bool]) {
        $readOnly = [bool]$readOnlyValue
    } elseif ($null -ne $readOnlyValue) {
        $readOnly = ([string]$readOnlyValue).Trim().ToLowerInvariant() -eq 'true'
    }

    $statefulRequired = $true
    $adjustments = Get-ObjectPropertyValue -Object $FeatureClassification -Name 'verifier_adjustments'
    if ($null -ne $adjustments) {
        $statefulValue = Get-ObjectPropertyValue -Object $adjustments -Name 'stateful_side_effect_required'
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

function Test-ReplayAutopilotPowerShellHarness {
    param(
        [string]$ModuleName,
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($ModuleName) -or [string]::IsNullOrWhiteSpace($Command)) {
        return $false
    }

    $moduleNorm = $ModuleName.Replace('/', '\').Trim('\').ToLowerInvariant()
    if ($moduleNorm -ne 'replay-autopilot\scripts\tests') {
        return $false
    }

    $commandNorm = $Command.Replace('/', '\').ToLowerInvariant()
    return (
        $commandNorm -match '(^|\s)(powershell|pwsh)(\.exe)?(\s|$)' -and
        $commandNorm -match '(\s|^)-file(\s|$)' -and
        $commandNorm -match 'replay-autopilot\\scripts\\tests\\test-v\d+-.+\.ps1'
    )
}

function Get-TestInfrastructureRealityIssues {
    param(
        $Infra,
        [string]$Worktree,
        [string]$ReplayRoot
    )

    $issues = @()
    $moduleName = [string](Get-ObjectPropertyValue -Object $Infra -Name 'test_module_for_target')
    $dryRunCommand = [string](Get-ObjectPropertyValue -Object $Infra -Name 'compilation_dry_run_command')
    $evidenceFile = [string](Get-ObjectPropertyValue -Object $Infra -Name 'compilation_dry_run_evidence_file')

    if ([string]::IsNullOrWhiteSpace($moduleName)) {
        $issues += 'test_infrastructure_check.test_module_for_target empty'
    }

    $isControlPlaneHarness = Test-ReplayAutopilotPowerShellHarness -ModuleName $moduleName -Command $dryRunCommand

    if ([string]::IsNullOrWhiteSpace($dryRunCommand)) {
        $issues += 'test_infrastructure_check.compilation_dry_run_command missing'
    } elseif (-not $isControlPlaneHarness) {
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
        if (-not [string]::IsNullOrWhiteSpace($Worktree) -and
            $normalizedCommand -match '(?i)-f[= ]\s*([a-z]:\\[^"]+)') {
            $targetPom = $matches[1].Trim('"', "'", '`')
            $worktreeNorm = $Worktree.Replace('/', '\').ToLowerInvariant()
            if (-not $targetPom.ToLowerInvariant().StartsWith($worktreeNorm)) {
                $issues += 'test_infrastructure_check.compilation_dry_run_command must target isolated worktree pom'
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($Worktree)) {
            $worktreePom = ([System.IO.Path]::GetFullPath((Join-Path $Worktree 'pom.xml'))).ToLowerInvariant().Replace('/', '\')
            $usesWorktreePlaceholder = ($normalizedCommand.Contains('<worktree>\pom.xml') -or $normalizedCommand.Contains('{{worktree}}\pom.xml') -or $normalizedCommand.Contains('$worktree\pom.xml'))
            if (-not ($normalizedCommand.Contains($worktreePom) -or $usesWorktreePlaceholder)) {
                $issues += 'test_infrastructure_check.compilation_dry_run_command must target isolated worktree root pom'
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Worktree) -and (Test-Path -LiteralPath $Worktree) -and -not [string]::IsNullOrWhiteSpace($moduleName)) {
        $modulePath = Join-Path $Worktree $moduleName
        if ($isControlPlaneHarness -and -not (Test-Path -LiteralPath $modulePath -PathType Container)) {
            $modulePath = Join-Path $Worktree 'replay-autopilot\scripts\tests'
        }
        if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
            $issues += "test_module_missing:$moduleName"
        } elseif ($isControlPlaneHarness) {
            $testSource = Get-ChildItem -LiteralPath $modulePath -Filter 'Test-v*.ps1' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $testSource) {
                $issues += "test_module_has_no_powershell_tests:$moduleName"
            }
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
                $evidenceCommandNorm = $evidenceCommandText.Replace('/', '\')
                $moduleNameNorm = $moduleName.ToLowerInvariant().Replace('/', '\')
                $isEvidenceControlPlaneHarness = Test-ReplayAutopilotPowerShellHarness -ModuleName $moduleName -Command $evidenceCommand
                if (-not [string]::IsNullOrWhiteSpace($moduleName) -and -not $evidenceCommandNorm.Contains($moduleNameNorm)) {
                    $issues += "compilation_dry_run_evidence_command_wrong_module:$moduleName"
                }
                if (-not $isEvidenceControlPlaneHarness -and (-not $evidenceCommandText.Contains('-am') -or -not $evidenceCommandText.Contains('-pl') -or -not $evidenceCommandText.Contains('test-compile'))) {
                    $issues += 'compilation_dry_run_evidence_command_incomplete'
                }
                if (-not [string]::IsNullOrWhiteSpace($Worktree) -and
                    $evidenceCommandText -match '(?i)-f[= ]\s*([a-z]:\\[^"]+)') {
                    $evidencePom = $matches[1].Trim('"', "'", '`')
                    $worktreeNorm = $Worktree.Replace('/', '\').ToLowerInvariant()
                    if (-not $evidencePom.ToLowerInvariant().StartsWith($worktreeNorm)) {
                        $issues += 'evidence_command_must_not_target_protected_root_pom'
                    }
                }
            }
            if (Test-MavenFailureSignal -Text $evidenceText) {
                $issues += 'compilation_dry_run_evidence_contains_failure_signal'
            }
            if ($evidenceText -notmatch '(?i)BUILD SUCCESS|ALL PASSED|PASS:' -and $evidenceText -notmatch '"exit_code"\s*:\s*0') {
                $issues += 'compilation_dry_run_evidence_missing_success_signal'
            }
        }
    }

    return @($issues)
}

function Get-CarrierClassName {
    param([string]$Carrier)

    if ([string]::IsNullOrWhiteSpace($Carrier)) {
        return ''
    }

    $value = $Carrier.Trim().Trim('`').Trim('"').Trim("'")
    $value = ($value -split '[;,]')[0].Trim()
    if ($value -match '[\\/]|\.java$') {
        $leaf = Split-Path -Leaf $value
        if ($leaf -match '\.java$') {
            return [System.IO.Path]::GetFileNameWithoutExtension($leaf)
        }
    }

    $value = $value -replace '\(.*$', ''
    if ($value -match '#') {
        $value = ($value -split '#')[0]
    }
    if ($value -match '::') {
        $value = ($value -split '::')[0]
    }
    if ($value -match '\.') {
        $parts = @($value -split '\.' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -ge 2 -and $parts[-1] -cmatch '^[a-z_]') {
            return $parts[-2]
        }
        return $parts[-1]
    }
    return $value
}

function Get-EntryCarrierForLayerCheck {
    param(
        [object]$Plan,
        [string]$FirstSliceProofText,
        [string]$FallbackCarrier
    )

    foreach ($field in @('selected_real_entry', 'selected_carrier', 'first_executable_carrier')) {
        $value = Get-KeyValueField -Text $FirstSliceProofText -Field $field
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    $planCarrier = Get-NonEmptyPlanValue -Plan $Plan -Names @('selected_real_entry', 'selected_carrier', 'target_carrier')
    if (-not [string]::IsNullOrWhiteSpace($planCarrier)) {
        return $planCarrier
    }
    return $FallbackCarrier
}

function Find-JavaFileByClassName {
    param(
        [string]$ClassName,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($ClassName) -or
        [string]::IsNullOrWhiteSpace($Root) -or
        -not (Test-Path -LiteralPath $Root -PathType Container)) {
        return ''
    }

    $expectedName = "$ClassName.java"
    $match = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.Equals($expectedName, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1

    if ($null -eq $match) {
        return ''
    }
    return $match.FullName
}

function Test-CarrierInBaseline {
    param(
        [string]$Carrier,
        [string]$Worktree,
        [string]$BaselineRoot
    )
    if ([string]::IsNullOrWhiteSpace($Carrier)) {
        return @{ Exists = $false; Reason = 'Carrier is empty or null' }
    }

    if ($Carrier -match '\.(java|ps1)$') {
        $candidate = if ([System.IO.Path]::IsPathRooted($Carrier)) {
            $Carrier
        } else {
            Join-Path $Worktree $Carrier
        }
        if (Test-Path -LiteralPath $candidate) {
            return @{ Exists = $true; Path = $candidate; Reason = $null }
        }

        if (-not [string]::IsNullOrWhiteSpace($BaselineRoot)) {
            $baselineCandidate = if ([System.IO.Path]::IsPathRooted($Carrier)) {
                $Carrier
            } else {
                Join-Path $BaselineRoot $Carrier
            }
            if (Test-Path -LiteralPath $baselineCandidate) {
                return @{ Exists = $true; Path = $baselineCandidate; Reason = $null }
            }
        }

        if ($Carrier -match '\.ps1$') {
            return @{ Exists = $false; Reason = "Script carrier '$Carrier' not found in baseline or worktree" }
        }
    }

    # Extract simple class name from path, fully qualified name, or method signature.
    $simpleName = Get-CarrierClassName -Carrier $Carrier
    if ([string]::IsNullOrWhiteSpace($simpleName)) {
        return @{ Exists = $false; Reason = "Carrier '$Carrier' did not resolve to a class name" }
    }

    # Search in worktree first
    $rgResult = rg "--type=java" "--fixed-strings" "--files-matching-match" $simpleName $Worktree 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rgResult)) {
        return @{ Exists = $true; Path = $rgResult; Reason = $null }
    }

    # Search in baseline if provided
    if (-not [string]::IsNullOrWhiteSpace($BaselineRoot) -and (Test-Path -LiteralPath $BaselineRoot)) {
        $rgResult = rg "--type=java" "--fixed-strings" "--files-matching-match" $simpleName $BaselineRoot 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rgResult)) {
            return @{ Exists = $true; Path = $rgResult; Reason = $null }
        }
    }

    return @{ Exists = $false; Reason = "Carrier '$Carrier' not found in baseline or worktree" }
}

function Test-ValidLayer {
    param([string]$Carrier, [string]$Worktree)

    if ([string]::IsNullOrWhiteSpace($Carrier)) {
        return @{ Valid = $false; Layer = 'Unknown'; Reason = 'Carrier is empty' }
    }

    $carrierNorm = $Carrier.Replace('/', '\').ToLowerInvariant()
    if ($carrierNorm -match '(^|\\)replay-autopilot\\scripts\\.+\.ps1$') {
        return @{ Valid = $true; Layer = 'ControlPlaneScript'; Reason = $null }
    }

    # Extract class name
    $className = Get-CarrierClassName -Carrier $Carrier

    # Check layer based on naming pattern
    if ($className -match 'Facade$|FacadeImpl$') {
        return @{ Valid = $true; Layer = 'Facade'; Reason = $null }
    }
    if ($className -match 'Controller$|ApiController$|RestController$') {
        return @{ Valid = $true; Layer = 'Controller'; Reason = $null }
    }
    if ($className -match 'Service$') {
        return @{ Valid = $false; Layer = 'Service'; Reason = 'Service layer not valid for core_entry without existing entry point' }
    }
    if ($className -match 'TaskProcessor$') {
        return @{ Valid = $true; Layer = 'TaskProcessor'; Reason = $null }
    }
    if ($className -match 'Task$') {
        return @{ Valid = $false; Layer = 'Task'; Reason = 'Task layer not valid for core_entry' }
    }

    # Try to find file and check package. Avoid invoking rg without a pattern;
    # otherwise PowerShell paths can be interpreted as a malformed regex.
    $filePath = Find-JavaFileByClassName -ClassName $className -Root $Worktree
    if ($filePath) {
        $contentText = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        if ($contentText -match '\s+(public|protected|private)\s+(abstract\s+)?(class|interface)\s+') {
            return @{ Valid = $false; Layer = 'Unknown'; Reason = 'Could not determine layer from naming pattern' }
        }
    }

    return @{ Valid = $false; Layer = 'Unknown'; Reason = 'Layer detection failed' }
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$planResultFull = Resolve-AbsolutePath $PlanResultPath

# Load plan result
$plan = Read-JsonObject -Path $planResultFull
$featureClassification = Read-FeatureClassification -ReplayRoot $replayRootFull -Path $FeatureClassificationPath
$narrowBackendReadOnlyFeature = Test-NarrowBackendReadOnlyFeature -FeatureClassification $featureClassification

if ($null -eq $plan) {
    $result = [ordered]@{
        stage = 'PreExecutionConstraintCheck'
        status = 'FAIL'
        required = $true
        checks = @()
        error = 'PLAN_RESULT not found or invalid'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'PRE_EXECUTION_CONSTRAINT_CHECK.json')
    exit 1
}

$planStatus = ''
if ($plan.PSObject.Properties.Name -contains 'plan_status') {
    $planStatus = ([string]$plan.plan_status).Trim().ToUpperInvariant()
} elseif ($plan.PSObject.Properties.Name -contains 'status') {
    $planStatus = ([string]$plan.status).Trim().ToUpperInvariant()
}

$firstSliceProofPath = Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md'
$firstSliceProofExists = Test-Path -LiteralPath $firstSliceProofPath
$firstSliceProofContent = ''
if ($firstSliceProofExists) {
    $firstSliceProofContent = Get-Content -LiteralPath $firstSliceProofPath -Raw -Encoding UTF8
}

$checks = @()
$overallStatus = 'PASS'

# Check 1: Target implementation carrier exists in baseline/worktree.
# The target file can be a Service/Entity/Mapper implementation file; core_entry
# layer validation is checked separately against the real entry carrier.
$selectedCarrier = Get-NonEmptyPlanValue -Plan $plan -Names @('target_carrier_file_path', 'target_carrier', 'selected_carrier')
$entryCarrierForLayer = Get-EntryCarrierForLayerCheck -Plan $plan -FirstSliceProofText $firstSliceProofContent -FallbackCarrier $selectedCarrier
$carrierExists = Test-CarrierInBaseline -Carrier $selectedCarrier -Worktree $worktreeFull -BaselineRoot $BaselineRoot

$checks += [ordered]@{
    name = 'carrier_exists_in_baseline'
    status = if ($carrierExists.Exists) { 'PASS' } else { 'FAIL' }
    carrier = $selectedCarrier
    reason = if ($carrierExists.Exists) { $null } else { $carrierExists.Reason }
}

if (-not $carrierExists.Exists) {
    $overallStatus = 'FAIL'
}

# Check 2: Real entry carrier is in a valid executable layer.
$layerValid = Test-ValidLayer -Carrier $entryCarrierForLayer -Worktree $worktreeFull

$checks += [ordered]@{
    name = 'carrier_in_valid_layer'
    status = if ($layerValid.Valid) { 'PASS' } else { 'FAIL' }
    carrier = $entryCarrierForLayer
    target_carrier_file_path = $selectedCarrier
    layer = $layerValid.Layer
    reason = if ($layerValid.Valid) { $null } else { $layerValid.Reason }
}

if (-not $layerValid.Valid) {
    $overallStatus = 'FAIL'
}

# Check 3: Plan schema is complete
$requiredFields = @('target_carrier_file_path', 'expected_test_class')
if (-not $narrowBackendReadOnlyFeature) {
    $requiredFields += 'side_effects'
}
$missingFields = @()

foreach ($field in $requiredFields) {
    if (-not $plan.PSObject.Properties.Name -contains $field) {
        $missingFields += $field
    } elseif (-not (Test-RequiredValuePresent $plan.$field) -or ($plan.$field -is [string] -and ($plan.$field -eq 'TBD' -or $plan.$field -eq 'NEW'))) {
        $missingFields += "$field (value: $($plan.$field))"
    }
}

$checks += [ordered]@{
    name = 'plan_schema_complete'
    status = if ($missingFields.Count -eq 0) { 'PASS' } else { 'FAIL' }
    required_fields = $requiredFields
    missing_fields = $missingFields
    feature_classification = if ($featureClassification) { [string](Get-ObjectPropertyValue -Object $featureClassification -Name 'classification') } else { '' }
    stateful_side_effect_required = (-not $narrowBackendReadOnlyFeature)
    side_effect_schema_mode = if ($narrowBackendReadOnlyFeature) { 'read_only_memory_or_not_required' } else { 'stateful_required' }
}

if ($missingFields.Count -gt 0) {
    $overallStatus = 'FAIL'
}

# Check 4: Test module strategy is executable before Phase 1
$infra = Get-ObjectPropertyValue -Object $plan -Name 'test_infrastructure_check'
$infraIssues = @()
if ($planStatus -eq 'PROCEED') {
    if ($null -eq $infra) {
        $infraIssues += 'missing_test_infrastructure_check'
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
            if ($null -eq (Get-ObjectPropertyValue -Object $infra -Name $field)) {
                $infraIssues += "missing:$field"
            }
        }
        foreach ($field in @('test_module_has_dependencies', 'test_harness_available', 'can_import_production_classes')) {
            $value = Get-ObjectPropertyValue -Object $infra -Name $field
            if ($null -ne $value -and -not (Test-BooleanTrue $value)) {
                $infraIssues += "$field=false"
            }
        }
        $exitValue = Get-ObjectPropertyValue -Object $infra -Name 'compilation_dry_run_exit_code'
        if ($null -ne $exitValue) {
            $exitText = ([string]$exitValue).Trim()
            if ($exitText -notmatch '^-?\d+$') {
                $infraIssues += 'compilation_dry_run_exit_code:not_integer'
            } elseif ([int]$exitText -ne 0) {
                $infraIssues += "compilation_dry_run_exit_code:$exitText"
            }
        }
        $blockerReason = [string](Get-ObjectPropertyValue -Object $infra -Name 'blocker_reason')
        if (-not [string]::IsNullOrWhiteSpace($blockerReason) -and $blockerReason.Trim() -notmatch '^(?i:none|no_blocker|not_blocked)$') {
            $infraIssues += "blocker_reason_present:$blockerReason"
        }
        $infraIssues += Get-TestInfrastructureRealityIssues -Infra $infra -Worktree $worktreeFull -ReplayRoot $replayRootFull
    }
}

$checks += [ordered]@{
    name = 'test_infrastructure_check'
    status = if ($infraIssues.Count -eq 0) { 'PASS' } else { 'FAIL' }
    required_for_proceed = $true
    plan_status = $planStatus
    issues = @($infraIssues)
    test_module_for_target = if ($null -ne $infra) { [string](Get-ObjectPropertyValue -Object $infra -Name 'test_module_for_target') } else { '' }
}

if ($infraIssues.Count -gt 0) {
    $overallStatus = 'FAIL'
}

# Check 5: TEST_CHARTER.md exists and is valid
$testCharterPath = Join-Path $replayRootFull 'TEST_CHARTER.md'
$testCharterExists = Test-Path -LiteralPath $testCharterPath

if ($testCharterExists) {
    $testCharterText = Get-Content -LiteralPath $testCharterPath -Raw -Encoding UTF8
    $testSurfaceDetection = Get-TestCharterSurfaceDetection -Text $testCharterText
    $hasTestSurface = -not [string]::IsNullOrWhiteSpace($testSurfaceDetection)
} else {
    $hasTestSurface = $false
    $testCharterText = ''
    $testSurfaceDetection = ''
}

$checks += [ordered]@{
    name = 'test_charter_valid'
    status = if ($testCharterExists -and $hasTestSurface) { 'PASS' } else { 'FAIL' }
    test_charter_exists = $testCharterExists
    has_test_surface = $hasTestSurface
    surface_detection = $testSurfaceDetection
}

if (-not ($testCharterExists -and $hasTestSurface)) {
    $overallStatus = 'FAIL'
}

# Check 6: FIRST_SLICE_PROOF_PLAN.md schema validation (v466)
$firstSliceProofSchemaValid = $false
$firstSliceProofMissingFields = @()

if ($firstSliceProofExists) {
    # Required fields for V457 schema
    $requiredProofFields = @(
        'target_carrier_file_path',
        'target_carrier_line_number',
        'expected_test_class',
        'expected_test_method',
        'expected_assertions',
        'expected_side_effects',
        'minimum_side_effect_or_blocker'
    )

    foreach ($field in $requiredProofFields) {
        # Build pattern without using $ in string to avoid encoding issues
        $patternStart = '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?'
        $patternEnd = '\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
        $fullPattern = $patternStart + [regex]::Escape($field) + $patternEnd
        $match = [regex]::Match($firstSliceProofContent, $fullPattern)

        if (-not $match.Success) {
            $firstSliceProofMissingFields += $field
        } else {
            $value = $match.Groups[1].Value.Trim()
            # Check for placeholder values
            if ($value -match '^(TBD|unknown|UNKNOWN|N/A|placeholder|NONE|none)$') {
                $firstSliceProofMissingFields += "$field (placeholder: $value)"
            }
            # Special check for minimum_side_effect_or_blocker
            if ($field -eq 'minimum_side_effect_or_blocker' -and $value -eq 'PLAN_BLOCKED_REAL_CARRIER') {
                # This is valid blocker value, don't fail
            } elseif ($field -eq 'expected_assertions' -or $field -eq 'expected_side_effects') {
                # Check for JSON array format with minimum items
                try {
                    $arrayValue = $value | ConvertFrom-Json
                    $minItems = if ($field -eq 'expected_assertions') { 3 } else { 1 }
                    if ($arrayValue.Count -lt $minItems) {
                        $firstSliceProofMissingFields += "$field (insufficient items: $($arrayValue.Count)/$minItems)"
                    }
                } catch {
                    $firstSliceProofMissingFields += "$field (invalid JSON format)"
                }
            }
        }
    }

    $firstSliceProofSchemaValid = ($firstSliceProofMissingFields.Count -eq 0)
}

$checks += [ordered]@{
    name = 'first_slice_proof_schema_valid'
    status = if ($firstSliceProofExists -and $firstSliceProofSchemaValid) { 'PASS' } else { 'FAIL' }
    first_slice_proof_exists = $firstSliceProofExists
    schema_valid = $firstSliceProofSchemaValid
    missing_fields = $firstSliceProofMissingFields
}

if (-not ($firstSliceProofExists -and $firstSliceProofSchemaValid)) {
    $overallStatus = 'FAIL'
}

# Check 7: Family-specific layer validation (v466)
# core_entry family requires Facade or Controller layer, not Service
$combinedArtifacts = "$firstSliceProofContent $testCharterContent"
$highestWeightGatePattern = '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?highest_weight_open_gate\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
$highestWeightGateMatch = [regex]::Match($combinedArtifacts, $highestWeightGatePattern)

$isCoreEntryFamily = $false
if ($highestWeightGateMatch.Success) {
    $highestWeightGate = $highestWeightGateMatch.Groups[1].Value.Trim()
    $isCoreEntryFamily = $highestWeightGate -match 'core_entry'
}

$familyLayerValid = $true
$familyLayerReason = $null

if ($isCoreEntryFamily) {
    # Check the real entry carrier, not the supporting implementation target.
    $carrierForLayerCheck = Get-EntryCarrierForLayerCheck -Plan $plan -FirstSliceProofText $combinedArtifacts -FallbackCarrier $selectedCarrier
    if (-not [string]::IsNullOrWhiteSpace($carrierForLayerCheck)) {
        # Extract actual carrier name before any parenthetical notes
        $actualCarrier = $carrierForLayerCheck.Split('(')[0].Trim()

        # Check if it's Service layer without Facade/Controller
        if ($actualCarrier -match 'Service$' -and $actualCarrier -notmatch 'Facade|Controller') {
            $familyLayerValid = $false
            $familyLayerReason = "core_entry family requires Facade/Controller layer, but selected carrier '$actualCarrier' is in Service layer"
        }
    }
}

$checks += [ordered]@{
    name = 'family_layer_validation'
    status = if ($familyLayerValid) { 'PASS' } else { 'FAIL' }
    is_core_entry_family = $isCoreEntryFamily
    layer_valid = $familyLayerValid
    reason = $familyLayerReason
}

if (-not $familyLayerValid) {
    $overallStatus = 'FAIL'
}

# Build result
$result = [ordered]@{
    stage = 'PreExecutionConstraintCheck'
    status = $overallStatus
    required = $true
    can_proceed_to_phase1 = ($overallStatus -eq 'PASS')
    checks = $checks
    selected_carrier = $selectedCarrier
    selected_entry_carrier = $entryCarrierForLayer
    timestamp = (Get-Date -Format 'o')
}

$outputPath = Join-Path $replayRootFull 'PRE_EXECUTION_CONSTRAINT_CHECK.json'
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

if ($overallStatus -ne 'PASS') {
    Write-Host "PRE_EXECUTION_CONSTRAINT_FAIL: $($checks.Where({$_.status -eq 'FAIL'}).Count -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "PRE_EXECUTION_CONSTRAINT_PASS: All constraints satisfied" -ForegroundColor Green
exit 0
