param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$RequirementSource,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedRequiredSourceChain
)

$ErrorActionPreference = 'Stop'

$resultText = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Analyze-SourceChainContract.ps1') -ReplayRoot $ReplayRoot -RequirementSource $RequirementSource
if ($LASTEXITCODE -ne 0) {
    throw "Analyze-SourceChainContract failed for $ReplayRoot"
}

$result = $resultText | ConvertFrom-Json
$expected = [System.Convert]::ToBoolean($ExpectedRequiredSourceChain)
if ([bool]$result.required_source_chain -ne $expected) {
    throw "required_source_chain expected $expected but got $($result.required_source_chain). activation_reason=$($result.activation_reason)"
}

[ordered]@{
    status = 'PASS'
    replay_root = $ReplayRoot
    required_source_chain = [bool]$result.required_source_chain
    activation_reason = [string]$result.activation_reason
} | ConvertTo-Json -Depth 5
