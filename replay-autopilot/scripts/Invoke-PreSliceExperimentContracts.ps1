param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [int]$SliceIndex,
    [string]$ForcedRequirementFamily = '',
    [string]$ForcedSliceType = '',
    [string]$ForcedSiblingSurface = '',
    [string]$MavenSettings = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-PlanField {
    param([string]$Text, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $escaped = [regex]::Escape($Name)
    foreach ($line in @($Text -split "\r?\n")) {
        if ([string]$line -match "^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?$escaped\s*\*{0,2}\s*:\s*`?([^`\r\n]*)`?\s*$") {
            return $matches[1].Trim().Trim('`').TrimEnd('.').Trim()
        }
    }
    return ''
}

function Normalize-ContractScalar {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Array]) {
        $items = @($Value | ForEach-Object { Normalize-ContractScalar $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($items.Count -eq 0) { return '' }
        return ($items -join '; ')
    }
    if ($Value -is [hashtable] -or $Value -is [pscustomobject]) { return '' }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text -eq '{' -or $text -eq '[') { return '' }
    if ($text -match '(?is)"schema"\s*:\s*"carrier_lock\.v1"') { return '' }
    if ($text -match '(?is)"carrier_lock_status"\s*:' -and $text -match '(?is)"expected_production_files"\s*:') { return '' }
    if ($text.Length -gt 16000) { return '' }
    return (($text -replace '\r?\n', ' ').Trim())
}

function Get-FirstNonEmpty {
    param([object[]]$Values)
    foreach ($value in $Values) {
        $text = Normalize-ContractScalar $value
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }
    return ''
}

function Get-ObjectString {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return '' }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties[$name]) {
            $value = $Object.$name
            if ($value -is [System.Array]) {
                $items = @($value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($items.Count -gt 0) { return ($items -join '; ') }
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return ([string]$value).Trim()
            }
        }
    }
    return ''
}

function Normalize-RepoPathText {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $text = ([string]$Path).Trim().Trim('"').Trim("'") -replace '\\', '/'
    $text = $text -replace '^[A-Z]:/', ''
    $srcIndex = $text.IndexOf('/src/', [System.StringComparison]::OrdinalIgnoreCase)
    if ($srcIndex -gt 0) {
        $moduleStart = $text.LastIndexOf('/', $srcIndex - 1)
        if ($moduleStart -ge 0 -and $moduleStart -lt $text.Length - 1) {
            $text = $text.Substring($moduleStart + 1)
        }
    }
    return $text.TrimStart('/')
}

function Get-JavaFilePathsFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($Text, '(?i)(?:[A-Za-z]:)?[A-Za-z0-9_.\-/\\]+src[\\/]+main[\\/]+java[\\/]+[A-Za-z0-9_.\-/\\]+\.java')) {
        $path = Normalize-RepoPathText -Path $match.Value
        if (-not [string]::IsNullOrWhiteSpace($path) -and -not $paths.Contains($path)) {
            $paths.Add($path) | Out-Null
        }
    }
    return @($paths)
}

function Get-JavaLeafFromCarrierText {
    param([string[]]$Values)
    foreach ($value in @($Values)) {
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        foreach ($path in @(Get-JavaFilePathsFromText -Text $text)) {
            $leaf = [System.IO.Path]::GetFileName($path)
            if (-not [string]::IsNullOrWhiteSpace($leaf)) { return $leaf }
        }
        $head = @($text -split '\s*->\s*' | Select-Object -First 1)[0]
        if ([string]$head -match '\b([A-Z][A-Za-z0-9_]*)[.#][A-Za-z_][A-Za-z0-9_]*\s*(?:\(|$)') {
            return "$($matches[1]).java"
        }
        if ([string]$head -match '\b([A-Z][A-Za-z0-9_]*(?:Service|Controller|Facade|Event|Mapper|Processor|Handler|Client|Provider|Task|Util|Helper|Repository|Dao|DAO))\b') {
            return "$($matches[1]).java"
        }
    }
    return ''
}

function Get-ExpectedProductionFiles {
    param(
        [string]$ProductionBoundary,
        [string]$EntryFile,
        [string]$SelectedCarrier,
        [string]$SelectedEntry,
        [string]$SelectedSignature
    )

    $files = New-Object System.Collections.Generic.List[string]
    $entryPath = Normalize-RepoPathText -Path $EntryFile
    if ($entryPath -match '(?i)(^|/)src/main/java/.+\.java$') {
        $files.Add($entryPath) | Out-Null
    }
    $carrierLeaf = Get-JavaLeafFromCarrierText -Values @($SelectedEntry, $SelectedCarrier, $SelectedSignature)
    foreach ($path in @(Get-JavaFilePathsFromText -Text $ProductionBoundary)) {
        $leaf = [System.IO.Path]::GetFileName($path)
        if ([string]::IsNullOrWhiteSpace($carrierLeaf) -or $leaf -ieq $carrierLeaf) {
            if (-not $files.Contains($path)) { $files.Add($path) | Out-Null }
        }
    }
    return @($files)
}

function Test-ForbiddenProofText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    return $Text -match '(?i)\b(none|static_only|helper_only|mock_only|dto_only|unknown|tbd|n/a|placeholder)\b'
}

function Test-CommandUsesIsolatedPom {
    param([string]$Command, [string]$Worktree)
    if ([string]::IsNullOrWhiteSpace($Command) -or [string]::IsNullOrWhiteSpace($Worktree)) { return $false }
    $normalizedCommand = $Command -replace '/', '\'
    $expectedPom = ([System.IO.Path]::Combine($Worktree, 'pom.xml')) -replace '/', '\'
    return $normalizedCommand -match ('(?i)(^|\s)-f\s+["'']?' + [regex]::Escape($expectedPom) + '["'']?(\s|$)')
}

function Test-ForbiddenMavenGoal {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $true }
    return $Command -match '(?i)(^|\s)(deploy|install)(\s|$)'
}

function Get-TestHarnessModuleFromCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    if ($Command -match '(?i)(^|\s)-pl\s+["'']?([^"''\s]+)') { return $matches[2].Trim() }
    return ''
}

function Get-TestClassFromTestName {
    param([string]$TestName)
    if ([string]::IsNullOrWhiteSpace($TestName)) { return '' }
    $trimmed = $TestName.Trim()
    if ($trimmed -match '(?i)src[\\/]+test[\\/]+java[\\/]+(?<classPath>.+?)\.java(?:[#.].*)?$') {
        return (($matches['classPath'] -replace '[\\/]', '.').Trim('.'))
    }
    if ($trimmed -match '^(?<class>[A-Za-z_][A-Za-z0-9_$.]*)(?:[#.].*)?$') {
        return $matches['class']
    }
    return ''
}

function Get-TestMethodFromTestName {
    param([string]$TestName)
    if ([string]::IsNullOrWhiteSpace($TestName)) { return '' }
    $trimmed = $TestName.Trim()
    if ($trimmed -match '[#](?<method>[A-Za-z_][A-Za-z0-9_]*)$') {
        return $matches['method']
    }
    if ($trimmed -match '^[A-Za-z_][A-Za-z0-9_$.]*[#.](?<method>[A-Za-z_][A-Za-z0-9_]*)$') {
        return $matches['method']
    }
    return ''
}

function Get-CommandMavenSettings {
    param([string]$ConfiguredValue)
    if ([string]::IsNullOrWhiteSpace($ConfiguredValue)) { return '-Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8' }
    return ('-s ' + $ConfiguredValue + ' -Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8')
}

function Add-MavenStopParsingIfNeeded {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $trimmed = $Command.Trim()
    if ($trimmed -notmatch '(?i)^mvn(?:\.cmd)?\s+') { return $trimmed }
    if ($trimmed -match '(?i)^mvn(?:\.cmd)?\s+--%(\s|$)') { return $trimmed }
    if ($trimmed -match '(?i)(-D(?:it\.)?test\s*=|#|-Dsurefire\.failIfNoSpecifiedTests=false)') {
        return ($trimmed -replace '^(?i)(mvn(?:\.cmd)?)\s+', '$1 --% ')
    }
    return $trimmed
}

function New-MavenTestCommand {
    param(
        [string]$Worktree,
        [string]$Module,
        [string]$TestClass,
        [string]$TestMethod,
        [string]$Settings
    )
    if ([string]::IsNullOrWhiteSpace($Worktree) -or [string]::IsNullOrWhiteSpace($Module) -or [string]::IsNullOrWhiteSpace($TestClass)) { return '' }
    $pom = [System.IO.Path]::Combine($Worktree, 'pom.xml')
    $selector = $TestClass
    if (-not [string]::IsNullOrWhiteSpace($TestMethod)) { $selector = "$selector#$TestMethod" }
    return ('mvn --% ' + (Get-CommandMavenSettings -ConfiguredValue $Settings) + ' -f "' + $pom + '" -pl ' + $Module + ' -am -Dtest=' + $selector + ' -Dsurefire.failIfNoSpecifiedTests=false test')
}

function Get-ProofTypeForFamily {
    param([string]$FamilyId, [string]$PlanText, [string]$ForcedSliceType)
    $proof = Get-FirstNonEmpty @(
        (Get-PlanField -Text $PlanText -Name 'required_proof_type'),
        (Get-PlanField -Text $PlanText -Name 'proof_kind'),
        (Get-PlanField -Text $PlanText -Name 'proof_type'),
        $ForcedSliceType,
        'real_entry_behavior'
    )
    if ($FamilyId -eq 'core_entry' -and $proof -notmatch '(?i)real_entry_behavior') {
        return 'real_entry_behavior'
    }
    return $proof
}

function Get-NumericOrDefault {
    param($Value, [int]$Default)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double]) { return [int]$Value }
    if ([string]$Value -match '^-?\d+$') { return [int]$Value }
    return $Default
}

function Get-HighestOpenRequiredFamily {
    param($Ledger)
    if ($null -eq $Ledger -or -not $Ledger.PSObject.Properties['families']) { return $null }
    $openRows = @($Ledger.families | Where-Object {
        $required = $false
        if ($_.PSObject.Properties['required']) { $required = [bool]$_.required }
        $status = if ($_.PSObject.Properties['status']) { [string]$_.status } else { 'OPEN' }
        $required -and $status -notmatch '^(?i)(closed|executable_closed|not_applicable|not_applicable_by_feature_classifier)$'
    })
    if ($openRows.Count -eq 0) { return $null }
    return @($openRows | Sort-Object @{ Expression = { Get-NumericOrDefault $_.weight 0 }; Descending = $true }, @{ Expression = { [string]$_.id }; Ascending = $true } | Select-Object -First 1)[0]
}

function Write-JsonFile {
    param($Value, [string]$Path, [int]$Depth = 12)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Write-JsonFile requires a non-empty path.' }
    $json = $Value | ConvertTo-Json -Depth $Depth
    $null = $json | ConvertFrom-Json

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $leaf = [System.IO.Path]::GetFileName($Path)
    $tmp = Join-Path $dir ('.{0}.{1}.{2}.tmp' -f $leaf, $PID, [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))

    $lastError = $null
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $backup = Join-Path $dir ('.{0}.{1}.{2}.bak' -f $leaf, $PID, [guid]::NewGuid().ToString('N'))
        try {
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                [System.IO.File]::Replace($tmp, $Path, $backup, $true)
                Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            } else {
                [System.IO.File]::Move($tmp, $Path)
            }
            return
        } catch {
            $lastError = $_
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds ([Math]::Min(1000, 25 * $attempt))
        }
    }

    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "Failed to atomically write JSON to $Path after retries: $lastError"
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$dryRunPath = Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_DRY_RUN_{0:D2}.json' -f $SliceIndex)
$slicePlanPath = Join-Path $replayRootFull ('SLICE_PLAN_CONTRACT_{0:D2}.json' -f $SliceIndex)
$carrierLockPath = Join-Path $replayRootFull 'CARRIER_LOCK.json'
$firstSliceRunCardPath = Join-Path $replayRootFull 'FIRST_SLICE_RUN_CARD.json'
$firstExecutableContractPath = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTABLE_CONTRACT.json'
$sliceExecutionContractPath = Join-Path $replayRootFull ('SLICE_EXECUTION_CONTRACT_{0:D2}.json' -f $SliceIndex)
$carrierInvocationContractPath = Join-Path $replayRootFull ('CARRIER_INVOCATION_CONTRACT_{0:D2}.json' -f $SliceIndex)
$runnableAuthorizationPath = Join-Path $replayRootFull ('RUNNABLE_SLICE_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
$testCharterContractPath = Join-Path $replayRootFull ('TEST_CHARTER_{0:D2}.json' -f $SliceIndex)
$preSliceBlockerPath = Join-Path $replayRootFull ('SLICE_RESULT_PRE_{0:D2}.json' -f $SliceIndex)
$contextIndexPath = Join-Path $replayRootFull 'replay-context-index.json'
$upperContextIndexPath = Join-Path $replayRootFull 'REPLAY_CONTEXT_INDEX.json'
if (-not (Test-Path -LiteralPath $contextIndexPath -PathType Leaf) -and (Test-Path -LiteralPath $upperContextIndexPath -PathType Leaf)) {
    $contextIndexPath = $upperContextIndexPath
}
$contextValidationPath = Join-Path $replayRootFull 'REPLAY_CONTEXT_INDEX_VALIDATION.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $replayRootFull
        worktree = $worktreeFull
        slice_index = $SliceIndex
        carrier_authorization_dry_run = $dryRunPath
        carrier_lock = $carrierLockPath
        first_slice_run_card = $firstSliceRunCardPath
        slice_plan_contract = $slicePlanPath
        runnable_slice_authorization = $runnableAuthorizationPath
        test_charter_contract = $testCharterContractPath
        pre_slice_blocker = $preSliceBlockerPath
    } | ConvertTo-Json -Depth 8
    exit 0
}

$carrier = Read-JsonIfExists (Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$callable = Read-JsonIfExists (Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$preAuth = Read-JsonIfExists (Join-Path $replayRootFull ('PRE_SLICE_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$sideEffect = Read-JsonIfExists (Join-Path $replayRootFull ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $SliceIndex))
$contextValidation = Read-JsonIfExists $contextValidationPath
$planJson = Read-JsonIfExists (Join-Path $replayRootFull 'PLAN_RESULT.json')
$planInfra = if ($null -ne $planJson -and $planJson.PSObject.Properties['test_infrastructure_check']) { $planJson.test_infrastructure_check } else { $null }
$familyLedger = Read-JsonIfExists (Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json')
$highestOpenFamily = Get-HighestOpenRequiredFamily -Ledger $familyLedger
$highestOpenFamilyId = if ($null -ne $highestOpenFamily -and $highestOpenFamily.PSObject.Properties['id']) { [string]$highestOpenFamily.id } else { '' }
$selectedFamilyForSlice = if (-not [string]::IsNullOrWhiteSpace($ForcedRequirementFamily)) { $ForcedRequirementFamily } elseif (-not [string]::IsNullOrWhiteSpace($highestOpenFamilyId)) { $highestOpenFamilyId } else { 'core_entry' }
$highestOpenFamilyWeight = if ($null -ne $highestOpenFamily -and $highestOpenFamily.PSObject.Properties['weight']) { Get-NumericOrDefault $highestOpenFamily.weight 0 } else { 0 }

$planText = @(
    (Read-TextIfExists (Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md')),
    (Read-TextIfExists (Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md')),
    (Read-TextIfExists (Join-Path $replayRootFull 'TEST_CHARTER.md'))
) -join "`n"

$selectedCarrier = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'selected_carrier'),
    $(if ($null -ne $carrier) { [string]$carrier.selected_carrier } else { '' }),
    $(if ($null -ne $callable) { [string]$callable.selected_carrier } else { '' })
)
$selectedEntry = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'selected_real_entry'),
    (Get-PlanField -Text $planText -Name 'real_entry_method'),
    $(if ($null -ne $carrier) { [string]$carrier.real_entry } else { '' }),
    $(if ($null -ne $callable) { [string]$callable.selected_real_entry } else { '' })
)
$redTestName = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'first_red_test'),
    (Get-PlanField -Text $planText -Name 'expected_test_class'),
    (Get-ObjectString -Object $planJson -Names @('first_red_test', 'expected_test_class')),
    $(if ($null -ne $sideEffect) { [string]$sideEffect.test_name } else { '' })
)
$downstream = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'downstream_output_or_side_effect'),
    $(if ($null -ne $carrier) { [string]$carrier.downstream_side_effect_or_output } else { '' }),
    $(if ($null -ne $sideEffect) { (@(Get-StringArray $sideEffect.expected_writes_or_outputs) -join '; ') } else { '' })
)
$productionBoundary = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'production_boundary'),
    $(if ($null -ne $carrier) { [string]$carrier.production_boundary } else { '' }),
    $selectedCarrier
)
$redAssertion = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'red_assertion'),
    $(if ($null -ne $carrier) { [string]$carrier.red_expectation } else { '' })
)
$greenBoundary = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'green_change_boundary'),
    $productionBoundary
)
$validationCommand = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'validation_command'),
    (Get-PlanField -Text $planText -Name 'green_command')
)
$redCommand = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'red_command'),
    $validationCommand
)
$greenCommand = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'green_command'),
    $validationCommand
)
$selectedSignature = Get-FirstNonEmpty @(
    $(if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.formatted } else { '' }),
    $selectedCarrier,
    $selectedEntry
)
$selectedVisibility = Get-FirstNonEmpty @(
    $(if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.visibility } else { '' }),
    'unknown'
)
$selectedModule = Get-FirstNonEmpty @(
    (Get-TestHarnessModuleFromCommand -Command $greenCommand),
    (Get-TestHarnessModuleFromCommand -Command $redCommand),
    (Get-ObjectString -Object $planInfra -Names @('test_module_for_target')),
    (Get-PlanField -Text $planText -Name 'module'),
    (Get-PlanField -Text $planText -Name 'test_harness_module'),
    (Get-PlanField -Text $planText -Name 'test_module')
)
$expectedRedFailure = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'expected_red_failure'),
    $redAssertion
)
$expectedGreenAssertion = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'expected_green_assertion'),
    (Get-PlanField -Text $planText -Name 'green_assertion'),
    $downstream
)
$testHarnessModule = Get-TestHarnessModuleFromCommand -Command $greenCommand
if ([string]::IsNullOrWhiteSpace($testHarnessModule)) { $testHarnessModule = $selectedModule }
$testClass = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'test_class'),
    (Get-ObjectString -Object $planJson -Names @('expected_test_class', 'test_class')),
    (Get-TestClassFromTestName -TestName $redTestName)
)
$testMethod = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'test_method'),
    (Get-ObjectString -Object $planJson -Names @('expected_test_method', 'test_method')),
    (Get-TestMethodFromTestName -TestName $redTestName)
)
if ([string]::IsNullOrWhiteSpace($selectedModule)) { $selectedModule = $testHarnessModule }
if ([string]::IsNullOrWhiteSpace($validationCommand)) {
    $validationCommand = New-MavenTestCommand -Worktree $worktreeFull -Module $testHarnessModule -TestClass $testClass -TestMethod $testMethod -Settings $MavenSettings
}
if ([string]::IsNullOrWhiteSpace($redCommand)) { $redCommand = $validationCommand }
if ([string]::IsNullOrWhiteSpace($greenCommand)) { $greenCommand = $validationCommand }
$validationCommand = Add-MavenStopParsingIfNeeded -Command $validationCommand
$redCommand = Add-MavenStopParsingIfNeeded -Command $redCommand
$greenCommand = Add-MavenStopParsingIfNeeded -Command $greenCommand
if ([string]::IsNullOrWhiteSpace($testHarnessModule)) { $testHarnessModule = Get-TestHarnessModuleFromCommand -Command $greenCommand }
$selectedProofType = Get-ProofTypeForFamily -FamilyId $selectedFamilyForSlice -PlanText $planText -ForcedSliceType $ForcedSliceType

$runnableIssues = New-Object System.Collections.Generic.List[string]
$redUsesIsolatedPom = Test-CommandUsesIsolatedPom -Command $redCommand -Worktree $worktreeFull
$greenUsesIsolatedPom = Test-CommandUsesIsolatedPom -Command $greenCommand -Worktree $worktreeFull
if ([string]::IsNullOrWhiteSpace($selectedEntry)) { $runnableIssues.Add('missing_real_entry_fqn') | Out-Null }
if ([string]::IsNullOrWhiteSpace($testHarnessModule)) { $runnableIssues.Add('missing_test_harness_module') | Out-Null }
if ([string]::IsNullOrWhiteSpace($testClass)) { $runnableIssues.Add('missing_test_class') | Out-Null }
if ([string]::IsNullOrWhiteSpace($testMethod)) { $runnableIssues.Add('missing_test_method') | Out-Null }
if ([string]::IsNullOrWhiteSpace($greenCommand)) { $runnableIssues.Add('missing_maven_test_command_template') | Out-Null }
if ([string]::IsNullOrWhiteSpace($redCommand)) { $runnableIssues.Add('missing_red_command') | Out-Null }
if ([string]::IsNullOrWhiteSpace($greenCommand)) { $runnableIssues.Add('missing_green_command') | Out-Null }
if (-not ($redUsesIsolatedPom -and $greenUsesIsolatedPom)) { $runnableIssues.Add('non_isolated_pom_command') | Out-Null }
if (Test-ForbiddenMavenGoal -Command $redCommand) { $runnableIssues.Add('red_command_forbidden_maven_goal') | Out-Null }
if (Test-ForbiddenMavenGoal -Command $greenCommand) { $runnableIssues.Add('green_command_forbidden_maven_goal') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedRedFailure) -or (Test-ForbiddenProofText $expectedRedFailure)) { $runnableIssues.Add('missing_expected_red_failure') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedGreenAssertion) -or (Test-ForbiddenProofText $expectedGreenAssertion)) { $runnableIssues.Add('missing_green_business_assertion') | Out-Null }
$runnableStatus = if ($runnableIssues.Count -eq 0) { 'AUTHORIZED' } else { 'BLOCKED_NO_RUNNABLE_SLICE' }
$runnableAuthorization = [ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    status = $runnableStatus
    real_entry_fqn = $selectedEntry
    isolated_pom = ([System.IO.Path]::Combine($worktreeFull, 'pom.xml'))
    maven_settings = Get-CommandMavenSettings -ConfiguredValue $MavenSettings
    test_harness_module = $testHarnessModule
    test_class = $testClass
    test_method = $testMethod
    maven_test_command_template = $greenCommand
    red_command = $redCommand
    green_command = $greenCommand
    expected_red_failure = $expectedRedFailure
    green_business_assertion = $expectedGreenAssertion
    expected_green_assertion = $expectedGreenAssertion
    forbidden_maven_goals_checked = $true
    uses_isolated_replay_pom = ($redUsesIsolatedPom -and $greenUsesIsolatedPom)
    issues = @($runnableIssues | Select-Object -Unique)
}
Write-JsonFile -Value $runnableAuthorization -Path $runnableAuthorizationPath

$carrierBlockers = New-Object System.Collections.Generic.List[string]
if ($null -eq $carrier) { $carrierBlockers.Add('carrier_authorization_missing') | Out-Null }
elseif ([string]$carrier.authorization -ne 'ALLOW') {
    foreach ($issue in @(Get-StringArray $carrier.issues)) { if (-not [string]::IsNullOrWhiteSpace($issue)) { $carrierBlockers.Add($issue) | Out-Null } }
    if ($carrierBlockers.Count -eq 0) { $carrierBlockers.Add('carrier_authorization_not_allow') | Out-Null }
}
if ($null -ne $preAuth -and [string]$preAuth.decision -ne 'ALLOW') {
    foreach ($issue in @(Get-StringArray $preAuth.issues)) { if (-not [string]::IsNullOrWhiteSpace($issue)) { $carrierBlockers.Add($issue) | Out-Null } }
}
if ($null -ne $callable -and -not [bool]$callable.can_proceed) {
    foreach ($blocker in @(Get-StringArray $callable.blockers)) { if (-not [string]::IsNullOrWhiteSpace($blocker)) { $carrierBlockers.Add($blocker) | Out-Null } }
}
if ([string]::IsNullOrWhiteSpace($selectedCarrier)) { $carrierBlockers.Add('selected_carrier_missing') | Out-Null }
if ([string]::IsNullOrWhiteSpace($selectedEntry)) { $carrierBlockers.Add('selected_real_entry_missing') | Out-Null }

$preAuthorized = ($carrierBlockers.Count -eq 0)
if ($SliceIndex -eq 1) {
    $carrierSourceFile = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'entry_file'), $(if ($null -ne $carrier) { [string]$carrier.entry_file } else { '' }), $(if ($null -ne $callable) { [string]$callable.file_path } else { '' }))
    $expectedProductionFiles = @(Get-ExpectedProductionFiles `
        -ProductionBoundary $productionBoundary `
        -EntryFile $carrierSourceFile `
        -SelectedCarrier $selectedCarrier `
        -SelectedEntry $selectedEntry `
        -SelectedSignature $selectedSignature)
    $carrierLock = [ordered]@{
        schema = 'carrier_lock.v1'
        experiment = 'pre_budget_carrier_lock'
        family_id = $selectedFamilyForSlice
        selected_family = $selectedFamilyForSlice
        selected_carrier_fqn = $selectedCarrier
        selected_entry_kind = 'production_existing'
        existing_source_file = $carrierSourceFile
        source_file = $carrierSourceFile
        expected_production_files = @($expectedProductionFiles)
        method_signature_found = ($preAuthorized -and -not [string]::IsNullOrWhiteSpace($selectedEntry))
        callable_from_test_harness = $preAuthorized
        authorization_status = if ($preAuthorized -and -not [string]::IsNullOrWhiteSpace($selectedEntry)) { 'PASS' } else { 'STOP' }
        fallback_candidates = @($replacementCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 5)
        qualified_entry = $selectedEntry
        selected_carrier = $selectedCarrier
        production_boundary = $productionBoundary
        downstream_side_effect_or_output = $downstream
        forbidden_substitute_check = if ($preAuthorized) { 'PASS' } else { 'FAIL' }
        test_harness_strategy = $testHarnessModule
        signature = $selectedSignature
        visibility = $selectedVisibility
        module = $selectedModule
        callability = if ($preAuthorized) { 'callable_from_allowed_harness' } else { 'blocked_or_unresolved' }
        allowed_test_harness = $testHarnessModule
        forbidden_substitutes = @('helper_only', 'private_method', 'dto_only', 'terminal_payload', 'generated_service', 'synthetic_carrier', 'mock_only', 'static_contract')
        source_evidence = [ordered]@{
            carrier_authorization = Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
            callable_carrier_authorization = Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
            first_slice_proof_plan = Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md'
            selected_carrier = $selectedCarrier
        }
        status = if ($preAuthorized -and -not [string]::IsNullOrWhiteSpace($selectedEntry)) { 'LOCKED' } else { 'BLOCKED_CARRIER_UNCALLABLE' }
        carrier_lock_status = if ($preAuthorized -and -not [string]::IsNullOrWhiteSpace($selectedEntry)) { 'PASS' } else { 'STOP' }
        executor_invoked = $false
        blockers = @($carrierBlockers | Select-Object -Unique)
    }
    Write-JsonFile -Value $carrierLock -Path $carrierLockPath
    if ([string]$carrierLock.status -ne 'LOCKED') {
        $carrierBlockers.Add('carrier_lock_not_locked') | Out-Null
    }
}

$replacementCandidates = @()
if (Test-Path -LiteralPath $contextIndexPath) {
    $contextIndex = Read-JsonIfExists $contextIndexPath
    foreach ($propName in @('carrier_candidates', 'real_entry_candidates')) {
        if ($null -ne $contextIndex -and $contextIndex.PSObject.Properties.Name -contains $propName) {
            foreach ($candidate in @($contextIndex.$propName | Select-Object -First 3)) {
                if ($candidate -is [string]) { $replacementCandidates += $candidate }
                elseif ($candidate.PSObject.Properties.Name -contains 'signature') { $replacementCandidates += [string]$candidate.signature }
                elseif ($candidate.PSObject.Properties.Name -contains 'carrier') { $replacementCandidates += [string]$candidate.carrier }
                elseif ($candidate.PSObject.Properties.Name -contains 'selected_carrier') { $replacementCandidates += [string]$candidate.selected_carrier }
            }
        }
    }
}

$preAuthorized = ($carrierBlockers.Count -eq 0)
$callableAuthorizationStatus = if ($preAuthorized) { 'AUTHORIZED' } else { 'BLOCKED' }
if ($null -ne $callable) {
    $callableNormalized = [ordered]@{
        gate = 'callable_carrier_authorization'
        slice_index = $SliceIndex
        family_id = $selectedFamilyForSlice
        selected_carrier_fqn = $selectedCarrier
        existing_source_file = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'entry_file'), $(if ($null -ne $carrier) { [string]$carrier.entry_file } else { '' }), $(if ($null -ne $callable) { [string]$callable.file_path } else { '' }))
        method_signature_found = ($preAuthorized -and -not [string]::IsNullOrWhiteSpace($selectedEntry))
        callable_from_test_harness = $preAuthorized
        selected_entry_kind = 'production_existing'
        fallback_candidates = @($replacementCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 5)
        existing_entry_fqn = $selectedEntry
        existing_entry_signature = if ($null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.formatted } else { $selectedEntry }
        carrier_origin = 'existing_production_entry'
        test_instantiation_strategy = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'test_instantiation_strategy'), 'instantiate_or_mock_dependencies_without_replacing_entry')
        method_invocation_statement = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'method_invocation_statement'), (Get-PlanField -Text $planText -Name 'test_invocation_expression'), 'invoke the declared existing production entry from the behavior test')
        resolved_in_baseline_index = $preAuthorized
        forbidden_substitute_check = if ($preAuthorized) { 'passed' } else { 'failed' }
        authorization_status = $callableAuthorizationStatus
        can_proceed = $preAuthorized
        selected_carrier = $selectedCarrier
        selected_real_entry = $selectedEntry
        resolved_signature = $callable.resolved_signature
        blockers = @($carrierBlockers | Select-Object -Unique)
    }
    Write-JsonFile -Value $callableNormalized -Path (Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
}
$dryRun = [ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    selected_symbol = $selectedCarrier
    resolved_declaring_class = if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.class_name } else { '' }
    visibility = if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.visibility } else { '' }
    signature = if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.formatted } else { $selectedCarrier }
    test_invocation_expression = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'test_invocation_expression'), 'pre_red_runner_gate')
    pre_authorized = $preAuthorized
    replacement_candidates = @($replacementCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 3)
    chosen_replacement_or_blocked = if ($preAuthorized) { 'authorized_original' } elseif ($replacementCandidates.Count -gt 0) { 'blocked_after_replacement_candidates_recorded' } else { 'blocked_no_valid_replacement' }
    blockers = @($carrierBlockers | Select-Object -Unique)
}
Write-JsonFile -Value $dryRun -Path $dryRunPath

$planBlockers = New-Object System.Collections.Generic.List[string]
if ($runnableStatus -ne 'AUTHORIZED') {
    foreach ($issue in @($runnableIssues | Select-Object -Unique)) { $planBlockers.Add($issue) | Out-Null }
    $planBlockers.Add('runnable_slice_authorization_not_authorized') | Out-Null
}
if ([string]::IsNullOrWhiteSpace($selectedEntry) -or (Test-ForbiddenProofText $selectedEntry)) { $planBlockers.Add('real_entry_method_missing_or_forbidden') | Out-Null }
if (-not $preAuthorized) { $planBlockers.Add('carrier_dry_run_not_authorized') | Out-Null }
if ([string]::IsNullOrWhiteSpace($productionBoundary) -or (Test-ForbiddenProofText $productionBoundary)) { $planBlockers.Add('production_boundary_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($downstream) -or (Test-ForbiddenProofText $downstream)) { $planBlockers.Add('downstream_output_or_side_effect_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($redTestName) -or (Test-ForbiddenProofText $redTestName)) { $planBlockers.Add('red_test_name_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($redAssertion) -or (Test-ForbiddenProofText $redAssertion)) { $planBlockers.Add('red_assertion_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($greenBoundary) -or (Test-ForbiddenProofText $greenBoundary)) { $planBlockers.Add('green_change_boundary_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($validationCommand) -or (Test-ForbiddenProofText $validationCommand)) { $planBlockers.Add('validation_command_missing_or_forbidden') | Out-Null }
if ($null -ne $contextValidation -and [string]$contextValidation.status -eq 'FAIL') { $planBlockers.Add('replay_context_index_validation_failed') | Out-Null }

$sideEffectProofFamilies = @(
    'stateful_side_effect',
    'core_entry',
    'wire_payload_api_contract',
    'generated_artifact_template_upload',
    'deploy_export_page',
    'external_integration',
    'lifecycle_cleanup_retention'
)
$requiresSideEffect = $sideEffectProofFamilies -contains $ForcedRequirementFamily
if ($requiresSideEffect -and ([string]::IsNullOrWhiteSpace($downstream) -or (Test-ForbiddenProofText $downstream))) {
    $planBlockers.Add('required_side_effect_or_output_proof_missing') | Out-Null
}

$mustNotBehavior = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'must_not_behavior'), (Get-PlanField -Text $planText -Name 'must_not'), 'do not use helper/static/mock/dto-only proof as closure')
$captureMechanism = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'capture_mechanism'),
    (Get-PlanField -Text $planText -Name 'side_effect_capture_mechanism'),
    (Get-PlanField -Text $planText -Name 'db_verification'),
    'behavior test assertion or collaborator argument capture'
)
$forbiddenTestSurface = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'forbidden_test_surface'),
    $mustNotBehavior
)
$positiveAssertions = @($redAssertion, $expectedGreenAssertion, $downstream) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not (Test-ForbiddenProofText ([string]$_)) } | Select-Object -Unique
$negativeAssertions = @($mustNotBehavior) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not (Test-ForbiddenProofText ([string]$_)) } | Select-Object -Unique
$testCharterIssues = New-Object System.Collections.Generic.List[string]
if (-not $preAuthorized) { $testCharterIssues.Add('real_entry_not_authorized_for_charter') | Out-Null }
if ($positiveAssertions.Count -eq 0) { $testCharterIssues.Add('positive_assertions_missing') | Out-Null }
if ($negativeAssertions.Count -eq 0) { $testCharterIssues.Add('negative_must_not_assertions_missing') | Out-Null }
if ([string]::IsNullOrWhiteSpace($downstream) -or (Test-ForbiddenProofText $downstream)) { $testCharterIssues.Add('state_or_output_surface_missing_or_forbidden') | Out-Null }
if ($requiresSideEffect -and ([string]::IsNullOrWhiteSpace($captureMechanism) -or (Test-ForbiddenProofText $captureMechanism))) { $testCharterIssues.Add('capture_mechanism_missing_or_forbidden') | Out-Null }
if ($requiresSideEffect -and ([string]::IsNullOrWhiteSpace($forbiddenTestSurface) -or (Test-ForbiddenProofText $forbiddenTestSurface))) { $testCharterIssues.Add('forbidden_test_surface_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedRedFailure) -or (Test-ForbiddenProofText $expectedRedFailure)) { $testCharterIssues.Add('red_phase_business_failure_missing') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedGreenAssertion) -or (Test-ForbiddenProofText $expectedGreenAssertion)) { $testCharterIssues.Add('green_phase_business_success_missing') | Out-Null }
$testCharterStatus = if ($testCharterIssues.Count -eq 0) { 'AUTHORIZED' } else { 'BLOCKED' }
$testCharterContract = [ordered]@{
    schema_version = 1
    experiment = 'behavior_test_charter_gate'
    slice_index = $SliceIndex
    family_id = $selectedFamilyForSlice
    status = $testCharterStatus
    behavior_test_charter_status = if ($testCharterStatus -eq 'AUTHORIZED') { 'PASS' } else { 'STOP' }
    side_effect_proof_required = $requiresSideEffect
    real_entry_method = $selectedEntry
    test_class = $testClass
    red_assertion = $expectedRedFailure
    green_assertion = $expectedGreenAssertion
    side_effect_assertions = @($downstream) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not (Test-ForbiddenProofText ([string]$_)) }
    must_not_assertions = @($negativeAssertions)
    maven_command = $greenCommand
    test_harness_module = $testHarnessModule
    no_spring_context = $true
    side_effect_target = $downstream
    capture_mechanism = $captureMechanism
    must_fail_before_change = $expectedRedFailure
    forbidden_test_surface = $forbiddenTestSurface
    real_entry_invoked = $preAuthorized
    positive_assertions = @($positiveAssertions)
    negative_must_not_assertions = @($negativeAssertions)
    state_or_output_surface = $downstream
    red_phase_business_failure = $expectedRedFailure
    green_phase_business_success = $expectedGreenAssertion
    proof_type = $selectedProofType
    non_authorizing_evidence = @('helper_only', 'mock_only', 'dto_only', 'static_only', 'wiring_only', 'file_presence_only')
    issues = @($testCharterIssues | Select-Object -Unique)
}
Write-JsonFile -Value $testCharterContract -Path $testCharterContractPath
if ($requiresSideEffect -and $testCharterStatus -ne 'AUTHORIZED') {
    foreach ($issue in @($testCharterIssues | Select-Object -Unique)) { $planBlockers.Add($issue) | Out-Null }
    $planBlockers.Add('test_charter_contract_not_authorized') | Out-Null
}

$slicePlan = [ordered]@{
    schema_version = 1
    experiment = 'high_weight_family_proof_router'
    slice_index = $SliceIndex
    forced_requirement_family = $ForcedRequirementFamily
    forced_slice_type = $ForcedSliceType
    forced_sibling_surface = $ForcedSiblingSurface
    selected_family = $selectedFamilyForSlice
    highest_weight_open_family = $highestOpenFamilyId
    highest_weight_open_family_weight = $highestOpenFamilyWeight
    family_id = $selectedFamilyForSlice
    selected_carrier = $selectedCarrier
    required_proof_type = Get-ProofTypeForFamily -FamilyId $selectedFamilyForSlice -PlanText $planText -ForcedSliceType $ForcedSliceType
    expected_actual_proof_type = Get-ProofTypeForFamily -FamilyId $selectedFamilyForSlice -PlanText $planText -ForcedSliceType $ForcedSliceType
    coverage_cap_if_open = if ($null -ne $highestOpenFamily -and $highestOpenFamily.PSObject.Properties['coverage_cap_if_open']) { Get-NumericOrDefault $highestOpenFamily.coverage_cap_if_open 0 } else { 0 }
    forbidden_proof = @('helper_only', 'static_only', 'mock_only', 'dto_only', 'compile_only', 'file_presence_only')
    real_entry_method = $selectedEntry
    callable_from_test = $preAuthorized
    production_boundary = $productionBoundary
    downstream_output_or_side_effect = $downstream
    must_not_behavior = $mustNotBehavior
    red_test_name = $redTestName
    red_assertion = $redAssertion
    green_change_boundary = $greenBoundary
    validation_command = $validationCommand
    forbidden_proof_checks = @('none', 'static_only', 'helper_only', 'mock_only', 'dto_only')
    carrier_authorization_dry_run = $dryRunPath
    carrier_lock = if (Test-Path -LiteralPath $carrierLockPath) { $carrierLockPath } else { '' }
    first_slice_run_card = if (Test-Path -LiteralPath $firstSliceRunCardPath) { $firstSliceRunCardPath } else { '' }
    runnable_slice_authorization = $runnableAuthorizationPath
    callable_carrier_authorization = Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
    test_charter_contract = $testCharterContractPath
    replay_context_index = if (Test-Path -LiteralPath $contextIndexPath) { $contextIndexPath } else { '' }
    replay_context_index_validation = if (Test-Path -LiteralPath $contextValidationPath) { $contextValidationPath } else { '' }
    blockers = @($planBlockers | Select-Object -Unique)
    authorization = if ($planBlockers.Count -eq 0) { 'ALLOW' } else { 'STOP' }
    router_status = if ($planBlockers.Count -eq 0 -and ([string]::IsNullOrWhiteSpace($highestOpenFamilyId) -or $selectedFamilyForSlice -eq $highestOpenFamilyId)) { 'PASS' } else { 'STOP' }
}
Write-JsonFile -Value $slicePlan -Path $slicePlanPath

$sliceExecutionContract = [ordered]@{
    schema = 'slice_execution_contract.v1'
    family_id = $selectedFamilyForSlice
    production_entry_qn = $selectedEntry
    test_class = $testClass
    test_method = $testMethod
    red_command = $redCommand
    green_command = $greenCommand
    isolated_pom_path = ([System.IO.Path]::Combine($worktreeFull, 'pom.xml'))
    maven_settings_arg = Get-CommandMavenSettings -ConfiguredValue $MavenSettings
    red_assertion = $expectedRedFailure
    side_effect_or_output_probe = $downstream
    must_not_assertion = $mustNotBehavior
    entry_invocation_method = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'entry_invocation_method'), (Get-PlanField -Text $planText -Name 'test_invocation_expression'), 'invoke the selected real production entry from the behavior test')
    contract_status = if ($planBlockers.Count -eq 0) { 'AUTHORIZED' } else { 'BLOCKED' }
    issues = @($planBlockers | Select-Object -Unique)
}
Write-JsonFile -Value $sliceExecutionContract -Path $sliceExecutionContractPath

$baselineCarrierIndexPath = Join-Path $replayRootFull 'replay-context-index\baseline-carriers.json'
if (-not (Test-Path -LiteralPath $baselineCarrierIndexPath -PathType Leaf)) {
    $baselineCarrierIndexPath = Join-Path $replayRootFull 'replay-context-index.json'
}
$carrierInvocationContract = [ordered]@{
    schema = 'carrier_invocation_contract.v1'
    status = if ($preAuthorized -and -not [string]::IsNullOrWhiteSpace($selectedEntry)) { 'PASS' } else { 'FAIL' }
    resolved = $preAuthorized
    signature_match = $preAuthorized
    test_invokes_entry = -not [string]::IsNullOrWhiteSpace($sliceExecutionContract.entry_invocation_method)
    carrier_origin = if ($preAuthorized) { 'existing_production' } else { 'unresolved' }
    production_entry_qn = $selectedEntry
    test_invocation_method = $sliceExecutionContract.entry_invocation_method
    contract = $sliceExecutionContractPath
    carrier_index = $baselineCarrierIndexPath
    issues = @($carrierBlockers | Select-Object -Unique)
}
Write-JsonFile -Value $carrierInvocationContract -Path $carrierInvocationContractPath

if ($SliceIndex -eq 1) {
    $firstExecutableContract = [ordered]@{
        schema_version = 1
        family_id = $selectedFamilyForSlice
        real_entry_fqn = $selectedEntry
        test_harness_module = $testHarnessModule
        test_class = $testClass
        test_method = $testMethod
        production_entry_qn = $selectedEntry
        entry_invocation_method = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'entry_invocation_method'), (Get-PlanField -Text $planText -Name 'test_invocation_expression'), 'invoke the selected real production entry from the behavior test')
        required_side_effects = @($downstream) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not (Test-ForbiddenProofText ([string]$_)) }
        business_red_assertion = $expectedRedFailure
        negative_guard_assertion = $mustNotBehavior
        forbidden_test_surfaces = @('helper_only', 'static_only', 'dto_only', 'service_only_when_plan_selected_public_entry', 'test_only', 'synthetic_carrier')
        allowed_mock_boundaries = @('collaborator_dependency', 'dao_mapper_gateway', 'common_request_assembly_helper.buildRequestCommon', 'request_builder_function collaborator input')
        maven_test_command_template = $greenCommand
        existing_entry_qn = $selectedEntry
        entry_file = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'entry_file'), $(if ($null -ne $carrier) { [string]$carrier.entry_file } else { '' }))
        method_signature = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'method_signature'), $selectedCarrier)
        required_proof_type = Get-ProofTypeForFamily -FamilyId $selectedFamilyForSlice -PlanText $planText -ForcedSliceType $ForcedSliceType
        side_effect_or_output = $downstream
        must_not_behavior = $slicePlan.must_not_behavior
        forbidden_substitute_surfaces = @('new_helper_only', 'new_service_without_existing_entry_call', 'dto_only', 'static_contract', 'mock_only', 'test_only')
        red_command = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'red_command'), $validationCommand)
        green_command = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'green_command'), $validationCommand)
        isolated_pom_path = ([System.IO.Path]::Combine($worktreeFull, 'pom.xml'))
        maven_settings_arg = Get-CommandMavenSettings -ConfiguredValue $MavenSettings
        uses_isolated_replay_pom = ($redUsesIsolatedPom -and $greenUsesIsolatedPom)
        expected_red_failure = $expectedRedFailure
        green_business_assertion = $expectedGreenAssertion
        assertion_names = @(
            $redAssertion,
            (Get-PlanField -Text $planText -Name 'assertion_names')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        authorization = $slicePlan.authorization
        blockers = @($planBlockers | Select-Object -Unique)
        carrier_authorization_dry_run = $dryRunPath
        slice_plan_contract = $slicePlanPath
        runnable_slice_authorization = $runnableAuthorizationPath
        callable_carrier_authorization = Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
        test_charter_contract = $testCharterContractPath
    }
    $firstContractMissing = New-Object System.Collections.Generic.List[string]
    foreach ($fieldName in @('real_entry_fqn', 'test_harness_module', 'test_class', 'test_method', 'production_entry_qn', 'entry_invocation_method', 'business_red_assertion', 'negative_guard_assertion', 'maven_test_command_template', 'red_command', 'green_command', 'expected_red_failure', 'green_business_assertion')) {
        if ([string]::IsNullOrWhiteSpace([string]$firstExecutableContract[$fieldName]) -or (Test-ForbiddenProofText ([string]$firstExecutableContract[$fieldName]))) {
            $firstContractMissing.Add($fieldName) | Out-Null
        }
    }
    if (-not [bool]$firstExecutableContract['uses_isolated_replay_pom']) {
        $firstContractMissing.Add('uses_isolated_replay_pom') | Out-Null
    }
    foreach ($arrayFieldName in @('required_side_effects', 'forbidden_test_surfaces', 'allowed_mock_boundaries')) {
        if (@($firstExecutableContract[$arrayFieldName]).Count -eq 0) {
            $firstContractMissing.Add($arrayFieldName) | Out-Null
        }
    }
    $firstExecutableContract['contract_status'] = if ($firstContractMissing.Count -eq 0) { 'AUTHORIZED' } else { 'BLOCKED' }
    $firstExecutableContract['contract_missing_fields'] = @($firstContractMissing | Select-Object -Unique)
    Write-JsonFile -Value $firstExecutableContract -Path $firstExecutableContractPath
    if ($firstContractMissing.Count -gt 0) {
        foreach ($missingField in @($firstContractMissing | Select-Object -Unique)) { $planBlockers.Add("first_slice_execution_contract_missing_$missingField") | Out-Null }
    }

    $runCardIssues = New-Object System.Collections.Generic.List[string]
    $runCardStatus = if ($firstContractMissing.Count -eq 0 -and $preAuthorized) { 'ALLOW' } elseif (-not $preAuthorized) { 'BLOCKED_CARRIER_CALLABILITY' } else { 'BLOCKED_ASSERTION_CONTRACT' }
    $lockedCarrierValue = ''
    $carrierLockObject = Read-JsonIfExists $carrierLockPath
    if ($null -ne $carrierLockObject) { $lockedCarrierValue = [string]$carrierLockObject.qualified_entry }
    foreach ($fieldName in @('lockedCarrierValue', 'testHarnessModule', 'redCommand', 'greenCommand', 'selectedEntry', 'downstream', 'mustNotBehavior', 'expectedRedFailure', 'expectedGreenAssertion')) {
        $value = Get-Variable -Name $fieldName -ValueOnly -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace([string]$value) -or (Test-ForbiddenProofText ([string]$value))) {
            $runCardIssues.Add("run_card_missing_$fieldName") | Out-Null
        }
    }
    if (-not ($redUsesIsolatedPom -and $greenUsesIsolatedPom)) { $runCardIssues.Add('run_card_commands_not_isolated') | Out-Null }
    if ($runCardIssues.Count -gt 0 -and $runCardStatus -eq 'ALLOW') { $runCardStatus = 'BLOCKED_ASSERTION_CONTRACT' }
    $firstSliceRunCard = [ordered]@{
        schema = 'first_slice_run_card.v1'
        status = $runCardStatus
        locked_carrier = $lockedCarrierValue
        existing_test_harness_module = $testHarnessModule
        isolated_pom_path = ([System.IO.Path]::Combine($worktreeFull, 'pom.xml'))
        red_command = $redCommand
        green_command = $greenCommand
        real_entry_assertion = $expectedGreenAssertion
        side_effect_assertion = $downstream
        must_not_assertion = $mustNotBehavior
        expected_red_failure = $expectedRedFailure
        expected_green_pass = $expectedGreenAssertion
        required_proof_type = $selectedProofType
        authorization_source = $firstExecutableContractPath
        issues = @($runCardIssues | Select-Object -Unique)
    }
    Write-JsonFile -Value $firstSliceRunCard -Path $firstSliceRunCardPath
    if ($runCardStatus -ne 'ALLOW') {
        $planBlockers.Add($runCardStatus) | Out-Null
        foreach ($issue in @($runCardIssues | Select-Object -Unique)) { $planBlockers.Add($issue) | Out-Null }
    }
}

$preSliceAuthorizationGatePath = Join-Path $replayRootFull 'PRE_SLICE_AUTHORIZATION_GATE.json'
$proofTypePolicyGatePath = Join-Path $replayRootFull 'PROOF_TYPE_POLICY_GATE.json'
$contextIndexContractCheckPath = Join-Path $replayRootFull 'REPLAY_CONTEXT_INDEX_CONTRACT_CHECK.json'
if (-not (Test-Path -LiteralPath $contextIndexPath -PathType Leaf) -and -not [string]::IsNullOrWhiteSpace($selectedEntry) -and -not [string]::IsNullOrWhiteSpace($testHarnessModule) -and -not [string]::IsNullOrWhiteSpace($greenCommand)) {
    $generatedContextIndex = [ordered]@{
        callable_carriers = @([ordered]@{ signature = $selectedEntry; carrier = $selectedCarrier; entry = $selectedEntry })
        failed_carrier_authorizations = @([ordered]@{ signature = 'forbidden_substitute'; reason = 'not_selected_for_first_slice' })
        test_harness_modules = @($testHarnessModule)
        valid_maven_command_templates = @([ordered]@{ module = $testHarnessModule; command = $greenCommand })
        forbidden_proof_types_by_family = [ordered]@{ core_entry = @('helper_only', 'static_only', 'mock_only', 'dto_only') }
        side_effect_probe_examples = @([ordered]@{ family = $selectedFamilyForSlice; probe = $downstream })
        real_entry_candidates = @([ordered]@{ signature = $selectedEntry })
        generated_by = 'Invoke-PreSliceExperimentContracts.ps1'
    }
    Write-JsonFile -Value $generatedContextIndex -Path $contextIndexPath
}
if (Test-Path -LiteralPath $firstExecutableContractPath -PathType Leaf) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'pre_slice_authorization_gate.ps1') `
        -ReplayRoot $replayRootFull `
        -Worktree $worktreeFull `
        -Contract $firstExecutableContractPath `
        -FamilyLedger (Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json') `
        -AllowedPomPath ([System.IO.Path]::Combine($worktreeFull, 'pom.xml')) `
        -OutputPath $preSliceAuthorizationGatePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $planBlockers.Add('pre_slice_authorization_gate_failed') | Out-Null
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'proof_type_policy_gate.ps1') `
        -ReplayRoot $replayRootFull `
        -TestCharter $testCharterContractPath `
        -FamilyLedger (Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json') `
        -Contract $firstExecutableContractPath `
        -OutputPath $proofTypePolicyGatePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $planBlockers.Add('proof_type_policy_gate_failed') | Out-Null
    }

    if (Test-Path -LiteralPath $contextIndexPath -PathType Leaf) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'replay_context_index_contract_check.ps1') `
            -ReplayRoot $replayRootFull `
            -Index $contextIndexPath `
            -Contract $firstExecutableContractPath `
            -OutputPath $contextIndexContractCheckPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $planBlockers.Add('replay_context_index_contract_check_failed') | Out-Null
        }
    } else {
        $planBlockers.Add('replay_context_index_missing_for_contract_check') | Out-Null
    }
}

if ($planBlockers.Count -gt 0) {
    $slicePlan.blockers = @($planBlockers | Select-Object -Unique)
    $slicePlan.authorization = 'STOP'
    Write-JsonFile -Value $slicePlan -Path $slicePlanPath
    $preSliceBlocker = [ordered]@{
        schema_version = 1
        slice_index = 0
        original_slice_index = $SliceIndex
        slice_status = 'BLOCKED'
        executor_invoked = $false
        slice_type = 'blocker'
        blocker = 'pre_slice_experiment_contract_stop'
        blocker_reasons = @($planBlockers | Select-Object -Unique)
        gap_flags = @('tooling_enforcement_stop', 'feedback_loop_blocker')
        implemented_files = @()
        touched_requirement_families = @()
        closed_requirement_families = @()
        coverage_delta = 0
        has_behavior_evidence = $false
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        carrier_authorization_dry_run = $dryRunPath
        slice_plan_contract = $slicePlanPath
    }
    Write-JsonFile -Value $preSliceBlocker -Path $preSliceBlockerPath
    exit 1
}

exit 0
