param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [string]$Contract = '',
    [string]$FamilyLedger = '',
    [string]$OutputPath = '',
    [string]$AllowedPomPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-PropertyValue {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return '' }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties[$name]) {
            $value = $Object.$name
            if ($value -is [System.Array]) {
                if (@($value).Count -gt 0) { return $value }
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }
    return ''
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Test-ForbiddenText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    return $Text -match '(?i)\b(tbd|pending|planned_only|helper_only|mock_only|static_only|dto_only|file_presence|synthetic|placeholder|none|n/a)\b'
}

function Test-CommandUsesPom {
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

function Test-ForbiddenMavenGoal {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $true }
    return $Command -match '(?i)(^|\s)(deploy|install)(\s|$)'
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
if ([string]::IsNullOrWhiteSpace($Contract)) {
    $Contract = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTION_CONTRACT.json'
    if (-not (Test-Path -LiteralPath $Contract -PathType Leaf)) {
        $Contract = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTABLE_CONTRACT.json'
    }
}
if ([string]::IsNullOrWhiteSpace($FamilyLedger)) {
    $FamilyLedger = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $replayRootFull 'PRE_SLICE_AUTHORIZATION_GATE.json'
}
if ([string]::IsNullOrWhiteSpace($AllowedPomPath)) {
    $AllowedPomPath = Join-Path $worktreeFull 'pom.xml'
}

$contractPath = Resolve-AbsolutePath $Contract
$ledgerPath = Resolve-AbsolutePath $FamilyLedger
$outputPathFull = Resolve-AbsolutePath $OutputPath
$allowedPomFull = Resolve-AbsolutePath $AllowedPomPath
$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $issues.Add('first_slice_execution_contract_missing') | Out-Null
    $contractObject = $null
} else {
    $contractObject = Read-JsonFile -Path $contractPath
}

if (-not (Test-Path -LiteralPath $worktreeFull -PathType Container)) {
    $issues.Add('worktree_missing') | Out-Null
}
if (-not (Test-Path -LiteralPath $allowedPomFull -PathType Leaf)) {
    $issues.Add('allowed_isolated_pom_missing') | Out-Null
}
if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
    $warnings.Add('family_ledger_missing') | Out-Null
}

$realEntry = [string](Get-PropertyValue -Object $contractObject -Names @('real_entry_signature', 'real_entry_fqn', 'production_entry_qn', 'existing_entry_qn'))
$harnessModule = [string](Get-PropertyValue -Object $contractObject -Names @('test_harness_module', 'harness_module'))
$redCommand = [string](Get-PropertyValue -Object $contractObject -Names @('red_command'))
$greenCommand = [string](Get-PropertyValue -Object $contractObject -Names @('green_command', 'maven_test_command_template'))
$sideEffectProbe = Get-PropertyValue -Object $contractObject -Names @('side_effect_probe', 'side_effect_or_output_probe', 'side_effect_or_output', 'required_side_effects')
$proofType = [string](Get-PropertyValue -Object $contractObject -Names @('required_proof_type', 'proof_type', 'family_id'))

if (Test-ForbiddenText $realEntry) { $issues.Add('real_entry_signature_missing_or_forbidden') | Out-Null }
if (Test-ForbiddenText $harnessModule) { $issues.Add('test_harness_module_missing_or_forbidden') | Out-Null }
if (Test-ForbiddenText $redCommand) { $issues.Add('red_command_missing_or_forbidden') | Out-Null }
if (Test-ForbiddenText $greenCommand) { $issues.Add('green_command_missing_or_forbidden') | Out-Null }
if (@(Get-StringArray $sideEffectProbe | Where-Object { -not (Test-ForbiddenText ([string]$_)) }).Count -eq 0) {
    $issues.Add('side_effect_probe_missing_or_forbidden') | Out-Null
}
if (Test-ForbiddenText $proofType) { $issues.Add('proof_type_missing_or_forbidden') | Out-Null }

foreach ($pair in @(@('red_command', $redCommand), @('green_command', $greenCommand))) {
    $field = [string]$pair[0]
    $command = [string]$pair[1]
    if ([string]::IsNullOrWhiteSpace($command)) { continue }
    if (-not (Test-CommandUsesPom -Command $command -PomPath $allowedPomFull)) {
        $issues.Add("${field}_does_not_use_allowed_isolated_pom") | Out-Null
    }
    if (-not (Test-PlHasAm -Command $command)) {
        $issues.Add("${field}_pl_without_am") | Out-Null
    }
    if (Test-ForbiddenMavenGoal -Command $command) {
        $issues.Add("${field}_forbidden_maven_goal") | Out-Null
    }
}

if (-not [string]::IsNullOrWhiteSpace($harnessModule) -and -not (Test-ForbiddenText $harnessModule)) {
    $modulePath = Join-Path $worktreeFull $harnessModule
    if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
        $warnings.Add("test_harness_module_path_not_found:$harnessModule") | Out-Null
    }
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$authorization = if ($status -eq 'PASS') { 'ALLOW' } else { 'STOP' }
$result = [ordered]@{
    schema = 'pre_slice_authorization_gate.v1'
    status = $status
    authorization = $authorization
    replay_root = $replayRootFull
    worktree = $worktreeFull
    contract = $contractPath
    family_ledger = $ledgerPath
    allowed_pom_path = $allowedPomFull
    real_entry_signature = $realEntry
    test_harness_module = $harnessModule
    red_command_present = -not [string]::IsNullOrWhiteSpace($redCommand)
    green_command_present = -not [string]::IsNullOrWhiteSpace($greenCommand)
    side_effect_probe = @(Get-StringArray $sideEffectProbe)
    proof_type = $proofType
    issues = @($issues.ToArray() | Select-Object -Unique)
    warnings = @($warnings.ToArray() | Select-Object -Unique)
    generated_at = (Get-Date).ToString('s')
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPathFull) | Out-Null
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPathFull -Encoding UTF8
Write-Host "Pre-slice authorization gate ${status}: $outputPathFull"
if ($status -ne 'PASS') { exit 1 }
exit 0
