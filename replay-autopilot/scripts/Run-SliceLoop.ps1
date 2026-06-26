param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$FeatureName = 'feature',
    [Parameter(Mandatory = $true)]
    [string]$RequirementSource,
    [Parameter(Mandatory = $true)]
    [string]$OracleBranch,
    [Parameter(Mandatory = $true)]
    [string]$OracleCommit,
    [Parameter(Mandatory = $true)]
    [string]$BaseCommit,
    [Parameter(Mandatory = $true)]
    [string]$BaselineIndex,
    [Parameter(Mandatory = $true)]
    [string]$ContextManifest,
    [string]$SystemContextDir = '',
    [string]$RunLabel = '',
    [string]$RoundId = 'r01',
    [ValidateSet('codex', 'claude', 'manual')]
    [string]$Executor = 'codex',
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$RequireExecutor = '',
    [switch]$AllowCodexExecutor,
    [string]$Model = '',
    [string]$ReasoningEffort = '',
    [string]$Sandbox = 'danger-full-access',
    [string]$Approval = 'never',
    [string]$MavenSettings = '',
    [int]$TimeoutMinutes = 240,
    [int]$MaxSlices = 3,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($RequireExecutor) -and $Executor -ne $RequireExecutor) {
    throw "Executor policy violation: actual executor '$Executor' does not match required executor '$RequireExecutor'."
}
if ($Executor -eq 'codex' -and -not $AllowCodexExecutor) {
    throw "Executor policy violation: Codex executor requires explicit authorization for slice execution. Pass -AllowCodexExecutor for a Codex-primary run."
}

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Expand-Template {
    param([string]$Template, [hashtable]$Values)
    $output = $Template
    foreach ($key in $Values.Keys) {
        $output = $output.Replace('{{' + $key + '}}', [string]$Values[$key])
    }
    return $output
}

function Write-Phase1InitFailure {
    param(
        [string]$ReplayRoot,
        [string]$LogsRoot,
        [string]$RunnerContractPath,
        [string]$ProgressPath,
        [int]$MaxSlices,
        [string]$Reason,
        [string]$EvidencePath = ''
    )

    if (-not (Test-Path -LiteralPath $ReplayRoot -PathType Container)) {
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($LogsRoot)) {
        New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null
    }

    $failurePath = Join-Path $ReplayRoot 'PHASE1_INIT_FAILURE.json'
    $failureMd = Join-Path $ReplayRoot 'PHASE1_INIT_FAILURE.md'
    $payload = [ordered]@{
        schema = 'phase1_init_failure.v1'
        status = 'BLOCKED'
        stage = 'phase1_init'
        reason = $Reason
        evidence_path = $EvidencePath
        replay_root = $ReplayRoot
        logs_root = $LogsRoot
        generated_at = (Get-Date).ToString('s')
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $failurePath -Encoding UTF8
    @(
        '# Phase1 Init Failure',
        '',
        "- status: BLOCKED",
        "- reason: $Reason",
        "- evidence: $EvidencePath",
        "- logs_root: $LogsRoot"
    ) -join "`n" | Set-Content -LiteralPath $failureMd -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($RunnerContractPath)) {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| phase1 init failure | phase1-init | runner_diagnostic | phase1_init_failure | reason={0}; evidence={1}. |" -f (($Reason -replace '\|', '/')), (($EvidencePath -replace '\|', '/')))
    }

    if (-not [string]::IsNullOrWhiteSpace($ProgressPath)) {
        [ordered]@{
            replay_root = $ReplayRoot
            max_slices = $MaxSlices
            completed = @()
            stopped = $true
            stop_reason = "phase1_init_failure:$Reason"
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ProgressPath -Encoding UTF8
    }
}

function Resolve-MavenSettingsPath {
    param([string]$ConfiguredValue)

    $script:ResolvedMavenSettingsSource = 'none'
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredValue)) {
        $candidates += [pscustomobject]@{ Source = 'argument:MavenSettings'; Path = $ConfiguredValue }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:AI_WORKFLOW_MAVEN_SETTINGS)) {
        $candidates += [pscustomobject]@{ Source = 'env:AI_WORKFLOW_MAVEN_SETTINGS'; Path = $env:AI_WORKFLOW_MAVEN_SETTINGS }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:MAVEN_SETTINGS)) {
        $candidates += [pscustomobject]@{ Source = 'env:MAVEN_SETTINGS'; Path = $env:MAVEN_SETTINGS }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates += [pscustomobject]@{ Source = 'userprofile:.m2/settings.xml'; Path = (Join-Path $env:USERPROFILE '.m2\settings.xml') }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:MAVEN_HOME)) {
        $candidates += [pscustomobject]@{ Source = 'env:MAVEN_HOME'; Path = (Join-Path $env:MAVEN_HOME 'conf\settings.xml') }
    }
    $mvnCommand = Get-Command 'mvn.cmd' -ErrorAction SilentlyContinue
    if ($null -eq $mvnCommand) {
        $mvnCommand = Get-Command 'mvn' -ErrorAction SilentlyContinue
    }
    if ($null -ne $mvnCommand) {
        $mavenHome = Split-Path -Parent (Split-Path -Parent $mvnCommand.Source)
        if (-not [string]::IsNullOrWhiteSpace($mavenHome)) {
            $candidates += [pscustomobject]@{ Source = 'maven-home-from-path'; Path = (Join-Path $mavenHome 'conf\settings.xml') }
        }
    }
    foreach ($candidate in $candidates) {
        $pathText = [string]$candidate.Path
        if ([string]::IsNullOrWhiteSpace($pathText)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($pathText)
        } catch {
            continue
        }
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $script:ResolvedMavenSettingsSource = [string]$candidate.Source
            return $full
        }
    }

    return ''
}

function Get-MavenArgumentList {
    param([string]$MavenSettings)
    $args = @()
    if (-not [string]::IsNullOrWhiteSpace($MavenSettings)) {
        $args += @('-s', $MavenSettings)
    }
    $args += @('-Dproject.build.sourceEncoding=UTF-8', '-Dfile.encoding=UTF-8')
    return $args
}

function Get-MavenSettingsCommandSegment {
    param([string]$MavenSettings)
    $args = @(Get-MavenArgumentList -MavenSettings $MavenSettings)
    if ($args.Count -eq 0) { return '' }
    return (($args | ForEach-Object {
        if ($_ -match '\s') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }) -join ' ')
}

function Read-JsonObject {
    param([string]$Path)
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

function Read-JsonIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Read-JsonObject -Path $Path } catch { return $null }
}

function Read-FeatureClassification {
    param([string]$ReplayRoot)
    if ([string]::IsNullOrWhiteSpace($ReplayRoot)) { return $null }
    return Read-JsonIfExists -Path (Join-Path $ReplayRoot 'FEATURE_CLASSIFICATION.json')
}

function Resolve-RunSliceLoopScriptRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:RunSliceLoopScriptRootOverride)) {
        return $script:RunSliceLoopScriptRootOverride
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }
    return (Split-Path -Parent $PSCommandPath)
}

function Test-NarrowBackendReadOnlyFeature {
    param($FeatureClassification)
    if ($null -eq $FeatureClassification) { return $false }
    $classification = [string]$FeatureClassification.classification
    $baseClassification = [string]$FeatureClassification.base_classification
    $readOnly = $false
    if ($FeatureClassification.PSObject.Properties.Name -contains 'read_only') {
        $readOnly = [bool]$FeatureClassification.read_only
    }
    return $readOnly -and (
        $classification -eq 'narrow_backend_read_only_fix' -or
        $baseClassification -eq 'narrow_backend_fix'
    )
}

function Get-FeatureNonApplicableFamilies {
    param($FeatureClassification)
    $families = New-Object System.Collections.Generic.List[string]
    if ($null -eq $FeatureClassification) { return @() }
    if ($null -ne $FeatureClassification.verifier_adjustments -and
        $FeatureClassification.verifier_adjustments.PSObject.Properties.Name -contains 'non_applicable_families') {
        foreach ($family in @(Get-StringArray $FeatureClassification.verifier_adjustments.non_applicable_families)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$family) -and -not $families.Contains([string]$family)) {
                $families.Add([string]$family) | Out-Null
            }
        }
    }
    if (Test-NarrowBackendReadOnlyFeature -FeatureClassification $FeatureClassification) {
        foreach ($family in @('stateful_side_effect', 'deploy_export_page', 'config_policy_threshold', 'generated_artifact_template_upload', 'external_integration', 'lifecycle_cleanup_retention')) {
            if (-not $families.Contains($family)) { $families.Add($family) | Out-Null }
        }
    }
    return @($families)
}

function Apply-FeatureClassificationToLedger {
    param(
        $Ledger,
        [string]$ReplayRoot
    )
    if ($null -eq $Ledger -or $null -eq $Ledger.families) { return $false }
    $feature = Read-FeatureClassification -ReplayRoot $ReplayRoot
    if ($null -eq $feature) { return $false }
    $nonApplicableFamilies = @(Get-FeatureNonApplicableFamilies -FeatureClassification $feature)
    if ($nonApplicableFamilies.Count -eq 0) { return $false }

    $changed = $false
    Set-ObjectProperty -Object $Ledger -Name 'feature_classification' -Value ([ordered]@{
        classification = [string]$feature.classification
        base_classification = [string]$feature.base_classification
        read_only = [bool]$feature.read_only
        non_applicable_families = @($nonApplicableFamilies)
    })
    foreach ($family in @($Ledger.families)) {
        $id = [string]$family.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($nonApplicableFamilies -notcontains $id) { continue }
        if (-not [bool]$family.required -and [string]$family.status -eq 'NOT_APPLICABLE_BY_FEATURE_CLASSIFIER') { continue }
        Set-ObjectProperty -Object $family -Name 'required' -Value $false
        Set-ObjectProperty -Object $family -Name 'status' -Value 'NOT_APPLICABLE_BY_FEATURE_CLASSIFIER'
        Set-ObjectProperty -Object $family -Name 'coverage_cap_if_open' -Value 100
        Set-ObjectProperty -Object $family -Name 'open_sibling_surfaces' -Value @()
        Set-ObjectProperty -Object $family -Name 'open_sibling_count' -Value 0
        Set-ObjectProperty -Object $family -Name 'last_reason' -Value 'Excluded by feature classifier; this feature class is narrow backend read-only and does not require this family unless requirement_source explicitly says otherwise.'
        $changed = $true
    }
    return $changed
}

function Move-ReplayScratchArtifacts {
    param([string]$ReplayRoot)

    $scratchPatterns = @('_head_*', '_tmp_*', '*.orig', '*.rej')
    $scratchRoot = Join-Path $ReplayRoot 'logs\scratch'
    $moved = New-Object System.Collections.Generic.List[string]

    foreach ($pattern in $scratchPatterns) {
        Get-ChildItem -LiteralPath $ReplayRoot -File -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not (Test-Path -LiteralPath $scratchRoot)) {
                New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null
            }

            $destination = Join-Path $scratchRoot $_.Name
            if (Test-Path -LiteralPath $destination) {
                $stamp = Get-Date -Format 'yyyyMMddHHmmss'
                $destination = Join-Path $scratchRoot ("{0}.{1}{2}" -f $_.BaseName, $stamp, $_.Extension)
            }

            Move-Item -LiteralPath $_.FullName -Destination $destination -Force
            $moved.Add(('- `{0}` -> `{1}`' -f $_.FullName, $destination)) | Out-Null
        }
    }

    if ($moved.Count -gt 0) {
        $ledger = Join-Path $ReplayRoot 'SCRATCH_ARTIFACTS.md'
        $entry = @(
            '',
            ('## {0}' -f (Get-Date -Format s)),
            '',
            'Archived root-level scratch artifacts generated by slice agents. These files are preserved as evidence and kept out of the replay root file list.',
            ''
        ) + $moved
        Add-Content -LiteralPath $ledger -Encoding UTF8 -Value ($entry -join "`n")
    }
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-PlanField {
    param([string]$Text, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $escaped = [regex]::Escape($Name)
    $lines = @($Text -split "\r?\n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ($line -match "^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?$escaped\s*\*{0,2}\s*:\s*`?([^`\r\n]*)`?\s*$") {
            $value = $matches[1].Trim().Trim('`').Trim()
            if ([string]::IsNullOrWhiteSpace($value)) {
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    $next = [string]$lines[$j]
                    if ([string]::IsNullOrWhiteSpace($next)) { continue }
                    if ($next -match '^\s*:\s*`?([^`\r\n]+)`?\s*$') {
                        $value = $matches[1].Trim().Trim('`').Trim()
                    }
                    break
                }
            }
            return $value.TrimEnd('.').Trim()
        }
    }
    return ''
}

function Get-FirstNonEmptyText {
    param([object[]]$Values)
    foreach ($value in $Values) {
        $text = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text.Trim() }
    }
    return ''
}

function Get-SafeInt {
    param(
        [AllowNull()]
        $Value,
        $Default = $null
    )
    if ($null -eq $Value) { return $Default }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double]) { return [int]$Value }
    if ($Value -is [string] -and $Value -match '^\d+$') { return [int]$Value }
    return $Default
}

function Get-TestModuleFromSliceEvidence {
    param(
        $SliceResultObject,
        [string[]]$ImplementedFiles
    )

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    foreach ($pathValue in @($ImplementedFiles)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pathValue)) {
            $candidatePaths.Add([string]$pathValue) | Out-Null
        }
    }

    foreach ($propertyName in @('current_slice_changed_files', 'round_changed_files_snapshot')) {
        if ($null -ne $SliceResultObject -and $SliceResultObject.PSObject.Properties[$propertyName]) {
            foreach ($pathValue in @($SliceResultObject.$propertyName)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$pathValue)) {
                    $candidatePaths.Add([string]$pathValue) | Out-Null
                }
            }
        }
    }

    if ($null -ne $SliceResultObject -and $SliceResultObject.PSObject.Properties['tests']) {
        foreach ($testEntry in @($SliceResultObject.tests)) {
            foreach ($propertyName in @('evidence_file', 'file', 'path')) {
                if ($testEntry.PSObject.Properties[$propertyName]) {
                    $pathValue = [string]$testEntry.$propertyName
                    if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
                        $candidatePaths.Add($pathValue) | Out-Null
                    }
                }
            }
        }
    }

    foreach ($pathValue in $candidatePaths) {
        $normalized = ([string]$pathValue).Replace('\', '/').TrimStart('./')
        if ($normalized -match '^([^/]+)/src/test/(java|resources)/') {
            return $matches[1]
        }
    }

    return ''
}

function Get-TestClassFromSliceEvidence {
    param($SliceResultObject)

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    if ($null -ne $SliceResultObject -and $SliceResultObject.PSObject.Properties['behavior_test_charter']) {
        foreach ($file in @(Get-SliceEvidenceFiles -BehaviorCharter $SliceResultObject.behavior_test_charter)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$file)) {
                $candidatePaths.Add([string]$file) | Out-Null
            }
        }
    }
    foreach ($propertyName in @('implemented_files', 'current_slice_changed_files', 'changed_files')) {
        if ($null -ne $SliceResultObject -and $SliceResultObject.PSObject.Properties[$propertyName]) {
            foreach ($file in @($SliceResultObject.$propertyName)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$file)) {
                    $candidatePaths.Add([string]$file) | Out-Null
                }
            }
        }
    }
    if ($null -ne $SliceResultObject -and $SliceResultObject.PSObject.Properties['tests']) {
        foreach ($testEntry in @($SliceResultObject.tests)) {
            foreach ($propertyName in @('evidence_file', 'file', 'path')) {
                if ($testEntry.PSObject.Properties[$propertyName]) {
                    $pathValue = [string]$testEntry.$propertyName
                    if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
                        $candidatePaths.Add($pathValue) | Out-Null
                    }
                }
            }
        }
    }

    foreach ($pathValue in @($candidatePaths | Select-Object -Unique)) {
        $normalized = ([string]$pathValue).Trim().Trim('"').Trim("'") -replace '\\', '/'
        $leaf = [System.IO.Path]::GetFileName($normalized)
        if ($leaf -match '^(?<class>[A-Za-z_][A-Za-z0-9_]*Test)\.java$') {
            return $matches['class']
        }
    }

    return ''
}

function Test-TransientExecutorError {
    param([string]$StdoutLogPath)
    if (-not (Test-Path -LiteralPath $StdoutLogPath)) { return $false }
    $logText = Get-Content -LiteralPath $StdoutLogPath -Raw -Encoding UTF8
    return ($logText -match '(?i)429|rate.?limit|too.?many.?requests|throttl|selected model is at capacity|please try a different model|model\s+is\s+at\s+capacity')
}

function Get-LatestExecutorMetadata {
    param([string]$LogDir)
    if ([string]::IsNullOrWhiteSpace($LogDir) -or -not (Test-Path -LiteralPath $LogDir)) { return $null }
    $metaFile = Get-ChildItem -LiteralPath $LogDir -Filter '*.exec.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $metaFile) { return $null }
    try {
        return Get-Content -LiteralPath $metaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-PermanentExecutorResourceBlocker {
    param([string]$LogDir)
    $meta = Get-LatestExecutorMetadata -LogDir $LogDir
    if ($null -eq $meta) {
        return [pscustomobject]@{ IsResourceBlocker = $false; Category = ''; Diagnostic = '' }
    }
    $category = [string]$meta.failure_category
    $resourceCategories = @('executor_credit_required', 'usage_limit', 'auth')
    if ($resourceCategories -notcontains $category) {
        return [pscustomobject]@{ IsResourceBlocker = $false; Category = $category; Diagnostic = '' }
    }
    $diagnostic = switch ($category) {
        'executor_credit_required' { 'Executor account needs credit or positive balance before replay can continue.' }
        'usage_limit' { 'Executor usage limit reached; wait for quota reset or intentionally switch executor.' }
        'auth' { 'Executor authentication failed; login must be repaired before replay can continue.' }
        default { 'Executor resource blocker.' }
    }
    return [pscustomobject]@{ IsResourceBlocker = $true; Category = $category; Diagnostic = $diagnostic }
}

function Convert-ToExecutorExitCode {
    param(
        [object]$Value,
        [int]$Default = 1
    )

    if ($null -eq $Value) { return $Default }

    $candidates = @($Value)
    for ($idx = $candidates.Count - 1; $idx -ge 0; $idx--) {
        $candidate = $candidates[$idx]
        if ($null -eq $candidate) { continue }
        $text = ([string]$candidate).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $parsed = 0
        if ([int]::TryParse($text, [ref]$parsed)) {
            return $parsed
        }
    }

    return $Default
}

function Get-CommandGuardRetryGuidance {
    param([string]$LogDir)

    $meta = Get-LatestExecutorMetadata -LogDir $LogDir
    if ($null -eq $meta) {
        return [pscustomobject]@{
            HasCommandGuardViolation = $false
            ReasonText = ''
            SampleText = '- (none parsed)'
            GuidanceText = ''
        }
    }

    $category = [string]$meta.failure_category
    $rawReasons = [string]$meta.command_guard_reasons
    if ($category -ne 'command_guard_violation' -and [string]::IsNullOrWhiteSpace($rawReasons)) {
        return [pscustomobject]@{
            HasCommandGuardViolation = $false
            ReasonText = ''
            SampleText = '- (none parsed)'
            GuidanceText = ''
        }
    }

    $guardLogPath = [string]$meta.command_guard_log
    $reasonValues = New-Object System.Collections.Generic.List[string]
    $sampleCommands = New-Object System.Collections.Generic.List[string]

    foreach ($part in @($rawReasons -split ';')) {
        $trimmed = ([string]$part).Trim()
        if ($trimmed -match '^([^:]+)') {
            $reasonValues.Add($matches[1]) | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($guardLogPath) -and (Test-Path -LiteralPath $guardLogPath)) {
        foreach ($line in @(Get-Content -LiteralPath $guardLogPath -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $entry = $line | ConvertFrom-Json
                if ($null -ne $entry.PSObject.Properties['reason']) {
                    $reason = [string]$entry.reason
                    if (-not [string]::IsNullOrWhiteSpace($reason)) {
                        $reasonValues.Add($reason) | Out-Null
                    }
                }
                if ($null -ne $entry.PSObject.Properties['command_line']) {
                    $command = [string]$entry.command_line
                    if (-not [string]::IsNullOrWhiteSpace($command)) {
                        if ($command.Length -gt 500) { $command = $command.Substring(0, 500) + '...' }
                        $sampleCommands.Add($command) | Out-Null
                    }
                }
            } catch {
                continue
            }
        }
    }

    $uniqueReasons = @($reasonValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $uniqueSamples = @($sampleCommands | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique | Select-Object -First 5)
    $guidance = New-Object System.Collections.Generic.List[string]
    if ($uniqueReasons -contains 'maven_pl_without_am_forbidden') {
        $guidance.Add('Every Maven command that uses -pl and runs compile, test-compile, or test must also include -am in the same command.') | Out-Null
        $guidance.Add('Use this shape for replay Maven tests: mvn <settings> -f <WORKTREE>\pom.xml -pl <test-module> -am test-compile, and mvn --% <settings> -f <WORKTREE>\pom.xml -pl <test-module> -am -Dtest=<class>#<method> -Dsurefire.failIfNoSpecifiedTests=false test.') | Out-Null
        $guidance.Add('Do not repeat the forbidden -pl command without -am. If a valid module cannot be identified, write BLOCKED SLICE_RESULT JSON instead of running Maven.') | Out-Null
    }
    if ($uniqueReasons -contains 'protected_root_pom_forbidden') {
        $guidance.Add('Never run Maven against the protected project root pom.xml; all build/test commands must point -f to the isolated worktree pom.xml.') | Out-Null
    }
    if ($uniqueReasons -contains 'maven_deploy_forbidden') {
        $guidance.Add('Never run Maven deploy during replay. Use only compile/test/test-compile commands required by the slice.') | Out-Null
    }
    if ($guidance.Count -eq 0 -and $uniqueReasons.Count -gt 0) {
        $guidance.Add('Do not repeat any command-guard violation. Convert the observed guard reason into a valid command or write BLOCKED SLICE_RESULT JSON.') | Out-Null
    }

    return [pscustomobject]@{
        HasCommandGuardViolation = ($category -eq 'command_guard_violation' -or $uniqueReasons.Count -gt 0)
        ReasonText = if ($uniqueReasons.Count -gt 0) { $uniqueReasons -join ', ' } else { $rawReasons }
        SampleText = if ($uniqueSamples.Count -gt 0) { ($uniqueSamples | ForEach-Object { "- $_" }) -join "`n" } else { '- (none parsed)' }
        GuidanceText = if ($guidance.Count -gt 0) { ($guidance | ForEach-Object { "- $_" }) -join "`n" } else { '' }
    }
}

function Get-DefaultMavenCommandGuardGuidance {
    @(
        'Maven command guard baseline:',
        '- Any Maven compile, test-compile, or test command that uses `-pl <module>` MUST include `-am` in the same command.',
        '- Do not run `mvn compile -pl <module>` or any offline variant without `-am`; it can bypass reactor source modules and trigger command guard termination.',
        '- Use this shape instead: `mvn <settings> -f <WORKTREE>\pom.xml -pl <test-module> -am test-compile` and `mvn --% <settings> -f <WORKTREE>\pom.xml -pl <test-module> -am -Dtest=<class>#<method> -Dsurefire.failIfNoSpecifiedTests=false test`.',
        '- If a valid module cannot be identified, write BLOCKED SLICE_RESULT JSON instead of probing with a forbidden Maven command.',
        ''
    ) -join "`n"
}

function Invoke-SliceExecutorWithRetry {
    param(
        [string[]]$AgentArgs,
        [string]$SliceLogDir,
        [string]$SliceId,
        [int]$MaxRetries = 2,
        [int]$DelaySeconds = 60
    )
    $attempt = 0
    while ($true) {
        $attempt++
        & powershell @AgentArgs
        if ($LASTEXITCODE -eq 0) { return $LASTEXITCODE }
        $stdoutLog = Get-ChildItem -LiteralPath $SliceLogDir -Filter '*.stdout.log' -ErrorAction SilentlyContinue | Select-Object -First 1
        $stdoutLogPath = if ($null -ne $stdoutLog) { $stdoutLog.FullName } else { '' }
        if ($attempt -le $MaxRetries -and (Test-TransientExecutorError $stdoutLogPath)) {
            Write-Host "WARNING: $SliceId executor failed with transient error (exit=$LASTEXITCODE, attempt $attempt/$MaxRetries). Retrying in ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
            continue
        }
        return $LASTEXITCODE
    }
}

function ConvertTo-ReplayRelativePath {
    param(
        [string]$Worktree,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $value = ([string]$Path).Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }

    try {
        if ([System.IO.Path]::IsPathRooted($value)) {
            $worktreeFull = [System.IO.Path]::GetFullPath($Worktree).TrimEnd('\', '/')
            $pathFull = [System.IO.Path]::GetFullPath($value)
            if ($pathFull.StartsWith($worktreeFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relative = $pathFull.Substring($worktreeFull.Length).TrimStart('\', '/')
                return ($relative -replace '\\', '/')
            }
        }
    } catch {
        # Fall through to textual normalization.
    }

    return ($value -replace '\\', '/')
}

function Get-WorktreeChangedFiles {
    param([string]$Worktree)

    if ([string]::IsNullOrWhiteSpace($Worktree) -or -not (Test-Path -LiteralPath $Worktree -PathType Container)) {
        return @()
    }

    $files = New-Object System.Collections.Generic.List[string]
    $commands = @(
        @('diff', '--name-only'),
        @('diff', '--cached', '--name-only'),
        @('ls-files', '--others', '--exclude-standard')
    )

    foreach ($command in $commands) {
        $output = @()
        try {
            $output = @(& git -C $Worktree @command 2>$null)
        } catch {
            $output = @()
        }
        if ($LASTEXITCODE -ne 0) { continue }
        foreach ($line in $output) {
            $relative = ConvertTo-ReplayRelativePath -Worktree $Worktree -Path ([string]$line)
            if (-not [string]::IsNullOrWhiteSpace($relative)) {
                $files.Add($relative) | Out-Null
            }
        }
    }

    return @($files | Sort-Object -Unique)
}

function Write-PartialWorktreeDiffAudit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [string]$Stage = 'after_retry',
        [string]$SliceLogDir = '',
        [int]$ExitCode = 0
    )

    $safeStage = if ([string]::IsNullOrWhiteSpace($Stage)) { 'after_retry' } else { ([string]$Stage -replace '[^A-Za-z0-9_.-]', '_') }
    $suffix = if ($safeStage -eq 'after_retry') { '' } else { "_$safeStage" }
    $jsonPath = Join-Path $ReplayRoot ('PARTIAL_WORKTREE_DIFF_{0:D2}{1}.json' -f $SliceIndex, $suffix)
    $mdPath = Join-Path $ReplayRoot ('PARTIAL_WORKTREE_DIFF_{0:D2}{1}.md' -f $SliceIndex, $suffix)

    $statusLines = @()
    $diffStatLines = @()
    try { $statusLines = @(& git -C $Worktree status --short 2>$null) } catch { $statusLines = @() }
    try { $diffStatLines = @(& git -C $Worktree diff --stat 2>$null) } catch { $diffStatLines = @() }

    $changedFiles = @(Get-WorktreeChangedFiles -Worktree $Worktree)
    $productionFiles = @($changedFiles | Where-Object { $_ -match '(?i)(^|/)src/main/(java|resources)/' })
    $testFiles = @($changedFiles | Where-Object { $_ -match '(?i)(^|/)src/test/(java|resources)/' })

    $payload = [ordered]@{
        schema = 'partial_worktree_diff_audit.v1'
        status = if ($changedFiles.Count -gt 0) { 'PARTIAL_DIFF_DETECTED' } else { 'NO_DIFF_DETECTED' }
        slice_index = $SliceIndex
        stage = $safeStage
        replay_root = $ReplayRoot
        worktree = $Worktree
        slice_log_dir = $SliceLogDir
        executor_exit_code = $ExitCode
        changed_file_count = $changedFiles.Count
        changed_files = @($changedFiles)
        production_files = @($productionFiles)
        test_files = @($testFiles)
        git_status_short = @($statusLines)
        git_diff_stat = @($diffStatLines)
        generated_at = (Get-Date).ToString('s')
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('# Partial Worktree Diff Audit') | Out-Null
    $md.Add('') | Out-Null
    $md.Add(('- status: {0}' -f $payload.status)) | Out-Null
    $md.Add(('- slice_index: {0}' -f $SliceIndex)) | Out-Null
    $md.Add(('- stage: {0}' -f $safeStage)) | Out-Null
    $md.Add(('- executor_exit_code: {0}' -f $ExitCode)) | Out-Null
    $md.Add(('- changed_file_count: {0}' -f $changedFiles.Count)) | Out-Null
    $md.Add(('- json: {0}' -f $jsonPath)) | Out-Null
    $md.Add('') | Out-Null
    $md.Add('## Changed Files') | Out-Null
    if ($changedFiles.Count -gt 0) {
        foreach ($file in $changedFiles) { $md.Add(("- $file")) | Out-Null }
    } else {
        $md.Add('- none') | Out-Null
    }
    $md.Add('') | Out-Null
    $md.Add('## Git Status') | Out-Null
    $md.Add('```text') | Out-Null
    $statusText = if ($statusLines.Count -gt 0) { ($statusLines -join "`n") } else { '(clean or unavailable)' }
    $md.Add($statusText) | Out-Null
    $md.Add('```') | Out-Null
    $md.Add('') | Out-Null
    $md.Add('## Diff Stat') | Out-Null
    $md.Add('```text') | Out-Null
    $diffStatText = if ($diffStatLines.Count -gt 0) { ($diffStatLines -join "`n") } else { '(no tracked diff stat)' }
    $md.Add($diffStatText) | Out-Null
    $md.Add('```') | Out-Null
    $md -join "`n" | Set-Content -LiteralPath $mdPath -Encoding UTF8

    return [pscustomobject]@{
        HasDiff = ($changedFiles.Count -gt 0)
        JsonPath = $jsonPath
        MdPath = $mdPath
        ChangedFiles = @($changedFiles)
        ProductionFiles = @($productionFiles)
        TestFiles = @($testFiles)
        Status = [string]$payload.status
    }
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $Value
    )
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Invoke-GreenPhaseNoMockGate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [string]$SliceResultPath,
        [Parameter(Mandatory = $true)]
        [string]$SliceVerifyPath,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gatePath = Join-Path $ReplayRoot ('GREEN_PHASE_VERIFY_{0:D2}.json' -f $SliceIndex)
    $gateScript = Join-Path $PSScriptRoot 'verify_green_phase.py'
    $stdoutPath = Join-Path $ReplayRoot ('GREEN_PHASE_VERIFY_{0:D2}.stdout.log' -f $SliceIndex)
    $stderrPath = Join-Path $ReplayRoot ('GREEN_PHASE_VERIFY_{0:D2}.stderr.log' -f $SliceIndex)
    $implementedFilesPath = Join-Path $ReplayRoot ('GREEN_PHASE_IMPLEMENTED_FILES_{0:D2}.json' -f $SliceIndex)
    $touchedFamiliesPath = Join-Path $ReplayRoot ('GREEN_PHASE_TOUCHED_FAMILIES_{0:D2}.json' -f $SliceIndex)

    $emptyPass = [ordered]@{
        gate = 'green_phase_no_mock'
        can_proceed = $true
        block_green = $false
        reason = 'no_implemented_files'
        slice_index = $SliceIndex
    }

    if (-not (Test-Path -LiteralPath $SliceResultPath)) {
        $emptyPass.reason = 'slice_result_missing'
        $emptyPass | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $gatePath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $gatePath; Blocker = '' }
    }

    $sliceResultObject = Read-JsonObject -Path $SliceResultPath
    $implementedFiles = @(Get-StringArray $sliceResultObject.implemented_files)
    $touchedFamilies = @(Get-StringArray $sliceResultObject.touched_requirement_families)
    if ($implementedFiles.Count -eq 0) {
        $emptyPass.implemented_files = @($implementedFiles)
        $emptyPass.touched_requirement_families = @($touchedFamilies)
        $emptyPass | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $gatePath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $gatePath; Blocker = '' }
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        $missing = [ordered]@{
            gate = 'green_phase_no_mock'
            can_proceed = $false
            block_green = $true
            reason = 'verify_green_phase_script_missing'
            script = $gateScript
            slice_index = $SliceIndex
        }
        $missing | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $gatePath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $false; ResultPath = $gatePath; Blocker = 'verify_green_phase_script_missing' }
    }

    ConvertTo-Json -InputObject @($implementedFiles) -Depth 6 | Set-Content -LiteralPath $implementedFilesPath -Encoding UTF8
    ConvertTo-Json -InputObject @($touchedFamilies) -Depth 6 | Set-Content -LiteralPath $touchedFamiliesPath -Encoding UTF8

    # v346: Test Execution Verification - implemented files require an executable GREEN test,
    # even when touched family metadata is missing or stale.
    $testExecutionPath = Join-Path $ReplayRoot ('GREEN_PHASE_TEST_EXECUTION_{0:D2}.json' -f $SliceIndex)
    $testStdoutPath = Join-Path $ReplayRoot ('GREEN_PHASE_TEST_EXECUTION_{0:D2}.stdout.log' -f $SliceIndex)
    $testExecutionResult = [ordered]@{
        gate = 'test_execution_verification'
        slice_index = $SliceIndex
        execution_status = 'FAILED'
        exit_code = $null
        test_class = ''
        test_module = ''
        reason = 'green_test_class_missing'
    }

    # Extract test class from slice result.
    $testClass = ''
    if ($null -ne $sliceResultObject.tests) {
        $testEntries = @($sliceResultObject.tests | Where-Object { [string]$_.phase -eq 'GREEN' })
        if ($testEntries.Count -gt 0) {
            $greenTest = $testEntries | Select-Object -First 1
            $command = [string]$greenTest.command
            if ($command -match '-Dtest=([^\s]+)') {
                $testClass = $matches[1]
            } elseif ($greenTest.PSObject.Properties['test_class']) {
                $testClass = [string]$greenTest.test_class
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($testClass)) {
        $testClass = Get-TestClassFromSliceEvidence -SliceResultObject $sliceResultObject
    }

    if (-not [string]::IsNullOrWhiteSpace($testClass)) {
        Write-Host "Running test execution verification for $testClass..." -ForegroundColor Cyan
        $testExecutionResult.test_class = $testClass

        $testModule = Get-TestModuleFromSliceEvidence -SliceResultObject $sliceResultObject -ImplementedFiles $implementedFiles
        $testExecutionResult.test_module = $testModule
        if ([string]::IsNullOrWhiteSpace($testModule)) {
            $testExecutionResult.reason = 'test_module_not_inferred'
            $testExecutionResult.issue = 'GREEN test exists, but no src/test/java or src/test/resources module path was present in slice evidence.'
        } else {
            $testExecutionResult.reason = 'test_execution_running'

            $mavenArgs = @(Get-MavenArgumentList -MavenSettings $MavenSettings)
            $mavenArgs += @(
                '-f', (Join-Path $Worktree 'pom.xml'),
                'test',
                '-pl', $testModule,
                '-am',
                "-Dtest=$testClass",
                '-Dsurefire.failIfNoSpecifiedTests=false'
            )

            & mvn @mavenArgs *> $testStdoutPath
            $mvnExitCode = $LASTEXITCODE
            $testStdoutText = Read-TextIfExists -Path $testStdoutPath

            $testExecutionResult.execution_status = if ($mvnExitCode -eq 0) { 'PASSED' } else { 'FAILED' }
            $testExecutionResult.exit_code = $mvnExitCode
            $testExecutionResult.stdout_log = $testStdoutPath

            if ($mvnExitCode -eq 0) {
                $testExecutionResult.reason = 'test_execution_passed'
                Write-Host "Test execution verification: PASSED" -ForegroundColor Green
            } else {
                $testExecutionResult.reason = 'test_execution_failed'
                $testExecutionResult.issue = "Maven test exit code $mvnExitCode; inspect $testStdoutPath"
                Write-Host "Test execution verification: FAILED (exit code $mvnExitCode)" -ForegroundColor Red
            }
        }
    }

    $testExecutionResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $testExecutionPath -Encoding UTF8

    # v346: Block GREEN phase unless the selected GREEN test actually executed and passed.
    if ($testExecutionResult.execution_status -ne 'PASSED') {
        $blocker = [string]$testExecutionResult.reason
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test execution verification stop | test_execution_verification | tdd_compliance | non_authorizing_evidence | test_class={1}; exit_code={2}; result={3}. |" -f $SliceIndex, $testExecutionResult.test_class, $testExecutionResult.exit_code, $testExecutionPath)
        return [pscustomobject]@{ CanProceed = $false; ResultPath = $testExecutionPath; Blocker = $blocker }
    }

    $pythonResolver = Join-Path (Resolve-RunSliceLoopScriptRoot) 'Resolve-PythonLauncher.ps1'
    . $pythonResolver
    $python = Resolve-PythonLauncher
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $pythonOutput = & $python.Command @($python.Arguments + @($gateScript, 'verify', $Worktree, $implementedFilesPath, $touchedFamiliesPath)) 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    $stdoutItems = @()
    $stderrItems = @()
    foreach ($line in @($pythonOutput)) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            $stderrItems += [string]$line
        } else {
            $stdoutItems += [string]$line
        }
    }
    Set-Content -LiteralPath $stdoutPath -Encoding UTF8 -Value $stdoutItems
    Set-Content -LiteralPath $stderrPath -Encoding UTF8 -Value $stderrItems
    $stdoutText = Read-TextIfExists -Path $stdoutPath
    $stderrText = Read-TextIfExists -Path $stderrPath
    try {
        if ([string]::IsNullOrWhiteSpace($stdoutText)) {
            $gateResult = [pscustomobject]@{
                can_proceed = $false
                block_green = $true
                issues = @([pscustomobject]@{
                    code = 'green_phase_gate_empty_output'
                    message = 'verify_green_phase.py produced no stdout JSON; failing closed instead of crashing the slice loop.'
                })
            }
        } else {
            $gateResult = $stdoutText | ConvertFrom-Json
            if ($null -eq $gateResult) {
                $gateResult = [pscustomobject]@{
                    can_proceed = $false
                    block_green = $true
                    issues = @([pscustomobject]@{
                        code = 'green_phase_gate_null_output'
                        message = 'verify_green_phase.py stdout parsed to null JSON; failing closed instead of crashing the slice loop.'
                    })
                }
            }
        }
    } catch {
        $gateResult = [pscustomobject]@{
            can_proceed = $false
            block_green = $true
            issues = @([pscustomobject]@{
                code = 'green_phase_gate_unparseable'
                message = $_.Exception.Message
            })
        }
    }
    Set-ObjectProperty -Object $gateResult -Name 'gate' -Value 'green_phase_no_mock'
    Set-ObjectProperty -Object $gateResult -Name 'slice_index' -Value $SliceIndex
    Set-ObjectProperty -Object $gateResult -Name 'exit_code' -Value $exitCode
    Set-ObjectProperty -Object $gateResult -Name 'stdout_log' -Value $stdoutPath
    Set-ObjectProperty -Object $gateResult -Name 'stderr_log' -Value $stderrPath
    Set-ObjectProperty -Object $gateResult -Name 'implemented_files_input' -Value $implementedFilesPath
    Set-ObjectProperty -Object $gateResult -Name 'touched_families_input' -Value $touchedFamiliesPath
    if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
        Set-ObjectProperty -Object $gateResult -Name 'stderr' -Value $stderrText
    }
    $gateResult | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $gatePath -Encoding UTF8

    $canProceed = ($exitCode -eq 0 -and $null -ne $gateResult.can_proceed -and [bool]$gateResult.can_proceed)
    if ($canProceed) {
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $gatePath; Blocker = '' }
    }

    $issueCodes = @()
    if ($null -ne $gateResult.issues) {
        $issueCodes = @(Get-StringArray ($gateResult.issues | ForEach-Object { $_.code }))
    }
    if ($issueCodes.Count -eq 0) { $issueCodes = @('green_phase_no_mock_gate_failed') }

    if (Test-Path -LiteralPath $SliceVerifyPath) {
        $verify = Read-JsonObject -Path $SliceVerifyPath
        $blockers = @((@(Get-StringArray $verify.authorization_blockers) + $issueCodes) | Select-Object -Unique)
        $gapFlags = @((@(Get-StringArray $verify.gap_flags) + @('mock_only_implementation_gap', 'side_effect_ledger_gap', 'tooling_enforcement_stop')) | Select-Object -Unique)
        $warnings = @((@(Get-StringArray $verify.warnings) + $issueCodes) | Select-Object -Unique)
        Set-ObjectProperty -Object $verify -Name 'verification_status' -Value 'FAIL'
        Set-ObjectProperty -Object $verify -Name 'adjusted_coverage_delta' -Value 0
        Set-ObjectProperty -Object $verify -Name 'coverage_delta' -Value 0
        Set-ObjectProperty -Object $verify -Name 'should_continue' -Value $false
        Set-ObjectProperty -Object $verify -Name 'authorized_for_next_slice' -Value $false
        Set-ObjectProperty -Object $verify -Name 'authorized_for_synthesis' -Value $false
        Set-ObjectProperty -Object $verify -Name 'authorization_blockers' -Value @($blockers)
        Set-ObjectProperty -Object $verify -Name 'gap_flags' -Value @($gapFlags)
        Set-ObjectProperty -Object $verify -Name 'warnings' -Value @($warnings)
        Set-ObjectProperty -Object $verify -Name 'green_phase_gate' -Value $gateResult
        $verify | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $SliceVerifyPath -Encoding UTF8
    }

    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} green-phase no-mock gate stop | green_phase_no_mock | implementation_quality | non_authorizing_evidence | issues={1}; result={2}. |" -f $SliceIndex, ($issueCodes -join ','), $gatePath)
    return [pscustomobject]@{ CanProceed = $false; ResultPath = $gatePath; Blocker = ($issueCodes -join ',') }
}

function Get-RequiredFamilyCountFromContract {
    param([string]$ReplayRoot)

    $familyContractPath = Join-Path $ReplayRoot 'FAMILY_CONTRACT.json'
    if (-not (Test-Path -LiteralPath $familyContractPath)) { return 0 }
    try {
        $familyContract = Read-JsonObject -Path $familyContractPath
        $families = @($familyContract.families)
        $requiredFamilies = @($families | Where-Object { [bool]$_.required })
        if ($requiredFamilies.Count -gt 0) { return $requiredFamilies.Count }
        return $families.Count
    } catch {
        return 0
    }
}

function Resolve-SliceEvidenceFile {
    param(
        [string]$Worktree,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $clean = ([string]$Path).Trim().Trim('"').Trim("'")
    if ([System.IO.Path]::IsPathRooted($clean)) { return $clean }
    return (Join-Path $Worktree $clean)
}

function Get-SliceEvidenceFiles {
    param($BehaviorCharter)

    $files = New-Object System.Collections.Generic.List[string]
    if ($null -eq $BehaviorCharter) { return @() }

    if ($BehaviorCharter.PSObject.Properties['evidence_files']) {
        foreach ($file in @(Get-StringArray $BehaviorCharter.evidence_files)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$file)) {
                $files.Add(([string]$file).Trim()) | Out-Null
            }
        }
    }

    if ($BehaviorCharter.PSObject.Properties['evidence_file']) {
        $rawEvidenceFile = [string]$BehaviorCharter.evidence_file
        if (-not [string]::IsNullOrWhiteSpace($rawEvidenceFile)) {
            foreach ($file in @($rawEvidenceFile -split "[,;`r`n]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
                $files.Add(([string]$file).Trim()) | Out-Null
            }
        }
    }

    return @($files | Select-Object -Unique)
}

function Get-SourcePathModule {
    param(
        [string]$Path,
        [ValidateSet('main', 'test')]
        [string]$SourceKind
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $normalized = ([string]$Path).Trim().Trim('"').Trim("'") -replace '\\', '/'
    $normalized = $normalized.TrimStart('./')

    if ($SourceKind -eq 'main') {
        if ($normalized -match '^(.+)/src/main/java/') { return $matches[1] }
        if ($normalized -match '^src/main/java/') { return '.' }
    } else {
        if ($normalized -match '^(.+)/src/test/(java|resources)/') { return $matches[1] }
        if ($normalized -match '^src/test/(java|resources)/') { return '.' }
    }

    return ''
}

function Get-MavenArtifactId {
    param(
        [string]$Worktree,
        [string]$Module
    )

    if ([string]::IsNullOrWhiteSpace($Worktree) -or [string]::IsNullOrWhiteSpace($Module)) { return '' }
    $moduleRelative = if ($Module -eq '.') { '' } else { $Module -replace '/', [System.IO.Path]::DirectorySeparatorChar }
    $pomPath = Join-Path (Join-Path $Worktree $moduleRelative) 'pom.xml'
    if (-not (Test-Path -LiteralPath $pomPath)) { return '' }

    $pomText = Get-Content -LiteralPath $pomPath -Raw -Encoding UTF8
    $matches = [regex]::Matches($pomText, '(?is)<artifactId>\s*([^<\s]+)\s*</artifactId>')
    foreach ($match in $matches) {
        $artifactId = ([string]$match.Groups[1].Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($artifactId) -and $artifactId -ne '${project.artifactId}') {
            return $artifactId
        }
    }

    return ''
}

function Test-TestModuleDependsOnProductionModule {
    param(
        [string]$Worktree,
        [string]$TestModule,
        [string]$ProductionModule
    )

    if ([string]::IsNullOrWhiteSpace($Worktree) -or [string]::IsNullOrWhiteSpace($TestModule) -or [string]::IsNullOrWhiteSpace($ProductionModule)) {
        return $false
    }

    $testModuleRelative = if ($TestModule -eq '.') { '' } else { $TestModule -replace '/', [System.IO.Path]::DirectorySeparatorChar }
    $testPom = Join-Path (Join-Path $Worktree $testModuleRelative) 'pom.xml'
    if (-not (Test-Path -LiteralPath $testPom)) { return $false }

    $productionArtifactId = Get-MavenArtifactId -Worktree $Worktree -Module $ProductionModule
    $candidateIds = @($ProductionModule, ($ProductionModule -split '[\\/]' | Select-Object -Last 1), $productionArtifactId) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Select-Object -Unique
    if ($candidateIds.Count -eq 0) { return $false }

    $testPomText = Get-Content -LiteralPath $testPom -Raw -Encoding UTF8
    foreach ($candidateId in $candidateIds) {
        if ($testPomText -match ('(?is)<artifactId>\s*' + [regex]::Escape([string]$candidateId) + '\s*</artifactId>')) {
            return $true
        }
    }

    return $false
}

function Test-TestFileMatchesProductionModule {
    param(
        [string]$TestFile,
        [string[]]$ImplementedFiles,
        [string]$Worktree = ''
    )

    $testModule = Get-SourcePathModule -Path $TestFile -SourceKind test
    $productionModules = @($ImplementedFiles | ForEach-Object {
        Get-SourcePathModule -Path ([string]$_) -SourceKind main
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    if ([string]::IsNullOrWhiteSpace($testModule) -or $productionModules.Count -eq 0) {
        return [pscustomobject]@{
            valid = $true
            test_module = $testModule
            production_modules = @($productionModules)
            reason = 'module_not_inferred'
        }
    }

    $sameModule = @($productionModules | Where-Object { $_ -eq $testModule }).Count -gt 0
    $crossModuleHarness = $false
    if (-not $sameModule -and -not [string]::IsNullOrWhiteSpace($Worktree)) {
        $dependencyChecks = @($productionModules | ForEach-Object {
            Test-TestModuleDependsOnProductionModule -Worktree $Worktree -TestModule $testModule -ProductionModule ([string]$_)
        })
        $crossModuleHarness = $dependencyChecks.Count -gt 0 -and @($dependencyChecks | Where-Object { -not $_ }).Count -eq 0
    }

    $valid = $sameModule -or $crossModuleHarness
    return [pscustomobject]@{
        valid = $valid
        test_module = $testModule
        production_modules = @($productionModules)
        reason = if ($sameModule) {
            'same_module'
        } elseif ($crossModuleHarness) {
            'cross_module_test_harness_depends_on_production_module'
        } else {
            'test_module_differs_from_production_module'
        }
    }
}

function Invoke-V348SliceQualityGates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [string]$SliceResultPath,
        [Parameter(Mandatory = $true)]
        [string]$SliceVerifyPath,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gatePath = Join-Path $ReplayRoot ('V348_SLICE_QUALITY_GATE_{0:D2}.json' -f $SliceIndex)
    $horizontalScript = Join-Path $PSScriptRoot 'verify-horizontal-slice.ps1'
    $testCharterScript = Join-Path $PSScriptRoot 'verify-test-charter.ps1'
    $horizontalStdout = Join-Path $ReplayRoot ('V348_HORIZONTAL_SLICE_GATE_{0:D2}.stdout.log' -f $SliceIndex)
    $horizontalStderr = Join-Path $ReplayRoot ('V348_HORIZONTAL_SLICE_GATE_{0:D2}.stderr.log' -f $SliceIndex)

    $result = [ordered]@{
        gate = 'v348_slice_quality'
        slice_index = $SliceIndex
        can_proceed = $true
        issues = @()
        horizontal_slice = [ordered]@{
            invoked = $false
            exit_code = $null
            decision = 'SKIPPED'
            stdout_log = $horizontalStdout
            stderr_log = $horizontalStderr
        }
        test_charter = [ordered]@{
            invoked = $false
            decision = 'SKIPPED'
            checked_files = @()
            failures = @()
        }
        exact_contract = [ordered]@{
            invoked = $false
            decision = 'SKIPPED'
            issues = @()
        }
    }

    if (-not (Test-Path -LiteralPath $SliceResultPath)) {
        $result.horizontal_slice.decision = 'SKIPPED_SLICE_RESULT_MISSING'
        $result.test_charter.decision = 'SKIPPED_SLICE_RESULT_MISSING'
        $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $gatePath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $gatePath; Blocker = '' }
    }

    $sliceResultObject = Read-JsonObject -Path $SliceResultPath
    $sliceStatus = [string]$sliceResultObject.slice_status
    if (@('BLOCKED', 'INVALID_REPLAY') -contains $sliceStatus) {
        $result.horizontal_slice.decision = "SKIPPED_$sliceStatus"
        $result.test_charter.decision = "SKIPPED_$sliceStatus"
        $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $gatePath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $gatePath; Blocker = '' }
    }

    $implementedFiles = @(Get-StringArray $sliceResultObject.implemented_files)
    $requiredFamilyCount = Get-RequiredFamilyCountFromContract -ReplayRoot $ReplayRoot
    # v351: Strengthened enforcement - removed $requiredFamilyCount -ge 3 bypass condition
    # Now applies to ALL S1 slices with implemented files, not just "complex" ones
    if ($SliceIndex -eq 1 -and $implementedFiles.Count -gt 0) {
        if (Test-Path -LiteralPath $horizontalScript) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $horizontalScript -SliceResultFile $SliceResultPath -FeatureClassificationPath (Join-Path $ReplayRoot 'FEATURE_CLASSIFICATION.json') > $horizontalStdout 2> $horizontalStderr
            $horizontalExit = $LASTEXITCODE
            $result.horizontal_slice.invoked = $true
            $result.horizontal_slice.exit_code = $horizontalExit
            $result.horizontal_slice.decision = if ($horizontalExit -eq 0) { 'PASS' } else { 'FAIL' }
            if ($horizontalExit -ne 0) {
                $result.can_proceed = $false
                $result.issues += 'horizontal_slice_minimum_not_met'
            }
        } else {
            $result.can_proceed = $false
            $result.issues += 'verify_horizontal_slice_script_missing'
            $result.horizontal_slice.decision = 'SCRIPT_MISSING'
        }
    } else {
        $result.horizontal_slice.decision = 'SKIPPED_NOT_COMPLEX_S1'
    }

    $candidateTestFiles = New-Object System.Collections.Generic.List[string]
    if ($null -ne $sliceResultObject.behavior_test_charter) {
        foreach ($evidenceFile in @(Get-SliceEvidenceFiles -BehaviorCharter $sliceResultObject.behavior_test_charter)) {
            $candidateTestFiles.Add([string]$evidenceFile) | Out-Null
        }
    }
    foreach ($file in @($implementedFiles + @(Get-StringArray $sliceResultObject.current_slice_changed_files))) {
        if ([string]$file -match 'Test\.java$') { $candidateTestFiles.Add([string]$file) | Out-Null }
    }
    $testFiles = @($candidateTestFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($testFiles.Count -gt 0) {
        if (Test-Path -LiteralPath $testCharterScript) {
            $result.test_charter.invoked = $true
            $result.test_charter.decision = 'PASS'
            foreach ($testFile in $testFiles) {
                $resolved = Resolve-SliceEvidenceFile -Worktree $Worktree -Path $testFile
                $stdout = Join-Path $ReplayRoot ('V348_TEST_CHARTER_GATE_{0:D2}_{1}.stdout.log' -f $SliceIndex, ([System.IO.Path]::GetFileNameWithoutExtension($resolved)))
                $stderr = Join-Path $ReplayRoot ('V348_TEST_CHARTER_GATE_{0:D2}_{1}.stderr.log' -f $SliceIndex, ([System.IO.Path]::GetFileNameWithoutExtension($resolved)))
                $normalizedTestFile = ([string]$testFile).Trim().Trim('"').Trim("'") -replace '\\', '/'
                $testFileLeaf = [System.IO.Path]::GetFileName(([string]$testFile))
                $entry = [ordered]@{
                    file = $resolved
                    exit_code = $null
                    stdout_log = $stdout
                    stderr_log = $stderr
                    decision = 'NOT_RUN'
                    surface_module = $null
                }
                $generatedReplayArtifact = $testFileLeaf -match '^(SLICE_RESULT|SLICE_VERIFY)_\d+\.json$|^(ROUND_RESULT|AUTOPILOT_SUMMARY|RUN_CONTROL_SUMMARY|FINAL_REPLAY_REPORT)\.(md|json)$'
                if ($generatedReplayArtifact -or $normalizedTestFile -notmatch '(?i)Test\.java$') {
                    $entry.decision = 'INVALID_EVIDENCE_FILE'
                    $result.test_charter.failures += @($entry)
                    $result.can_proceed = $false
                    $result.issues += 'behavior_test_charter_evidence_file_invalid'
                    continue
                }
                if (-not (Test-Path -LiteralPath $resolved)) {
                    $entry.decision = 'MISSING'
                    $result.test_charter.failures += @($entry)
                    $result.can_proceed = $false
                    $result.issues += 'test_charter_file_missing'
                    continue
                }
                $surfaceModule = Test-TestFileMatchesProductionModule -TestFile $testFile -ImplementedFiles $implementedFiles -Worktree $Worktree
                $entry.surface_module = $surfaceModule
                if (-not [bool]$surfaceModule.valid) {
                    $entry.decision = 'WRONG_TEST_SURFACE'
                    $result.test_charter.failures += @($entry)
                    $result.can_proceed = $false
                    $result.issues += 'wrong_test_surface'
                    continue
                }
                & powershell -NoProfile -ExecutionPolicy Bypass -File $testCharterScript -TestFile $resolved > $stdout 2> $stderr
                $testExit = $LASTEXITCODE
                $entry.exit_code = $testExit
                $entry.decision = if ($testExit -eq 0) { 'PASS' } else { 'FAIL' }
                $result.test_charter.checked_files += @($entry)
                if ($testExit -ne 0) {
                    $result.test_charter.failures += @($entry)
                    $result.can_proceed = $false
                    $result.issues += 'behavioral_test_charter_failed'
                }
            }
            if (-not [bool]$result.can_proceed) { $result.test_charter.decision = 'FAIL' }
        } else {
            $result.can_proceed = $false
            $result.issues += 'verify_test_charter_script_missing'
            $result.test_charter.decision = 'SCRIPT_MISSING'
        }
    } else {
        $result.test_charter.decision = 'SKIPPED_NO_TEST_FILE'
    }

    if (Test-Path -LiteralPath $SliceVerifyPath) {
        try {
            $verifyForExact = Read-JsonObject -Path $SliceVerifyPath
            $exactSignals = @(
                @(Get-StringArray $verifyForExact.gap_flags),
                @(Get-StringArray $verifyForExact.warnings),
                @(Get-StringArray $verifyForExact.authorization_blockers)
            ) | ForEach-Object { $_ }
            $blockingExactSignals = @($exactSignals | Where-Object {
                @(
                    'exact_contract_assertion_missing',
                    'exact_contract_not_closed',
                    'exact_contract_boundary_proof_stop',
                    'exact_contract_minimum_coverage_gap'
                ) -contains [string]$_
            } | Select-Object -Unique)
            if ($blockingExactSignals.Count -gt 0) {
                $result.exact_contract.invoked = $true
                $result.exact_contract.decision = 'FAIL'
                $result.exact_contract.issues = @($blockingExactSignals)
                $result.can_proceed = $false
                $result.issues += 'exact_contract_post_green_not_closed'
            } else {
                $result.exact_contract.invoked = $true
                $result.exact_contract.decision = 'PASS'
            }
        } catch {
            $result.exact_contract.invoked = $true
            $result.exact_contract.decision = 'UNREADABLE_VERIFY'
            $result.exact_contract.issues = @('slice_verify_unreadable_for_exact_contract_gate')
            $result.can_proceed = $false
            $result.issues += 'slice_verify_unreadable_for_exact_contract_gate'
        }
    }

    $result.issues = @($result.issues | Select-Object -Unique)
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $gatePath -Encoding UTF8

    if ([bool]$result.can_proceed) {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} v348 slice quality gate | v348_slice_quality | implementation_quality | pass | result={1}. |" -f $SliceIndex, $gatePath)
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $gatePath; Blocker = '' }
    }

    if (Test-Path -LiteralPath $SliceVerifyPath) {
        $verify = Read-JsonObject -Path $SliceVerifyPath
        $issueCodes = @(Get-StringArray $result.issues)
        $blockers = @((@(Get-StringArray $verify.authorization_blockers) + $issueCodes) | Select-Object -Unique)
        $gapFlags = @((@(Get-StringArray $verify.gap_flags) + @('tooling_enforcement_stop', 'behavior_test_charter_gap', 'horizontal_slice_gap')) | Select-Object -Unique)
        Set-ObjectProperty -Object $verify -Name 'verification_status' -Value 'FAIL'
        Set-ObjectProperty -Object $verify -Name 'adjusted_coverage_delta' -Value 0
        Set-ObjectProperty -Object $verify -Name 'coverage_delta' -Value 0
        Set-ObjectProperty -Object $verify -Name 'should_continue' -Value $false
        Set-ObjectProperty -Object $verify -Name 'authorized_for_next_slice' -Value $false
        Set-ObjectProperty -Object $verify -Name 'authorized_for_synthesis' -Value $false
        Set-ObjectProperty -Object $verify -Name 'authorization_blockers' -Value @($blockers)
        Set-ObjectProperty -Object $verify -Name 'gap_flags' -Value @($gapFlags)
        Set-ObjectProperty -Object $verify -Name 'v348_slice_quality_gate' -Value $result
        $verify | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $SliceVerifyPath -Encoding UTF8
    }

    $blocker = ((Get-StringArray $result.issues) -join ',')
    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} v348 slice quality stop | v348_slice_quality | implementation_quality | non_authorizing_evidence | issues={1}; result={2}. |" -f $SliceIndex, $blocker, $gatePath)
    return [pscustomobject]@{ CanProceed = $false; ResultPath = $gatePath; Blocker = $blocker }
}

function Invoke-RedPhaseHardGate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$SliceResultPath,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gateScript = Join-Path $PSScriptRoot 'Invoke-RedPhaseHardGate.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('RED_PHASE_GATE_{0:D2}.stdout.log' -f $SliceIndex)
    $stderrPath = Join-Path $ReplayRoot ('RED_PHASE_GATE_{0:D2}.stderr.log' -f $SliceIndex)

    if (-not (Test-Path -LiteralPath $SliceResultPath)) {
        Write-Host "RED phase gate skipped: slice result missing" -ForegroundColor DarkGray
        return [pscustomobject]@{ CanProceed = $true; ResultPath = ''; Blocker = '' }
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "RED phase gate: script missing at $gateScript" -ForegroundColor Yellow
        return [pscustomobject]@{ CanProceed = $true; ResultPath = ''; Blocker = '' }
    }

    Write-Host "Running RED phase hard gate for slice $SliceIndex..." -ForegroundColor Cyan

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -VerifyOnly -SliceResultPath $SliceResultPath -SliceIndex $SliceIndex -ReplayRoot $ReplayRoot > $stdoutPath 2> $stderrPath
    $exitCode = $LASTEXITCODE
    $stdoutText = Read-TextIfExists -Path $stdoutPath
    $stderrText = Read-TextIfExists -Path $stderrPath

    $gatePath = Join-Path $ReplayRoot ('RED_PHASE_GATE_{0:D2}.json' -f $SliceIndex)

    if ($exitCode -eq 0) {
        Write-Host "RED phase hard gate: PASSED" -ForegroundColor Green
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} red-phase hard gate pass | red_phase_hard_gate | tdd_compliance | executable_evidence | result={1}. |" -f $SliceIndex, $gatePath)
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $gatePath; Blocker = '' }
    }

    Write-Host "RED phase hard gate: FAILED (exit code $exitCode)" -ForegroundColor Red
    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} red-phase hard gate stop | red_phase_hard_gate | tdd_compliance | non_authorizing_evidence | exit_code={1}; result={2}. |" -f $SliceIndex, $exitCode, $gatePath)

    # Read gate result for issue codes
    if (Test-Path -LiteralPath $gatePath) {
        try {
            $gateResult = Read-JsonObject -Path $gatePath
            $issueCodes = @(Get-StringArray $gateResult.issues | ForEach-Object { $_.code })
            if ($issueCodes.Count -eq 0) { $issueCodes = @('red_phase_hard_gate_failed') }
        } catch {
            $issueCodes = @('red_phase_hard_gate_failed')
        }
    } else {
        $issueCodes = @('red_phase_hard_gate_failed')
    }

    return [pscustomobject]@{ CanProceed = $false; ResultPath = $gatePath; Blocker = ($issueCodes -join ',') }
}

function Invoke-ContractVerificationGate {
    <#
    .SYNOPSIS
    Pre-implementation contract verification gate

    .DESCRIPTION
    Verifies all referenced service methods exist with correct signatures
    before Phase 1 RED phase starts. Prevents carrier invention anti-pattern.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gateScript = Join-Path $PSScriptRoot 'Invoke-ContractVerification.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('CONTRACT_VERIFICATION_{0:D2}.stdout.log' -f $SliceIndex)
    $resultPath = Join-Path $ReplayRoot ('CONTRACT_VERIFICATION_{0:D2}.json' -f $SliceIndex)

    $result = [ordered]@{
        gate = 'contract_verification'
        slice_index = $SliceIndex
        verification_status = 'SKIPPED'
        can_proceed = $true
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "Contract verification gate: script missing at $gateScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    # Check if TEST_CHARTER.md exists
    $testCharterPath = Join-Path $ReplayRoot 'TEST_CHARTER.md'
    if (-not (Test-Path -LiteralPath $testCharterPath)) {
        Write-Host "Contract verification gate: TEST_CHARTER.md not found (skipping)" -ForegroundColor DarkGray
        $result.verification_status = 'NO_TEST_CHARTER'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    Write-Host "Running pre-implementation contract verification..." -ForegroundColor Cyan

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -WorkDir $ReplayRoot -PassThru *> $stdoutPath
    $exitCode = $LASTEXITCODE
    $stdoutText = Read-TextIfExists -Path $stdoutPath

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath

    if ($exitCode -eq 0) {
        Write-Host "Contract verification: PASSED" -ForegroundColor Green
        $result.verification_status = 'PASSED'
        $result.can_proceed = $true
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} contract verification pass | contract_verification | tdd_compliance | executable_evidence | result={1}. |" -f $SliceIndex, $resultPath)
    } else {
        Write-Host "Contract verification: FAILED" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        $result.stdout_output = $stdoutText
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} contract verification stop | contract_verification | tdd_compliance | non_authorizing_evidence | exit_code={1}; result={2}. |" -f $SliceIndex, $exitCode, $resultPath)
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    return [pscustomobject]@{ CanProceed = $result.can_proceed; ResultPath = $resultPath; Blocker = 'contract_verification_failed' }
}

function Invoke-CallableCarrierAuthorizationGate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gateScript = Join-Path $PSScriptRoot 'Invoke-CallableCarrierAuthorization.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.stdout.log' -f $SliceIndex)
    $resultPath = Join-Path $ReplayRoot ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} callable-carrier authorization missing | callable_carrier_authorization | tdd_compliance | non_authorizing_evidence | script_missing={1}. |" -f $SliceIndex, $gateScript)
        return [pscustomobject]@{ CanProceed = $false; ResultPath = $resultPath; Blocker = 'callable_carrier_gate_missing' }
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $ReplayRoot -Worktree $Worktree -SliceIndex $SliceIndex *> $stdoutPath
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} callable-carrier authorization pass | callable_carrier_authorization | tdd_compliance | executable_evidence | result={1}. |" -f $SliceIndex, $resultPath)
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    $blocker = 'callable_carrier_authorization_failed'
    if (Test-Path -LiteralPath $resultPath) {
        try {
            $result = Read-JsonObject -Path $resultPath
            $blockers = @(Get-StringArray $result.blockers)
            if ($blockers.Count -gt 0) { $blocker = ($blockers -join ',') }
        } catch {
            $blocker = 'callable_carrier_authorization_unreadable'
        }
    }
    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} callable-carrier authorization stop | callable_carrier_authorization | tdd_compliance | non_authorizing_evidence | exit_code={1}; blocker={2}; result={3}. |" -f $SliceIndex, $exitCode, $blocker, $resultPath)
    return [pscustomobject]@{ CanProceed = $false; ResultPath = $resultPath; Blocker = $blocker }
}

function Invoke-IncrementalVerificationGate {
    <#
    .SYNOPSIS
    Incremental verification after TDD phases

    .DESCRIPTION
    Runs lightweight verification after RED (test surface check) and GREEN (no-TODO check)
    to catch issues earlier and reduce wasted tokens.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase,
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$SliceResultPath,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $validPhases = @('RED', 'GREEN', 'SIDE_EFFECT')
    if ($Phase -notin $validPhases) {
        Write-Error "Invalid phase: $Phase"
        return [pscustomobject]@{ CanProceed = $false; Blocker = "invalid_phase_$Phase" }
    }

    $localScriptRoot = Resolve-RunSliceLoopScriptRoot
    $gateScript = Join-Path $localScriptRoot 'Invoke-IncrementalVerification.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('INCREMENTAL_VERIFICATION_{0}_{1:D2}.stdout.log' -f $Phase, $SliceIndex)
    $resultPath = Join-Path $ReplayRoot ('INCREMENTAL_VERIFICATION_{0}_{1:D2}.json' -f $Phase, $SliceIndex)

    $result = [ordered]@{
        gate = 'incremental_verification'
        phase = $Phase
        slice_index = $SliceIndex
        verification_status = 'SKIPPED'
        can_proceed = $true
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "$Phase phase incremental verification: script missing at $gateScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    if (-not (Test-Path -LiteralPath $SliceResultPath)) {
        Write-Host "$Phase phase incremental verification: slice result missing (skipping)" -ForegroundColor DarkGray
        $result.verification_status = 'NO_SLICE_RESULT'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    Write-Host "Running $Phase phase incremental verification..." -ForegroundColor Cyan

    $filesToCheck = @()
    if (Test-Path -LiteralPath $SliceResultPath) {
        $sliceResult = Read-JsonObject -Path $SliceResultPath
        if ($Phase -eq 'RED') {
            $redEvidenceFiles = New-Object System.Collections.Generic.List[string]
            if ($null -ne $sliceResult.behavior_test_charter) {
                foreach ($file in @(Get-SliceEvidenceFiles -BehaviorCharter $sliceResult.behavior_test_charter)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$file)) {
                        $redEvidenceFiles.Add([string]$file) | Out-Null
                    }
                }
            }
            if ($null -ne $sliceResult.tests) {
                foreach ($test in $sliceResult.tests) {
                    if ($test.phase -eq $Phase -and $null -ne $test.evidence_file) {
                        $redEvidenceFiles.Add([string]$test.evidence_file) | Out-Null
                    }
                }
            }
            if ($redEvidenceFiles.Count -gt 0) {
                $filesToCheck = @($redEvidenceFiles | Select-Object -Unique)
            }
        }
        if ($filesToCheck.Count -eq 0 -and $null -ne $sliceResult.implemented_files) {
            $filesToCheck = @(Get-StringArray $sliceResult.implemented_files)
        }
        if ($Phase -ne 'RED' -and $null -ne $sliceResult.tests) {
            foreach ($test in $sliceResult.tests) {
                if ($test.phase -eq $Phase -and $null -ne $test.evidence_file) {
                    $filesToCheck += [string]$test.evidence_file
                }
            }
        }
    }

    $runInfo = Read-JsonIfExists -Path (Join-Path $ReplayRoot 'AUTOPILOT_RUN.json')
    $workDir = if ($null -ne $runInfo -and $runInfo.PSObject.Properties.Name -contains 'worktree' -and -not [string]::IsNullOrWhiteSpace([string]$runInfo.worktree)) {
        [string]$runInfo.worktree
    } else {
        Join-Path $ReplayRoot 'worktree'
    }
    if (-not (Test-Path -LiteralPath $workDir)) {
        $workDir = $ReplayRoot
    }

    $invokeArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $gateScript,
        '-Phase', $Phase,
        '-WorkDir', $workDir
    )
    if ($filesToCheck.Count -gt 0) {
        $invokeArgs += '-Files'
        foreach ($file in $filesToCheck) { $invokeArgs += [string]$file }
    }
    $invokeArgs += '-PassThru'

    & powershell @invokeArgs *> $stdoutPath
    $exitCode = $LASTEXITCODE
    $stdoutText = Read-TextIfExists -Path $stdoutPath

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath
    $result.work_dir = $workDir
    $result.files_checked = @($filesToCheck)

    if ($exitCode -eq 0) {
        Write-Host "$Phase phase incremental verification: PASSED" -ForegroundColor Green
        $result.verification_status = 'PASSED'
        $result.can_proceed = $true
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} {1} incremental verification pass | incremental_verification | tdd_compliance | executable_evidence | result={2}. |" -f $SliceIndex, $Phase, $resultPath)
    } else {
        Write-Host "$Phase phase incremental verification: FAILED" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        $result.stdout_output = $stdoutText
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} {1} incremental verification stop | incremental_verification | tdd_compliance | non_authorizing_evidence | exit_code={2}; result={3}. |" -f $SliceIndex, $Phase, $exitCode, $resultPath)
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    return [pscustomobject]@{ CanProceed = $result.can_proceed; ResultPath = $resultPath; Blocker = "${Phase}_incremental_verification_failed" }
}

function Invoke-TodoDetectorGate {
    <#
    .SYNOPSIS
    TODO placeholder detection gate

    .DESCRIPTION
    Explicitly bans TODO placeholders in implementation code.
    Forces either real implementation or honest BLOCKED declaration.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $localScriptRoot = Resolve-RunSliceLoopScriptRoot
    $gateScript = Join-Path $localScriptRoot 'Invoke-TodoPlaceholderCheck.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('TODO_DETECTION_{0:D2}.stdout.log' -f $SliceIndex)
    $resultPath = Join-Path $ReplayRoot ('TODO_DETECTION_{0:D2}.json' -f $SliceIndex)

    $result = [ordered]@{
        gate = 'todo_detector'
        slice_index = $SliceIndex
        verification_status = 'SKIPPED'
        can_proceed = $true
        todo_count = 0
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "TODO placeholder check: script missing at $gateScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    Write-Host "Running TODO placeholder production-code gate..." -ForegroundColor Cyan

    $todoPaths = @()
    $sliceResultPath = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
    if (Test-Path -LiteralPath $sliceResultPath) {
        try {
            $sliceResult = Read-JsonObject -Path $sliceResultPath
            $todoPaths = @(
                @($sliceResult.implemented_files) +
                @($sliceResult.current_slice_changed_files) +
                @($sliceResult.changed_files)
            ) | ForEach-Object { [string]$_ } | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -match '(?i)src[\\/]+main[\\/]+java' -and
                $_ -notmatch '(?i)src[\\/]+test[\\/]+java'
            } | Select-Object -Unique
        } catch {
            $todoPaths = @()
        }
    }

    $todoArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $gateScript,
        '-Worktree', $Worktree,
        '-ResultPath', (Join-Path $ReplayRoot ('TODO_CHECK_RESULT_{0:D2}.json' -f $SliceIndex))
    )
    if ($todoPaths.Count -gt 0) {
        $todoArgs += @('-PathList', (($todoPaths | ForEach-Object { [string]$_ }) -join [System.IO.Path]::PathSeparator))
    }

    & powershell @todoArgs *> $stdoutPath
    $exitCode = $LASTEXITCODE
    $stdoutText = Read-TextIfExists -Path $stdoutPath

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath
    $result.paths_checked = @($todoPaths)
    $result.placeholder_result_path = (Join-Path $ReplayRoot ('TODO_CHECK_RESULT_{0:D2}.json' -f $SliceIndex))

    if ($exitCode -eq 0) {
        Write-Host "TODO placeholder gate: NO PRODUCTION PLACEHOLDERS" -ForegroundColor Green
        $result.verification_status = 'PASSED'
        $result.can_proceed = $true
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} TODO placeholder gate pass | todo_placeholder_check | implementation_quality | executable_evidence | script=Invoke-TodoPlaceholderCheck.ps1; result={1}. |" -f $SliceIndex, $resultPath)
    } else {
        Write-Host "TODO placeholder gate: PRODUCTION PLACEHOLDERS FOUND" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        $result.stdout_output = $stdoutText
        # Count TODOs from output
        if ($stdoutText -match '(?i)(TODO|FIXME|XXX)') {
            $todoLines = $stdoutText -split '\n' | Where-Object { $_ -match '(?i)(TODO|FIXME|XXX)' }
            $result.todo_count = $todoLines.Count
        }
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} TODO placeholder gate stop | todo_placeholder_check | implementation_quality | non_authorizing_evidence | script=Invoke-TodoPlaceholderCheck.ps1; exit_code={1}; todos={2}; result={3}. |" -f $SliceIndex, $exitCode, $result.todo_count, $resultPath)
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    return [pscustomobject]@{ CanProceed = $result.can_proceed; ResultPath = $resultPath; Blocker = 'todo_placeholders_found' }
}

function Convert-TestCharterDiagnosticList {
    param($Items)

    $diagnostics = @()
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $entry = [ordered]@{}
        foreach ($name in @('code', 'message', 'detail')) {
            if ($item.PSObject.Properties[$name]) {
                $entry[$name] = [string]$item.$name
            }
        }
        if ($item.PSObject.Properties['patterns']) {
            $entry['patterns'] = @(Get-StringArray $item.patterns)
        }
        if ($item.PSObject.Properties['classifications']) {
            $entry['classifications'] = @(Get-StringArray $item.classifications)
        }
        if ($item.PSObject.Properties['repairable_charter_failure']) {
            $entry['repairable_charter_failure'] = [bool]$item.repairable_charter_failure
        }
        if ($entry.Count -eq 0) {
            $entry['message'] = [string]$item
        }
        $diagnostics += [pscustomobject]$entry
    }
    return @($diagnostics)
}

function Invoke-TestCharterPrevalidatorGate {
    <#
    .SYNOPSIS
    Test Charter Pre-Validation Gate (v379)

    .DESCRIPTION
    Validates TEST_CHARTER.md completeness BEFORE RED phase starts.
    Prevents wrong_test_surface failures by requiring:
    - Entry Point specified
    - Test Surface at Facade/Controller layer (not Service)
    - DB Verification queries documented
    - Side Effects with verification method
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gateScript = Join-Path $PSScriptRoot 'Invoke-TestCharterPrevalidator.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('TEST_CHARTER_VALIDATION_{0:D2}.stdout.log' -f $SliceIndex)
    $resultPath = Join-Path $ReplayRoot ('TEST_CHARTER_VALIDATION_{0:D2}.json' -f $SliceIndex)

    $result = [ordered]@{
        gate = 'test_charter_prevalidation'
        slice_index = $SliceIndex
        verification_status = 'SKIPPED'
        can_proceed = $true
        failures = @()
        warnings = @()
        source_chain_classifications = @()
        repairable_charter_failure = $false
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "Test charter prevalidation: script missing at $gateScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    # Check if TEST_CHARTER.md exists
    $testCharterPath = Join-Path $ReplayRoot 'TEST_CHARTER.md'
    if (-not (Test-Path -LiteralPath $testCharterPath)) {
        Write-Host "Test charter prevalidation: TEST_CHARTER.md not found" -ForegroundColor Red
        $result.verification_status = 'NO_TEST_CHARTER'
        $result.can_proceed = $false
        $result.failures = @([ordered]@{
            code = 'TEST_CHARTER_MISSING'
            message = 'TEST_CHARTER.md is required before RED/test implementation.'
        })
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test charter prevalidation stop | test_charter_prevalidation | tdd_compliance | non_authorizing_evidence | missing=TEST_CHARTER.md; result={1}. |" -f $SliceIndex, $resultPath)
        return [pscustomobject]@{ CanProceed = $false; ResultPath = $resultPath; Blocker = 'test_charter_missing_before_implementation' }
    }

    Write-Host "Running test charter prevalidation..." -ForegroundColor Cyan

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -WorkDir $ReplayRoot -PassThru *> $stdoutPath
    $exitCode = $LASTEXITCODE
    $stdoutText = Read-TextIfExists -Path $stdoutPath

    # Parse JSON output
    $jsonOutput = $null
    if (Test-Path -LiteralPath $stdoutPath) {
        $stdoutLines = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
        try {
            $jsonOutput = $stdoutLines | ConvertFrom-Json
        } catch {
            # Output parsing failed, use exit code
        }
    }

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath

    if ($exitCode -eq 0) {
        Write-Host "Test charter prevalidation: PASSED" -ForegroundColor Green
        $result.verification_status = 'PASSED'
        $result.can_proceed = $true
        if ($null -ne $jsonOutput) {
            $result.warnings = @(Convert-TestCharterDiagnosticList $jsonOutput.warnings)
            if ($jsonOutput.PSObject.Properties['warning_count']) {
                $result.warning_count = [int]$jsonOutput.warning_count
            }
        }
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test charter prevalidation pass | test_charter_prevalidation | tdd_compliance | executable_evidence | result={1}. |" -f $SliceIndex, $resultPath)
    } else {
        Write-Host "Test charter prevalidation: FAILED" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        if ($null -ne $jsonOutput) {
            $result.failures = @(Convert-TestCharterDiagnosticList $jsonOutput.failures)
            $result.warnings = @(Convert-TestCharterDiagnosticList $jsonOutput.warnings)
            if ($jsonOutput.PSObject.Properties['source_chain_classifications']) {
                $result.source_chain_classifications = @($jsonOutput.source_chain_classifications)
            }
            if ($jsonOutput.PSObject.Properties['repairable_charter_failure']) {
                $result.repairable_charter_failure = [bool]$jsonOutput.repairable_charter_failure
            }
            if ($jsonOutput.PSObject.Properties['failure_count']) {
                $result.failure_count = [int]$jsonOutput.failure_count
            }
            if ($jsonOutput.PSObject.Properties['warning_count']) {
                $result.warning_count = [int]$jsonOutput.warning_count
            }
        }
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test charter prevalidation stop | test_charter_prevalidation | tdd_compliance | non_authorizing_evidence | exit_code={1}; result={2}. |" -f $SliceIndex, $exitCode, $resultPath)
    }

    ([pscustomobject]$result) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    return [pscustomobject]@{
        CanProceed = $result.can_proceed
        ResultPath = $resultPath
        Blocker = 'test_charter_validation_failed'
        RepairableCharterFailure = [bool]$result.repairable_charter_failure
        SourceChainClassifications = @($result.source_chain_classifications)
    }
}

function Invoke-TestCharterRepairGate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath,
        [Parameter(Mandatory = $true)]
        $ForcedDecision,
        [Parameter(Mandatory = $true)]
        $FailedGate,
        [string]$Executor = 'codex',
        [string]$Sandbox = 'danger-full-access',
        [string]$Approval = 'never',
        [int]$TimeoutMinutes = 10,
        [string]$Model = '',
        [string]$ReasoningEffort = ''
    )

    if ($Executor -eq 'manual') {
        return $FailedGate
    }

    $repairPrompt = Join-Path $ReplayRoot ('TEST_CHARTER_REPAIR_PROMPT_{0:D2}.md' -f $SliceIndex)
    $repairResult = Join-Path $ReplayRoot ('TEST_CHARTER_REPAIR_RESULT_{0:D2}.md' -f $SliceIndex)
    $repairLogDir = Join-Path (Join-Path $ReplayRoot 'logs\test-charter-repair') ('slice{0:D2}' -f $SliceIndex)
    $validator = Join-Path $PSScriptRoot 'Invoke-TestCharterPrevalidator.ps1'
    $charterPath = Join-Path $ReplayRoot 'TEST_CHARTER.md'
    $stdoutPath = Join-Path $ReplayRoot ('TEST_CHARTER_VALIDATION_{0:D2}.stdout.log' -f $SliceIndex)
    $failedEvidence = ''
    if ($null -ne $FailedGate -and -not [string]::IsNullOrWhiteSpace([string]$FailedGate.ResultPath) -and (Test-Path -LiteralPath ([string]$FailedGate.ResultPath))) {
        $failedEvidence = Read-TextIfExists -Path ([string]$FailedGate.ResultPath)
    } elseif (Test-Path -LiteralPath $stdoutPath) {
        $failedEvidence = Read-TextIfExists -Path $stdoutPath
    }
    if ([string]::IsNullOrWhiteSpace($failedEvidence)) {
        $failedEvidence = 'No structured validation evidence was written; inspect TEST_CHARTER.md against Invoke-TestCharterPrevalidator.ps1.'
    }

    $referenceFiles = @(
        'PLAN_RESULT.md',
        'FIRST_SLICE_PROOF_PLAN.md',
        ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex),
        ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $SliceIndex),
        ('NEXT_SLICE_EXACT_CONTRACT_{0:D2}.json' -f $SliceIndex),
        'IMPLEMENTATION_CONTRACT.md',
        'REPLAY_PLAN.md'
    ) | ForEach-Object { Join-Path $ReplayRoot $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $referenceText = if (@($referenceFiles).Count -gt 0) { ($referenceFiles | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $forcedFamily = [string]$ForcedDecision.family_id
    $forcedSliceType = [string]$ForcedDecision.slice_type
    $forcedSurface = [string]$ForcedDecision.target_sibling_surface
    $repairTimeout = [Math]::Min([Math]::Max($TimeoutMinutes, 1), 10)

    $prompt = @(
        '# Test Charter Repair',
        '',
        'Repair only the replay-root TEST_CHARTER.md so the pre-implementation test charter prevalidator passes.',
        '',
        'Hard constraints:',
        '- Edit only TEST_CHARTER.md in the replay root unless writing the required repair result file.',
        '- Do not edit production code or test code in the worktree.',
        '- Do not introduce fixed numeric database case ids, real database dependencies, Spring test harnesses, or null-task-data pass paths.',
        '- Preserve the selected real production carrier and source-chain proof from the reference artifacts.',
        '',
        'Validation failure evidence:',
        '```json',
        $failedEvidence.Trim(),
        '```',
        '',
        'Forced slice:',
        "- family: $forcedFamily",
        "- slice_type: $forcedSliceType",
        "- sibling_surface: $forcedSurface",
        '',
        'Reference artifacts:',
        $referenceText,
        '',
        'TEST_CHARTER.md must include markdown labels recognized by scripts/test_charter_prevalidator.py:',
        '- `Entry Point: <exact production entry method(s)>`',
        '- `Test Class: <no-Spring JUnit/Mockito test class in the selected test module>`',
        '- `DB Verification: <AtomicReference capture, mock ArgumentCaptor, or SELECT/query verification method>`',
        '- `Side Effects:` followed by bullet lines that each include verify/assert/query language.',
        '',
        'For source-chain rebuild requirements, the entry point must name the real production carrier(s), and the verification must prove declared source fields move from the production source chain into the rebuilt downstream data or payload. Do not describe a synthetic or hand-built terminal-data-only proof.',
        '',
        'After editing, run this validation command and continue editing until it reports can_proceed=true:',
        "powershell -NoProfile -ExecutionPolicy Bypass -File `"$validator`" -WorkDir `"$ReplayRoot`" -PassThru",
        '',
        "Finally write $repairResult with:",
        '- repair_status: COMPLETE or BLOCKED',
        '- validation_status: PASSED or FAILED',
        '- files_modified: TEST_CHARTER.md',
        '- remaining_blocker: none or a concrete blocker'
    ) -join "`n"
    Set-Content -LiteralPath $repairPrompt -Value $prompt -Encoding UTF8

    $repairArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
        '-PromptPath', $repairPrompt,
        '-WorkDir', $Worktree,
        '-LogDir', $repairLogDir,
        '-Executor', $Executor,
        '-Sandbox', $Sandbox,
        '-Approval', $Approval,
        '-TimeoutMinutes', $repairTimeout,
        '-CompletionPath', $repairResult,
        '-CompletionQuietSeconds', 30,
        '-Name', ('test-charter-repair-{0:D2}' -f $SliceIndex)
    )
    if (-not [string]::IsNullOrWhiteSpace($Model)) { $repairArgs += @('-Model', $Model) }
    if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) { $repairArgs += @('-ReasoningEffort', $ReasoningEffort) }

    $smokeArgs = @($repairArgs + @('-ValidateOnly'))
    & powershell @smokeArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test charter repair smoke stop | {1} | {2} | test_charter_repair_invocation_failed | validate-only exit_code={3}; original_result={4}. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $LASTEXITCODE, $FailedGate.ResultPath)
        return $FailedGate
    }

    $repairExit = Invoke-SliceExecutorWithRetry -AgentArgs $repairArgs -SliceLogDir $repairLogDir -SliceId ('test-charter-repair-{0:D2}' -f $SliceIndex) -MaxRetries 1 -DelaySeconds 30
    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test charter repair pass | {1} | {2} | test_charter_repair_attempt | exit_code={3}; result={4}. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $repairExit, $repairResult)

    $recheck = Invoke-TestCharterPrevalidatorGate -ReplayRoot $ReplayRoot -SliceIndex $SliceIndex -RunnerContractPath $RunnerContractPath
    if ([bool]$recheck.CanProceed) {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test charter repair verified | {1} | {2} | executable_evidence | prevalidator passed after repair; result={3}. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $recheck.ResultPath)
        if ($repairExit -ne 0) {
            Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} test charter repair executor nonzero ignored | {1} | {2} | executable_evidence | repair executor exit_code={3}; prevalidator passed after repair; result={4}. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $repairExit, $recheck.ResultPath)
        }
        return $recheck
    }
    if ($repairExit -ne 0) {
        return $FailedGate
    }
    return $recheck
}

function Invoke-LayerValidationGate {
    <#
    .SYNOPSIS
    Layer Validation Gate (v431 Experiment 1)

    .DESCRIPTION
    Validates TEST_CHARTER.md specifies Facade/Controller layer, not Service layer.
    Prevents wrong_test_surface violations by checking layer selection BEFORE execution.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gateScript = Join-Path $PSScriptRoot 'pre-flight-check.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('LAYER_VALIDATION_{0:D2}.stdout.log' -f $SliceIndex)
    $resultPath = Join-Path $ReplayRoot ('LAYER_VALIDATION_RESULT.json')

    $result = [ordered]@{
        gate = 'layer_validation'
        slice_index = $SliceIndex
        verification_status = 'SKIPPED'
        can_proceed = $true
        failures = @()
        warnings = @()
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "Layer validation: script missing at $gateScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $resultPath; Blocker = '' }
    }

    $stdoutText = & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $ReplayRoot -Worktree $Worktree 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath
    $stdoutText | Out-File -LiteralPath $stdoutPath -Encoding UTF8

    if ($exitCode -eq 0) {
        Write-Host "Layer validation: PASSED" -ForegroundColor Green
        $result.verification_status = 'PASSED'
        $result.can_proceed = $true
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} layer validation pass | layer_validation | wrong_test_surface | executable_evidence | result={1}. |" -f $SliceIndex, $resultPath)

        # v450: Experiment 2 - Apply service layer allowlist check after pre-flight passes
        $layerAllowlistScript = Join-Path $PSScriptRoot 'layer_validation_gate.ps1'
        if (Test-Path -LiteralPath $layerAllowlistScript) {
            # Get selected carrier from phase0 result
            $phase0ResultPath = Join-Path $ReplayRoot 'PHASE0_RESULT.md'
            $selectedCarrier = ''
            if (Test-Path -LiteralPath $phase0ResultPath) {
                $phase0Content = Get-Content -LiteralPath $phase0ResultPath -Raw -Encoding UTF8
                if ($phase0Content -match 'selected_real_entry\s*[:=]\s*`?([^\s`]+)') {
                    $selectedCarrier = $matches[1]
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($selectedCarrier)) {
                Write-Host "INFO: Checking service layer allowlist for carrier '$selectedCarrier' (v450 Experiment 2)..." -ForegroundColor Cyan
                & powershell -NoProfile -ExecutionPolicy Bypass -File $layerAllowlistScript -ReplayRoot $ReplayRoot -SelectedCarrier $selectedCarrier -SliceAuthorizationPath $resultPath | Out-Null
            }
        }
    } else {
        Write-Host "Layer validation: FAILED" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        $result.stdout_output = $stdoutText
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} layer validation stop | layer_validation | wrong_test_surface | non_authorizing_evidence | exit_code={1}; result={2}. |" -f $SliceIndex, $exitCode, $resultPath)
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    return [pscustomobject]@{ CanProceed = $result.can_proceed; ResultPath = $resultPath; Blocker = 'layer_validation_failed' }
}

function Invoke-SideEffectLedgerGate {
    <#
    .SYNOPSIS
    Side Effect Ledger Gate (v431 Experiment 2)

    .DESCRIPTION
    Validates SIDE_EFFECT_LEDGER.md exists and has proper verification for stateful families.
    Prevents side_effect_ledger_gap by requiring side effect documentation before slice completion.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gateScript = Join-Path $PSScriptRoot 'verify-slice.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('SIDE_EFFECT_LEDGER_VERIFICATION_{0:D2}.stdout.log' -f $SliceIndex)
    $sliceResultPath = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)

    $result = [ordered]@{
        gate = 'side_effect_ledger'
        slice_index = $SliceIndex
        verification_status = 'SKIPPED'
        can_proceed = $true
        failures = @()
        warnings = @()
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "Side effect ledger: script missing at $gateScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        return [pscustomobject]@{ CanProceed = $true; ResultPath = ''; Blocker = '' }
    }

    $stdoutText = & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $ReplayRoot -SliceResultPath $sliceResultPath 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath
    $stdoutText | Out-File -LiteralPath $stdoutPath -Encoding UTF8

    # Read the JSON result if it exists
    $jsonResultPath = Join-Path $ReplayRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json'
    if (Test-Path -LiteralPath $jsonResultPath) {
        $jsonOutput = Get-Content -LiteralPath $jsonResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.can_proceed = $jsonOutput.can_proceed
        $result.verification_status = $jsonOutput.validation_status
    }

    if ($exitCode -eq 0 -and $result.can_proceed) {
        Write-Host "Side effect ledger: PASSED" -ForegroundColor Green
        $result.verification_status = 'PASSED'
        $result.can_proceed = $true
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} side effect ledger pass | side_effect_ledger | side_effect_ledger_gap | executable_evidence | result={1}. |" -f $SliceIndex, $jsonResultPath)
    } else {
        Write-Host "Side effect ledger: FAILED" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        $result.stdout_output = $stdoutText
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} side effect ledger stop | side_effect_ledger | side_effect_ledger_gap | non_authorizing_evidence | exit_code={1}; result={2}. |" -f $SliceIndex, $exitCode, $jsonResultPath)
    }

    return [pscustomobject]@{ CanProceed = $result.can_proceed; ResultPath = $jsonResultPath; Blocker = 'side_effect_ledger_failed' }
}

function Invoke-FamilyProofLedgerGate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath
    )

    $gateScript = Join-Path $PSScriptRoot 'verify_family_proof_ledger.ps1'
    $familyLedgerPath = Join-Path $ReplayRoot 'REQUIREMENT_FAMILY_LEDGER.json'
    $sliceContractPath = Join-Path $ReplayRoot ('SLICE_EXECUTION_CONTRACT_{0:D2}.json' -f $SliceIndex)
    $sliceResultPath = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
    $outputPath = Join-Path $ReplayRoot ('FAMILY_PROOF_LEDGER_{0:D2}.json' -f $SliceIndex)

    if (-not (Test-Path -LiteralPath $gateScript -PathType Leaf)) {
        return [pscustomobject]@{ CanProceed = $false; ResultPath = ''; Blocker = 'family_proof_ledger_script_missing' }
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript `
        -FamilyLedger $familyLedgerPath `
        -SliceContract $sliceContractPath `
        -SliceResult $sliceResultPath `
        -OutputPath $outputPath | Out-Null
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} family proof ledger pass | family_proof_ledger | side_effect_ledger_gap,wrong_test_surface,exact_contract_gap | executable_evidence | result={1}. |" -f $SliceIndex, $outputPath)
        return [pscustomobject]@{ CanProceed = $true; ResultPath = $outputPath; Blocker = '' }
    }

    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} family proof ledger stop | family_proof_ledger | side_effect_ledger_gap,wrong_test_surface,exact_contract_gap | non_authorizing_evidence | exit_code={1}; result={2}. |" -f $SliceIndex, $exitCode, $outputPath)
    return [pscustomobject]@{ CanProceed = $false; ResultPath = $outputPath; Blocker = 'family_proof_ledger_failed' }
}

function Invoke-Phase0PrecheckGate {
    <#
    .SYNOPSIS
    Phase0 Precheck Gate (v431 Experiment 3)

    .DESCRIPTION
    Pre-validates test framework and RED phase authorization.
    Prevents RC3 (implementation after blocked RED) and RC5 (test framework not pre-validated).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [string]$Worktree,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath,
        [string]$MavenSettings = ''
    )

    $gateScript = Join-Path $PSScriptRoot 'phase0-precheck.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('PHASE0_PRECHECK_{0:D2}.stdout.log' -f $SliceIndex)
    $sliceResultPath = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)

    $result = [ordered]@{
        gate = 'phase0_precheck'
        slice_index = $SliceIndex
        verification_status = 'SKIPPED'
        can_proceed = $true
        failures = @()
        warnings = @()
    }

    if (-not (Test-Path -LiteralPath $gateScript)) {
        Write-Host "Phase0 precheck: script missing at $gateScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        return [pscustomobject]@{ CanProceed = $true; ResultPath = ''; Blocker = '' }
    }

    $phase0Args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $gateScript,
        '-ReplayRoot', $ReplayRoot,
        '-Worktree', $Worktree,
        '-SliceIndex', $SliceIndex
    )
    if (-not [string]::IsNullOrWhiteSpace($MavenSettings)) {
        $phase0Args += @('-MavenSettings', $MavenSettings)
    }

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $stdoutText = & powershell @phase0Args 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath
    $stdoutText | Out-File -LiteralPath $stdoutPath -Encoding UTF8

    # Read the JSON result if it exists
    $jsonResultPath = Join-Path $ReplayRoot 'PHASE0_PRECHECK_RESULT.json'
    if (Test-Path -LiteralPath $jsonResultPath) {
        $jsonOutput = Get-Content -LiteralPath $jsonResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.can_proceed = $jsonOutput.can_proceed
        $result.verification_status = $jsonOutput.validation_status
    }

    if ($exitCode -eq 0 -and $result.can_proceed) {
        Write-Host "Phase0 precheck: PASSED" -ForegroundColor Green
        $result.verification_status = 'PASSED'
        $result.can_proceed = $true
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} phase0 precheck pass | phase0_precheck | test_framework_validation | executable_evidence | result={1}. |" -f $SliceIndex, $jsonResultPath)
    } else {
        Write-Host "Phase0 precheck: FAILED" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        $result.stdout_output = $stdoutText
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} phase0 precheck stop | phase0_precheck | test_framework_validation | non_authorizing_evidence | exit_code={1}; result={2}. |" -f $SliceIndex, $exitCode, $jsonResultPath)
    }

    return [pscustomobject]@{ CanProceed = $result.can_proceed; ResultPath = $jsonResultPath; Blocker = 'phase0_precheck_failed' }
}

function Invoke-EconomyCheckpointGate {
    <#
    .SYNOPSIS
    Economy Checkpoint Gate (v454 Experiment 1)

    .DESCRIPTION
    Implements progressive checkpoint system to break circular gate deadlock.
    For S1 in discovery mode, WARN is acceptable at layer validation.
    S2-S12 require full checkpoint passing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReplayRoot,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [string]$RunnerContractPath,
        [string]$CheckpointId = 'CP2_LAYER_VALIDATION',
        [bool]$DiscoveryMode = $false
    )

    $checkpointScript = Join-Path $PSScriptRoot 'Invoke-EconomyCheckpoint.ps1'
    $stdoutPath = Join-Path $ReplayRoot ('CHECKPOINT_{0}_{1:D2}.stdout.log' -f $CheckpointId, $SliceIndex)

    $result = [ordered]@{
        gate = 'economy_checkpoint'
        slice_index = $SliceIndex
        checkpoint_id = $CheckpointId
        verification_status = 'SKIPPED'
        can_proceed = $true
        failures = @()
        warnings = @()
        discovery_mode = $DiscoveryMode
    }

    if (-not (Test-Path -LiteralPath $checkpointScript)) {
        Write-Host "Economy checkpoint: script missing at $checkpointScript" -ForegroundColor Yellow
        $result.verification_status = 'SCRIPT_MISSING'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot ('CHECKPOINT_GATE_{0:D2}.json' -f $SliceIndex)) -Encoding UTF8
        return [pscustomobject]@{ CanProceed = $true; ResultPath = ''; Blocker = '' }
    }

    # Run checkpoint validation
    $stdoutText = & powershell -NoProfile -ExecutionPolicy Bypass -File $checkpointScript -ReplayRoot $ReplayRoot -CheckpointId $CheckpointId 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    $result.exit_code = $exitCode
    $result.stdout_log = $stdoutPath
    $stdoutText | Out-File -LiteralPath $stdoutPath -Encoding UTF8

    # Read checkpoint result if it exists
    $checkpointResultPath = Join-Path $ReplayRoot ("CHECKPOINT_$($CheckpointId).json")
    $checkpointPassed = $false
    if (Test-Path -LiteralPath $checkpointResultPath) {
        try {
            $checkpointOutput = Get-Content -LiteralPath $checkpointResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $checkpointPassed = $checkpointOutput.validation_passed -eq $true
            $result.can_proceed = $checkpointOutput.can_proceed -eq $true
            $result.validation_status = if ($checkpointPassed) { 'PASS' } else { 'FAIL' }
            $result.validation_reason = $checkpointOutput.validation_reason
        } catch {
            Write-Host "WARN: Failed to parse checkpoint result: $_" -ForegroundColor Yellow
        }
    }

    # Discovery mode: WARN is acceptable for S1
    if ($DiscoveryMode -and $CheckpointId -eq 'CP2_LAYER_VALIDATION') {
        if ($exitCode -eq 0 -or $result.validation_status -eq 'WARN') {
            Write-Host "Economy checkpoint (Discovery Mode): PASSED with WARN tolerance" -ForegroundColor Green
            $result.verification_status = 'PASS'
            $result.can_proceed = $true
            $result.discovery_mode_warn_accepted = $true
            Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} economy checkpoint pass (discovery) | economy_checkpoint | {1} | executable_evidence | checkpoint={2}; result={3}. |" -f $SliceIndex, $CheckpointId, $checkpointResultPath, $result.validation_reason)
        } else {
            Write-Host "Economy checkpoint: FAILED" -ForegroundColor Red
            $result.verification_status = 'FAILED'
            $result.can_proceed = $false
            Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} economy checkpoint stop | economy_checkpoint | {1} | non_authorizing_evidence | checkpoint={2}; exit_code={3}. |" -f $SliceIndex, $CheckpointId, $checkpointResultPath, $exitCode)
        }
    } elseif ($exitCode -eq 0 -and $result.can_proceed) {
        Write-Host "Economy checkpoint: PASSED" -ForegroundColor Green
        $result.verification_status = 'PASS'
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} economy checkpoint pass | economy_checkpoint | {1} | executable_evidence | checkpoint={2}. |" -f $SliceIndex, $CheckpointId, $checkpointResultPath)
    } else {
        Write-Host "Economy checkpoint: FAILED" -ForegroundColor Red
        $result.verification_status = 'FAILED'
        $result.can_proceed = $false
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} economy checkpoint stop | economy_checkpoint | {1} | non_authorizing_evidence | checkpoint={2}; exit_code={3}. |" -f $SliceIndex, $CheckpointId, $checkpointResultPath, $exitCode)
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot ('CHECKPOINT_GATE_{0:D2}.json' -f $SliceIndex)) -Encoding UTF8
    return [pscustomobject]@{ CanProceed = $result.can_proceed; ResultPath = $checkpointResultPath; Blocker = 'economy_checkpoint_failed' }
}

function Get-RequirementFamilySpecs {
    return @(
        [pscustomobject]@{
            id = 'core_entry'
            title = 'Core real entry'
            weight = 100
            slice_type = 'tracer_bullet'
            keywords = @('core_entry', 'entry', 'real entry', 'processor', 'controller', 'facade', 'task', 'trigger', 'core path', 'main path', 'handler', 'worker')
        },
        [pscustomobject]@{
            id = 'stateful_side_effect'
            title = 'Stateful side effects'
            weight = 95
            slice_type = 'stateful_success_slice'
            keywords = @('stateful_side_effect', 'state', 'status', 'transaction', 'task', 'progress', 'log', 'db', 'persist', 'persistence', 'rollback', 'side effect', 'write')
        },
        [pscustomobject]@{
            id = 'deploy_export_page'
            title = 'Deploy-facing page/export surface'
            weight = 90
            slice_type = 'deploy_surface_first_slice'
            keywords = @('deploy_export_page', 'export', 'report', 'page', 'view', 'jsp', 'js', 'html', 'excel', 'screen', 'display', 'query', 'column', 'header')
        },
        [pscustomobject]@{
            id = 'wire_payload_api_contract'
            title = 'Wire/API exact contract'
            weight = 88
            slice_type = 'exact_contract_slice'
            keywords = @('wire_payload_api_contract', 'payload', 'request', 'response', 'api', 'endpoint', 'type', 'field', 'enum', 'json', 'wire', 'contract', 'body')
        },
        [pscustomobject]@{
            id = 'config_policy_threshold'
            title = 'Configurable policy/threshold'
            weight = 87
            slice_type = 'exact_contract_slice'
            keywords = @('config_policy_threshold', 'config', 'configuration', 'setting', 'threshold', 'amount', 'validator', 'validate', 'save', 'edit', 'query', 'clear', 'switch', 'rule')
        },
        [pscustomobject]@{
            id = 'generated_artifact_template_upload'
            title = 'Generated artifact/template/upload'
            weight = 86
            slice_type = 'deploy_surface_first_slice'
            keywords = @('generated_artifact_template_upload', 'template', 'image', 'png', 'pdf', 'upload', 'render', 'artifact', 'file', 'generate', 'attachment')
        },
        [pscustomobject]@{
            id = 'external_integration'
            title = 'External integration surface'
            weight = 82
            slice_type = 'deploy_surface_first_slice'
            keywords = @('external_integration', 'external', 'integration', 'dock', 'third', 'provider', 'payload', 'callback', 'refund', 'push', 'partner')
        },
        [pscustomobject]@{
            id = 'automation_test_interface'
            title = 'Automation/test interface contract'
            weight = 78
            slice_type = 'exact_contract_slice'
            keywords = @('automation_test_interface', 'automation', 'test interface', 'project_list', 'projectList', 'raw', 'original', 'test api')
        },
        [pscustomobject]@{
            id = 'lifecycle_cleanup_retention'
            title = 'Lifecycle cleanup/retention'
            weight = 76
            slice_type = 'stateful_success_slice'
            keywords = @('lifecycle_cleanup_retention', 'cleanup', 'clean up', 'delete', 'remove', 'retention', 'expire', 'stale', 'auto report', 'auto-report', 'history log', 'report log', 'idempotent')
        }
    )
}

function Get-KeywordHits {
    param([string]$Text, [object[]]$Keywords)
    $hits = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    foreach ($keyword in $Keywords) {
        $kw = [string]$keyword
        if (-not [string]::IsNullOrWhiteSpace($kw) -and $Text.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $hits.Add($kw) | Out-Null
        }
    }
    return @($hits)
}

function Test-ExplicitRequirementFamilyScope {
    param(
        [string]$FamilyId,
        [string]$RequirementText,
        $ContractFamily,
        [string]$EvidenceText = ''
    )

    $contractRequired = $null -ne $ContractFamily -and $null -ne $ContractFamily.required -and [bool]$ContractFamily.required
    $carrier = if ($null -ne $ContractFamily) { [string]$ContractFamily.first_executable_carrier } else { '' }
    $plannedSlice = if ($null -ne $ContractFamily) { [string]$ContractFamily.planned_slice } else { '' }
    $proof = if ($null -ne $ContractFamily -and $null -ne $ContractFamily.proof_required) { ((Get-StringArray $ContractFamily.proof_required) -join ' ') } else { '' }
    $hasConcreteContract = $contractRequired -and (
        -not [string]::IsNullOrWhiteSpace($carrier) -or
        -not [string]::IsNullOrWhiteSpace($proof) -or
        (-not [string]::IsNullOrWhiteSpace($plannedSlice) -and $plannedSlice -ne 'not_required')
    )
    if ($hasConcreteContract) { return $true }
    $combined = @($RequirementText, $EvidenceText, $carrier, $proof) -join "`n"

    switch ($FamilyId) {
        'deploy_export_page' {
            if ($combined -match '(?i)(导出|报表|报表接口|excel|页面|前端|jsp|javascript|js\b|展示字段|列表接口|查询接口|接口返回|下载|header|column|view|screen|display)') { return $true }
            if ($carrier -match '(?i)(controller|endpoint|export|report|excel|download|\.jsp|\.js|\.ts|\.vue|\.html|\.ftl|\.vm)') { return $true }
            return $false
        }
        'automation_test_interface' {
            return $combined -match '(?i)(自动化测试接口|测试接口|projectList|project_list|raw|original|原始责任项|automation\s+test)'
        }
        'wire_payload_api_contract' {
            return $combined -match '(?i)(payload|request|response|api|接口|请求|响应|报文|字段|json|wire|body)'
        }
        'generated_artifact_template_upload' {
            return $combined -match '(?i)(模板|图片|png|pdf|附件|上传|生成文件|影像|template|image|upload|artifact|attachment)'
        }
        'external_integration' {
            return $combined -match '(?i)(外部|对接|保司接口|第三方|回调|推送|http|client|adapter|external|integration|partner)'
        }
        'lifecycle_cleanup_retention' {
            if ($combined -match '(?i)(清理|删除|移除|过期|保留|留存|expire|cleanup|delete|remove|retention|duplicate|idempotent|same-status|same status|re-entry)') { return $true }
            return $contractRequired -and $combined -match '(?i)(cleanup|retention|expire|expired|delete|remove|preserve|must_not|must-not|do_not|do-not)'
        }
        default {
            return $contractRequired -or -not [string]::IsNullOrWhiteSpace($RequirementText)
        }
    }
}

function Apply-FamilyScopeFilter {
    param(
        $Ledger,
        [string]$RequirementSource,
        [string]$ReplayRoot
    )

    if ($null -eq $Ledger -or $null -eq $Ledger.families) { return $false }
    $featureChanged = Apply-FeatureClassificationToLedger -Ledger $Ledger -ReplayRoot $ReplayRoot
    $requirementText = Read-TextIfExists -Path $RequirementSource
    $familyContractPath = Join-Path $ReplayRoot 'FAMILY_CONTRACT.json'
    $contractFamiliesById = @{}
    if (Test-Path -LiteralPath $familyContractPath) {
        try {
            $familyContract = Read-JsonObject -Path $familyContractPath
            foreach ($family in @($familyContract.families)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$family.id)) {
                    $contractFamiliesById[[string]$family.id] = $family
                }
            }
        } catch {
            $contractFamiliesById = @{}
        }
    }
    $evidenceText = (@(
        $RequirementSource,
        $familyContractPath,
        (Join-Path $ReplayRoot 'EXPECTED_DIFF_MATRIX.md'),
        (Join-Path $ReplayRoot 'IMPLEMENTATION_CONTRACT.md'),
        (Join-Path $ReplayRoot 'REPLAY_PLAN.md')
    ) | ForEach-Object { Read-TextIfExists $_ }) -join "`n"

    $changed = [bool]$featureChanged
    $strictScopeFamilies = @(
        'deploy_export_page',
        'automation_test_interface',
        'wire_payload_api_contract',
        'generated_artifact_template_upload',
        'external_integration',
        'lifecycle_cleanup_retention'
    )
    foreach ($family in @($Ledger.families)) {
        $id = [string]$family.id
        if (-not [bool]$family.required) { continue }
        if ($strictScopeFamilies -notcontains $id) { continue }
        $contractFamily = if ($contractFamiliesById.ContainsKey($id)) { $contractFamiliesById[$id] } else { $null }
        if (-not (Test-ExplicitRequirementFamilyScope -FamilyId $id -RequirementText $requirementText -ContractFamily $contractFamily -EvidenceText $evidenceText)) {
            Set-ObjectProperty -Object $family -Name 'required' -Value $false
            Set-ObjectProperty -Object $family -Name 'status' -Value 'NOT_REQUIRED_BY_SCOPE_FILTER'
            Set-ObjectProperty -Object $family -Name 'coverage_cap_if_open' -Value 100
            Set-ObjectProperty -Object $family -Name 'open_sibling_surfaces' -Value @()
            Set-ObjectProperty -Object $family -Name 'open_sibling_count' -Value 0
            Set-ObjectProperty -Object $family -Name 'last_reason' -Value 'Excluded by requirement-scope filter; no explicit requirement or concrete production carrier supports this family.'
            $changed = $true
        }
    }
    return $changed
}

function Initialize-RequirementFamilyLedger {
    param(
        [string]$Path,
        [string]$ReplayRoot,
        [string]$RequirementSource,
        [int]$MaxSlices
    )

    if (Test-Path -LiteralPath $Path) { return }

    $familyContractPath = Join-Path $ReplayRoot 'FAMILY_CONTRACT.json'
    $contractFamiliesById = @{}
    if (Test-Path -LiteralPath $familyContractPath) {
        try {
            $familyContract = Read-JsonObject -Path $familyContractPath
            foreach ($family in @($familyContract.families)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$family.id)) {
                    $contractFamiliesById[[string]$family.id] = $family
                }
            }
        } catch {
            # Fall back to text-based detection; Phase0 contract verification owns JSON validity.
            $contractFamiliesById = @{}
        }
    }

    $requirementText = Read-TextIfExists $RequirementSource
    $sourceNames = @(
        $RequirementSource,
        $familyContractPath,
        (Join-Path $ReplayRoot 'ROUND_CONTRACT.md'),
        (Join-Path $ReplayRoot 'PHASE0_RESULT.md'),
        (Join-Path $ReplayRoot 'EXPLORATION_REPORT.md'),
        (Join-Path $ReplayRoot 'PLAN_RESULT.md'),
        (Join-Path $ReplayRoot 'REPLAY_PLAN.md'),
        (Join-Path $ReplayRoot 'IMPLEMENTATION_CONTRACT.md'),
        (Join-Path $ReplayRoot 'EXPECTED_DIFF_MATRIX.md'),
        (Join-Path $ReplayRoot 'SIDE_EFFECT_LEDGER.md'),
        (Join-Path $ReplayRoot 'TEST_CHARTER.md'),
        (Join-Path $ReplayRoot 'FIRST_SLICE_PROOF_PLAN.md')
    )
    $sourceText = ($sourceNames | ForEach-Object { Read-TextIfExists $_ }) -join "`n"

    $families = @(foreach ($spec in Get-RequirementFamilySpecs) {
        $hits = Get-KeywordHits -Text $sourceText -Keywords $spec.keywords
        $requirementHits = Get-KeywordHits -Text $requirementText -Keywords $spec.keywords
        $contractFamily = if ($contractFamiliesById.ContainsKey($spec.id)) { $contractFamiliesById[$spec.id] } else { $null }
        $required = if ($null -ne $contractFamily -and $null -ne $contractFamily.required) {
            [bool]$contractFamily.required
        } else {
            $hits.Count -gt 0
        }
        if ($required -and -not (Test-ExplicitRequirementFamilyScope -FamilyId $spec.id -RequirementText $requirementText -ContractFamily $contractFamily -EvidenceText $sourceText)) {
            $required = $false
        }
        $carrier = if ($null -ne $contractFamily) { [string]$contractFamily.first_executable_carrier } else { '' }
        $plannedSlice = if ($null -ne $contractFamily) { [string]$contractFamily.planned_slice } else { '' }
        $capIfOpen = if ($null -ne $contractFamily) { $raw = Get-SafeInt $contractFamily.coverage_cap_if_open -Default $null; $raw } else { $null }
        $proofRequired = if ($null -ne $contractFamily -and $null -ne $contractFamily.proof_required) { @(Get-StringArray $contractFamily.proof_required) } else { @() }
        $forbiddenProof = if ($null -ne $contractFamily -and $null -ne $contractFamily.forbidden_proof) { @(Get-StringArray $contractFamily.forbidden_proof) } else { @() }
        [ordered]@{
            id = $spec.id
            title = $spec.title
            weight = $spec.weight
            recommended_slice_type = $spec.slice_type
            required = $required
            status = $(if ($required) { 'OPEN' } else { 'NOT_DETECTED' })
            touched_count = 0
            first_slice = $null
            last_slice = $null
            slices = @()
            first_executable_carrier = $carrier
            planned_slice = $plannedSlice
            proof_required = @($proofRequired)
            forbidden_proof = @($forbiddenProof)
            coverage_cap_if_open = $capIfOpen
            open_sibling_surfaces = @(if ($required -and -not [string]::IsNullOrWhiteSpace($carrier)) { $carrier })
            open_sibling_count = @(if ($required -and -not [string]::IsNullOrWhiteSpace($carrier)) { $carrier }).Count
            last_next_recommended_slice_type = ''
            last_gap_flags = @()
            evidence_keywords = @((@($requirementHits) + @($hits)) | Select-Object -Unique | Select-Object -First 12)
            last_reason = $(if ($required) { 'Detected in requirement scope or concrete family contract.' } else { 'Not required by requirement-scope filter or no keyword evidence in requirement/planning artifacts.' })
        }
    })

    $ledgerObject = [ordered]@{
        schema_version = 1
        replay_root = $ReplayRoot
        max_slices = $MaxSlices
        created_at = (Get-Date).ToString('s')
        updated_at = (Get-Date).ToString('s')
        policy = [ordered]@{
            force_open_family_from_slice = 3
            require_core_first = $true
            no_progress_slice_flag = 'no_progress_slice'
            gate_present_but_not_enforced_flag = 'gate_present_but_not_enforced'
        }
        families = $families
        no_progress_slices = @()
        open_required_after_max = @()
        coverage_cap = 100
    }
    Apply-FeatureClassificationToLedger -Ledger $ledgerObject -ReplayRoot $ReplayRoot | Out-Null
    $ledgerObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-FamilyLedger {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Read-JsonObject -Path $Path
}

function Save-FamilyLedger {
    param($Ledger, [string]$Path)
    $Ledger.updated_at = (Get-Date).ToString('s')
    $tmp = "$Path.tmp.$PID"
    $Ledger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Write-FamilyLedgerAudit {
    param(
        [string]$ReplayRoot,
        [string]$Stage,
        [int]$SliceIndex,
        $Before,
        $After,
        [string[]]$ClosedFamilies = @(),
        [string[]]$TouchedFamilies = @()
    )

    $auditPath = Join-Path $ReplayRoot 'LEDGER_AUDIT_TRAIL.jsonl'
    $summarize = {
        param($Ledger)
        if ($null -eq $Ledger -or $null -eq $Ledger.families) { return @() }
        return @($Ledger.families | ForEach-Object {
            [ordered]@{
                id = [string]$_.id
                required = [bool]$_.required
                status = [string]$_.status
                touched_count = $(if ($null -ne $_.touched_count -and "$($_.touched_count)" -match '^\d+$') { [int]$_.touched_count } else { 0 })
                slices = @(Get-StringArray $_.slices)
                open_sibling_count = $(if ($null -ne $_.open_sibling_count -and "$($_.open_sibling_count)" -match '^\d+$') { [int]$_.open_sibling_count } else { 0 })
            }
        })
    }
    $entry = [ordered]@{
        timestamp = (Get-Date).ToString('s')
        stage = $Stage
        slice_index = $SliceIndex
        touched_families = @($TouchedFamilies)
        closed_families = @($ClosedFamilies)
        before = (& $summarize $Before)
        after = (& $summarize $After)
    }
    Add-Content -LiteralPath $auditPath -Encoding UTF8 -Value ($entry | ConvertTo-Json -Depth 12 -Compress)
}

function Normalize-SiblingSurface {
    param([string]$Surface)
    if ([string]::IsNullOrWhiteSpace($Surface)) { return '' }
    $text = $Surface.Trim()
    if ($text -match '^[A-Za-z]\s*:\s*(?![\\/])(.+)$') {
        return $matches[1].Trim()
    }
    return $text
}

function Get-CarrierSurfacePriority {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    $score = 0
    if ($Text -match '(?i)\b(callback|webhook|fallback|external|integration|client|adapter|partner|provider)\b') { $score += 45 }
    if ($Text -match '(?i)\b(payload|request|response|wire|json|message|mq|queue|exchange|producer|consumer|publish|notify|push|event)\b') { $score += 35 }
    if ($Text -match '(?i)\b(controller|endpoint|route|handler|export|download|workbook|excel|page|view|display|template|render|upload|artifact)\b') { $score += 30 }
    if ($Text -match '(?i)\b(mapper|dao|repository|insert|update|delete|save|persist|db|database|column|transaction|rollback)\b') { $score += 20 }
    if ($Text -match '(?i)\b(helper|util|constant|enum[-_ ]?only|dto[-_ ]?only|static[-_ ]?only)\b') { $score -= 25 }
    return $score
}

function Get-FamilyCarrierScore {
    param($Family, [int]$SliceIndex)
    if ($null -eq $Family) { return 0 }
    $carrier = Get-FamilyTargetSiblingSurface -Family $Family
    $proof = @(Get-StringArray $Family.proof_required) -join ' '
    $text = @(
        [string]$Family.id,
        [string]$Family.title,
        [string]$Family.recommended_slice_type,
        [string]$Family.planned_slice,
        [string]$carrier,
        [string]$proof,
        (Get-StringArray $Family.last_gap_flags) -join ' '
    ) -join "`n"
    $score = 0
    if ($null -ne $Family.weight -and "$($Family.weight)" -match '^\d+$') { $score += [int]$Family.weight }
    $score += Get-CarrierSurfacePriority -Text $text
    switch ([string]$Family.id) {
        'core_entry' {
            if ($SliceIndex -eq 1) { $score += 1000 } else { $score -= 8 * [Math]::Max(0, [int]$Family.touched_count) }
        }
        'deploy_export_page' { $score += 25 }
        'external_integration' { $score += 25 }
        'generated_artifact_template_upload' { $score += 20 }
        'wire_payload_api_contract' { $score += 15 }
        'config_policy_threshold' { $score += 10 }
        default { }
    }
    if ([int]$Family.touched_count -gt 0) { $score -= (5 * [int]$Family.touched_count) }
    if ($text -match '(?i)\b(callback|payload|wire|mq|message|external|integration|controller|endpoint)\b' -and [int]$Family.touched_count -eq 0) {
        $score += 15
    }
    return $score
}

function New-CarrierRankMap {
    param($Ledger, [int]$SliceIndex)
    $families = @()
    if ($null -ne $Ledger -and $null -ne $Ledger.families) {
        $families = @($Ledger.families | Where-Object {
            [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
        })
    }
    $rows = @($families | ForEach-Object {
        $carrier = Get-FamilyTargetSiblingSurface -Family $_
        $proof = @(Get-StringArray $_.proof_required)
        [pscustomobject]@{
            family = [string]$_.id
            required = [bool]$_.required
            status = [string]$_.status
            touched_count = [int]$_.touched_count
            base_weight = [int]$_.weight
            rank_score = (Get-FamilyCarrierScore -Family $_ -SliceIndex $SliceIndex)
            production_carrier = $carrier
            required_assertion = (($proof | Select-Object -First 3) -join '; ')
            forbidden_substitute = ((Get-StringArray $_.forbidden_proof | Select-Object -First 3) -join '; ')
            selected_reason = 'rank = family weight + executable carrier priority - repeat-touch penalty'
        }
    } | Sort-Object @{Expression = 'rank_score'; Descending = $true}, @{Expression = 'base_weight'; Descending = $true}, @{Expression = 'touched_count'; Ascending = $true})

    $rank = 1
    foreach ($row in $rows) {
        $row | Add-Member -NotePropertyName rank -NotePropertyValue $rank -Force
        $rank++
    }
    [ordered]@{
        schema_version = 1
        slice_index = $SliceIndex
        families = @($rows)
        missing_required_rank1 = @($rows | Where-Object { [bool]$_.required -and [string]::IsNullOrWhiteSpace([string]$_.production_carrier) } | ForEach-Object { [string]$_.family })
        gate = 'carrier_ranking_hard_stop'
    }
}

function Get-FamilyTargetSiblingSurface {
    param($Family)
    if ($null -eq $Family) { return '' }
    $fromSibling = @(@(Get-StringArray $Family.open_sibling_surfaces) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
    $allSiblings = @(Get-StringArray $Family.open_sibling_surfaces | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($allSiblings.Count -gt 0) {
        $rankedSibling = @($allSiblings | Sort-Object @{Expression = { Get-CarrierSurfacePriority -Text ([string]$_) }; Descending = $true} | Select-Object -First 1)
        if ($rankedSibling.Count -gt 0) { return (Normalize-SiblingSurface -Surface ([string]$rankedSibling[0])) }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Family.first_executable_carrier)) {
        return (Normalize-SiblingSurface -Surface ([string]$Family.first_executable_carrier))
    }
    return ''
}

function Get-SliceTypeForSurface {
    param([string]$Surface)
    if ([string]::IsNullOrWhiteSpace($Surface)) { return '' }
    if ($Surface -match '(?i)(controller|endpoint|route|export|download|workbook|excel|page|view|display|jsp|js|html|submit|query)\b') {
        return 'deploy_surface_first_slice'
    }
    if ($Surface -match '(?i)\b(payload|request|response|wire|json|dto|field|body)\b') {
        return 'exact_contract_slice'
    }
    if ($Surface -match '(?i)\b(callback|webhook|external|integration|client|adapter|provider|partner)\b') {
        return 'deploy_surface_first_slice'
    }
    return ''
}

function Get-ForcedFamilyDecision {
    param($Ledger, [int]$SliceIndex, $CarrierRank = $null, [string]$ReplayRoot = '')

    $empty = [ordered]@{
        family_id = ''
        slice_type = ''
        target_sibling_surface = ''
        reason = 'No requirement-family backpressure.'
        open_families = ''
    }
    if ($null -eq $Ledger -or $null -eq $Ledger.families) { return $empty }

    $open = @($Ledger.families | Where-Object {
        [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
    } | Sort-Object @{Expression = 'touched_count'; Ascending = $true}, @{Expression = 'weight'; Descending = $true})

    $empty.open_families = (($open | ForEach-Object { "$($_.id):$($_.status):touch=$($_.touched_count)" }) -join ', ')
    if ($open.Count -eq 0) { return $empty }

    if ($SliceIndex -eq 1 -and -not [string]::IsNullOrWhiteSpace($ReplayRoot)) {
        $firstSlicePlanText = Read-TextIfExists -Path (Join-Path $ReplayRoot 'FIRST_SLICE_PROOF_PLAN.md')
        $plannedFamily = Get-FirstNonEmptyText @(
            (Get-PlanField -Text $firstSlicePlanText -Name 'first_slice_family'),
            (Get-PlanField -Text $firstSlicePlanText -Name 'highest_weight_open_gate'),
            (Get-PlanField -Text $firstSlicePlanText -Name 'target_family'),
            (Get-PlanField -Text $firstSlicePlanText -Name 'family_id')
        )
        if (-not [string]::IsNullOrWhiteSpace($plannedFamily)) {
            $candidate = @($open | Where-Object { [string]$_.id -eq $plannedFamily } | Select-Object -First 1)
            if ($candidate.Count -gt 0) {
                return [ordered]@{
                    family_id = $candidate[0].id
                    slice_type = $candidate[0].recommended_slice_type
                    target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate[0])
                    reason = "FIRST_SLICE_PROOF_PLAN.md selected $plannedFamily for S1; runner must preserve the planner's concrete first-slice family instead of forcing core_entry."
                    open_families = $empty.open_families
                }
            }
        }
    }

    $deploySiblingPressure = @($open | Where-Object {
        $siblingCount = if ($null -ne $_.open_sibling_count) { [int]$_.open_sibling_count } else { 0 }
        $nextType = [string]$_.last_next_recommended_slice_type
        [string]$_.id -eq 'deploy_export_page' -and
        $siblingCount -gt 0 -and
        [int]$_.touched_count -lt 3 -and
        @('deploy_surface_first_slice', 'exact_contract_slice', 'stateful_success_slice') -contains $nextType
    } | Sort-Object @{Expression = 'touched_count'; Ascending = $true}, @{Expression = 'weight'; Descending = $true})

    $otherSiblingPressureFamilies = @(
        'wire_payload_api_contract',
        'generated_artifact_template_upload',
        'external_integration',
        'automation_test_interface'
    )
    $otherSiblingPressure = @($open | Where-Object {
        $siblingCount = if ($null -ne $_.open_sibling_count) { [int]$_.open_sibling_count } else { 0 }
        $nextType = [string]$_.last_next_recommended_slice_type
        $otherSiblingPressureFamilies -contains [string]$_.id -and
        $siblingCount -gt 0 -and
        [int]$_.touched_count -lt 2 -and
        @('deploy_surface_first_slice', 'exact_contract_slice', 'stateful_success_slice') -contains $nextType
    } | Sort-Object @{Expression = 'touched_count'; Ascending = $true}, @{Expression = 'weight'; Descending = $true})

    $untouchedOpenCount = @($open | Where-Object { [int]$_.touched_count -eq 0 }).Count

    $coreStatefulClosurePressure = @($open | Where-Object {
        $siblingCount = if ($null -ne $_.open_sibling_count) { [int]$_.open_sibling_count } else { 0 }
        $lastFlags = @(Get-StringArray $_.last_gap_flags)
        @('core_entry', 'stateful_side_effect') -contains [string]$_.id -and
        [int]$_.touched_count -gt 0 -and
        [int]$_.touched_count -lt 4 -and
        (
            $siblingCount -gt 0 -or
            ($lastFlags -contains 'side_effect_ledger_gap') -or
            ($lastFlags -contains 'core_entry_unclosed') -or
            ($lastFlags -contains 'transaction_depth_gap')
        )
    } | Sort-Object @{Expression = 'touched_count'; Ascending = $true}, @{Expression = 'weight'; Descending = $true})

    if ($SliceIndex -ge 4 -and $untouchedOpenCount -eq 0 -and $coreStatefulClosurePressure.Count -gt 0) {
        $candidate = $coreStatefulClosurePressure | Select-Object -First 1
        return [ordered]@{
            family_id = $candidate.id
            slice_type = 'stateful_success_slice'
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate)
            reason = "Runner contract: all required families have first-touch coverage; return budget to high-weight core/stateful sibling closure."
            open_families = $empty.open_families
        }
    }

    if ($SliceIndex -ge 4 -and $deploySiblingPressure.Count -gt 0) {
        $candidate = $deploySiblingPressure | Select-Object -First 1
        $candidateSliceType = if ([string]::IsNullOrWhiteSpace([string]$candidate.last_next_recommended_slice_type)) {
            $candidate.recommended_slice_type
        } else {
            [string]$candidate.last_next_recommended_slice_type
        }
        return [ordered]@{
            family_id = $candidate.id
            slice_type = $candidateSliceType
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate)
            reason = "Runner contract: $($candidate.id) reported $($candidate.open_sibling_count) open deploy/page sibling surface(s); allow bounded sibling closure before planned low-touch breadth."
            open_families = $empty.open_families
        }
    }

    if ($SliceIndex -ge 4 -and $untouchedOpenCount -eq 0 -and $otherSiblingPressure.Count -gt 0) {
        $candidate = $otherSiblingPressure | Select-Object -First 1
        $candidateSliceType = if ([string]::IsNullOrWhiteSpace([string]$candidate.last_next_recommended_slice_type)) {
            $candidate.recommended_slice_type
        } else {
            [string]$candidate.last_next_recommended_slice_type
        }
        return [ordered]@{
            family_id = $candidate.id
            slice_type = $candidateSliceType
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate)
            reason = "Runner contract: $($candidate.id) reported $($candidate.open_sibling_count) open sibling surface(s); allow one bounded follow-up only after every required family has at least one touch."
            open_families = $empty.open_families
        }
    }

    $plannedForSlice = @($open | Where-Object { [string]$_.planned_slice -eq ('S{0}' -f $SliceIndex) } | Sort-Object @{Expression = 'weight'; Descending = $true})
    if ($plannedForSlice.Count -gt 0) {
        $candidate = $plannedForSlice | Select-Object -First 1
        return [ordered]@{
            family_id = $candidate.id
            slice_type = $candidate.recommended_slice_type
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate)
            reason = "FAMILY_CONTRACT.json planned $($candidate.id) for S$SliceIndex; runner must honor the machine-readable family contract."
            open_families = $empty.open_families
        }
    }

    $openByWeight = @($open | Sort-Object @{Expression = 'weight'; Descending = $true}, @{Expression = 'touched_count'; Ascending = $true})
    $core = @($open | Where-Object { $_.id -eq 'core_entry' } | Select-Object -First 1)
    if ($SliceIndex -eq 1 -and $core.Count -gt 0) {
        return [ordered]@{
            family_id = $core[0].id
            slice_type = $core[0].recommended_slice_type
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $core[0])
            reason = 'Slice 1 must close the highest-weight real entry family first.'
            open_families = $empty.open_families
        }
    }

    $rankedRows = @()
    if ($null -ne $CarrierRank -and $null -ne $CarrierRank.families) {
        $rankedRows = @($CarrierRank.families | Where-Object {
            [bool]$_.required -and -not [string]::IsNullOrWhiteSpace([string]$_.production_carrier)
        } | Sort-Object @{Expression = 'rank'; Ascending = $true})
    }
    if ($SliceIndex -ge 2 -and $rankedRows.Count -gt 0) {
        $top = $rankedRows | Select-Object -First 1
        $candidate = @($open | Where-Object { [string]$_.id -eq [string]$top.family } | Select-Object -First 1)
        if ($candidate.Count -gt 0) {
            $candidateSliceType = if ([string]$candidate[0].id -eq 'core_entry' -and $SliceIndex -gt 1) {
                $surfaceSliceType = Get-SliceTypeForSurface -Surface ([string]$top.production_carrier)
                if (-not [string]::IsNullOrWhiteSpace($surfaceSliceType)) { $surfaceSliceType } else { 'stateful_success_slice' }
            } else {
                $surfaceSliceType = Get-SliceTypeForSurface -Surface ([string]$top.production_carrier)
                if (-not [string]::IsNullOrWhiteSpace($surfaceSliceType)) { $surfaceSliceType } else { [string]$candidate[0].recommended_slice_type }
            }
            return [ordered]@{
                family_id = [string]$candidate[0].id
                slice_type = $candidateSliceType
                target_sibling_surface = [string]$top.production_carrier
                reason = "Carrier ranking hard stop: rank $($top.rank) $($top.family) selected before lower-value helper or generic sibling surfaces."
                open_families = $empty.open_families
            }
        }
    }

    $stateful = @($open | Where-Object { $_.id -eq 'stateful_side_effect' } | Select-Object -First 1)
    if ($SliceIndex -eq 2 -and $stateful.Count -gt 0) {
        return [ordered]@{
            family_id = $stateful[0].id
            slice_type = $stateful[0].recommended_slice_type
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $stateful[0])
            reason = 'Slice 2 must close the stateful side-effect family before more helper/supporting work.'
            open_families = $empty.open_families
        }
    }

    if ($SliceIndex -eq 3 -and $stateful.Count -gt 0 -and [int]$stateful[0].touched_count -lt 1) {
        return [ordered]@{
            family_id = $stateful[0].id
            slice_type = $stateful[0].recommended_slice_type
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $stateful[0])
            reason = 'Runner contract: stateful side effects have not been touched yet; force a real side-effect slice before lower-weight surfaces.'
            open_families = $empty.open_families
        }
    }

    if ($SliceIndex -ge 3) {
        $untouched = @($open | Where-Object { [int]$_.touched_count -eq 0 } | Sort-Object @{Expression = 'weight'; Descending = $true})
        if ($untouched.Count -gt 0) {
            $candidate = $untouched | Select-Object -First 1
            # EXPERIMENT_1 (v339): Stateful Success Slice for high-weight, multi-surface core_entry
            # Condition: weight >= 90 AND open_sibling_surfaces.Count >= 3
            $siblingCount = @(Get-StringArray $candidate.open_sibling_surfaces).Count
            $candidateSliceType = if (
                [string]$candidate.id -eq 'core_entry' -and
                $SliceIndex -gt 1 -and
                (if ($null -ne $candidate.weight) { [int]$candidate.weight } else 0) -ge 90 -and
                $siblingCount -ge 3
            ) { 'stateful_success_slice' } else { $candidate.recommended_slice_type }
            return [ordered]@{
                family_id = $candidate.id
                slice_type = $candidateSliceType
                target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate)
                reason = 'Runner contract: target the highest-weight untouched OPEN/PARTIAL family before any partial-family deepening.'
                open_families = $empty.open_families
            }
        }

        $underExploredNonCore = @($open | Where-Object {
            @('core_entry', 'stateful_side_effect') -notcontains [string]$_.id -and
            [string]$_.status -eq 'OPEN' -and
            [int]$_.touched_count -eq 0
        } | Sort-Object @{Expression = 'touched_count'; Ascending = $true}, @{Expression = 'weight'; Descending = $true})
        if ($underExploredNonCore.Count -gt 0) {
            $candidate = $underExploredNonCore | Select-Object -First 1
            return [ordered]@{
                family_id = $candidate.id
                slice_type = $candidate.recommended_slice_type
                target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate)
                reason = 'Runner contract: first-touch the highest-weight non-core required family only when it has no prior executable attempt.'
                open_families = $empty.open_families
            }
        }

        $balancedOpen = @($open | Sort-Object @{Expression = 'touched_count'; Ascending = $true}, @{Expression = 'weight'; Descending = $true})
        $candidate = if ($balancedOpen.Count -gt 0) { $balancedOpen | Select-Object -First 1 } else { $openByWeight | Select-Object -First 1 }
        # EXPERIMENT_1 (v339): Stateful Success Slice for high-weight, multi-surface core_entry
        # Condition: weight >= 90 AND open_sibling_surfaces.Count >= 3
        $siblingCount = @(Get-StringArray $candidate.open_sibling_surfaces).Count
        $candidateSliceType = if (
            [string]$candidate.id -eq 'core_entry' -and
            $SliceIndex -gt 1 -and
            (if ($null -ne $candidate.weight) { [int]$candidate.weight } else 0) -ge 90 -and
            $siblingCount -ge 3
        ) { 'stateful_success_slice' } else { $candidate.recommended_slice_type }
        return [ordered]@{
            family_id = $candidate.id
            slice_type = $candidateSliceType
            target_sibling_surface = (Get-FamilyTargetSiblingSurface -Family $candidate)
            reason = 'Runner contract: after first-touch coverage, balance by lowest touched_count before weight so sibling surfaces are not starved by core/stateful revisits.'
            open_families = $empty.open_families
        }
    }

    return $empty
}

function Test-RequiredFamilyOpenInLedger {
    param($Ledger, [string]$FamilyId)
    if ($null -eq $Ledger -or $null -eq $Ledger.families -or [string]::IsNullOrWhiteSpace($FamilyId)) { return $false }
    $family = @($Ledger.families | Where-Object { [string]$_.id -eq $FamilyId } | Select-Object -First 1)
    if ($family.Count -eq 0) { return $false }
    return [bool]$family[0].required -and @('OPEN', 'PARTIAL') -contains ([string]$family[0].status)
}

function Test-NoOpenRequiredFamilyForSlice {
    param($Ledger, $CarrierRank, $ForcedDecision)

    if ($null -eq $Ledger -or $null -eq $Ledger.families) { return $false }

    $openRequired = @($Ledger.families | Where-Object {
        [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
    })
    if ($openRequired.Count -gt 0) { return $false }

    $rankedFamilies = @()
    if ($null -ne $CarrierRank -and $null -ne $CarrierRank.families) {
        $rankedFamilies = @($CarrierRank.families | Where-Object {
            [bool]$_.required -and -not [string]::IsNullOrWhiteSpace([string]$_.family)
        })
    }
    if ($rankedFamilies.Count -gt 0) { return $false }

    if ($null -ne $ForcedDecision -and -not [string]::IsNullOrWhiteSpace([string]$ForcedDecision.family_id)) {
        return $false
    }

    return $true
}

function Test-SourceChainOverrideAllowedForForcedDecision {
    param(
        $ForcedDecision,
        $SourceChain,
        [int]$SliceIndex,
        [string]$ReplayRoot = ''
    )

    if ($null -eq $SourceChain -or $null -eq $SourceChain.next_required_slice) { return $false }
    if ($null -eq $ForcedDecision) { return $true }

    $family = if ($ForcedDecision.PSObject.Properties.Name -contains 'family_id') { [string]$ForcedDecision.family_id } else { '' }
    $surface = if ($ForcedDecision.PSObject.Properties.Name -contains 'target_sibling_surface') { [string]$ForcedDecision.target_sibling_surface } else { '' }
    $reason = if ($ForcedDecision.PSObject.Properties.Name -contains 'reason') { [string]$ForcedDecision.reason } else { '' }
    if ([string]::IsNullOrWhiteSpace($family)) { return $true }

    if ($SliceIndex -eq 1 -and $family -eq 'core_entry' -and -not [string]::IsNullOrWhiteSpace($ReplayRoot)) {
        $firstSlicePlanText = Read-TextIfExists -Path (Join-Path $ReplayRoot 'FIRST_SLICE_PROOF_PLAN.md')
        $implementationContractText = Read-TextIfExists -Path (Join-Path $ReplayRoot 'IMPLEMENTATION_CONTRACT.md')
        $planText = @($firstSlicePlanText, $implementationContractText) -join "`n"
        $plannedCarrier = Get-PlanField -Text $planText -Name 'selected_carrier'
        $plannedFirstRedTest = Get-PlanField -Text $planText -Name 'first_red_test'
        $sourceCarrier = if ($SourceChain.next_required_slice.PSObject.Properties.Name -contains 'carrier') { [string]$SourceChain.next_required_slice.carrier } else { '' }
        $sourceEntry = if ($SourceChain.next_required_slice.PSObject.Properties.Name -contains 'entry') { [string]$SourceChain.next_required_slice.entry } else { '' }
        $sourceTest = if ($SourceChain.next_required_slice.PSObject.Properties.Name -contains 'test_name') { [string]$SourceChain.next_required_slice.test_name } else { '' }
        $plannedText = @($plannedCarrier, $plannedFirstRedTest) -join "`n"
        $sourceText = @($sourceCarrier, $sourceEntry, $sourceTest) -join "`n"
        if (
            -not [string]::IsNullOrWhiteSpace($plannedCarrier) -and
            -not [string]::IsNullOrWhiteSpace($sourceText) -and
            $sourceText -notmatch [regex]::Escape($plannedCarrier) -and
            $plannedText -notmatch '(?i)\b(rebuildTaskData|source_chain|source[-_\s]?chain|source field|wire field|input_data)\b'
        ) {
            return $false
        }
    }
    if ($family -in @('core_entry', 'source_chain')) { return $true }

    $sourceCarrier = if ($SourceChain.next_required_slice.PSObject.Properties.Name -contains 'carrier') { [string]$SourceChain.next_required_slice.carrier } else { '' }
    $sourceEntry = if ($SourceChain.next_required_slice.PSObject.Properties.Name -contains 'entry') { [string]$SourceChain.next_required_slice.entry } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($sourceCarrier) -and $surface -eq $sourceCarrier) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($sourceEntry) -and $surface -match [regex]::Escape($sourceEntry)) { return $true }

    $decisionText = @($surface, $reason) -join ' '
    if ($decisionText -match '(?i)\b(rebuildTaskData|RequestBuildContext|source_chain|source[-_\s]?chain|source field|wire field|input_data)\b') {
        return $true
    }

    return $false
}

function Resolve-ForcedFamilyDecisionForSlice {
    param(
        $Ledger,
        [int]$SliceIndex,
        $CarrierRank,
        [string]$SourceChainContractPath,
        [string]$RunnerContractPath
    )

    $replayRootForDecision = if ([string]::IsNullOrWhiteSpace($SourceChainContractPath)) { '' } else { [System.IO.Path]::GetDirectoryName($SourceChainContractPath) }
    $forced = Get-ForcedFamilyDecision -Ledger $Ledger -SliceIndex $SliceIndex -CarrierRank $CarrierRank -ReplayRoot $replayRootForDecision
    if (-not (Test-Path -LiteralPath $SourceChainContractPath)) { return $forced }

    try {
        $sourceChain = Read-JsonObject -Path $SourceChainContractPath
        $coreStillOpen = Test-RequiredFamilyOpenInLedger -Ledger $Ledger -FamilyId 'core_entry'
        if ([bool]$sourceChain.required_source_chain -and $null -ne $sourceChain.next_required_slice -and $coreStillOpen) {
            if (-not (Test-SourceChainOverrideAllowedForForcedDecision -ForcedDecision $forced -SourceChain $sourceChain -SliceIndex $SliceIndex -ReplayRoot ([System.IO.Path]::GetDirectoryName($SourceChainContractPath)))) {
                Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} source-chain override skipped | source_chain | exact_contract_slice | planned_slice_guard | preserving planned/router-selected family={1}; source-chain contract cannot override a concrete non-source-chain slice. |" -f $SliceIndex, $forced.family_id)
                return $forced
            }
            return [ordered]@{
                family_id = 'core_entry'
                slice_type = [string]$sourceChain.next_required_slice.slice_type
                target_sibling_surface = [string]$sourceChain.next_required_slice.carrier
                reason = 'Runner contract: named source-chain requirement detected; source extraction/service/request/task chain must be closed before terminal payload/stateful follow-up.'
                open_families = [string]$forced.open_families
            }
        }
        if ([bool]$sourceChain.required_source_chain -and $null -ne $sourceChain.next_required_slice -and -not $coreStillOpen -and $SliceIndex -gt 1) {
            Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} source-chain override skipped | source_chain | exact_contract_slice | executable_evidence | core_entry is already closed; preserving router-selected family={1}. |" -f $SliceIndex, $forced.family_id)
        }
    } catch {
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} source-chain analysis warning | source_chain | exact_contract_slice | source_chain_contract_unreadable | {1}. |" -f $SliceIndex, $_.Exception.Message)
    }
    return $forced
}

function Archive-StaleSliceArtifacts {
    param(
        [string]$ReplayRoot,
        [int]$SliceIndex,
        [string[]]$Paths,
        [string]$Reason,
        [string]$RunnerContractPath
    )

    $staleDir = Join-Path (Join-Path $ReplayRoot 'logs\stale-slice-results') ('slice{0:D2}' -f $SliceIndex)
    if (-not (Test-Path -LiteralPath $staleDir)) {
        New-Item -ItemType Directory -Force -Path $staleDir | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    foreach ($path in @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $leaf = [System.IO.Path]::GetFileName($path)
        Move-Item -LiteralPath $path -Destination (Join-Path $staleDir ("{0}.{1}" -f $leaf, $stamp)) -Force
    }
    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} stale slice artifact invalidated | resume_safety | stale_blocker_replay | executable_evidence | {1}. |" -f $SliceIndex, ($Reason -replace '\|', '/'))
}

function Test-AuthorizingSliceEvidence {
    param(
        [string]$ReplayRoot,
        [int]$SliceIndex
    )

    $sliceResultPath = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
    $sliceVerifyPath = Join-Path $ReplayRoot ('SLICE_VERIFY_{0:D2}.json' -f $SliceIndex)
    if (-not (Test-Path -LiteralPath $sliceResultPath) -or -not (Test-Path -LiteralPath $sliceVerifyPath)) {
        return $false
    }

    try {
        $sliceResult = Read-JsonObject -Path $sliceResultPath
        $sliceVerify = Read-JsonObject -Path $sliceVerifyPath
        $resultStatus = [string]$sliceResult.slice_status
        $verifyStatus = [string]$sliceVerify.verification_status
        $verifySliceStatus = [string]$sliceVerify.slice_status
        $hasAuthorization = (
            ($sliceVerify.PSObject.Properties.Name -contains 'authorized_for_next_slice' -and [bool]$sliceVerify.authorized_for_next_slice) -or
            ($sliceVerify.PSObject.Properties.Name -contains 'authorized_for_synthesis' -and [bool]$sliceVerify.authorized_for_synthesis)
        )
        return (
            $verifyStatus -in @('PASS', 'PARTIAL') -and
            ($resultStatus -in @('DONE', 'PARTIAL') -or $verifySliceStatus -in @('DONE', 'PARTIAL')) -and
            $hasAuthorization
        )
    } catch {
        return $false
    }
}

function Set-SliceProgressFromAuthorizingEvidence {
    param(
        [string]$Path,
        [string]$ReplayRoot,
        [int]$MaxSlices
    )

    $completed = New-Object System.Collections.Generic.List[int]
    for ($idx = 1; $idx -le $MaxSlices; $idx++) {
        if (Test-AuthorizingSliceEvidence -ReplayRoot $ReplayRoot -SliceIndex $idx) {
            $completed.Add($idx) | Out-Null
        }
    }

    [ordered]@{
        replay_root = $ReplayRoot
        max_slices = $MaxSlices
        completed = @($completed)
        stopped = $false
        stop_reason = ''
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SliceScopedArtifactPaths {
    param(
        [string]$ReplayRoot,
        [int]$SliceIndex
    )

    $names = @(
        'SLICE_RESULT_{0:D2}.json',
        'SLICE_VERIFY_{0:D2}.json',
        'SLICE_AUTHORIZATION_{0:D2}.json',
        'CARRIER_AUTHORIZATION_{0:D2}.json',
        'CARRIER_RANK_{0:D2}.json',
        'EXACT_CONTRACT_ASSERTION_MATRIX_{0:D2}.json',
        'NEXT_SLICE_EXACT_CONTRACT_{0:D2}.json',
        'SIDE_EFFECT_EVIDENCE_{0:D2}.json',
        'PRE_SLICE_AUTHORIZATION_{0:D2}.json',
        'PRE_SLICE_CAP_DISPLAY_{0:D2}.json',
        'CHECKPOINT_GATE_{0:D2}.json',
        'V348_SLICE_QUALITY_GATE_{0:D2}.json',
        'V348_HORIZONTAL_SLICE_GATE_{0:D2}.stdout.log',
        'V348_HORIZONTAL_SLICE_GATE_{0:D2}.stderr.log',
        'RED_PHASE_GATE_{0:D2}.json',
        'RED_PHASE_GATE_{0:D2}.stdout.log',
        'RED_PHASE_GATE_{0:D2}.stderr.log',
        'CONTRACT_VERIFICATION_{0:D2}.json',
        'CONTRACT_VERIFICATION_{0:D2}.stdout.log',
        'GREEN_PHASE_VERIFY_{0:D2}.json',
        'GREEN_PHASE_VERIFY_{0:D2}.stdout.log',
        'GREEN_PHASE_VERIFY_{0:D2}.stderr.log',
        'GREEN_PHASE_IMPLEMENTED_FILES_{0:D2}.json',
        'GREEN_PHASE_TOUCHED_FAMILIES_{0:D2}.json',
        'GREEN_PHASE_TEST_EXECUTION_{0:D2}.json',
        'GREEN_PHASE_TEST_EXECUTION_{0:D2}.stdout.log',
        'LAYER_VALIDATION_{0:D2}.stdout.log',
        'SIDE_EFFECT_LEDGER_VERIFICATION_{0:D2}.stdout.log',
        'PHASE0_PRECHECK_{0:D2}.stdout.log',
        'TEST_CHARTER_VALIDATION_{0:D2}.json',
        'TEST_CHARTER_VALIDATION_{0:D2}.stdout.log',
        'TODO_DETECTION_{0:D2}.json',
        'TODO_DETECTION_{0:D2}.stdout.log',
        'TODO_CHECK_RESULT_{0:D2}.json',
        'TEST_CHARTER_REPAIR_PROMPT_{0:D2}.md',
        'TEST_CHARTER_REPAIR_RESULT_{0:D2}.md',
        'PHASE1_SLICE_{0:D2}_PROMPT.md',
        'PHASE1_SLICE_{0:D2}_RETRY_PROMPT.md',
        'PHASE1_SLICE_{0:D2}_FORCED_FAMILY_REPAIR_PROMPT.md',
        'SLICE_RESULT_{0:D2}.before_forced_family_repair.json',
        'SLICE_RESULT_{0:D2}.worktree_before_forced_family_repair.json',
        'EXECUTABLE_EVIDENCE_GATE_{0:D2}.json'
    )

    return @($names | ForEach-Object { Join-Path $ReplayRoot ($_ -f $SliceIndex) })
}

function Clear-SliceArtifactsAfterRequirementClosure {
    param(
        [string]$ReplayRoot,
        [int]$SliceIndex,
        [int]$MaxSlices,
        [string]$RunnerContractPath
    )

    $archivedCount = 0
    for ($idx = $SliceIndex; $idx -le $MaxSlices; $idx++) {
        if (Test-AuthorizingSliceEvidence -ReplayRoot $ReplayRoot -SliceIndex $idx) {
            Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} closure cleanup skipped | requirement_family_ledger | authorized_slice | all_required_families_closed | preserving active authorized slice evidence while removing only future/stale artifacts. |" -f $idx)
            continue
        }
        $paths = @(Get-SliceScopedArtifactPaths -ReplayRoot $ReplayRoot -SliceIndex $idx)
        $existing = @($paths | Where-Object { Test-Path -LiteralPath $_ })
        if ($existing.Count -eq 0) { continue }
        Archive-StaleSliceArtifacts `
            -ReplayRoot $ReplayRoot `
            -SliceIndex $idx `
            -Paths $existing `
            -Reason 'all_required_families_closed before this slice; future/stale slice artifacts are ignored before synthesis' `
            -RunnerContractPath $RunnerContractPath
        $archivedCount += $existing.Count
    }

    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} completion stop | requirement_family_ledger | none | all_required_families_closed | no OPEN/PARTIAL required family remains; archived_future_or_stale_artifacts={1}; proceeding to synthesis without creating another slice. |" -f $SliceIndex, $archivedCount)
    return $archivedCount
}

function Test-StaleBlockedSliceForResume {
    param(
        $SliceResultObject,
        $SliceVerifyObject,
        $ForcedDecision
    )

    if ($null -eq $SliceResultObject) { return $false }
    $sliceStatus = [string]$SliceResultObject.slice_status
    if (@('BLOCKED', 'INVALID_REPLAY') -notcontains $sliceStatus) { return $false }

    $gapFlags = @((@(Get-StringArray $SliceResultObject.gap_flags) + @(Get-StringArray $SliceVerifyObject.gap_flags)) | Select-Object -Unique)
    $implementedFiles = @(Get-StringArray $SliceResultObject.implemented_files)
    $closedFamilies = @(Get-StringArray $SliceVerifyObject.closed_requirement_families)
    $currentFamily = [string]$ForcedDecision.family_id
    $oldForcedFamily = ''
    if ($SliceVerifyObject -and $SliceVerifyObject.PSObject.Properties['next_required_slice']) {
        $oldForcedFamily = [string]$SliceVerifyObject.next_required_slice.family
    }
    $reasonText = @(
        [string]$SliceResultObject.slice_title,
        [string]$SliceResultObject.blocker,
        (Get-StringArray $SliceResultObject.remaining_gaps) -join ' ',
        (Get-StringArray $SliceVerifyObject.authorization_blockers) -join ' '
    ) -join "`n"

    $hasNoProgressFlag = @(@('no_progress_slice', 'gate_present_but_not_enforced', 'tooling_executor_failed') | Where-Object { $gapFlags -contains $_ }).Count -gt 0
    $noProgressBlocker = ($implementedFiles.Count -eq 0 -and $hasNoProgressFlag)
    if ($noProgressBlocker) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($currentFamily) -and -not [string]::IsNullOrWhiteSpace($oldForcedFamily) -and $oldForcedFamily -ne $currentFamily) { return $true }
    if ($reasonText -match 'forced_family_not_highest_weight_open' -and -not [string]::IsNullOrWhiteSpace($currentFamily) -and $closedFamilies -notcontains $currentFamily) { return $true }
    return $false
}

function Add-RunnerEnforcementContract {
    param(
        [string]$Path,
        [int]$SliceIndex,
        $ForcedDecision
    )

    if ($SliceIndex -eq 1 -and -not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Encoding UTF8 -Value @(
            '# Runner Enforcement Contract',
            '',
            'Each slice must bind the current high-weight gap to a concrete executable target.',
            '',
            '| slice | target family | target slice type | target sibling surface | fail-closed condition | verifier assertion |',
            '|---|---|---|---|---|---|'
        )
    }

    $targetFamily = if ([string]::IsNullOrWhiteSpace($ForcedDecision.family_id)) { 'none' } else { [string]$ForcedDecision.family_id }
    $targetSliceType = if ([string]::IsNullOrWhiteSpace($ForcedDecision.slice_type)) { 'none' } else { [string]$ForcedDecision.slice_type }
    $targetSiblingSurface = if ([string]::IsNullOrWhiteSpace([string]$ForcedDecision.target_sibling_surface)) { 'none' } else { [string]$ForcedDecision.target_sibling_surface }
    $failClosed = if ($targetFamily -eq 'none') {
        'No forced family; normal verifier rules apply.'
    } else {
        "If SLICE_RESULT does not touch $targetFamily and is not BLOCKED/INVALID_REPLAY, stop before the next slice with tooling_enforcement_stop."
    }
    $assertion = if ($targetFamily -eq 'none') {
        'Verify behavior evidence, diff, RED/GREEN, and cap rules.'
    } else {
        "touched_requirement_families must include $targetFamily, target_subsurface_or_carrier must bind to a production carrier, and blocker must explain any missing executable proof."
    }
    Add-Content -LiteralPath $Path -Encoding UTF8 -Value ("| S{0} | {1} | {2} | {3} | {4} | {5} |" -f $SliceIndex, $targetFamily, $targetSliceType, $targetSiblingSurface, $failClosed, $assertion)
}

function Update-FamilyLedgerFromSlice {
    param(
        [string]$Path,
        [string]$SliceResultPath,
        [string]$SliceVerifyPath,
        [int]$SliceIndex,
        [int]$MaxSlices
    )

    $ledger = Get-FamilyLedger -Path $Path
    if ($null -eq $ledger) { return }
    $replayRootForLedger = Split-Path -Parent $Path
    $featureClassification = Read-FeatureClassification -ReplayRoot $replayRootForLedger
    $narrowReadOnlyFeature = Test-NarrowBackendReadOnlyFeature -FeatureClassification $featureClassification
    if (Apply-FeatureClassificationToLedger -Ledger $ledger -ReplayRoot $replayRootForLedger) {
        Save-FamilyLedger -Ledger $ledger -Path $Path
    }
    $result = Read-JsonObject -Path $SliceResultPath
    $verify = Read-JsonObject -Path $SliceVerifyPath
    $specs = Get-RequirementFamilySpecs

    $verifyTouched = @(Get-StringArray $verify.touched_requirement_families)
    $verifyClosed = @(Get-StringArray $verify.closed_requirement_families)
    $explicitTouched = @(if ($verifyTouched.Count -gt 0 -or $verifyClosed.Count -gt 0) { @($verifyTouched + $verifyClosed) | Select-Object -Unique } else { Get-StringArray $result.touched_requirement_families })
    $explicitClosed = @(if ($verifyClosed.Count -gt 0) { $verifyClosed } else { Get-StringArray $result.closed_requirement_families })
    $hasExplicitTouched = $explicitTouched.Count -gt 0
    $ledgerBefore = $ledger | ConvertTo-Json -Depth 12 | ConvertFrom-Json

    $resultText = @(
        [string]$result.slice_type,
        [string]$result.slice_title,
        [string]$result.next_recommended_slice_type,
        (Get-StringArray $result.implemented_files) -join ' ',
        (Get-StringArray $result.closed_assertions) -join ' '
    ) -join "`n"

    $gapFlags = @((@(Get-StringArray $result.gap_flags) + @(Get-StringArray $verify.gap_flags)) | Select-Object -Unique)
    $touched = New-Object System.Collections.Generic.List[string]
    foreach ($family in $ledger.families) {
        if (-not [bool]$family.required) { continue }
        $spec = @($specs | Where-Object { $_.id -eq $family.id } | Select-Object -First 1)
        if ($spec.Count -eq 0) { continue }

        $keywordHits = Get-KeywordHits -Text $resultText -Keywords $spec[0].keywords
        $sliceTypeHit = ([string]$result.slice_type) -eq ([string]$family.recommended_slice_type)
        $familyGap = switch ($family.id) {
            'core_entry' { @('core_entry_unclosed', 'real_entry_gap', 'helper_only_surface_gap') }
            'stateful_side_effect' { @('side_effect_ledger_gap', 'needs_transaction_test') }
            'deploy_export_page' { @('executable_surface_slice_gap', 'deploy_surface_contract_gap', 'surface_budget_gap') }
            'wire_payload_api_contract' { @('exact_contract_gap') }
            'config_policy_threshold' { @('exact_contract_gap', 'exact_contract_not_closed', 'config_policy_threshold_gap', 'executable_surface_slice_gap') }
            'generated_artifact_template_upload' { @('executable_surface_slice_gap', 'side_effect_ledger_gap') }
            'external_integration' { @('executable_surface_slice_gap', 'wrong_test_surface') }
            'automation_test_interface' { @('exact_contract_gap', 'wrong_test_surface') }
            'lifecycle_cleanup_retention' { @('side_effect_ledger_gap', 'needs_transaction_test', 'exact_contract_gap', 'lifecycle_cleanup_gap') }
            default { @() }
        }
        if ($narrowReadOnlyFeature -and [string]$family.id -eq 'automation_test_interface') {
            $familyGap = @('wrong_test_surface', 'behavior_test_charter_gap')
        }
          $hasFamilyGap = @($familyGap | Where-Object { $gapFlags -contains $_ }).Count -gt 0
         $isTouched = if ($hasExplicitTouched) {
             $explicitTouched -contains [string]$family.id
         } else {
             ($keywordHits.Count -gt 0) -or ($sliceTypeHit -and [int]$family.touched_count -eq 0)
         }
        $verifyProofMismatchFamiliesAtTouch = @(Get-StringArray $verify.proof_type_mismatch_families)
        if ($verifyProofMismatchFamiliesAtTouch -contains [string]$family.id) {
            $isTouched = $false
            if ($gapFlags -notcontains 'carrier_plan_mismatch') {
                $gapFlags += 'carrier_plan_mismatch'
            }
        }
         $sliceLabel = "S$SliceIndex"
        $existingSliceLabels = @($family.slices | ForEach-Object {
            $raw = [string]$_
            if ($raw -match '^S\d+$') {
                $raw
            } elseif ($raw -match '^\d+$') {
                "S$raw"
            }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $family.slices = @($existingSliceLabels)
        $family.touched_count = @($family.slices).Count
        $alreadyRecorded = @($family.slices) -contains $sliceLabel

        if ($isTouched) {
            $wasExecutableClosed = @('EXECUTABLE_CLOSED', 'CLOSED') -contains ([string]$family.status)
            $touched.Add([string]$family.id) | Out-Null
            $siblingSurfaces = @(Get-FamilySiblingSurfaces -Value $result.required_sibling_surfaces -FamilyId ([string]$family.id) -TouchedFamilies $explicitTouched)
            if ($narrowReadOnlyFeature -and @('core_entry', 'automation_test_interface') -contains [string]$family.id) {
                $siblingSurfaces = @()
            }
            $family.open_sibling_surfaces = @($siblingSurfaces)
            $family.open_sibling_count = @($siblingSurfaces).Count
            $family.last_next_recommended_slice_type = [string]$result.next_recommended_slice_type
            $family.last_gap_flags = @($gapFlags)
            if (-not $alreadyRecorded) {
                $family.slices = @($family.slices) + @($sliceLabel)
                $family.touched_count = @($family.slices).Count
            }
            if ($null -eq $family.first_slice) { $family.first_slice = $SliceIndex }
            $family.last_slice = $SliceIndex
            $explicitlyClosed = $explicitClosed -contains [string]$family.id
            $verifyWarnings = @(Get-StringArray $verify.warnings)
            $blockingClosureWarnings = @(
                'red_phase_did_not_fail',
                'red_phase_passed_before_fix',
                'red_phase_missing',
                'target_subsurface_missing',
                'production_boundary_missing',
                'proof_kind_missing',
                'red_expectation_missing',
                'static_contract_cannot_close_family_alone',
                'family_sibling_surface_open',
                'production_carrier_missing',
                'existing_production_carrier_missing',
                'synthetic_production_carrier',
                'side_effect_ledger_depth_incomplete',
                'proof_type_mismatch'
            ) | Where-Object { $verifyWarnings -contains $_ }
            if ($narrowReadOnlyFeature) {
                $blockingClosureWarnings = @($blockingClosureWarnings | Where-Object {
                    @('red_phase_missing', 'family_sibling_surface_open', 'side_effect_ledger_depth_incomplete') -notcontains [string]$_
                })
            }
            $authorizedForNextSlice = if ($null -ne $verify.authorized_for_next_slice) { [bool]$verify.authorized_for_next_slice } else { $true }
            $verifyBlockers = @(Get-StringArray $verify.authorization_blockers)
            $proofMismatchFamilies = @(Get-StringArray $verify.proof_type_mismatch_families)
            $familyProofTypeMatches = -not ($proofMismatchFamilies -contains [string]$family.id)
            $nonAuthorizingForFamily = @(
                'wrong_test_surface',
                'shallow_module',
                'synthetic_carrier_gap',
                'tooling_enforcement_stop',
                'mock_behavior_gap',
                'tdd_red_not_replayed',
                'no_progress_slice',
                'carrier_authorization_missing',
                'carrier_authorization_stop',
                'exact_contract_assertion_missing',
                'side_effect_evidence_missing',
                'side_effect_red_not_business_assertion',
                'exact_contract_not_closed'
            ) | Where-Object { $gapFlags -contains $_ }
            $explicitlyClosedByVerifier = $verifyClosed -contains [string]$family.id
            $authoritativeVerifierClosure = $explicitlyClosedByVerifier `
                -and $authorizedForNextSlice `
                -and [string]$verify.verification_status -eq 'PASS' `
                -and @('DONE', 'PARTIAL') -contains [string]$result.slice_status `
                -and -not $hasFamilyGap `
                -and $familyProofTypeMatches `
                -and $verifyBlockers.Count -eq 0 `
                -and @($nonAuthorizingForFamily).Count -eq 0
            if ($authoritativeVerifierClosure -or ($explicitlyClosed -and $authorizedForNextSlice -and @('PASS', 'PARTIAL') -contains [string]$verify.verification_status -and @('DONE', 'PARTIAL') -contains [string]$result.slice_status -and -not $hasFamilyGap -and $familyProofTypeMatches -and $blockingClosureWarnings.Count -eq 0 -and @($nonAuthorizingForFamily).Count -eq 0)) {
                Set-ObjectProperty -Object $family -Name 'status' -Value 'EXECUTABLE_CLOSED'
                Set-ObjectProperty -Object $family -Name 'open_sibling_surfaces' -Value @()
                Set-ObjectProperty -Object $family -Name 'open_sibling_count' -Value 0
                $closureReason = if ($authoritativeVerifierClosure) {
                    "Closed by S$SliceIndex from authoritative SLICE_VERIFY closed_requirement_families."
                } else {
                    "Closed by S$SliceIndex with family-scoped executable verification."
                }
                Set-ObjectProperty -Object $family -Name 'last_reason' -Value $closureReason
            } elseif ($wasExecutableClosed -and -not $explicitlyClosed -and -not $hasFamilyGap -and $familyProofTypeMatches -and $blockingClosureWarnings.Count -eq 0 -and @($nonAuthorizingForFamily).Count -eq 0) {
                Set-ObjectProperty -Object $family -Name 'status' -Value 'EXECUTABLE_CLOSED'
                Set-ObjectProperty -Object $family -Name 'open_sibling_surfaces' -Value @()
                Set-ObjectProperty -Object $family -Name 'open_sibling_count' -Value 0
                Set-ObjectProperty -Object $family -Name 'last_reason' -Value "Retained prior executable closure after S$SliceIndex supporting touch; no family-specific gap or proof mismatch was introduced."
            } else {
                $family.status = 'PARTIAL'
                $siblingReason = if (@($siblingSurfaces).Count -gt 0) { " Open sibling surfaces: $((@($siblingSurfaces) | Select-Object -First 3) -join '; ')" } else { '' }
                $family.last_reason = "Touched by S$SliceIndex but still has gap or partial verification.$siblingReason"
            }
        }
    }

    if ($touched.Count -eq 0) {
        $ledger.no_progress_slices = @($ledger.no_progress_slices) + @([ordered]@{
            slice = "S$SliceIndex"
            reason = 'Slice did not touch any detected requirement family.'
        })
    }

    $open = @($ledger.families | Where-Object {
        [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
    } | Sort-Object @{Expression = 'weight'; Descending = $true})

    if ($open.Count -gt 0) {
        $highest = Get-SafeInt ($open | Select-Object -First 1).weight -Default 100
        $computedCap = [Math]::Max(25, [int](95 - ($open.Count * 8) - [Math]::Floor($highest / 10)))
        $ledger.coverage_cap = [Math]::Min([int]$ledger.coverage_cap, $computedCap)
        foreach ($family in $open) {
            if ($null -ne $family.coverage_cap_if_open) {
                $familyCap = Get-SafeInt $family.coverage_cap_if_open -Default 100
                $ledger.coverage_cap = [Math]::Min([int]$ledger.coverage_cap, $familyCap)
            }
        }
        if (@($ledger.no_progress_slices).Count -gt 0) {
            $ledger.coverage_cap = [Math]::Min([int]$ledger.coverage_cap, 10)
        }
    } else {
        $ledger.coverage_cap = 100
    }

    if ($SliceIndex -ge $MaxSlices) {
        $ledger.open_required_after_max = @($open | ForEach-Object { "$($_.id):$($_.status)" })
    }

    Save-FamilyLedger -Ledger $ledger -Path $Path
    $ledgerAfter = Get-FamilyLedger -Path $Path
    Write-FamilyLedgerAudit -ReplayRoot $replayRootForLedger -Stage 'post_slice_verify_absorption' -SliceIndex $SliceIndex -Before $ledgerBefore -After $ledgerAfter -TouchedFamilies $explicitTouched -ClosedFamilies $explicitClosed
}

function Write-FamilyCapReport {
    param([string]$LedgerPath, [string]$OutPath)
    $ledger = Get-FamilyLedger -Path $LedgerPath
    if ($null -eq $ledger) { return }
    $open = @($ledger.families | Where-Object {
        [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
    } | Sort-Object @{Expression = 'weight'; Descending = $true})
    $rows = if ($open.Count -gt 0) {
        ($open | ForEach-Object { "| $($_.id) | $($_.status) | $($_.weight) | $($_.touched_count) | $($_.open_sibling_count) | $($_.last_reason) |" }) -join "`n"
    } else {
        "| none | EXECUTABLE_CLOSED | 0 | 0 | 0 | all detected families closed |"
    }
    $content = @"
# Requirement Family Cap

- ledger: `$LedgerPath`
- max_slices: $($ledger.max_slices)
- coverage_cap_from_ledger: $($ledger.coverage_cap)

| family | status | weight | touched | open siblings | reason |
|---|---|---:|---:|---:|---|
$rows
"@
    Set-Content -LiteralPath $OutPath -Value $content -Encoding UTF8
}

function Enforce-RoundCoverageCap {
    param([string]$RoundResultPath, [string]$RouterCapPath)

    if (-not (Test-Path -LiteralPath $RoundResultPath) -or -not (Test-Path -LiteralPath $RouterCapPath)) { return }

    try {
        $routerCap = Read-JsonObject -Path $RouterCapPath
    } catch {
        return
    }
    if ($null -eq $routerCap.coverage_cap_from_ledger -or "$($routerCap.coverage_cap_from_ledger)" -notmatch '^\d+$') { return }

    $ledgerCap = [int]$routerCap.coverage_cap_from_ledger
    $finalPassAllowed = if ($null -ne $routerCap.final_pass_allowed) { [bool]$routerCap.final_pass_allowed } else { $true }
    $text = Get-Content -LiteralPath $RoundResultPath -Raw -Encoding UTF8
    $originalCapped = $null
    $cappedPattern = [regex]'(?m)(verification_capped_coverage\s*[:=]\s*`?)(\d+)(`?)'
    $cappedMatch = $cappedPattern.Match($text)
    if ($cappedMatch.Success) {
        $originalCapped = [int]$cappedMatch.Groups[2].Value
        if ($originalCapped -gt $ledgerCap) {
            $text = $cappedPattern.Replace($text, { param($m) $m.Groups[1].Value + $ledgerCap + $m.Groups[3].Value }, 1)
        }
    }

    $coverageCapPattern = [regex]'(?m)(coverage_cap\s*[:=]\s*`?)(\d+)(`?)'
    $coverageCapMatch = $coverageCapPattern.Match($text)
    if ($coverageCapMatch.Success -and [int]$coverageCapMatch.Groups[2].Value -gt $ledgerCap) {
        $text = $coverageCapPattern.Replace($text, { param($m) $m.Groups[1].Value + $ledgerCap + $m.Groups[3].Value }, 1)
    }

    if (-not $finalPassAllowed) {
        $statusPattern = [regex]'(?m)(final_status\s*[:=]\s*`?)(PASS|DONE)(`?)'
        $text = $statusPattern.Replace($text, { param($m) $m.Groups[1].Value + 'BLOCKED' + $m.Groups[3].Value }, 1)
    }

    if ($text -notmatch '(?m)^## Runner Cap Enforcement\s*$') {
        $originalCappedText = if ($null -ne $originalCapped) { [string]$originalCapped } else { 'N/A' }
        $enforcementLines = @(
            '',
            '## Runner Cap Enforcement',
            "- family_router_and_cap: $RouterCapPath",
            "- coverage_cap_from_ledger: $ledgerCap",
            "- original_verification_capped_coverage: $originalCappedText",
            "- final_pass_allowed_by_ledger: $finalPassAllowed",
            '- enforcement: `verification_capped_coverage and final_status must not exceed ledger cap/final-pass decision`'
        ) -join "`n"
        $text = $text.TrimEnd() + $enforcementLines
    }

    Set-Content -LiteralPath $RoundResultPath -Value $text -Encoding UTF8
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-FamilySiblingSurfaces {
    param(
        $Value,
        [string]$FamilyId,
        [string[]]$TouchedFamilies
    )

    $all = @(Get-StringArray $Value)
    $matched = New-Object System.Collections.Generic.List[string]
    $unscoped = New-Object System.Collections.Generic.List[string]
    foreach ($item in $all) {
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match '^\s*([a-z][a-z0-9_]+)\s*:\s*(.+)$') {
            if ($matches[1] -eq $FamilyId) {
                $matched.Add((Normalize-SiblingSurface -Surface $matches[2])) | Out-Null
            } elseif ($matches[1].Length -eq 1) {
                $unscoped.Add((Normalize-SiblingSurface -Surface $text)) | Out-Null
            }
        } else {
            $unscoped.Add((Normalize-SiblingSurface -Surface $text)) | Out-Null
        }
    }
    if ($matched.Count -gt 0) { return @($matched) }
    if (@($TouchedFamilies).Count -eq 1 -or (@($TouchedFamilies).Count -gt 0 -and [string]$TouchedFamilies[0] -eq $FamilyId)) {
        return @($unscoped)
    }
    return @()
}

function Get-PreflightCompilationEvidenceForBlockedSlice {
    param([string]$SliceResultPath)

    $evidence = [ordered]@{
        command = ''
        exit_code = $null
        evidence = $false
        evidence_source = ''
    }
    if ([string]::IsNullOrWhiteSpace($SliceResultPath)) { return $evidence }

    $replayRootDir = Split-Path -Parent $SliceResultPath
    if ([string]::IsNullOrWhiteSpace($replayRootDir)) { return $evidence }

    $preflightPath = Join-Path $replayRootDir 'PREFLIGHT_TEST_COMPILATION.json'
    if (-not (Test-Path -LiteralPath $preflightPath -PathType Leaf)) { return $evidence }

    try {
        $preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $preflightExitCode = $null
        if ($preflight.PSObject.Properties.Name -contains 'exit_code') {
            $preflightExitCode = $preflight.exit_code
        }
        if ($null -ne $preflightExitCode) {
            $evidence.exit_code = [int]$preflightExitCode
            $evidence.evidence_source = $preflightPath
            if ([int]$preflightExitCode -eq 0) {
                $evidence.evidence = $true
            }
        }
        if ($preflight.PSObject.Properties.Name -contains 'maven_command_args') {
            $evidence.command = [string]$preflight.maven_command_args
        }
    } catch {
        # Malformed preflight artifacts must not prevent blocked-result synthesis.
    }
    return $evidence
}

function Write-ExecutorBlockedSliceResult {
    param(
        [string]$Path,
        [int]$SliceIndex,
        $ForcedDecision,
        [string]$SliceLogDir,
        [int]$ExitCode,
        [string]$Reason = 'executor failed before completing slice',
        [string]$FailureCategory = '',
        [string]$ExecutorDiagnostic = '',
        $PartialDiffAudit = $null
    )

    $sliceId = 'S{0}' -f $SliceIndex
    $forcedFamily = [string]$ForcedDecision.family_id
    $gapFlags = @('tooling_executor_failed', 'no_progress_slice')
    $partialChangedFiles = @()
    $partialAuditJson = ''
    $partialAuditMd = ''
    if ($null -ne $PartialDiffAudit) {
        $partialChangedFiles = @(Get-StringArray $PartialDiffAudit.ChangedFiles)
        $partialAuditJson = [string]$PartialDiffAudit.JsonPath
        $partialAuditMd = [string]$PartialDiffAudit.MdPath
        if ($partialChangedFiles.Count -gt 0) {
            $gapFlags += 'partial_worktree_diff_detected'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($FailureCategory)) {
        $gapFlags += $FailureCategory
        if (@('executor_credit_required', 'usage_limit', 'auth') -contains $FailureCategory) {
            $gapFlags += 'executor_resource_blocker'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($forcedFamily)) {
        $gapFlags += 'gate_present_but_not_enforced'
    }
    $preflightCompilation = Get-PreflightCompilationEvidenceForBlockedSlice -SliceResultPath $Path

    [ordered]@{
        slice_index = $SliceIndex
        slice_id = $sliceId
        slice_title = $Reason
        slice_type = 'blocker'
        slice_status = 'BLOCKED'
        coverage_delta = 0
        target_subsurface_or_carrier = 'executor:blocker'
        required_sibling_surfaces = @()
        production_boundary = $(if ($partialChangedFiles.Count -gt 0) { 'partial worktree diff exists but executor failed before proof artifact' } else { 'none - executor failed before production boundary could be changed' })
        proof_kind = $(if ($partialChangedFiles.Count -gt 0) { 'partial_worktree_diff_audit' } else { 'static_contract' })
        red_expectation = 'not executed - executor failed before RED could run'
        implemented_files = @()
        current_slice_changed_files = @($partialChangedFiles)
        round_changed_files_snapshot = @($partialChangedFiles)
        tests = @(
            [ordered]@{
                command = "Invoke-AgentPrompt.ps1"
                phase = 'EXECUTOR'
                result = 'blocked'
                evidence = "$Reason; executor exit code $ExitCode; inspect $SliceLogDir"
            }
        )
        closed_assertions = @()
        must_not_assertions = @()
        remaining_gaps = @(
            "$Reason. Forced family: $forcedFamily",
            $(if ($partialChangedFiles.Count -gt 0) { "Partial worktree diff requires recovery or cleanup before the next slice. Audit: $partialAuditJson" } else { "No partial worktree diff was detected." })
        )
        gap_flags = $gapFlags
        executor_failure_category = $FailureCategory
        executor_diagnostic = $ExecutorDiagnostic
        partial_worktree_diff_detected = ($partialChangedFiles.Count -gt 0)
        partial_worktree_diff_audit = $partialAuditJson
        partial_worktree_diff_report = $partialAuditMd
        executor_resource_blocker = (@('executor_credit_required', 'usage_limit', 'auth') -contains $FailureCategory)
        test_compilation_command = [string]$preflightCompilation.command
        test_compilation_exit_code = $preflightCompilation.exit_code
        test_compilation_evidence = [bool]$preflightCompilation.evidence
        test_compilation_evidence_source = [string]$preflightCompilation.evidence_source
        touched_requirement_families = @()
        closed_requirement_families = @()
        blocker = "Phase1 slice blocked: $Reason. Executor exit code $ExitCode. Inspect logs under $SliceLogDir."
        next_recommended_slice_type = $(if ([string]::IsNullOrWhiteSpace([string]$ForcedDecision.slice_type)) { 'stateful_success_slice' } else { [string]$ForcedDecision.slice_type })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-EvidenceCaptureRepair {
    param(
        [string]$SliceResultPath,
        [string]$SliceLogDir,
        [string]$ReplayRoot
    )

    if ([string]::IsNullOrWhiteSpace($SliceResultPath) -or -not (Test-Path -LiteralPath $SliceResultPath -PathType Leaf)) { return }

    try {
        $resultText = Get-Content -LiteralPath $SliceResultPath -Raw -Encoding UTF8
        $result = $resultText | ConvertFrom-Json
        $sliceStatus = ([string]$result.slice_status).ToUpperInvariant()
        if (@('DONE', 'COMPLETED') -notcontains $sliceStatus) { return }

        $changed = $false
        $hasExecCmd = -not [string]::IsNullOrWhiteSpace([string]$result.test_execution_command)
        $hasCompileCmd = -not [string]::IsNullOrWhiteSpace([string]$result.test_compilation_command)

        if (-not $hasExecCmd) {
            $tests = @()
            if ($null -ne $result.tests) {
                if ($result.tests -is [System.Array]) { $tests = @($result.tests) } else { $tests = @($result.tests) }
            }
            foreach ($test in $tests) {
                if ($null -eq $test) { continue }
                $testCommand = [string]$test.command
                $testPhase = ([string]$test.phase).ToUpperInvariant()
                $testResult = ([string]$test.result).ToLowerInvariant()
                $exitCodeValue = $test.exit_code
                if ($null -eq $exitCodeValue) { $exitCodeValue = $test.test_execution_exit_code }
                $exitCodeParsed = 1
                $hasParsedExitCode = $false
                if ($null -ne $exitCodeValue) {
                    $exitCodeText = ([string]$exitCodeValue).Trim()
                    $hasParsedExitCode = [int]::TryParse($exitCodeText, [ref]$exitCodeParsed)
                }
                $isExecutableMavenTest = (
                    $testCommand -match '(?i)\bmvn(?:\.cmd)?\b' -and
                    $testCommand -match '(?i)-D(?:it\.)?test\s*=' -and
                    $testCommand -match '(?i)(^|[\s"`''])-am($|[\s"`''])'
                )
                if (-not [string]::IsNullOrWhiteSpace($testCommand) -and
                    @('GREEN', 'VERIFY') -contains $testPhase -and
                    $testResult -eq 'pass' -and
                    $hasParsedExitCode -and
                    [int]$exitCodeParsed -eq 0 -and
                    $isExecutableMavenTest) {
                    Set-ObjectProperty -Object $result -Name 'test_execution_command' -Value $testCommand
                    Set-ObjectProperty -Object $result -Name 'test_execution_exit_code' -Value 0
                    Set-ObjectProperty -Object $result -Name 'test_execution_evidence_source' -Value 'SLICE_RESULT.tests'
                    $testModule = [string]$test.test_module
                    if (-not [string]::IsNullOrWhiteSpace($testModule)) {
                        Set-ObjectProperty -Object $result -Name 'test_module' -Value $testModule
                    }
                    $changed = $true
                    break
                }
            }
        }

        $preflightPath = Join-Path $ReplayRoot 'PREFLIGHT_TEST_COMPILATION.json'
        if (-not $hasCompileCmd -and (Test-Path -LiteralPath $preflightPath -PathType Leaf)) {
            try {
                $preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $preflightCommand = [string]$preflight.maven_command_args
                if (-not [string]::IsNullOrWhiteSpace($preflightCommand)) {
                    Set-ObjectProperty -Object $result -Name 'test_compilation_command' -Value $preflightCommand
                    Set-ObjectProperty -Object $result -Name 'test_compilation_evidence_source' -Value $preflightPath
                    $changed = $true
                }
                if ($preflight.PSObject.Properties.Name -contains 'exit_code') {
                    $preflightExitCode = $preflight.exit_code
                    if ($null -ne $preflightExitCode) {
                        $preflightExitCodeParsed = [int]$preflightExitCode
                        Set-ObjectProperty -Object $result -Name 'test_compilation_exit_code' -Value $preflightExitCodeParsed
                        if ($preflightExitCodeParsed -eq 0) {
                            Set-ObjectProperty -Object $result -Name 'test_compilation_evidence' -Value $true
                        }
                        $changed = $true
                    }
                }
            } catch {}
        }

        # v635: Fallback for NL-only evidence with BUILD_SUCCESS. When the agent
        # produced GREEN/pass evidence with test execution results (BUILD_SUCCESS,
        # tests_run) but omitted the `command` field in the tests array, synthesize
        # a test_execution_command from the available compilation command and test
        # class. This prevents has_behavior_evidence=false when tests were actually
        # executed and passed (proven by the evidence text).
        if (-not $hasExecCmd -and -not $changed -and $hasCompileCmd) {
            $compileCmdText = [string]$result.test_compilation_command
            if ($compileCmdText -match '(?i)\bmvn(?:\.cmd)?\b') {
                $testClassSimple = ''
                $testClassFull = [string]$result.test_class
                if (-not [string]::IsNullOrWhiteSpace($testClassFull)) {
                    $lastDot = $testClassFull.LastIndexOf('.')
                    if ($lastDot -ge 0 -and $lastDot -lt $testClassFull.Length - 1) {
                        $testClassSimple = $testClassFull.Substring($lastDot + 1)
                    } else {
                        $testClassSimple = $testClassFull
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($testClassSimple)) {
                    foreach ($test in $tests) {
                        if ($null -eq $test) { continue }
                        $testPhase = ([string]$test.phase).ToUpperInvariant()
                        $testResult = ([string]$test.result).ToLowerInvariant()
                        $evidenceText = [string]$test.evidence
                        $hasCommand = -not [string]::IsNullOrWhiteSpace([string]$test.command)
                        $hasBuildEvidence = $evidenceText -match '(?i)BUILD[ _]SUCCESS|tests_run\s*=\s*[1-9]\d*'
                        if (-not $hasCommand -and $testPhase -eq 'GREEN' -and $testResult -eq 'pass' -and $hasBuildEvidence) {
                            $worktreeDir = Join-Path $ReplayRoot 'worktree'
                            $worktreePom = Join-Path $worktreeDir 'pom.xml'
                            if (Test-Path -LiteralPath $worktreePom -PathType Leaf) {
                                $synthesizedCommand = "mvn -f `"$worktreePom`" -Dtest=$testClassSimple -Dsurefire.failIfNoSpecifiedTests=false test"
                                Set-ObjectProperty -Object $result -Name 'test_execution_command' -Value $synthesizedCommand
                                Set-ObjectProperty -Object $result -Name 'test_execution_exit_code' -Value 0
                                Set-ObjectProperty -Object $result -Name 'test_execution_evidence_source' -Value 'SLICE_RESULT.tests.evidence'
                                $changed = $true
                                break
                            }
                        }
                    }
                }
            }
        }

        if ($changed) {
            $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SliceResultPath -Encoding UTF8
        }
    } catch {
        # Best-effort metadata repair must never hide verifier failures.
    }
}

function Normalize-SliceProgress {
    param(
        [string]$Path,
        [string]$ReplayRoot,
        [int]$MaxSlices,
        [int]$SliceIndex = 0,
        [switch]$MarkStopped,
        [string]$StopReason = ''
    )

    $completed = New-Object System.Collections.Generic.List[int]
    $existingStopped = $false
    $existingStopReason = ''

    if (Test-Path -LiteralPath $Path) {
        try {
            $existing = Read-JsonObject -Path $Path
            foreach ($item in @($existing.completed)) {
                if ($null -eq $item) { continue }
                $text = [string]$item
                if ($text -match '(\d+)') {
                    $value = [int]$Matches[1]
                    if ($value -gt 0 -and -not $completed.Contains($value)) {
                        $completed.Add($value) | Out-Null
                    }
                }
            }
            if ($existing.PSObject.Properties.Name -contains 'stopped') {
                $existingStopped = [bool]$existing.stopped
            }
            if ($existing.PSObject.Properties.Name -contains 'stop_reason') {
                $existingStopReason = [string]$existing.stop_reason
            }
        } catch {
            $existingStopped = $false
            $existingStopReason = ''
        }
    }

    if ($SliceIndex -gt 0 -and -not $completed.Contains($SliceIndex)) {
        $completed.Add($SliceIndex) | Out-Null
    }

    $orderedCompleted = @($completed | Sort-Object -Unique)
    $stoppedValue = if ($MarkStopped) { $true } else { $false }
    $reasonValue = if ($MarkStopped -and -not [string]::IsNullOrWhiteSpace($StopReason)) {
        $StopReason
    } elseif ($MarkStopped) {
        $existingStopReason
    } else {
        ''
    }

    [ordered]@{
        replay_root = $ReplayRoot
        max_slices = $MaxSlices
        completed = $orderedCompleted
        stopped = $stoppedValue
        stop_reason = $reasonValue
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Copy-SliceResultFromWorktree {
    param(
        [string]$Worktree,
        [string]$Destination,
        [int]$SliceIndex
    )

    if (Test-Path -LiteralPath $Destination) { return $true }
    $worktreeSliceResult = Join-Path $Worktree ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
    if (Test-Path -LiteralPath $worktreeSliceResult) {
        Copy-Item -LiteralPath $worktreeSliceResult -Destination $Destination -Force
        return $true
    }
    return $false
}

function Invoke-ForcedFamilyRepair {
    param(
        [string]$ReplayRoot,
        [string]$Worktree,
        [string]$SlicePrompt,
        [string]$SliceResult,
        [int]$SliceIndex,
        $ForcedDecision,
        [string]$Executor,
        [string]$Sandbox,
        [string]$Approval,
        [int]$TimeoutMinutes,
        [string]$Model,
        [string]$ReasoningEffort,
        [string]$RunnerContractPath,
        [string[]]$TouchedFamilies
    )

    $sliceId = 'slice{0:D2}' -f $SliceIndex
    $forcedFamily = [string]$ForcedDecision.family_id
    $forcedSliceType = [string]$ForcedDecision.slice_type
    $forcedSiblingSurface = [string]$ForcedDecision.target_sibling_surface
    $touchedText = if (@($TouchedFamilies).Count -gt 0) { (@($TouchedFamilies) -join ', ') } else { 'none' }
    $repairPrompt = Join-Path $ReplayRoot ('PHASE1_SLICE_{0:D2}_FORCED_FAMILY_REPAIR_PROMPT.md' -f $SliceIndex)
    $repairLogDir = Join-Path (Join-Path $ReplayRoot 'logs\phase1-slices') ('{0}-forced-family-repair' -f $sliceId)
    $previousResult = Read-TextIfExists -Path $SliceResult

    if (Test-Path -LiteralPath $SliceResult) {
        $backupResult = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.before_forced_family_repair.json' -f $SliceIndex)
        Copy-Item -LiteralPath $SliceResult -Destination $backupResult -Force
        Remove-Item -LiteralPath $SliceResult -Force
    }
    $worktreeSliceResult = Join-Path $Worktree ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
    if (Test-Path -LiteralPath $worktreeSliceResult) {
        $backupWorktreeResult = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.worktree_before_forced_family_repair.json' -f $SliceIndex)
        Copy-Item -LiteralPath $worktreeSliceResult -Destination $backupWorktreeResult -Force
        Remove-Item -LiteralPath $worktreeSliceResult -Force
    }

    $repairPreamble = @(
        'REPAIR MODE: the previous slice touched the wrong requirement family.',
        '',
        "Forced requirement family: $forcedFamily",
        "Forced slice type: $forcedSliceType",
        "Forced sibling surface: $forcedSiblingSurface",
        "Previous touched_requirement_families: $touchedText",
        '',
        'This is not a scoring issue. The runner requires this slice to either touch the forced family or declare BLOCKED/INVALID_REPLAY with a concrete blocker.',
        'Do not keep a helper/supporting-family slice as DONE or PARTIAL evidence. Do not continue improving a lower-weight validator, DTO, constant, field mapper, static guard, or test-only carrier.',
        'If the wrong-family files are not required by the forced family, remove them from the isolated worktree before writing the repaired result.',
        '',
        'Required repair outcome:',
        "1. Implement or test the forced family ($forcedFamily) and write touched_requirement_families including it; OR",
        '2. Write a BLOCKED SLICE_RESULT with coverage_delta=0 and gap_flags including tooling_enforcement_stop and no_progress_slice.',
        '',
        "Overwrite the required SLICE_RESULT JSON at: $SliceResult",
        '',
        'Previous SLICE_RESULT excerpt:',
        '```json',
        ($previousResult.Substring(0, [Math]::Min($previousResult.Length, 3000))),
        '```',
        '',
        'Original slice prompt follows.',
        ''
    ) -join "`n"
    Set-Content -LiteralPath $repairPrompt -Encoding UTF8 -Value ($repairPreamble + "`n" + (Get-Content -LiteralPath $SlicePrompt -Raw -Encoding UTF8))
    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} forced-family repair | {1} | {2} | forced_family_mismatch_repair | previous touched families={3}; retrying once before fail-closed. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $touchedText)

    $repairAgentArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
        '-PromptPath', $repairPrompt,
        '-WorkDir', $Worktree,
        '-LogDir', $repairLogDir,
        '-Executor', $Executor,
        '-Sandbox', $Sandbox,
        '-Approval', $Approval,
        '-TimeoutMinutes', $TimeoutMinutes,
        '-CompletionPath', $SliceResult,
        '-CompletionQuietSeconds', 90,
        '-Name', ('phase1-{0}-forced-family-repair' -f $sliceId)
    )
    if (-not [string]::IsNullOrWhiteSpace($Model)) { $repairAgentArgs += @('-Model', $Model) }
    if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) { $repairAgentArgs += @('-ReasoningEffort', $ReasoningEffort) }

    $repairSmokeArgs = @($repairAgentArgs + @('-ValidateOnly'))
    & powershell @repairSmokeArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-ExecutorBlockedSliceResult -Path $SliceResult -SliceIndex $SliceIndex -ForcedDecision $ForcedDecision -SliceLogDir $repairLogDir -ExitCode $LASTEXITCODE -Reason 'forced-family repair runner invocation smoke failed before starting executor'
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} forced-family repair smoke blocked | {1} | {2} | runner_invocation_error | validate-only exit_code={3}. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $LASTEXITCODE)
        return $false
    }

    $repairExitCode = Invoke-SliceExecutorWithRetry -AgentArgs $repairAgentArgs -SliceLogDir $repairLogDir -SliceId "$sliceId-forced-family-repair" -MaxRetries 1 -DelaySeconds 60
    [void](Copy-SliceResultFromWorktree -Worktree $Worktree -Destination $SliceResult -SliceIndex $SliceIndex)
    if (-not (Test-Path -LiteralPath $SliceResult)) {
        Write-ExecutorBlockedSliceResult -Path $SliceResult -SliceIndex $SliceIndex -ForcedDecision $ForcedDecision -SliceLogDir $repairLogDir -ExitCode $repairExitCode -Reason 'forced-family repair completed without writing required SLICE_RESULT'
        Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} forced-family repair blocked | {1} | {2} | missing_slice_result_after_repair | exit_code={3}. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $repairExitCode)
        return $false
    }

    Add-Content -LiteralPath $RunnerContractPath -Encoding UTF8 -Value ("| S{0} forced-family repair completed | {1} | {2} | repair_result_written | exit_code={3}. |" -f $SliceIndex, $forcedFamily, $forcedSliceType, $repairExitCode)
    return $true
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$projectRootFull = Resolve-AbsolutePath $ProjectRoot
$requirementSourceFull = Resolve-AbsolutePath $RequirementSource
$baselineIndexFull = Resolve-AbsolutePath $BaselineIndex
$contextManifestFull = Resolve-AbsolutePath $ContextManifest
$systemContextDirFull = if ([string]::IsNullOrWhiteSpace($SystemContextDir)) { '' } else { Resolve-AbsolutePath $SystemContextDir }

$sliceTemplatePath = Join-Path $scriptRoot 'prompts\phase1-slice-executor.prompt.md'
$synthesisTemplatePath = Join-Path $scriptRoot 'prompts\phase1-round-synthesis.prompt.md'
$progressPath = Join-Path $replayRootFull 'SLICE_PROGRESS.json'
$progressMdPath = Join-Path $replayRootFull 'SLICE_PROGRESS.md'
$familyLedgerPath = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'
$sourceChainContractPath = Join-Path $replayRootFull 'SOURCE_CHAIN_CONTRACT.json'
$familyCapPath = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_CAP.md'
$runnerContractPath = Join-Path $replayRootFull 'RUNNER_ENFORCEMENT_CONTRACT.md'
$roundResultPath = Join-Path $replayRootFull 'ROUND_RESULT.md'
$surfaceCarrierScanPath = Join-Path $replayRootFull 'SURFACE_CARRIER_SCAN.md'
$featureClassificationPath = Join-Path $replayRootFull 'FEATURE_CLASSIFICATION.json'
$logsRoot = Join-Path $replayRootFull 'logs\phase1-slices'
$phase1InitGateActive = $true
$phase1InitExceptionPath = Join-Path $replayRootFull 'PHASE1_INIT_EXCEPTION.txt'

trap {
    if ($phase1InitGateActive) {
        $message = [string]$_.Exception.Message
        $position = if ($null -ne $_.InvocationInfo) { [string]$_.InvocationInfo.PositionMessage } else { '' }
        $detail = @(
            "message: $message",
            '',
            $position
        ) -join "`n"
        try {
            $detail | Set-Content -LiteralPath $phase1InitExceptionPath -Encoding UTF8
            Write-Phase1InitFailure -ReplayRoot $replayRootFull -LogsRoot $logsRoot -RunnerContractPath $runnerContractPath -ProgressPath $progressPath -MaxSlices $MaxSlices -Reason "phase1_init_exception:$message" -EvidencePath $phase1InitExceptionPath
        } catch {
            # If diagnostic writing itself fails, keep the stable exit code.
        }
        exit 95
    }
    break
}

$required = @($replayRootFull, $worktreeFull, $requirementSourceFull, $baselineIndexFull, $contextManifestFull, $sliceTemplatePath, $synthesisTemplatePath)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Phase1InitFailure -ReplayRoot $replayRootFull -LogsRoot $logsRoot -RunnerContractPath $runnerContractPath -ProgressPath $progressPath -MaxSlices $MaxSlices -Reason "required_path_missing:$path" -EvidencePath $path
        exit 95
    }
}

if ($MaxSlices -lt 1) { $MaxSlices = 1 }
New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null
$MavenSettings = Resolve-MavenSettingsPath -ConfiguredValue $MavenSettings
if (-not [string]::IsNullOrWhiteSpace($MavenSettings)) {
    Write-Host "Using Maven settings ($script:ResolvedMavenSettingsSource): $MavenSettings"
}

if ($ValidateOnly) {
    [pscustomobject]@{
        status = 'VALID'
        replay_root = $replayRootFull
        worktree = $worktreeFull
        max_slices = $MaxSlices
        slice_template = $sliceTemplatePath
        synthesis_template = $synthesisTemplatePath
        requirement_family_ledger = $familyLedgerPath
        surface_carrier_scan = $surfaceCarrierScanPath
        model = $Model
        reasoning_effort = $ReasoningEffort
    } | Format-List
    exit 0
}

if (-not (Test-Path -LiteralPath $featureClassificationPath)) {
    $featureClassifierScript = Join-Path $PSScriptRoot 'Classify-Feature.ps1'
    if (Test-Path -LiteralPath $featureClassifierScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $featureClassifierScript `
            -ReplayRoot $replayRootFull `
            -Worktree $worktreeFull `
            -RequirementSource $requirementSourceFull `
            -OutPath $featureClassificationPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Phase1InitFailure -ReplayRoot $replayRootFull -LogsRoot $logsRoot -RunnerContractPath $runnerContractPath -ProgressPath $progressPath -MaxSlices $MaxSlices -Reason "classify_feature_failed:exit_$LASTEXITCODE" -EvidencePath $featureClassificationPath
            exit 95
        }
    }
}

Initialize-RequirementFamilyLedger -Path $familyLedgerPath -ReplayRoot $replayRootFull -RequirementSource $requirementSourceFull -MaxSlices $MaxSlices
$initialLedger = Get-FamilyLedger -Path $familyLedgerPath
if (Apply-FamilyScopeFilter -Ledger $initialLedger -RequirementSource $requirementSourceFull -ReplayRoot $replayRootFull) {
    Save-FamilyLedger -Ledger $initialLedger -Path $familyLedgerPath
}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Analyze-SourceChainContract.ps1') -ReplayRoot $replayRootFull -RequirementSource $requirementSourceFull | Out-Null

# v465: Plan schema fail-fast validation
if (Test-Path -LiteralPath (Join-Path $replayRootFull 'PLAN_RESULT.json')) {
    $planMachineNormalizer = Join-Path $PSScriptRoot 'Sync-PlanMachineContract.ps1'
    if (Test-Path -LiteralPath $planMachineNormalizer -PathType Leaf) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $planMachineNormalizer `
            -ReplayRoot $replayRootFull `
            -PlanResultPath (Join-Path $replayRootFull 'PLAN_RESULT.json') `
            -FirstSliceProofPath (Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md') | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Phase1InitFailure -ReplayRoot $replayRootFull -LogsRoot $logsRoot -RunnerContractPath $runnerContractPath -ProgressPath $progressPath -MaxSlices $MaxSlices -Reason "plan_machine_contract_normalization_failed:exit_$LASTEXITCODE" -EvidencePath (Join-Path $replayRootFull 'PLAN_MACHINE_CONTRACT_NORMALIZATION.json')
            exit 95
        }
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-PlanSchemaFailFast.ps1') -ReplayRoot $replayRootFull -PlanResultPath (Join-Path $replayRootFull 'PLAN_RESULT.json') | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Phase1InitFailure -ReplayRoot $replayRootFull -LogsRoot $logsRoot -RunnerContractPath $runnerContractPath -ProgressPath $progressPath -MaxSlices $MaxSlices -Reason "plan_schema_validation_failed:exit_$LASTEXITCODE" -EvidencePath (Join-Path $replayRootFull 'PLAN_SCHEMA_FAILFAST.json')
        exit 95
    }
}

# v465: Pre-execution constraint check
if (Test-Path -LiteralPath (Join-Path $replayRootFull 'PLAN_RESULT.json')) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-PreExecutionConstraintCheck.ps1') -ReplayRoot $replayRootFull -Worktree $worktreeFull -PlanResultPath (Join-Path $replayRootFull 'PLAN_RESULT.json') -BaselineRoot $projectRootFull -FeatureClassificationPath $featureClassificationPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Phase1InitFailure -ReplayRoot $replayRootFull -LogsRoot $logsRoot -RunnerContractPath $runnerContractPath -ProgressPath $progressPath -MaxSlices $MaxSlices -Reason "pre_execution_constraint_check_failed:exit_$LASTEXITCODE" -EvidencePath (Join-Path $replayRootFull 'PRE_EXECUTION_CONSTRAINT_CHECK.json')
        exit 95
    }
}

if (-not (Test-Path -LiteralPath $progressPath)) {
    [ordered]@{
        replay_root = $replayRootFull
        max_slices = $MaxSlices
        completed = @()
        stopped = $false
        stop_reason = ''
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $progressPath -Encoding UTF8
}
Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'ReplayDryRunGate.ps1') -ReplayRoot $replayRootFull -Mode FirstSliceProofPlan -ExpectStatus ALLOW | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Phase1InitFailure -ReplayRoot $replayRootFull -LogsRoot $logsRoot -RunnerContractPath $runnerContractPath -ProgressPath $progressPath -MaxSlices $MaxSlices -Reason "first_slice_dry_run_denied:exit_$LASTEXITCODE" -EvidencePath (Join-Path $replayRootFull 'DRY_RUN_GATE.json')
    exit 95
}

$sliceTemplate = Get-Content -LiteralPath $sliceTemplatePath -Raw -Encoding UTF8
$synthesisTemplate = Get-Content -LiteralPath $synthesisTemplatePath -Raw -Encoding UTF8
$phase1InitGateActive = $false

for ($i = 1; $i -le $MaxSlices; $i++) {
    $sliceId = 'slice{0:D2}' -f $i
    $slicePrompt = Join-Path $replayRootFull ('PHASE1_SLICE_{0:D2}_PROMPT.md' -f $i)
    $sliceResult = Join-Path $replayRootFull ('SLICE_RESULT_{0:D2}.json' -f $i)
    $sliceVerify = Join-Path $replayRootFull ('SLICE_VERIFY_{0:D2}.json' -f $i)
    $carrierAuthorization = Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $i)
    $carrierRank = Join-Path $replayRootFull ('CARRIER_RANK_{0:D2}.json' -f $i)
    $exactContractMatrix = Join-Path $replayRootFull ('EXACT_CONTRACT_ASSERTION_MATRIX_{0:D2}.json' -f $i)
    $nextSliceExactContract = Join-Path $replayRootFull ('NEXT_SLICE_EXACT_CONTRACT_{0:D2}.json' -f $i)
    $sideEffectEvidence = Join-Path $replayRootFull ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $i)
    $preSliceAuthorization = Join-Path $replayRootFull ('PRE_SLICE_AUTHORIZATION_{0:D2}.json' -f $i)
    $preSliceCapDisplay = Join-Path $replayRootFull ('PRE_SLICE_CAP_DISPLAY_{0:D2}.json' -f $i)
    $sliceLogDir = Join-Path $logsRoot $sliceId

    $executorExitCode = $null
    $retryExitCode = $null
    $hasExistingResult = Test-Path -LiteralPath $sliceResult
    $hasExistingVerify = Test-Path -LiteralPath $sliceVerify
    $blockedBeforeExecutor = $false
    $ledger = Get-FamilyLedger -Path $familyLedgerPath
    $rankMap = New-CarrierRankMap -Ledger $ledger -SliceIndex $i
    $rankMap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $carrierRank -Encoding UTF8
    $rankMap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRootFull 'CARRIER_RANK.json') -Encoding UTF8
    $currentForced = Resolve-ForcedFamilyDecisionForSlice `
        -Ledger $ledger `
        -SliceIndex $i `
        -CarrierRank $rankMap `
        -SourceChainContractPath $sourceChainContractPath `
        -RunnerContractPath $runnerContractPath

    if (Test-NoOpenRequiredFamilyForSlice -Ledger $ledger -CarrierRank $rankMap -ForcedDecision $currentForced) {
        Clear-SliceArtifactsAfterRequirementClosure `
            -ReplayRoot $replayRootFull `
            -SliceIndex $i `
            -MaxSlices $MaxSlices `
            -RunnerContractPath $runnerContractPath | Out-Null
        Set-SliceProgressFromAuthorizingEvidence -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices
        break
    }

    $testCharterRepairResult = Join-Path $replayRootFull ('TEST_CHARTER_REPAIR_RESULT_{0:D2}.md' -f $i)
    if ($hasExistingResult -and $hasExistingVerify -and (Test-Path -LiteralPath $testCharterRepairResult)) {
        try {
            $existingSliceResult = Read-JsonObject -Path $sliceResult
            $repairResultText = Read-TextIfExists -Path $testCharterRepairResult
            $isStaleTestCharterBlocker = (
                [string]$existingSliceResult.slice_status -eq 'BLOCKED' -and
                (
                    [string]$existingSliceResult.blocker -match 'test charter' -or
                    [string]$existingSliceResult.slice_title -match 'test charter'
                ) -and
                $repairResultText -match '(?im)^\s*-\s*validation_status:\s*PASSED\s*$' -and
                $repairResultText -match '(?im)^\s*-\s*can_proceed:\s*true\s*$'
            )
            if ($isStaleTestCharterBlocker) {
                $staleDir = Join-Path (Join-Path $replayRootFull 'logs\stale-slice-results') ('slice{0:D2}' -f $i)
                if (-not (Test-Path -LiteralPath $staleDir)) {
                    New-Item -ItemType Directory -Force -Path $staleDir | Out-Null
                }
                $stamp = Get-Date -Format 'yyyyMMddHHmmss'
                Move-Item -LiteralPath $sliceResult -Destination (Join-Path $staleDir ("SLICE_RESULT_{0:D2}.{1}.json" -f $i, $stamp)) -Force
                Move-Item -LiteralPath $sliceVerify -Destination (Join-Path $staleDir ("SLICE_VERIFY_{0:D2}.{1}.json" -f $i, $stamp)) -Force
                Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} stale test charter blocker invalidated | test_charter_repair | resume_safety | executable_evidence | archived stale slice result because repair result passed; repair_result={1}. |" -f $i, $testCharterRepairResult)
                $hasExistingResult = $false
                $hasExistingVerify = $false
            }
        } catch {
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} stale test charter blocker check skipped | test_charter_repair | resume_safety | non_authorizing_evidence | error={1}. |" -f $i, ($_.Exception.Message -replace '\|', '/'))
        }
    }
    if ($hasExistingResult -and $hasExistingVerify) {
        try {
            $existingSliceResult = Read-JsonObject -Path $sliceResult
            $existingSliceVerify = Read-JsonObject -Path $sliceVerify
            if (Test-StaleBlockedSliceForResume -SliceResultObject $existingSliceResult -SliceVerifyObject $existingSliceVerify -ForcedDecision $currentForced) {
                Archive-StaleSliceArtifacts `
                    -ReplayRoot $replayRootFull `
                    -SliceIndex $i `
                    -Paths @(
                        $sliceResult,
                        $sliceVerify,
                        $carrierAuthorization,
                        $preSliceAuthorization,
                        $preSliceCapDisplay,
                        $carrierRank,
                        $exactContractMatrix,
                        $nextSliceExactContract,
                        $sideEffectEvidence,
                        (Join-Path $replayRootFull ('CHECKPOINT_GATE_{0:D2}.json' -f $i)),
                        (Join-Path $replayRootFull ('V348_SLICE_QUALITY_GATE_{0:D2}.json' -f $i)),
                        (Join-Path $replayRootFull ('LAYER_VALIDATION_{0:D2}.stdout.log' -f $i)),
                        (Join-Path $replayRootFull ('PHASE0_PRECHECK_{0:D2}.stdout.log' -f $i))
                    ) `
                    -Reason ("stale no-progress/blocker slice invalidated before resume; current forced family={0}; old status={1}" -f $currentForced.family_id, $existingSliceResult.slice_status) `
                    -RunnerContractPath $runnerContractPath
                $hasExistingResult = $false
                $hasExistingVerify = $false
            }
        } catch {
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} stale blocker resume check skipped | resume_safety | stale_blocker_replay | non_authorizing_evidence | error={1}. |" -f $i, ($_.Exception.Message -replace '\|', '/'))
        }
    }
    if ($hasExistingResult -and $hasExistingVerify) {
        Write-Host "Reusing existing Phase 1 $sliceId result; regenerating authoritative verification."
        Invoke-EvidenceCaptureRepair -SliceResultPath $sliceResult -SliceLogDir $sliceLogDir -ReplayRoot $replayRootFull
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SliceVerifier.ps1') -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResult $sliceResult -SliceIndex $i | Out-Null
        $v348Gate = Invoke-V348SliceQualityGates -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$v348Gate.CanProceed) {
            Write-Host "v348 slice quality gate failed for slice ${i}: $($v348Gate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "v348_slice_quality_gate: $($v348Gate.Blocker)"
            break
        }
        # v431: Layer validation gate (pre-flight check)
        $layerGate = Invoke-LayerValidationGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$layerGate.CanProceed) {
            Write-Host "Layer validation gate failed for slice ${i}: $($layerGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "layer_validation: $($layerGate.Blocker)"
            break
        }
        # v454: Economy checkpoint - CP2_LAYER_VALIDATION (after layer validation)
        $discoveryMode = ($i -eq 1)  # Discovery mode only for S1
        $layerCheckpoint = Invoke-EconomyCheckpointGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath -CheckpointId 'CP2_LAYER_VALIDATION' -DiscoveryMode $discoveryMode
        if (-not [bool]$layerCheckpoint.CanProceed) {
            Write-Host "Layer validation checkpoint failed for slice ${i}: $($layerCheckpoint.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "layer_checkpoint: $($layerCheckpoint.Blocker)"
            break
        }
        # v379: Test charter pre-validation gate
        $testCharterGate = Invoke-TestCharterPrevalidatorGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$testCharterGate.CanProceed) {
            Write-Host "Test charter prevalidation gate failed for slice ${i}: $($testCharterGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "test_charter_prevalidation: $($testCharterGate.Blocker)"
            break
        }
        # v454: Economy checkpoint - CP4_TEST_CHARTER (after test charter)
        $testCharterCheckpoint = Invoke-EconomyCheckpointGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath -CheckpointId 'CP4_TEST_CHARTER' -DiscoveryMode $discoveryMode
        if (-not [bool]$testCharterCheckpoint.CanProceed) {
            Write-Host "Test charter checkpoint failed for slice ${i}: $($testCharterCheckpoint.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "test_charter_checkpoint: $($testCharterCheckpoint.Blocker)"
            break
        }
        # v431: Phase0 precheck gate (test framework validation)
        $phase0Precheck = Invoke-Phase0PrecheckGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath -MavenSettings $MavenSettings
        if (-not [bool]$phase0Precheck.CanProceed) {
            Write-Host "Phase0 precheck gate failed for slice ${i}: $($phase0Precheck.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "phase0_precheck: $($phase0Precheck.Blocker)"
            break
        }
        # v378: Pre-implementation contract verification gate
        $contractGate = Invoke-ContractVerificationGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$contractGate.CanProceed) {
            Write-Host "Contract verification gate failed for slice ${i}: $($contractGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "contract_verification: $($contractGate.Blocker)"
            break
        }
        # v454: Economy checkpoint - CP5_IMPLEMENTATION (before RED phase)
        $implementationCheckpoint = Invoke-EconomyCheckpointGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath -CheckpointId 'CP5_IMPLEMENTATION' -DiscoveryMode $false
        if (-not [bool]$implementationCheckpoint.CanProceed) {
            Write-Host "Implementation checkpoint failed for slice ${i}: $($implementationCheckpoint.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "implementation_checkpoint: $($implementationCheckpoint.Blocker)"
            break
        }
        $redGate = Invoke-RedPhaseHardGate -ReplayRoot $replayRootFull -SliceResultPath $sliceResult -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$redGate.CanProceed) {
            Write-Host "RED phase hard gate failed for slice ${i}: $($redGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "red_phase_hard_gate: $($redGate.Blocker)"
            break
        }
        # v378: RED phase incremental verification
        $redIncrementalGate = Invoke-IncrementalVerificationGate -Phase 'RED' -ReplayRoot $replayRootFull -SliceResultPath $sliceResult -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$redIncrementalGate.CanProceed) {
            Write-Host "RED incremental verification gate failed for slice ${i}: $($redIncrementalGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "red_incremental_verification: $($redIncrementalGate.Blocker)"
            break
        }
        $greenGate = Invoke-GreenPhaseNoMockGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -RunnerContractPath $runnerContractPath
        Move-ReplayScratchArtifacts -ReplayRoot $replayRootFull
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i
        $verify = Read-JsonObject -Path $sliceVerify
        # v431: Side effect ledger gate (verify after GREEN phase)
        $sideEffectGate = Invoke-SideEffectLedgerGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$sideEffectGate.CanProceed) {
            Write-Host "Side effect ledger gate failed for slice ${i}: $($sideEffectGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "side_effect_ledger: $($sideEffectGate.Blocker)"
            break
        }
        # v378: TODO detector gate after GREEN phase
        $todoGate = Invoke-TodoDetectorGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$todoGate.CanProceed) {
            Write-Host "TODO detector gate failed for slice ${i}: $($todoGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "todo_detector: $($todoGate.Blocker)"
            break
        }
        if (-not [bool]$greenGate.CanProceed) {
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "green_phase_no_mock_gate: $($greenGate.Blocker)"
            break
        }
        Update-FamilyLedgerFromSlice -Path $familyLedgerPath -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -MaxSlices $MaxSlices
        $verify = Read-JsonObject -Path $sliceVerify
        if ($null -ne $verify.authorized_for_next_slice -and -not [bool]$verify.authorized_for_next_slice) {
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} reuse replay authorization stop | existing_artifact_replay | existing_artifact_replay | non_authorizing_evidence | authorized_for_next_slice=false; downstream existing slice artifacts are ignored until S{0} is fixed. blockers={1}. |" -f $i, ((Get-StringArray $verify.authorization_blockers) -join ','))
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "non_authorizing_existing_artifact_replay: $(((Get-StringArray $verify.authorization_blockers) -join ','))"
            break
        }
        if (-not [bool]$verify.should_continue) {
            $nextExistingResult = Join-Path $replayRootFull ('SLICE_RESULT_{0:D2}.json' -f ($i + 1))
            if (Test-Path -LiteralPath $nextExistingResult) {
                Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} reuse replay stop | existing_artifact_replay | existing_artifact_replay | verifier_stop | should_continue=false; S{1} existing artifact is ignored until S{0} passes verification. |" -f $i, ($i + 1))
                Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "verifier_stop_existing_artifact_replay"
            }
            break
        }
        continue
    }

    $ledger = Get-FamilyLedger -Path $familyLedgerPath
    $rankMap = New-CarrierRankMap -Ledger $ledger -SliceIndex $i
    $rankMap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $carrierRank -Encoding UTF8
    $rankMap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRootFull 'CARRIER_RANK.json') -Encoding UTF8
    $forced = Resolve-ForcedFamilyDecisionForSlice `
        -Ledger $ledger `
        -SliceIndex $i `
        -CarrierRank $rankMap `
        -SourceChainContractPath $sourceChainContractPath `
        -RunnerContractPath $runnerContractPath
    Add-RunnerEnforcementContract -Path $runnerContractPath -SliceIndex $i -ForcedDecision $forced

    $capDisplayArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Write-PreSliceCapDisplay.ps1'),
        '-ReplayRoot', $replayRootFull,
        '-RequirementFamilyLedger', $familyLedgerPath,
        '-SliceIndex', $i
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$forced.family_id)) {
        $capDisplayArgs += @('-ForcedRequirementFamily', ([string]$forced.family_id))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$forced.slice_type)) {
        $capDisplayArgs += @('-ForcedSliceType', ([string]$forced.slice_type))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$forced.target_sibling_surface)) {
        $capDisplayArgs += @('-ForcedSiblingSurface', ([string]$forced.target_sibling_surface))
    }
    & powershell @capDisplayArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "pre-slice cap display generation failed"
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} pre-slice cap display blocked | {1} | {2} | pre_slice_cap_display_failed | Write-PreSliceCapDisplay exit_code={3}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE)
        $blockedBeforeExecutor = $true
        $hasExistingResult = $true
    }

    $prepareArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1'),
        '-ReplayRoot', $replayRootFull,
        '-Worktree', $worktreeFull,
        '-RequirementFamilyLedger', $familyLedgerPath,
        '-SliceIndex', $i
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$forced.family_id)) {
        $prepareArgs += @('-ForcedRequirementFamily', ([string]$forced.family_id))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$forced.slice_type)) {
        $prepareArgs += @('-ForcedSliceType', ([string]$forced.slice_type))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$forced.target_sibling_surface)) {
        $prepareArgs += @('-ForcedSiblingSurface', ([string]$forced.target_sibling_surface))
    }
    if (-not [string]::IsNullOrWhiteSpace($surfaceCarrierScanPath)) {
        $prepareArgs += @('-SurfaceCarrierScan', $surfaceCarrierScanPath)
    }
    & powershell @prepareArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "slice evidence contract preparation failed"
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} evidence contract prep blocked | {1} | {2} | contract_preparation_failed | Prepare-SliceEvidenceContracts exit_code={3}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE)
        $blockedBeforeExecutor = $true
        $hasExistingResult = $true
    } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-NextSliceExactContract.ps1') -ReplayRoot $replayRootFull -SliceIndex $i -MaxRows 5 -FailOnBroadRows | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "next-slice exact contract subset preparation failed"
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} exact contract subset prep blocked | {1} | {2} | exact_contract_subset_failed | Build-NextSliceExactContract exit_code={3}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE)
            $blockedBeforeExecutor = $true
            $hasExistingResult = $true
        }
    }
    if (-not $blockedBeforeExecutor -and (Test-Path -LiteralPath $carrierAuthorization)) {
        $carrierGate = Read-JsonObject -Path $carrierAuthorization
        if ([string]$carrierGate.authorization -ne 'ALLOW') {
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode 0 -Reason "carrier authorization stopped before implementation: $(((Get-StringArray $carrierGate.issues) -join ','))"
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} carrier authorization stop | {1} | {2} | carrier_authorization_stop | issues={3}. |" -f $i, $forced.family_id, $forced.slice_type, ((Get-StringArray $carrierGate.issues) -join ','))
            $blockedBeforeExecutor = $true
            $hasExistingResult = $true
        }
    }
    if (-not $blockedBeforeExecutor) {
        $preAuthArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1'),
            '-ReplayRoot', $replayRootFull,
            '-SliceIndex', $i
        )
        if (-not [string]::IsNullOrWhiteSpace([string]$forced.family_id)) {
            $preAuthArgs += @('-ForcedRequirementFamily', ([string]$forced.family_id))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$forced.slice_type)) {
            $preAuthArgs += @('-ForcedSliceType', ([string]$forced.slice_type))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$forced.target_sibling_surface)) {
            $preAuthArgs += @('-ForcedSiblingSurface', ([string]$forced.target_sibling_surface))
        }
        & powershell @preAuthArgs | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "pre-slice authorization failed"
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} pre-slice authorization failed | {1} | {2} | pre_slice_authorization_error | exit_code={3}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE)
            $blockedBeforeExecutor = $true
            $hasExistingResult = $true
        } elseif (Test-Path -LiteralPath $preSliceAuthorization) {
            $preGate = Read-JsonObject -Path $preSliceAuthorization
            if ([string]$preGate.decision -ne 'ALLOW') {
                Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode 0 -Reason "pre-slice authorization stopped before implementation: $(((Get-StringArray $preGate.issues) -join ','))"
                Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} pre-slice authorization stop | {1} | {2} | pre_slice_authorization_stop | issues={3}. |" -f $i, $forced.family_id, $forced.slice_type, ((Get-StringArray $preGate.issues) -join ','))
                $blockedBeforeExecutor = $true
                $hasExistingResult = $true
            }
        }
    }

    if (-not $blockedBeforeExecutor) {
        $preSliceToolGatePath = Join-Path $replayRootFull 'PRE_SLICE_TOOL_AVAILABILITY.json'
        $preSliceToolGateStdoutPath = Join-Path $replayRootFull ('PRE_SLICE_TOOL_AVAILABILITY_{0:D2}.stdout.log' -f $i)
        $preSliceToolGateStderrPath = Join-Path $replayRootFull ('PRE_SLICE_TOOL_AVAILABILITY_{0:D2}.stderr.log' -f $i)
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-PreSliceToolAvailabilityGate.ps1') `
            -ReplayRoot $replayRootFull `
            -Worktree $worktreeFull > $preSliceToolGateStdoutPath 2> $preSliceToolGateStderrPath
        $preSliceToolGateExitCode = $LASTEXITCODE
        $preSliceToolGateStatus = ''
        $preSliceToolGateBlocker = ''
        if (Test-Path -LiteralPath $preSliceToolGatePath) {
            try {
                $preSliceToolGate = Read-JsonObject -Path $preSliceToolGatePath
                $preSliceToolGateStatus = [string]$preSliceToolGate.status
                $missingToolScripts = @(Get-StringArray $preSliceToolGate.missing_scripts)
                $unrunnableToolScripts = @(Get-StringArray $preSliceToolGate.unrunnable_scripts)
                $preSliceToolGateBlocker = (@(
                    $(if ($missingToolScripts.Count -gt 0) { 'missing_scripts=' + ($missingToolScripts -join ',') } else { $null }),
                    $(if ($unrunnableToolScripts.Count -gt 0) { 'unrunnable_scripts=' + ($unrunnableToolScripts -join ',') } else { $null })
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '; '
            } catch {
                $preSliceToolGateStatus = 'UNREADABLE'
                $preSliceToolGateBlocker = 'pre_slice_tool_availability_unreadable'
            }
        } else {
            $preSliceToolGateStatus = 'MISSING'
            $preSliceToolGateBlocker = 'pre_slice_tool_availability_missing'
        }
        if ($preSliceToolGateStatus -ne 'PASS') {
            if ([string]::IsNullOrWhiteSpace($preSliceToolGateBlocker)) {
                $preSliceToolGateBlocker = "status=$preSliceToolGateStatus"
            }
            $preSliceToolReason = "pre-slice tool availability gate blocked before executor: $preSliceToolGateBlocker"
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $preSliceToolGateExitCode -Reason $preSliceToolReason -ExecutorDiagnostic "availability=$preSliceToolGatePath; stdout=$preSliceToolGateStdoutPath; stderr=$preSliceToolGateStderrPath"
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} pre-slice tool availability stop | {1} | {2} | tooling_preflight_blocker | PRE_SLICE_TOOL_AVAILABILITY status={3}; exit_code={4}; blocker={5}; result={6}; stdout={7}; stderr={8}. |" -f $i, $forced.family_id, $forced.slice_type, $preSliceToolGateStatus, $preSliceToolGateExitCode, $preSliceToolGateBlocker, $preSliceToolGatePath, $preSliceToolGateStdoutPath, $preSliceToolGateStderrPath)
            $blockedBeforeExecutor = $true
            $hasExistingResult = $true
        } else {
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} pre-slice tool availability pass | {1} | {2} | executable_evidence | PRE_SLICE_TOOL_AVAILABILITY status=PASS; exit_code={3}; result={4}; stdout={5}; stderr={6}. |" -f $i, $forced.family_id, $forced.slice_type, $preSliceToolGateExitCode, $preSliceToolGatePath, $preSliceToolGateStdoutPath, $preSliceToolGateStderrPath)
        }
    }

    if (-not $blockedBeforeExecutor) {
        $callableCarrierGate = Invoke-CallableCarrierAuthorizationGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$callableCarrierGate.CanProceed) {
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode 0 -Reason "callable carrier authorization stopped before implementation: $($callableCarrierGate.Blocker)"
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} callable-carrier authorization pre-executor stop | {1} | {2} | callable_carrier_authorization_failed | blocker={3}; result={4}. |" -f $i, $forced.family_id, $forced.slice_type, $callableCarrierGate.Blocker, $callableCarrierGate.ResultPath)
            $blockedBeforeExecutor = $true
            $hasExistingResult = $true
        }
    }

    if (-not $blockedBeforeExecutor) {
        $preSliceExperimentArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $PSScriptRoot 'Invoke-PreSliceExperimentContracts.ps1'),
            '-ReplayRoot', $replayRootFull,
            '-Worktree', $worktreeFull,
            '-SliceIndex', $i,
            '-MavenSettings', $MavenSettings
        )
        if (-not [string]::IsNullOrWhiteSpace([string]$forced.family_id)) {
            $preSliceExperimentArgs += @('-ForcedRequirementFamily', ([string]$forced.family_id))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$forced.slice_type)) {
            $preSliceExperimentArgs += @('-ForcedSliceType', ([string]$forced.slice_type))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$forced.target_sibling_surface)) {
            $preSliceExperimentArgs += @('-ForcedSiblingSurface', ([string]$forced.target_sibling_surface))
        }
        & powershell @preSliceExperimentArgs | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $preSliceBlockerPath = Join-Path $replayRootFull ('SLICE_RESULT_PRE_{0:D2}.json' -f $i)
            if (Test-Path -LiteralPath $preSliceBlockerPath) {
                Copy-Item -LiteralPath $preSliceBlockerPath -Destination $sliceResult -Force
            } else {
                Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "pre-slice experiment contract stopped before executor"
            }
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} pre-slice experiment contract stop | {1} | {2} | tooling_enforcement_stop | Invoke-PreSliceExperimentContracts exit_code={3}; dry_run={4}; runnable={5}; callable={6}; carrier_resolve={7}; plan_contract={8}; test_charter={9}; charter={10}; contract={11}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE, (Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_DRY_RUN_{0:D2}.json' -f $i)), (Join-Path $replayRootFull ('RUNNABLE_SLICE_AUTHORIZATION_{0:D2}.json' -f $i)), (Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $i)), (Join-Path $replayRootFull 'carrier_resolve.json'), (Join-Path $replayRootFull 'PLAN_CONTRACT.json'), (Join-Path $replayRootFull 'TEST_CHARTER.json'), (Join-Path $replayRootFull ('TEST_CHARTER_{0:D2}.json' -f $i)), (Join-Path $replayRootFull 'FIRST_SLICE_EXECUTABLE_CONTRACT.json'))
            $blockedBeforeExecutor = $true
            $hasExistingResult = $true
        } else {
            $sliceExecutionContractPath = Join-Path $replayRootFull ('SLICE_EXECUTION_CONTRACT_{0:D2}.json' -f $i)
            $baselineCarrierIndexPath = Join-Path $replayRootFull 'replay-context-index\baseline-carriers.json'
            if (-not (Test-Path -LiteralPath $baselineCarrierIndexPath -PathType Leaf)) {
                $baselineCarrierIndexPath = Join-Path $replayRootFull 'replay-context-index.json'
            }
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify_first_slice_runnable_contract.ps1') `
                -Contract $sliceExecutionContractPath `
                -ReplayRoot $replayRootFull | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "first-slice runnable contract verification stopped before executor"
                Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} first-slice runnable contract stop | {1} | {2} | first_slice_runnable_contract | exit_code={3}; contract={4}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE, $sliceExecutionContractPath)
                $blockedBeforeExecutor = $true
                $hasExistingResult = $true
            }
            if (-not $blockedBeforeExecutor) {
                & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate-first-slice-executable-contract.ps1') `
                    -ReplayRoot $replayRootFull `
                    -Worktree $worktreeFull `
                    -Slice $i `
                    -MavenSettings $MavenSettings | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "first-slice executable contract validation stopped before executor"
                    Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} first-slice executable contract validation stop | {1} | {2} | first_slice_executable_contract_validation | exit_code={3}; script=validate-first-slice-executable-contract.ps1; result={4}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE, (Join-Path $replayRootFull ('FIRST_SLICE_CONTRACT_VALIDATE_{0:D2}.json' -f $i)))
                    $blockedBeforeExecutor = $true
                    $hasExistingResult = $true
                }
            }
            if (-not $blockedBeforeExecutor) {
                & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify_carrier_invocation_contract.ps1') `
                    -Contract $sliceExecutionContractPath `
                    -CarrierIndex $baselineCarrierIndexPath `
                    -OutputPath (Join-Path $replayRootFull ('CARRIER_INVOCATION_CONTRACT_{0:D2}.json' -f $i)) | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "carrier invocation contract verification stopped before executor"
                    Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} carrier invocation contract stop | {1} | {2} | carrier_invocation_contract | exit_code={3}; contract={4}. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE, (Join-Path $replayRootFull ('CARRIER_INVOCATION_CONTRACT_{0:D2}.json' -f $i)))
                    $blockedBeforeExecutor = $true
                    $hasExistingResult = $true
                }
            }
        }
    }

    if (-not $blockedBeforeExecutor) {
        $preImplementationCharterGate = Invoke-TestCharterPrevalidatorGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if ((-not [bool]$preImplementationCharterGate.CanProceed) -and [bool]$preImplementationCharterGate.RepairableCharterFailure) {
            Write-Host "Test charter prevalidation failed before executor for slice ${i}. Starting test charter repair pass."
            $preImplementationCharterGate = Invoke-TestCharterRepairGate `
                -ReplayRoot $replayRootFull `
                -Worktree $worktreeFull `
                -SliceIndex $i `
                -RunnerContractPath $runnerContractPath `
                -ForcedDecision $forced `
                -FailedGate $preImplementationCharterGate `
                -Executor $Executor `
                -Sandbox $Sandbox `
                -Approval $Approval `
                -TimeoutMinutes $sliceTimeoutMinutes `
                -Model $Model `
                -ReasoningEffort $ReasoningEffort
        } elseif (-not [bool]$preImplementationCharterGate.CanProceed) {
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} test charter repair skipped | {1} | {2} | non_repairable_charter_failure | result={3}; repairable_charter_failure=false. |" -f $i, $forced.family_id, $forced.slice_type, $preImplementationCharterGate.ResultPath)
        }
        if (-not [bool]$preImplementationCharterGate.CanProceed) {
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode 0 -Reason "pre-implementation test charter gate stopped before executor: $($preImplementationCharterGate.Blocker)"
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} pre-implementation test charter stop | {1} | {2} | test_charter_missing_before_implementation | result={3}. |" -f $i, $forced.family_id, $forced.slice_type, $preImplementationCharterGate.ResultPath)
            $blockedBeforeExecutor = $true
            $hasExistingResult = $true
        }
    }

    $values = @{
        PROJECT_ROOT = $projectRootFull
        FEATURE_NAME = $FeatureName
        REQUIREMENT_SOURCE = $requirementSourceFull
        ORACLE_BRANCH = $OracleBranch
        ORACLE_COMMIT = $OracleCommit
        BASE_COMMIT = $BaseCommit
        REPLAY_ROOT = $replayRootFull
        REPLAY_AUTOPILOT_SCRIPTS = $PSScriptRoot
        WORKTREE = $worktreeFull
        BASELINE_INDEX = $baselineIndexFull
        CONTEXT_MANIFEST = $contextManifestFull
        SURFACE_CARRIER_SCAN = $surfaceCarrierScanPath
        FEATURE_CLASSIFICATION = $featureClassificationPath
        SYSTEM_CONTEXT_DIR = $systemContextDirFull
        MAVEN_SETTINGS_ARG = Get-MavenSettingsCommandSegment -MavenSettings $MavenSettings
        RUN_LABEL = $RunLabel
        ROUND_ID = $RoundId
        SLICE_INDEX = $i
        MAX_SLICES = $MaxSlices
        SLICE_RESULT = $sliceResult
        SLICE_VERIFY = $sliceVerify
        CARRIER_AUTHORIZATION = $carrierAuthorization
        CARRIER_RANK = $carrierRank
        EXACT_CONTRACT_ASSERTION_MATRIX = $exactContractMatrix
        NEXT_SLICE_EXACT_CONTRACT = $nextSliceExactContract
        SIDE_EFFECT_EVIDENCE = $sideEffectEvidence
        PRE_SLICE_CAP_DISPLAY = $preSliceCapDisplay
        RUNNABLE_SLICE_AUTHORIZATION = Join-Path $replayRootFull ('RUNNABLE_SLICE_AUTHORIZATION_{0:D2}.json' -f $i)
        CALLABLE_CARRIER_AUTHORIZATION = Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $i)
        TEST_CHARTER_CONTRACT = Join-Path $replayRootFull ('TEST_CHARTER_{0:D2}.json' -f $i)
        SLICE_PROGRESS = $progressPath
        SLICE_PROGRESS_MD = $progressMdPath
        REQUIREMENT_FAMILY_LEDGER = $familyLedgerPath
        FORCED_REQUIREMENT_FAMILY = $forced.family_id
        FORCED_SLICE_TYPE = $forced.slice_type
        FORCED_SIBLING_SURFACE = [string]$forced.target_sibling_surface
        OPEN_FAMILY_BACKPRESSURE = $forced.reason
        OPEN_REQUIREMENT_FAMILIES = $forced.open_families
    }

    $sliceTimeoutMinutes = [Math]::Min($TimeoutMinutes, 45)
    if (@('generated_artifact_template_upload', 'external_integration', 'lifecycle_cleanup_retention') -contains [string]$forced.family_id) {
        $sliceTimeoutMinutes = [Math]::Min($sliceTimeoutMinutes, 25)
    }

    if (-not $hasExistingResult -and -not $blockedBeforeExecutor) {
        $expanded = Expand-Template -Template $sliceTemplate -Values $values
        Set-Content -LiteralPath $slicePrompt -Value $expanded -Encoding UTF8

        $agentArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
            '-PromptPath', $slicePrompt,
            '-WorkDir', $worktreeFull,
            '-LogDir', $sliceLogDir,
            '-Executor', $Executor,
            '-Sandbox', $Sandbox,
            '-Approval', $Approval,
            '-TimeoutMinutes', $sliceTimeoutMinutes,
            '-CompletionPath', $sliceResult,
            '-CompletionQuietSeconds', 90,
            '-Name', ('phase1-{0}' -f $sliceId)
        )
        if (-not [string]::IsNullOrWhiteSpace($Model)) { $agentArgs += @('-Model', $Model) }
        if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) { $agentArgs += @('-ReasoningEffort', $ReasoningEffort) }

        $smokeArgs = @($agentArgs + @('-ValidateOnly'))
        & powershell @smokeArgs | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $LASTEXITCODE -Reason "runner invocation smoke failed before starting executor"
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} runner invocation smoke blocked | {1} | {2} | runner_invocation_error | validate-only exit_code={3}; implementation executor was not started. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE)
        } else {
            $executorExitCode = Invoke-SliceExecutorWithRetry -AgentArgs $agentArgs -SliceLogDir $sliceLogDir -SliceId $sliceId -MaxRetries 2 -DelaySeconds 60
            if ($executorExitCode -ne 0) {
                $executorExitCode = Convert-ToExecutorExitCode $executorExitCode
                if (Test-Path -LiteralPath $sliceResult) {
                    Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} executor nonzero with result | {1} | {2} | executor_failed_but_result_present | exit_code={3}; preserving agent-authored slice result for verification. |" -f $i, $forced.family_id, $forced.slice_type, $executorExitCode)
                } else {
                    Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} executor retry pending | {1} | {2} | executor_failed_without_result | exit_code={3}; no blocked result generated yet so retry can narrow and continue. |" -f $i, $forced.family_id, $forced.slice_type, $executorExitCode)
                }
            }
        }
    } elseif ($blockedBeforeExecutor) {
        Write-Host "Phase 1 $sliceId blocked before executor: $sliceResult"
    } else {
        Write-Host "Reusing existing Phase 1 $sliceId result; verification is missing and will be regenerated."
    }

    [void](Copy-SliceResultFromWorktree -Worktree $worktreeFull -Destination $sliceResult -SliceIndex $i)
    if (-not (Test-Path -LiteralPath $sliceResult) -and -not $hasExistingResult -and -not $blockedBeforeExecutor) {
        $resourceBlocker = Get-PermanentExecutorResourceBlocker -LogDir $sliceLogDir
        if ([bool]$resourceBlocker.IsResourceBlocker) {
            $retryExitCode = $executorExitCode
            $blockedReason = "permanent executor resource blocker: $($resourceBlocker.Category)"
            Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $executorExitCode -Reason $blockedReason -FailureCategory ([string]$resourceBlocker.Category) -ExecutorDiagnostic ([string]$resourceBlocker.Diagnostic)
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} executor resource blocked | {1} | {2} | {3} | exit_code={4}; no retry prompt generated because this requires external executor remediation. |" -f $i, $forced.family_id, $forced.slice_type, $resourceBlocker.Category, $executorExitCode)
        } else {
            $retryPrompt = Join-Path $replayRootFull ('PHASE1_SLICE_{0:D2}_RETRY_PROMPT.md' -f $i)
            $retryLogDir = Join-Path $logsRoot ('{0}-retry' -f $sliceId)
            $lastMessagePath = Join-Path $sliceLogDir ('phase1-{0}.last-message.md' -f $sliceId)
            $lastMessage = Read-TextIfExists -Path $lastMessagePath
            $partialBeforeRetry = Write-PartialWorktreeDiffAudit -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -Stage 'before_retry' -SliceLogDir $sliceLogDir -ExitCode $executorExitCode
            $guardGuidance = Get-CommandGuardRetryGuidance -LogDir $sliceLogDir
            $defaultMavenGuardSection = Get-DefaultMavenCommandGuardGuidance
            $guardSection = ''
            if ([bool]$guardGuidance.HasCommandGuardViolation) {
                $guardSection = @(
                    'Previous command-guard failure:',
                    "- reasons: $($guardGuidance.ReasonText)",
                    '',
                    'Observed forbidden command samples:',
                    '```text',
                    $guardGuidance.SampleText,
                    '```',
                    '',
                    'Mandatory retry corrections:',
                    $guardGuidance.GuidanceText,
                    '',
                    'This retry must not repeat a command that matches any reason above. If the only available command would violate the guard, write BLOCKED SLICE_RESULT JSON with command_guard_blocker instead of running it.',
                    ''
                ) -join "`n"
            }
            $partialDiffSection = ''
            if ($null -ne $partialBeforeRetry -and [bool]$partialBeforeRetry.HasDiff) {
                $partialDiffSection = @(
                    'Partial worktree diff detected before retry:',
                    "- audit_json: $($partialBeforeRetry.JsonPath)",
                    "- audit_md: $($partialBeforeRetry.MdPath)",
                    '- changed_files:',
                    (($partialBeforeRetry.ChangedFiles | ForEach-Object { "  - $_" }) -join "`n"),
                    '',
                    'Mandatory partial-diff recovery:',
                    '- Either complete these partial changes into a valid RED/GREEN slice and write the required SLICE_RESULT JSON, or write BLOCKED SLICE_RESULT JSON that cites the partial diff audit.',
                    '- Do not leave modified or untracked worktree files invisible to the slice result.',
                    ''
                ) -join "`n"
            }
            $retryPreamble = @(
                'RECOVERY MODE: the previous slice executor exited without writing the required SLICE_RESULT JSON.',
                '',
                'Do not ask the user for confirmation. In this automated replay, dirty or untracked files inside the isolated worktree are expected from earlier slices and are authorized context.',
                'Continue from the current isolated worktree, execute or classify this one slice, and always write the required JSON to the exact slice result path.',
                'Narrow the slice before retrying: choose the smallest deployable carrier for the forced family, close one concrete surface with RED/GREEN evidence, and leave sibling surfaces as explicit remaining gaps.',
                'If you cannot safely continue, write a BLOCKED SLICE_RESULT JSON with the concrete blocker instead of ending with a question.',
                '',
                $defaultMavenGuardSection,
                $guardSection,
                $partialDiffSection,
                'Previous last message excerpt:',
                '```text',
                ($lastMessage.Substring(0, [Math]::Min($lastMessage.Length, 2000))),
                '```',
                '',
                'Original slice prompt follows.',
                ''
            ) -join "`n"
            Set-Content -LiteralPath $retryPrompt -Encoding UTF8 -Value ($retryPreamble + "`n" + (Get-Content -LiteralPath $slicePrompt -Raw -Encoding UTF8))
            $retryReason = if ([bool]$guardGuidance.HasCommandGuardViolation) {
                "first attempt hit command guard reasons=$($guardGuidance.ReasonText); retry prompt includes mandatory command corrections."
            } else {
                'first attempt wrote no result; retrying once with non-interactive dirty-worktree authorization.'
            }
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} executor retry | {1} | {2} | missing_slice_result_retry | {3} |" -f $i, $forced.family_id, $forced.slice_type, ($retryReason -replace '\|', '/'))

            $retryAgentArgs = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
                '-PromptPath', $retryPrompt,
                '-WorkDir', $worktreeFull,
                '-LogDir', $retryLogDir,
                '-Executor', $Executor,
                '-Sandbox', $Sandbox,
                '-Approval', $Approval,
                '-TimeoutMinutes', $sliceTimeoutMinutes,
                '-CompletionPath', $sliceResult,
                '-CompletionQuietSeconds', 90,
                '-Name', ('phase1-{0}-retry' -f $sliceId)
            )
            if (-not [string]::IsNullOrWhiteSpace($Model)) { $retryAgentArgs += @('-Model', $Model) }
            if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) { $retryAgentArgs += @('-ReasoningEffort', $ReasoningEffort) }
            $retryExitCode = 0
            $retrySmokeArgs = @($retryAgentArgs + @('-ValidateOnly'))
            & powershell @retrySmokeArgs | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $retryExitCode = $LASTEXITCODE
                Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $retryLogDir -ExitCode $LASTEXITCODE -Reason "runner retry invocation smoke failed before starting executor"
                Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} retry runner invocation smoke blocked | {1} | {2} | runner_invocation_error | validate-only exit_code={3}; retry executor was not started. |" -f $i, $forced.family_id, $forced.slice_type, $LASTEXITCODE)
            } else {
                $retryExitCode = Invoke-SliceExecutorWithRetry -AgentArgs $retryAgentArgs -SliceLogDir $retryLogDir -SliceId "$sliceId-retry" -MaxRetries 1 -DelaySeconds 60
                $retryExitCode = Convert-ToExecutorExitCode $retryExitCode
                if ($retryExitCode -ne 0) {
                    Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} retry executor failed | {1} | {2} | executor_failed_without_result | retry exit_code={3}; preserving actual retry failure code for synthesis/evolution. |" -f $i, $forced.family_id, $forced.slice_type, $retryExitCode)
                }
            }
            [void](Copy-SliceResultFromWorktree -Worktree $worktreeFull -Destination $sliceResult -SliceIndex $i)
        }
    }
    if (-not (Test-Path -LiteralPath $sliceResult)) {
        $finalExecutorExitCode = 0
        if ($null -ne $retryExitCode) {
            $finalExecutorExitCode = Convert-ToExecutorExitCode $retryExitCode
        } elseif ($null -ne $executorExitCode) {
            $finalExecutorExitCode = Convert-ToExecutorExitCode $executorExitCode
        }
        $partialAfterRetry = Write-PartialWorktreeDiffAudit -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -Stage 'after_retry' -SliceLogDir $sliceLogDir -ExitCode $finalExecutorExitCode
        Write-ExecutorBlockedSliceResult -Path $sliceResult -SliceIndex $i -ForcedDecision $forced -SliceLogDir $sliceLogDir -ExitCode $finalExecutorExitCode -Reason "executor completed without writing required SLICE_RESULT after retry" -PartialDiffAudit $partialAfterRetry
        $partialText = if ($null -ne $partialAfterRetry -and [bool]$partialAfterRetry.HasDiff) { "partial_diff=$($partialAfterRetry.JsonPath)" } else { 'partial_diff=none' }
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} executor blocked | {1} | {2} | missing_slice_result_after_retry | exit_code={3}; {4}; blocked slice result generated for synthesis/evolution. |" -f $i, $forced.family_id, $forced.slice_type, $finalExecutorExitCode, ($partialText -replace '\|', '/'))
    }

    Invoke-EvidenceCaptureRepair -SliceResultPath $sliceResult -SliceLogDir $sliceLogDir -ReplayRoot $replayRootFull

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SliceVerifier.ps1') -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResult $sliceResult -SliceIndex $i | Out-Null
    $v348Gate = Invoke-V348SliceQualityGates -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$v348Gate.CanProceed) {
        Write-Host "v348 slice quality gate failed for slice ${i}: $($v348Gate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "v348_slice_quality_gate: $($v348Gate.Blocker)"
        break
    }
    if ($blockedBeforeExecutor) {
        $blockedVerify = if (Test-Path -LiteralPath $sliceVerify) { Read-JsonObject -Path $sliceVerify } else { $null }
        $blockedReasons = @()
        if ($null -ne $blockedVerify) {
            $blockedReasons = @(
                @(Get-StringArray $blockedVerify.authorization_blockers) +
                @(Get-StringArray $blockedVerify.gap_flags) +
                @(Get-StringArray $blockedVerify.warnings)
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
        }
        if ($blockedReasons.Count -eq 0) {
            $blockedReasons = @('blocked_before_executor')
        }
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} blocked-before-executor synthesis stop | {1} | {2} | local_gate_blocked_before_executor | reasons={3}; slice_result={4}. |" -f $i, $forced.family_id, $forced.slice_type, (($blockedReasons -join ',') -replace '\|', '/'), $sliceResult)
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "blocked_before_executor: $($blockedReasons -join ',')"
        break
    }
    # v431: Layer validation gate (pre-flight check)
    $layerGate = Invoke-LayerValidationGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$layerGate.CanProceed) {
        Write-Host "Layer validation gate failed for slice ${i}: $($layerGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "layer_validation: $($layerGate.Blocker)"
        break
    }
    # v431: Phase0 precheck gate (test framework validation)
    $phase0Precheck = Invoke-Phase0PrecheckGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath -MavenSettings $MavenSettings
    if (-not [bool]$phase0Precheck.CanProceed) {
        Write-Host "Phase0 precheck gate failed for slice ${i}: $($phase0Precheck.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "phase0_precheck: $($phase0Precheck.Blocker)"
        break
    }
    # v378: Pre-implementation contract verification gate
    $contractGate = Invoke-ContractVerificationGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$contractGate.CanProceed) {
        Write-Host "Contract verification gate failed for slice ${i}: $($contractGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "contract_verification: $($contractGate.Blocker)"
        break
    }
    $redGate = Invoke-RedPhaseHardGate -ReplayRoot $replayRootFull -SliceResultPath $sliceResult -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$redGate.CanProceed) {
        Write-Host "RED phase hard gate failed for slice ${i}: $($redGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "red_phase_hard_gate: $($redGate.Blocker)"
        break
    }
    # v378: RED phase incremental verification
    $redIncrementalGate = Invoke-IncrementalVerificationGate -Phase 'RED' -ReplayRoot $replayRootFull -SliceResultPath $sliceResult -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$redIncrementalGate.CanProceed) {
        Write-Host "RED incremental verification gate failed for slice ${i}: $($redIncrementalGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "red_incremental_verification: $($redIncrementalGate.Blocker)"
        break
    }
    $greenGate = Invoke-GreenPhaseNoMockGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -RunnerContractPath $runnerContractPath
    Move-ReplayScratchArtifacts -ReplayRoot $replayRootFull
    Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i
    # v431: Side effect ledger gate (verify after GREEN phase)
    $sideEffectGate = Invoke-SideEffectLedgerGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$sideEffectGate.CanProceed) {
        Write-Host "Side effect ledger gate failed for slice ${i}: $($sideEffectGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "side_effect_ledger: $($sideEffectGate.Blocker)"
        break
    }
    $familyProofLedgerGate = Invoke-FamilyProofLedgerGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$familyProofLedgerGate.CanProceed) {
        Write-Host "Family proof ledger gate failed for slice ${i}: $($familyProofLedgerGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "family_proof_ledger: $($familyProofLedgerGate.Blocker)"
        break
    }
    # v378: TODO detector gate after GREEN phase
    $todoGate = Invoke-TodoDetectorGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
    if (-not [bool]$todoGate.CanProceed) {
        Write-Host "TODO detector gate failed for slice ${i}: $($todoGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "todo_detector: $($todoGate.Blocker)"
        break
    }
    if (-not [bool]$greenGate.CanProceed) {
        Write-Host "GREEN phase no-mock gate failed for slice ${i}: $($greenGate.Blocker)"
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "green_phase_no_mock_gate: $($greenGate.Blocker)"
        break
    }

    # v281: Executable evidence gate - Validate before granting coverage credit
    Write-Host "Running v281 executable evidence gate for slice $i..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $replayRootFull `
        -Worktree $worktreeFull `
        -SliceResultPath $sliceResult `
        -SliceIndex $i | Out-Null
    $evidenceGateExitCode = $LASTEXITCODE

    if ($evidenceGateExitCode -ne 0) {
        # Executable evidence gate failed - call recovery router and stop
        $evidenceGatePath = Join-Path $replayRootFull ('EXECUTABLE_EVIDENCE_GATE_{0:D2}.json' -f $i)
        $evidenceGateResult = Get-Content -LiteralPath $evidenceGatePath -Raw -Encoding UTF8 | ConvertFrom-Json

        $blockerReason = if ($evidenceGateResult.issues.Count -gt 0) { $evidenceGateResult.issues[0] } else { "executable_evidence_gate_failed" }
        Write-Host "Executable evidence gate failed for slice ${i}: $blockerReason"

        # Call recovery router for evidence gate failure
        $recoveryArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $PSScriptRoot 'Get-RecoveryAction.ps1'),
            '-ReplayRoot', $replayRootFull,
            '-SliceIndex', $i,
            '-BlockerReason', $blockerReason
        )
        $forcedFamily = [string]$forced.family_id
        if (-not [string]::IsNullOrWhiteSpace($forcedFamily)) {
            $recoveryArgs += @('-ForcedFamily', $forcedFamily)
        }
        $forcedSliceType = [string]$forced.slice_type
        if (-not [string]::IsNullOrWhiteSpace($forcedSliceType)) {
            $recoveryArgs += @('-SliceType', $forcedSliceType)
        }
        & powershell @recoveryArgs | Out-Null

        # Write to runner contract
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} executable evidence gate stop | {1} | {2} | non_authorizing_evidence | executable evidence validation failed: {3}. |" -f $i, $forced.family_id, $forced.slice_type, $blockerReason)

        # Stop the loop - do not grant coverage credit for this slice
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "executable_evidence_gate: $blockerReason"
        break
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate-behavior-proof.ps1') `
        -ReplayRoot $replayRootFull `
        -Worktree $worktreeFull `
        -SliceResultPath $sliceResult `
        -Slice $i | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $behaviorProofPath = Join-Path $replayRootFull ('BEHAVIOR_PROOF_VALIDATE_{0:D2}.json' -f $i)
        $behaviorProofResult = Read-JsonObject -Path $behaviorProofPath
        $blockerReason = if ($behaviorProofResult.issues.Count -gt 0) { $behaviorProofResult.issues[0] } else { 'behavior_proof_schema_failed' }
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} behavior proof schema stop | {1} | {2} | behavior_proof_schema | blocker={3}; result={4}. |" -f $i, $forced.family_id, $forced.slice_type, $blockerReason, $behaviorProofPath)
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "behavior_proof_schema: $blockerReason"
        break
    }

    Write-Host "Executable evidence gate and behavior proof schema passed for slice $i."

    $result = Read-JsonObject -Path $sliceResult
    $touchedFamilies = @(Get-StringArray $result.touched_requirement_families)
    if (-not [string]::IsNullOrWhiteSpace($forced.family_id) -and
        -not ($touchedFamilies -contains [string]$forced.family_id) -and
        @('BLOCKED', 'INVALID_REPLAY') -notcontains [string]$result.slice_status) {
        Write-Host "Forced family mismatch for slice ${i}: expected $($forced.family_id), touched=$($touchedFamilies -join ','). Starting forced-family repair."
        [void](Invoke-ForcedFamilyRepair `
            -ReplayRoot $replayRootFull `
            -Worktree $worktreeFull `
            -SlicePrompt $slicePrompt `
            -SliceResult $sliceResult `
            -SliceIndex $i `
            -ForcedDecision $forced `
            -Executor $Executor `
            -Sandbox $Sandbox `
            -Approval $Approval `
            -TimeoutMinutes $sliceTimeoutMinutes `
            -Model $Model `
            -ReasoningEffort $ReasoningEffort `
            -RunnerContractPath $runnerContractPath `
            -TouchedFamilies $touchedFamilies)

        if (Test-Path -LiteralPath $sliceVerify) {
            Remove-Item -LiteralPath $sliceVerify -Force -ErrorAction SilentlyContinue
        }
        $repairEvidenceGate = Join-Path $replayRootFull ('EXECUTABLE_EVIDENCE_GATE_{0:D2}.json' -f $i)
        if (Test-Path -LiteralPath $repairEvidenceGate) {
            Remove-Item -LiteralPath $repairEvidenceGate -Force -ErrorAction SilentlyContinue
        }
        Invoke-EvidenceCaptureRepair -SliceResultPath $sliceResult -SliceLogDir $sliceLogDir -ReplayRoot $replayRootFull
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SliceVerifier.ps1') -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResult $sliceResult -SliceIndex $i | Out-Null
        $v348Gate = Invoke-V348SliceQualityGates -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$v348Gate.CanProceed) {
            Write-Host "v348 slice quality gate failed for repaired slice ${i}: $($v348Gate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "v348_slice_quality_gate_after_forced_family_repair: $($v348Gate.Blocker)"
            break
        }
        # v431: Layer validation gate (pre-flight check)
        $layerGate = Invoke-LayerValidationGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$layerGate.CanProceed) {
            Write-Host "Layer validation gate failed for repaired slice ${i}: $($layerGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "layer_validation_after_repair: $($layerGate.Blocker)"
            break
        }
        # v379: Test charter pre-validation gate
        $testCharterGate = Invoke-TestCharterPrevalidatorGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$testCharterGate.CanProceed) {
            Write-Host "Test charter prevalidation failed after forced-family repair for slice ${i}. Starting test charter repair pass."
            $testCharterGate = Invoke-TestCharterRepairGate `
                -ReplayRoot $replayRootFull `
                -Worktree $worktreeFull `
                -SliceIndex $i `
                -RunnerContractPath $runnerContractPath `
                -ForcedDecision $forced `
                -FailedGate $testCharterGate `
                -Executor $Executor `
                -Sandbox $Sandbox `
                -Approval $Approval `
                -TimeoutMinutes $sliceTimeoutMinutes `
                -Model $Model `
                -ReasoningEffort $ReasoningEffort
        }
        if (-not [bool]$testCharterGate.CanProceed) {
            Write-Host "Test charter prevalidation gate failed for slice ${i}: $($testCharterGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "test_charter_prevalidation: $($testCharterGate.Blocker)"
            break
        }
        # v454: Economy checkpoint - CP4_TEST_CHARTER (after test charter)
        $testCharterCheckpoint = Invoke-EconomyCheckpointGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath -CheckpointId 'CP4_TEST_CHARTER' -DiscoveryMode $discoveryMode
        if (-not [bool]$testCharterCheckpoint.CanProceed) {
            Write-Host "Test charter checkpoint failed for slice ${i}: $($testCharterCheckpoint.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "test_charter_checkpoint: $($testCharterCheckpoint.Blocker)"
            break
        }
        # v431: Phase0 precheck gate (test framework validation)
        $phase0Precheck = Invoke-Phase0PrecheckGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath -MavenSettings $MavenSettings
        if (-not [bool]$phase0Precheck.CanProceed) {
            Write-Host "Phase0 precheck gate failed for repaired slice ${i}: $($phase0Precheck.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "phase0_precheck_after_repair: $($phase0Precheck.Blocker)"
            break
        }
        # v378: Pre-implementation contract verification gate
        $contractGate = Invoke-ContractVerificationGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$contractGate.CanProceed) {
            Write-Host "Contract verification gate failed for repaired slice ${i}: $($contractGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "contract_verification_after_repair: $($contractGate.Blocker)"
            break
        }
        $redGate = Invoke-RedPhaseHardGate -ReplayRoot $replayRootFull -SliceResultPath $sliceResult -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$redGate.CanProceed) {
            Write-Host "RED phase hard gate failed for repaired slice ${i}: $($redGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "red_phase_hard_gate_after_forced_family_repair: $($redGate.Blocker)"
            break
        }
        # v378: RED phase incremental verification
        $redIncrementalGate = Invoke-IncrementalVerificationGate -Phase 'RED' -ReplayRoot $replayRootFull -SliceResultPath $sliceResult -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$redIncrementalGate.CanProceed) {
            Write-Host "RED incremental verification gate failed for repaired slice ${i}: $($redIncrementalGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "red_incremental_verification_after_repair: $($redIncrementalGate.Blocker)"
            break
        }
        $greenGate = Invoke-GreenPhaseNoMockGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -RunnerContractPath $runnerContractPath
        Move-ReplayScratchArtifacts -ReplayRoot $replayRootFull
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i
        # v431: Side effect ledger gate (verify after GREEN phase)
        $sideEffectGate = Invoke-SideEffectLedgerGate -ReplayRoot $replayRootFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$sideEffectGate.CanProceed) {
            Write-Host "Side effect ledger gate failed for repaired slice ${i}: $($sideEffectGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "side_effect_ledger_after_repair: $($sideEffectGate.Blocker)"
            break
        }
        # v378: TODO detector gate after GREEN phase
        $todoGate = Invoke-TodoDetectorGate -ReplayRoot $replayRootFull -Worktree $worktreeFull -SliceIndex $i -RunnerContractPath $runnerContractPath
        if (-not [bool]$todoGate.CanProceed) {
            Write-Host "TODO detector gate failed for repaired slice ${i}: $($todoGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "todo_detector_after_repair: $($todoGate.Blocker)"
            break
        }
        if (-not [bool]$greenGate.CanProceed) {
            Write-Host "GREEN phase no-mock gate failed for repaired slice ${i}: $($greenGate.Blocker)"
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "green_phase_no_mock_gate_after_forced_family_repair: $($greenGate.Blocker)"
            break
        }

        Write-Host "Running v281 executable evidence gate for repaired slice $i..."
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
            -ReplayRoot $replayRootFull `
            -Worktree $worktreeFull `
            -SliceResultPath $sliceResult `
            -SliceIndex $i | Out-Null
        $evidenceGateExitCode = $LASTEXITCODE
        if ($evidenceGateExitCode -ne 0) {
            $evidenceGatePath = Join-Path $replayRootFull ('EXECUTABLE_EVIDENCE_GATE_{0:D2}.json' -f $i)
            $evidenceGateResult = Get-Content -LiteralPath $evidenceGatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $blockerReason = if ($evidenceGateResult.issues.Count -gt 0) { $evidenceGateResult.issues[0] } else { "executable_evidence_gate_failed_after_forced_family_repair" }
            Write-Host "Executable evidence gate failed for repaired slice ${i}: $blockerReason"
            $recoveryArgs = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', (Join-Path $PSScriptRoot 'Get-RecoveryAction.ps1'),
                '-ReplayRoot', $replayRootFull,
                '-SliceIndex', $i,
                '-BlockerReason', $blockerReason
            )
            $forcedFamily = [string]$forced.family_id
            if (-not [string]::IsNullOrWhiteSpace($forcedFamily)) {
                $recoveryArgs += @('-ForcedFamily', $forcedFamily)
            }
            $forcedSliceType = [string]$forced.slice_type
            if (-not [string]::IsNullOrWhiteSpace($forcedSliceType)) {
                $recoveryArgs += @('-SliceType', $forcedSliceType)
            }
            & powershell @recoveryArgs | Out-Null
            Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} repaired executable evidence gate stop | {1} | {2} | non_authorizing_evidence | executable evidence validation failed after forced-family repair: {3}. |" -f $i, $forced.family_id, $forced.slice_type, $blockerReason)
            Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "executable_evidence_gate_after_forced_family_repair: $blockerReason"
            break
        }
        Write-Host "Executable evidence gate passed for repaired slice $i."
        $result = Read-JsonObject -Path $sliceResult
        $touchedFamilies = @(Get-StringArray $result.touched_requirement_families)
    }

    Update-FamilyLedgerFromSlice -Path $familyLedgerPath -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -SliceIndex $i -MaxSlices $MaxSlices
    if (-not [string]::IsNullOrWhiteSpace($forced.family_id) -and
        -not ($touchedFamilies -contains [string]$forced.family_id) -and
        @('BLOCKED', 'INVALID_REPLAY') -notcontains [string]$result.slice_status) {
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} enforcement stop | {1} | {2} | tooling_enforcement_stop | forced family was not touched and no blocker was declared. |" -f $i, $forced.family_id, $forced.slice_type)
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "tooling_enforcement_stop: forced family $($forced.family_id) was not touched by S$i"
        break
    }
    $verify = Read-JsonObject -Path $sliceVerify
    $authorizedForSynthesis = $null -ne $verify.authorized_for_synthesis -and [bool]$verify.authorized_for_synthesis
    if ($authorizedForSynthesis) {
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} synthesis authorization signal | {1} | {2} | authorized_for_synthesis | verifier says this slice is synthesis-capable, subject to family ledger cap. |" -f $i, $forced.family_id, $forced.slice_type)
    }
    if ($null -ne $verify.authorized_for_next_slice -and -not [bool]$verify.authorized_for_next_slice) {
        Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| S{0} authorization stop | {1} | {2} | non_authorizing_evidence | authorized_for_next_slice=false; blockers={3}. |" -f $i, $forced.family_id, $forced.slice_type, ((Get-StringArray $verify.authorization_blockers) -join ','))
        Normalize-SliceProgress -Path $progressPath -ReplayRoot $replayRootFull -MaxSlices $MaxSlices -SliceIndex $i -MarkStopped -StopReason "non_authorizing_evidence: $(((Get-StringArray $verify.authorization_blockers) -join ','))"
        break
    }
    if (-not [bool]$verify.should_continue) {
        break
    }
}

Write-FamilyCapReport -LedgerPath $familyLedgerPath -OutPath $familyCapPath
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-family-ledger-from-slice-verify.ps1') -ReplayRoot $replayRootFull -Ledger $familyLedgerPath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Family ledger verifier-closure validation failed. Inspect $(Join-Path $replayRootFull 'FAMILY_LEDGER_FROM_SLICE_VERIFY.json'); ledger CLOSED families must come from SLICE_VERIFY closed_requirement_families."
}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'FamilyRouterAndCap.ps1') -ReplayRoot $replayRootFull -Ledger $familyLedgerPath -ValidateOnly | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Family router/cap validation failed. Inspect $(Join-Path $replayRootFull 'FAMILY_ROUTER_AND_CAP.json'); coverage_cap_from_ledger must forbid PASS while required families remain OPEN/PARTIAL."
}

$sliceResults = (Get-ChildItem -LiteralPath $replayRootFull -File -Filter 'SLICE_RESULT_*.json' | Sort-Object Name | ForEach-Object { $_.FullName }) -join "`n"
$sliceVerifies = (Get-ChildItem -LiteralPath $replayRootFull -File -Filter 'SLICE_VERIFY_*.json' | Sort-Object Name | ForEach-Object { $_.FullName }) -join "`n"
$synthesisPrompt = Join-Path $replayRootFull 'PHASE1_SYNTHESIS_PROMPT.md'
$synthesisValues = @{
    PROJECT_ROOT = $projectRootFull
    FEATURE_NAME = $FeatureName
    REQUIREMENT_SOURCE = $requirementSourceFull
    ORACLE_BRANCH = $OracleBranch
    ORACLE_COMMIT = $OracleCommit
    BASE_COMMIT = $BaseCommit
    REPLAY_ROOT = $replayRootFull
    WORKTREE = $worktreeFull
    BASELINE_INDEX = $baselineIndexFull
    CONTEXT_MANIFEST = $contextManifestFull
    SURFACE_CARRIER_SCAN = $surfaceCarrierScanPath
    FEATURE_CLASSIFICATION = $featureClassificationPath
    SYSTEM_CONTEXT_DIR = $systemContextDirFull
    RUN_LABEL = $RunLabel
    ROUND_ID = $RoundId
    MAX_SLICES = $MaxSlices
    SLICE_PROGRESS = $progressPath
    SLICE_PROGRESS_MD = $progressMdPath
    REQUIREMENT_FAMILY_LEDGER = $familyLedgerPath
    REQUIREMENT_FAMILY_CAP = $familyCapPath
    RUNNER_ENFORCEMENT_CONTRACT = $runnerContractPath
    SLICE_RESULTS = $sliceResults
    SLICE_VERIFIES = $sliceVerifies
    ROUND_RESULT = $roundResultPath
}
Set-Content -LiteralPath $synthesisPrompt -Value (Expand-Template -Template $synthesisTemplate -Values $synthesisValues) -Encoding UTF8

$synthesisArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
    '-PromptPath', $synthesisPrompt,
    '-WorkDir', $worktreeFull,
    '-LogDir', (Join-Path $replayRootFull 'logs\phase1-synthesis'),
    '-Executor', $Executor,
    '-Sandbox', $Sandbox,
    '-Approval', $Approval,
    '-TimeoutMinutes', $TimeoutMinutes,
    '-Name', 'phase1-synthesis',
    '-CompletionPath', $roundResultPath,
    '-CompletionQuietSeconds', '90'
)
if (-not [string]::IsNullOrWhiteSpace($Model)) { $synthesisArgs += @('-Model', $Model) }
if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) { $synthesisArgs += @('-ReasoningEffort', $ReasoningEffort) }

& powershell @synthesisArgs
if ($LASTEXITCODE -ne 0) {
    Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value ("| synthesis fallback | phase1-synthesis | round_result | synthesis_executor_failed | exit_code={0}; attempting deterministic fallback. |" -f $LASTEXITCODE)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Write-RoundResultFallback.ps1') -ReplayRoot $replayRootFull -Worktree $worktreeFull -BaseCommit $BaseCommit -FeatureName $FeatureName -RequirementSource $requirementSourceFull | Out-Null
    if (-not (Test-Path -LiteralPath $roundResultPath)) {
        throw "Phase1 synthesis failed with exit code $LASTEXITCODE"
    }
}
Move-ReplayScratchArtifacts -ReplayRoot $replayRootFull

if (-not (Test-Path -LiteralPath $roundResultPath)) {
    $worktreeRoundResult = Join-Path $worktreeFull 'ROUND_RESULT.md'
    if (Test-Path -LiteralPath $worktreeRoundResult) {
        Copy-Item -LiteralPath $worktreeRoundResult -Destination $roundResultPath -Force
    }
}

if (-not (Test-Path -LiteralPath $roundResultPath)) {
    Add-Content -LiteralPath $runnerContractPath -Encoding UTF8 -Value "| synthesis fallback | phase1-synthesis | round_result | missing_round_result | synthesis completed without ROUND_RESULT.md; deterministic fallback generated from blind artifacts. |"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Write-RoundResultFallback.ps1') -ReplayRoot $replayRootFull -Worktree $worktreeFull -BaseCommit $BaseCommit -FeatureName $FeatureName -RequirementSource $requirementSourceFull | Out-Null
}

if (-not (Test-Path -LiteralPath $roundResultPath)) {
    throw "Phase1 slice loop completed without ROUND_RESULT.md"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Enforce-RoundCoverageCap.ps1') `
    -RoundResultPath $roundResultPath `
    -RouterCapPath (Join-Path $replayRootFull 'FAMILY_ROUTER_AND_CAP.json') `
    -ReplayRoot $replayRootFull
if ($LASTEXITCODE -ne 0) {
    throw "Round coverage cap enforcement failed with exit code $LASTEXITCODE"
}

$coverageRecomputeScript = Join-Path $PSScriptRoot 'recompute_round_coverage.py'
if (Test-Path -LiteralPath $coverageRecomputeScript) {
    $coverageRecomputePath = Join-Path $replayRootFull 'ROUND_COVERAGE_RECOMPUTE.json'
    $coverageRecomputeStderr = Join-Path $replayRootFull 'ROUND_COVERAGE_RECOMPUTE.stderr.log'
    & python $coverageRecomputeScript `
        --root $replayRootFull `
        --fail-on-positive-without-synthesis > $coverageRecomputePath 2> $coverageRecomputeStderr
    if ($LASTEXITCODE -ne 0) {
        throw "Round coverage recomputation gate failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Phase1 slice loop completed: $roundResultPath"
