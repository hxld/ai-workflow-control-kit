param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Text
}

function Write-Json {
    param([string]$Path, $Object)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Import-RunSliceLoopFunctions {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $needed = @(
        'Read-JsonObject',
        'Read-TextIfExists',
        'Get-StringArray',
        'Get-RequirementFamilySpecs',
        'Get-KeywordHits',
        'Test-ExplicitRequirementFamilyScope',
        'Initialize-RequirementFamilyLedger'
    )
    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $needed -contains $node.Name
    }, $true)
    if (@($functionAsts).Count -lt $needed.Count) {
        throw 'Required Run-SliceLoop functions were not found.'
    }
    $order = @{
        'Read-JsonObject' = 0
        'Read-TextIfExists' = 1
        'Get-StringArray' = 2
        'Get-RequirementFamilySpecs' = 3
        'Get-KeywordHits' = 4
        'Test-ExplicitRequirementFamilyScope' = 5
        'Initialize-RequirementFamilyLedger' = 6
    }
    foreach ($functionAst in @($functionAsts | Sort-Object { $order[$_.Name] })) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        script = $PSCommandPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\family-ledger-init-{0}' -f $PID)
$root = Join-Path $tempRoot 'root'
New-Item -ItemType Directory -Force -Path $root | Out-Null

$requirement = Join-Path $root 'REQUIREMENT_SOURCE_SNAPSHOT.md'
Write-Text $requirement 'Compact requirement: H5 carries wxId, persist wxId, emit MQ payload, and insurer callback fallback sends wait-material notification.'
Write-Text (Join-Path $root 'EXPECTED_DIFF_MATRIX.md') @"
# Expected Diff Matrix

| requirement | expected file families | validation |
| --- | --- | --- |
| H5 request carries wxId | CaseInfoParam.java; ClaimNofityParam.java | source field reaches payload |
| insurer callback fallback | InsureCompanyPushService.java | callback emits MQ |
| no duplicate while still wait-material | CaseFlowStatusService.java; InsureCompanyPushService.java | same-status callback does not duplicate |
"@
Write-Json (Join-Path $root 'FAMILY_CONTRACT.json') ([ordered]@{
    schema_version = 1
    families = @(
        [ordered]@{
            id = 'wire_payload_api_contract'
            required = $true
            weight = 95
            first_executable_carrier = 'ClaimNofityParam.wxId -> ClaimNotifyEvent.pushMsgToMQ'
            planned_slice = 'S2'
            proof_required = @('payload includes wxId')
            forbidden_proof = @('enum_only')
            coverage_cap_if_open = 70
        },
        [ordered]@{
            id = 'external_integration'
            required = $true
            weight = 90
            first_executable_carrier = 'InsureCompanyPushService.updateCaseFlowStatus -> ClaimNotifyEvent.pushMsgToMQ'
            planned_slice = 'S3'
            proof_required = @('callback emits MQ')
            forbidden_proof = @('wechat_only')
            coverage_cap_if_open = 80
        },
        [ordered]@{
            id = 'lifecycle_cleanup_retention'
            required = $true
            weight = 85
            first_executable_carrier = 'InsureCompanyPushService old/new status guard'
            planned_slice = 'S3'
            proof_required = @('same-status callback does not duplicate')
            forbidden_proof = @('happy_path_only')
            coverage_cap_if_open = 75
        }
    )
})

Import-RunSliceLoopFunctions
$ledgerPath = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json'
Initialize-RequirementFamilyLedger -Path $ledgerPath -ReplayRoot $root -RequirementSource $requirement -MaxSlices 3
$ledger = Read-Json $ledgerPath

function Assert-FamilyOpen {
    param([string]$Id)
    $family = @($ledger.families | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1)
    if ($family.Count -eq 0) { throw "Missing family $Id" }
    if (-not [bool]$family[0].required) { throw "Expected $Id required=true" }
    if ([string]$family[0].status -ne 'OPEN') { throw "Expected $Id status OPEN, got $($family[0].status)" }
    if ([string]::IsNullOrWhiteSpace([string]$family[0].first_executable_carrier)) { throw "Expected $Id first_executable_carrier" }
    if (@($family[0].open_sibling_surfaces).Count -eq 0) { throw "Expected $Id open_sibling_surfaces from first_executable_carrier" }
}

Assert-FamilyOpen 'wire_payload_api_contract'
Assert-FamilyOpen 'external_integration'
Assert-FamilyOpen 'lifecycle_cleanup_retention'

[ordered]@{
    status = 'PASS'
    cases = @('required_family_from_contract_and_expected_diff', 'required_family_gets_open_sibling_surface')
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 8

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
