param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [int]$SliceIndex,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-TextIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
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

function Resolve-PythonCommand {
    $resolver = Join-Path $PSScriptRoot 'Resolve-PythonLauncher.ps1'
    if (Test-Path -LiteralPath $resolver) {
        . $resolver
        return Resolve-PythonLauncher
    }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { throw 'python not found' }
    return [pscustomobject]@{ Command = 'python'; Arguments = @() }
}

$root = [System.IO.Path]::GetFullPath($ReplayRoot)
$worktreeFull = [System.IO.Path]::GetFullPath($Worktree)
$resultPath = Join-Path $root ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        worktree = $worktreeFull
        slice_index = $SliceIndex
        output = $resultPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$carrier = Read-JsonIfExists (Join-Path $root ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$firstSlicePlanText = Read-TextIfExists (Join-Path $root 'FIRST_SLICE_PROOF_PLAN.md')
$implementationContractText = Read-TextIfExists (Join-Path $root 'IMPLEMENTATION_CONTRACT.md')
$planText = @($firstSlicePlanText, $implementationContractText) -join "`n"

$selectedCarrier = if ($null -ne $carrier -and $carrier.PSObject.Properties.Name -contains 'selected_carrier') { [string]$carrier.selected_carrier } else { '' }
$selectedRealEntry = if ($null -ne $carrier -and $carrier.PSObject.Properties.Name -contains 'real_entry') { [string]$carrier.real_entry } else { '' }
$plannedCarrier = Get-PlanField -Text $planText -Name 'selected_carrier'
$plannedEntry = Get-PlanField -Text $planText -Name 'selected_real_entry'
$proofObservationPoint = if ($null -ne $carrier -and $carrier.PSObject.Properties.Name -contains 'downstream_side_effect_or_output') { [string]$carrier.downstream_side_effect_or_output } else { '' }

if ($SliceIndex -eq 1 -and -not [string]::IsNullOrWhiteSpace($plannedCarrier)) {
    $selectedCarrier = $plannedCarrier
}
if ($SliceIndex -eq 1 -and -not [string]::IsNullOrWhiteSpace($plannedEntry)) {
    $selectedRealEntry = $plannedEntry
}

$result = [ordered]@{
    gate = 'callable_carrier_authorization'
    slice_index = $SliceIndex
    authorization = 'STOP'
    can_proceed = $false
    selected_carrier = $selectedCarrier
    selected_real_entry = $selectedRealEntry
    blockers = @()
    checks = @()
}

if ([string]::IsNullOrWhiteSpace($selectedCarrier)) {
    $result.blockers = @('selected_carrier_missing')
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    exit 1
}

$scriptPath = Join-Path $PSScriptRoot 'verify_carrier_signature.py'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    $result.blockers = @('verify_carrier_signature_missing')
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    exit 1
}

$inputObject = [ordered]@{
    plan_carrier = $selectedCarrier
    worktree_path = $worktreeFull
    selected_real_entry = $selectedRealEntry
    test_invocation_path = 'pre_red_runner_gate'
    proof_observation_point = $proofObservationPoint
}

$tempInput = Join-Path ([System.IO.Path]::GetTempPath()) ('callable-carrier-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    $inputObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempInput -Encoding UTF8
    $python = Resolve-PythonCommand
    $output = & $python.Command @($python.Arguments + @($scriptPath, '--input', $tempInput)) 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = ($output | ForEach-Object { [string]$_ }) -join "`n"
    $parsed = $null
    try { $parsed = $outputText | ConvertFrom-Json } catch { $parsed = $null }

    if ($null -eq $parsed) {
        $result.blockers = @('carrier_signature_output_unparseable')
        $result.stdout = $outputText
        $result.exit_code = $exitCode
    } else {
        $result.checks = @($parsed)
        $result.exit_code = $exitCode
        $result.resolved_signature = $parsed.resolved_signature
        $result.file_path = $parsed.file_path
        $result.reachable_from_entry = $parsed.reachable_from_entry
        $result.blockers = @($parsed.blockers | ForEach-Object { [string]$_ })
        if ($exitCode -eq 0 -and [bool]$parsed.authorized) {
            $result.authorization = 'ALLOW'
            $result.can_proceed = $true
            $result.blockers = @()
        }
    }
} finally {
    if (Test-Path -LiteralPath $tempInput) {
        Remove-Item -LiteralPath $tempInput -Force -ErrorAction SilentlyContinue
    }
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
exit $(if ($result.can_proceed) { 0 } else { 1 })
