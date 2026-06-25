param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Index,
    [Parameter(Mandatory = $true)]
    [string]$Contract,
    [string]$OutputPath = ''
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

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
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

function Get-NestedValues {
    param($Node, [string]$Pattern)
    $values = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Node) { return @() }
    if ($Node -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($Node)) { $values.Add($Node) | Out-Null }
        return @($values.ToArray())
    }
    if ($Node -is [System.Array]) {
        foreach ($item in @($Node)) {
            foreach ($value in @(Get-NestedValues -Node $item -Pattern $Pattern)) { $values.Add($value) | Out-Null }
        }
        return @($values.ToArray() | Select-Object -Unique)
    }
    foreach ($prop in @($Node.PSObject.Properties)) {
        if ($prop.Name -match $Pattern) {
            foreach ($value in @(Get-StringArray $prop.Value)) {
                if (-not [string]::IsNullOrWhiteSpace($value)) { $values.Add($value) | Out-Null }
            }
        }
        if ($prop.Value -isnot [string] -and ($prop.Value -is [System.Array] -or $prop.Value.PSObject.Properties.Count -gt 0)) {
            foreach ($nested in @(Get-NestedValues -Node $prop.Value -Pattern $Pattern)) { $values.Add($nested) | Out-Null }
        }
    }
    return @($values.ToArray() | Select-Object -Unique)
}

function Test-CommandTemplateValid {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    if ($Command -match '(?i)(^|\s)(deploy|install)(\s|$)') { return $false }
    if ($Command -match '(?i)(^|\s)-pl\s+' -and $Command -notmatch '(?i)(^|\s)-am(\s|$)') { return $false }
    return $Command -match '(?i)(^|\s)-f\s+'
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$indexPath = Resolve-AbsolutePath $Index
$contractPath = Resolve-AbsolutePath $Contract
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $replayRootFull 'REPLAY_CONTEXT_INDEX_CONTRACT_CHECK.json'
}
$outputPathFull = Resolve-AbsolutePath $OutputPath
$issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    $issues.Add('replay_context_index_missing') | Out-Null
    $indexObject = $null
} else {
    $indexObject = Read-JsonFile -Path $indexPath
}
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $issues.Add('first_slice_execution_contract_missing') | Out-Null
    $contractObject = $null
} else {
    $contractObject = Read-JsonFile -Path $contractPath
}

foreach ($requiredField in @('callable_carriers', 'failed_carrier_authorizations', 'test_harness_modules', 'valid_maven_command_templates', 'forbidden_proof_types_by_family', 'side_effect_probe_examples')) {
    if ($null -eq $indexObject -or -not $indexObject.PSObject.Properties[$requiredField] -or @($indexObject.$requiredField).Count -eq 0) {
        $issues.Add("context_index_missing_$requiredField") | Out-Null
    }
}

$selectedCarrier = [string](Get-PropertyValue -Object $contractObject -Names @('real_entry_signature', 'real_entry_fqn', 'production_entry_qn', 'existing_entry_qn'))
$harnessModule = [string](Get-PropertyValue -Object $contractObject -Names @('test_harness_module', 'harness_module'))
$greenCommand = [string](Get-PropertyValue -Object $contractObject -Names @('green_command', 'maven_test_command_template'))
$invalidationReason = [string](Get-PropertyValue -Object $contractObject -Names @('context_index_invalidation_reason', 'invalidation_reason'))

$callableCarriers = @(Get-NestedValues -Node $(if ($null -ne $indexObject) { $indexObject.callable_carriers } else { $null }) -Pattern '(?i)(signature|carrier|entry|method|qn)$')
if (-not [string]::IsNullOrWhiteSpace($selectedCarrier)) {
    $matchedCarrier = $false
    foreach ($candidate in $callableCarriers) {
        if ($candidate -eq $selectedCarrier -or $candidate -like "*$selectedCarrier*" -or $selectedCarrier -like "*$candidate*") {
            $matchedCarrier = $true
            break
        }
    }
    if (-not $matchedCarrier -and [string]::IsNullOrWhiteSpace($invalidationReason)) {
        $issues.Add('selected_carrier_not_reused_or_invalidated') | Out-Null
    }
}

$harnessModules = @(Get-NestedValues -Node $(if ($null -ne $indexObject) { $indexObject.test_harness_modules } else { $null }) -Pattern '(?i)(module|name|path)$')
if (-not [string]::IsNullOrWhiteSpace($harnessModule) -and $harnessModules.Count -gt 0 -and $harnessModules -notcontains $harnessModule -and [string]::IsNullOrWhiteSpace($invalidationReason)) {
    $issues.Add('test_harness_module_not_reused_or_invalidated') | Out-Null
}

$validCommands = @(Get-NestedValues -Node $(if ($null -ne $indexObject) { $indexObject.valid_maven_command_templates } else { $null }) -Pattern '(?i)(command|template)$')
$hasValidTemplate = $false
foreach ($command in $validCommands) {
    if (Test-CommandTemplateValid -Command $command) {
        $hasValidTemplate = $true
        break
    }
}
if (-not $hasValidTemplate) {
    $issues.Add('valid_maven_command_template_missing') | Out-Null
}
if (-not (Test-CommandTemplateValid -Command $greenCommand)) {
    $issues.Add('contract_maven_command_template_invalid') | Out-Null
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema = 'replay_context_index_contract_check.v1'
    status = $status
    replay_root = $replayRootFull
    index = $indexPath
    contract = $contractPath
    selected_carrier = $selectedCarrier
    test_harness_module = $harnessModule
    command_template_present = -not [string]::IsNullOrWhiteSpace($greenCommand)
    invalidation_reason = $invalidationReason
    issues = @($issues.ToArray() | Select-Object -Unique)
    generated_at = (Get-Date).ToString('s')
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPathFull) | Out-Null
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPathFull -Encoding UTF8
Write-Host "Replay context index contract check ${status}: $outputPathFull"
if ($status -ne 'PASS') { exit 1 }
exit 0
