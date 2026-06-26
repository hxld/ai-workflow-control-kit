param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$Slice = 1,
    [string]$Worktree = '',
    [string]$MavenSettings = '',
    [string]$Contract = '',
    [switch]$Regenerate
)

$ErrorActionPreference = 'Stop'

function Resolve-Worktree {
    param([string]$ReplayRoot, [string]$Worktree)
    if (-not [string]::IsNullOrWhiteSpace($Worktree)) { return [System.IO.Path]::GetFullPath($Worktree) }
    return [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($ReplayRoot), 'worktree')
}

function Read-Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-StringValue {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return '' }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Object.$name)) {
            return ([string]$Object.$name).Trim()
        }
    }
    return ''
}

function Get-ArrayCount {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return 0 }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties[$name]) { return @($Object.$name).Count }
    }
    return 0
}

function Get-BooleanValue {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return $false }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties[$name]) {
            $value = $Object.$name
            if ($value -is [bool]) { return [bool]$value }
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return @('1', 'true', 'yes', 'y', 'authorized', 'pass') -contains ([string]$value).Trim().ToLowerInvariant()
            }
        }
    }
    return $false
}

function Test-UsesPom {
    param([string]$Command, [string]$PomPath)
    if ([string]::IsNullOrWhiteSpace($Command) -or [string]::IsNullOrWhiteSpace($PomPath)) { return $false }
    $normalizedCommand = $Command -replace '/', '\'
    $normalizedPom = ([System.IO.Path]::GetFullPath($PomPath)) -replace '/', '\'
    return $normalizedCommand -match ('(?i)(^|\s)-f\s+["'']?' + [regex]::Escape($normalizedPom) + '["'']?(\s|$)')
}

function Test-PlHasAm {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    if ($Command -notmatch '(?i)(^|\s)-pl\s+') { return $true }
    return $Command -match '(?i)(^|\s)-am(\s|$)'
}

function Test-NeedsStopParsing {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    return $Command -match '(?i)(-D(?:it\.)?test\s*=|#|-Dsurefire\.failIfNoSpecifiedTests=false)'
}

$replayRootFull = [System.IO.Path]::GetFullPath($ReplayRoot)
$worktreeFull = Resolve-Worktree -ReplayRoot $replayRootFull -Worktree $Worktree
$isolatedPom = Join-Path $worktreeFull 'pom.xml'

$aggregateExit = 0
if ($Regenerate) {
    $aggregateArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Invoke-PreSliceExperimentContracts.ps1'),
        '-ReplayRoot', $replayRootFull,
        '-Worktree', $worktreeFull,
        '-SliceIndex', $Slice
    )
    if (-not [string]::IsNullOrWhiteSpace($MavenSettings)) { $aggregateArgs += @('-MavenSettings', $MavenSettings) }
    & powershell @aggregateArgs | Out-Null
    $aggregateExit = $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($Contract)) {
    $preferred = Join-Path $replayRootFull 'FIRST_SLICE_CONTRACT.json'
    $compat = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTABLE_CONTRACT.json'
    $sliceContract = Join-Path $replayRootFull ('SLICE_EXECUTION_CONTRACT_{0:D2}.json' -f $Slice)
    if (Test-Path -LiteralPath $preferred -PathType Leaf) { $Contract = $preferred }
    elseif (Test-Path -LiteralPath $compat -PathType Leaf) { $Contract = $compat }
    else { $Contract = $sliceContract }
}

$contractFull = [System.IO.Path]::GetFullPath($Contract)
$contractObject = Read-Json $contractFull
$issues = New-Object System.Collections.Generic.List[string]

if ($null -eq $contractObject) {
    $issues.Add('first_slice_contract_missing') | Out-Null
} else {
    $requiredScalarFields = [ordered]@{
        family_id = @('family_id')
        existing_test_harness_module = @('existing_test_harness_module', 'test_harness_module')
        isolated_pom_maven_command = @('isolated_pom_maven_command', 'maven_test_command_template', 'green_command')
        carrier_fqn = @('carrier_fqn', 'real_entry_fqn', 'production_entry_qn')
        real_entry_signature = @('real_entry_signature', 'real_entry_fqn', 'production_entry_qn')
        test_harness_module = @('test_harness_module')
        test_class = @('test_class')
        test_method = @('test_method')
        red_command = @('red_command')
        green_command = @('green_command')
        expected_red_failure = @('expected_red_failure', 'business_red_assertion', 'red_assertion')
        expected_green_assertion = @('expected_green_assertion', 'green_business_assertion')
        trigger_positive_assertion = @('trigger_positive_assertion', 'green_business_assertion', 'expected_green_assertion')
        trigger_negative_assertion = @('trigger_negative_assertion', 'negative_guard_assertion', 'must_not_assertion')
        side_effect_proof_method = @('side_effect_proof_method', 'entry_invocation_method', 'side_effect_or_output_probe')
        isolated_pom = @('isolated_pom', 'isolated_pom_path')
        maven_settings_arg = @('maven_settings_arg', 'maven_settings')
    }
    foreach ($entry in $requiredScalarFields.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace((Get-StringValue -Object $contractObject -Names $entry.Value))) {
            $issues.Add("missing_$($entry.Key)") | Out-Null
        }
    }

    foreach ($entry in @{
        required_side_effects = @('required_side_effects', 'side_effect_or_output_probe')
        negative_probe = @('negative_probe', 'negative_guard_assertion', 'must_not_assertion')
        forbidden_substitute_carriers = @('forbidden_substitute_carriers', 'forbidden_substitute_surfaces', 'forbidden_test_surfaces')
    }.GetEnumerator()) {
        if ((Get-ArrayCount -Object $contractObject -Names $entry.Value) -eq 0 -and [string]::IsNullOrWhiteSpace((Get-StringValue -Object $contractObject -Names $entry.Value))) {
            $issues.Add("missing_$($entry.Key)") | Out-Null
        }
    }

    if (-not (Get-BooleanValue -Object $contractObject -Names @('uses_isolated_replay_pom'))) {
        $issues.Add('uses_isolated_replay_pom_not_true') | Out-Null
    }
    $contractStatus = Get-StringValue -Object $contractObject -Names @('contract_status', 'authorization', 'status')
    if (-not [string]::IsNullOrWhiteSpace($contractStatus) -and $contractStatus -notmatch '^(?i)(AUTHORIZED|ALLOW|PASS)$') {
        $issues.Add("contract_status_not_authorized:$contractStatus") | Out-Null
    }

    foreach ($commandField in @('red_command', 'green_command')) {
        $command = Get-StringValue -Object $contractObject -Names @($commandField)
        if ([string]::IsNullOrWhiteSpace($command)) { continue }
        if ($command -match '(?i)(^|\s)(deploy|install)(\s|$)') { $issues.Add("${commandField}_forbidden_maven_goal") | Out-Null }
        if (-not (Test-UsesPom -Command $command -PomPath $isolatedPom)) { $issues.Add("${commandField}_non_isolated_pom_command") | Out-Null }
        if (-not (Test-PlHasAm -Command $command)) { $issues.Add("${commandField}_pl_without_am") | Out-Null }
        if ((Test-NeedsStopParsing -Command $command) -and $command -notmatch '(?i)\bmvn(?:\.cmd)?\s+--%') {
            $issues.Add("${commandField}_missing_powershell_stop_parsing") | Out-Null
        }
    }
}

if ($aggregateExit -ne 0) { $issues.Add('pre_slice_contract_aggregate_stop') | Out-Null }

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema = 'first_slice_contract_validation.v1'
    status = $status
    aggregate_exit_code = $aggregateExit
    replay_root = $replayRootFull
    worktree = $worktreeFull
    slice = $Slice
    contract = $contractFull
    isolated_pom = $isolatedPom
    issues = @($issues | Select-Object -Unique)
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRootFull ('FIRST_SLICE_CONTRACT_VALIDATE_{0:D2}.json' -f $Slice)) -Encoding UTF8

if ($status -ne 'PASS') { exit 1 }
exit 0
