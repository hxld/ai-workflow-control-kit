param(
    [Parameter(Mandatory = $true)]
    [string]$Contract,
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
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

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return '' }
    return ([string]$Object.$Name).Trim()
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

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$contractPath = Resolve-AbsolutePath $Contract
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $replayRootFull 'SLICE_EXECUTION_CONTRACT_01_VERIFY.json'
}
$outputPathFull = Resolve-AbsolutePath $OutputPath

$issues = New-Object System.Collections.Generic.List[string]
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $issues.Add('contract_missing') | Out-Null
    $contractObject = $null
} else {
    $contractObject = Read-JsonFile -Path $contractPath
}

$requiredFields = @(
    'family_id',
    'production_entry_qn',
    'test_class',
    'test_method',
    'red_command',
    'green_command',
    'isolated_pom_path',
    'maven_settings_arg',
    'red_assertion',
    'side_effect_or_output_probe',
    'must_not_assertion'
)

if ($null -ne $contractObject) {
    foreach ($field in $requiredFields) {
        if ([string]::IsNullOrWhiteSpace((Get-StringValue -Object $contractObject -Name $field))) {
            $issues.Add("missing_$field") | Out-Null
        }
    }

    $isolatedPom = Get-StringValue -Object $contractObject -Name 'isolated_pom_path'
    if (-not [string]::IsNullOrWhiteSpace($isolatedPom)) {
        $isolatedPomFull = Resolve-AbsolutePath $isolatedPom
        if ((Split-Path -Leaf $isolatedPomFull) -ne 'pom.xml') {
            $issues.Add('isolated_pom_path_not_pom_xml') | Out-Null
        }
        if (-not (Test-Path -LiteralPath $isolatedPomFull -PathType Leaf)) {
            $issues.Add('isolated_pom_missing') | Out-Null
        }
        if (-not ($isolatedPomFull.StartsWith($replayRootFull, [System.StringComparison]::OrdinalIgnoreCase))) {
            $issues.Add('isolated_pom_not_under_replay_root') | Out-Null
        }
    }

    foreach ($commandField in @('red_command', 'green_command')) {
        $command = Get-StringValue -Object $contractObject -Name $commandField
        if ([string]::IsNullOrWhiteSpace($command)) { continue }
        if ($command -match '(?i)(^|\s)(deploy|install)(\s|$)') {
            $issues.Add("${commandField}_forbidden_maven_goal") | Out-Null
        }
        if (-not (Test-CommandUsesPom -Command $command -PomPath $isolatedPom)) {
            $issues.Add("${commandField}_does_not_use_isolated_pom") | Out-Null
        }
        if (-not (Test-PlHasAm -Command $command)) {
            $issues.Add("${commandField}_pl_without_am") | Out-Null
        }
    }

    $testClass = Get-StringValue -Object $contractObject -Name 'test_class'
    if (-not [string]::IsNullOrWhiteSpace($testClass) -and $testClass -notmatch '^[A-Za-z_][A-Za-z0-9_$.]*Test$') {
        $issues.Add('test_class_not_behavior_test_class') | Out-Null
    }
    $testMethod = Get-StringValue -Object $contractObject -Name 'test_method'
    if (-not [string]::IsNullOrWhiteSpace($testMethod) -and $testMethod -notmatch '^[A-Za-z_][A-Za-z0-9_]{7,}$') {
        $issues.Add('test_method_not_descriptive') | Out-Null
    }
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema = 'slice_execution_contract_verify.v1'
    status = $status
    replay_root = $replayRootFull
    contract = $contractPath
    issues = @($issues.ToArray())
    generated_at = (Get-Date).ToString('s')
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPathFull) | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPathFull -Encoding UTF8
Write-Host "First slice runnable contract verification ${status}: $outputPathFull"
if ($status -ne 'PASS') { exit 1 }
exit 0
