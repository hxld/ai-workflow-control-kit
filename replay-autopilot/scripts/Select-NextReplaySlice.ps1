param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$SliceIndex = 0,
    [string]$AssertExpectedFamily = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-SchedulerFunctionTexts {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }
    $needed = @('Read-JsonObject', 'Get-StringArray', 'Normalize-SiblingSurface', 'Get-CarrierSurfacePriority', 'Get-FamilyTargetSiblingSurface', 'Get-ForcedFamilyDecision')
    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $needed -contains $node.Name
    }, $true)
    if (@($functionAsts).Count -lt $needed.Count) {
        throw "Required scheduler functions were not found."
    }
    $order = @{ 'Read-JsonObject' = 0; 'Get-StringArray' = 1; 'Normalize-SiblingSurface' = 2; 'Get-CarrierSurfacePriority' = 3; 'Get-FamilyTargetSiblingSurface' = 4; 'Get-ForcedFamilyDecision' = 5 }
    return @($functionAsts | Sort-Object { $order[$_.Name] } | ForEach-Object { $_.Extent.Text })
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        script = $PSCommandPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$ledgerPath = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'
if (-not (Test-Path -LiteralPath $ledgerPath)) {
    throw "REQUIREMENT_FAMILY_LEDGER.json not found: $ledgerPath"
}

foreach ($functionText in (Get-SchedulerFunctionTexts)) {
    Invoke-Expression $functionText
}

$ledger = Read-JsonObject -Path $ledgerPath
if ($SliceIndex -le 0) {
    $progressPath = Join-Path $replayRootFull 'SLICE_PROGRESS.json'
    $completedCount = 0
    if (Test-Path -LiteralPath $progressPath) {
        try {
            $progress = Read-JsonObject -Path $progressPath
            $completedCount = @($progress.completed).Count
        } catch {
            $completedCount = 0
        }
    }
    $SliceIndex = $completedCount + 1
}

$decision = Get-ForcedFamilyDecision -Ledger $ledger -SliceIndex $SliceIndex
$openFamilies = @($ledger.families | Where-Object {
    [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
} | Sort-Object @{Expression = 'touched_count'; Ascending = $true}, @{Expression = 'weight'; Descending = $true})

$result = [ordered]@{
    status = 'ALLOW'
    replay_root = $replayRootFull
    slice_index = $SliceIndex
    selected_family = [string]$decision.family_id
    selected_slice_type = [string]$decision.slice_type
    target_sibling_surface = [string]$decision.target_sibling_surface
    reason = [string]$decision.reason
    open_families = @($openFamilies | ForEach-Object {
        [ordered]@{
            id = [string]$_.id
            status = [string]$_.status
            weight = $(if ($null -ne $_.weight) { [int]$_.weight } else { 0 })
            touched_count = $(if ($null -ne $_.touched_count) { [int]$_.touched_count } else { 0 })
        }
    })
}

if (-not [string]::IsNullOrWhiteSpace($AssertExpectedFamily) -and [string]$decision.family_id -ne $AssertExpectedFamily) {
    $result.status = 'BLOCKED_PLAN_MISMATCH'
    $result.expected_family = $AssertExpectedFamily
    $result | ConvertTo-Json -Depth 12
    exit 1
}

$result | ConvertTo-Json -Depth 12
