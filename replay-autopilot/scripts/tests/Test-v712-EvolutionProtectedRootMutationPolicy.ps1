#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Import-FunctionsFromScript {
    param([string]$Path, [string[]]$Names)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Parse failed for $Path"
    }

    foreach ($name in $Names) {
        $functionAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true)
        if ($null -eq $functionAst) {
            throw "Missing function: $name"
        }
        $bodyText = $functionAst.Body.Extent.Text
        $bodyText = $bodyText.Substring(1, $bodyText.Length - 2)
        Set-Item -Path "function:script:$name" -Value ([scriptblock]::Create($bodyText))
    }
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$invokeAgent = Join-Path $scriptsRoot 'Invoke-AgentPrompt.ps1'

Import-FunctionsFromScript -Path $invokeAgent -Names @(
    'ConvertTo-GitStatusPath',
    'Convert-GitStatusTextToPathMap',
    'Get-GitStatusChangedPaths',
    'Test-ProtectedRootStatusChangeAllowed',
    'Test-ToolingEvolutionStage',
    'Get-ProtectedRootAllowedMutationPrefixes'
)

$ordinaryPrefixes = @(Get-ProtectedRootAllowedMutationPrefixes -Name 'phase1')
$evolutionPrefixes = @(Get-ProtectedRootAllowedMutationPrefixes -Name 'evolution-repair')

Assert-True (-not (Test-ToolingEvolutionStage -Name 'phase1')) 'ordinary replay stages should not use tooling mutation policy'
Assert-True (Test-ToolingEvolutionStage -Name 'evolution') 'evolution stage should use tooling mutation policy'
Assert-True (Test-ToolingEvolutionStage -Name 'evolution-repair') 'evolution-repair stage should use tooling mutation policy'
Assert-True ($ordinaryPrefixes.Count -eq 0) 'ordinary stages should have no protected-root allowlist'
Assert-True ($evolutionPrefixes -contains 'replay-autopilot/') 'evolution-repair should allow replay-autopilot tooling changes'
Assert-True ($evolutionPrefixes -contains 'workflow-history/') 'evolution-repair should allow workflow history updates'
Assert-True ($evolutionPrefixes -contains 'custom-skills-history/') 'evolution-repair should allow knowledge history updates required by evolution prompts'
Assert-True ($evolutionPrefixes -contains 'custom-skills-guide.md') 'evolution-repair should allow knowledge guide updates required by evolution prompts'
Assert-True ($evolutionPrefixes -contains 'CURRENT_VERSION.md') 'evolution-repair should allow exact root version file updates required by evolution prompts'

$before = @'
 M README.md
 M replay-autopilot/scripts/Run-ReplayLoop.ps1
?? replay-autopilot/scripts/Test-v709-EvolutionChangedFilesExist.ps1
'@

$allowlistedAfter = @'
 M README.md
 M replay-autopilot/scripts/Run-ReplayLoop.ps1
?? replay-autopilot/scripts/Test-v709-EvolutionChangedFilesExist.ps1
?? replay-autopilot/scripts/tests/Test-v712-EvolutionProtectedRootMutationPolicy.ps1
?? workflow-history/changes/v712-evolution-protected-root-policy.md
?? custom-skills-history/v687-replay-control-plane-powershell-harness.md
?? CURRENT_VERSION.md
 M workflow-history/latest.json
'@

$forbiddenAfter = @'
 M README.md
 M replay-autopilot/scripts/Run-ReplayLoop.ps1
?? README.generated.md
?? replay-autopilot/scripts/Test-v709-EvolutionChangedFilesExist.ps1
'@

$changedPaths = @(Get-GitStatusChangedPaths -Before $before -After $allowlistedAfter)
Assert-True ($changedPaths -contains 'replay-autopilot/scripts/tests/Test-v712-EvolutionProtectedRootMutationPolicy.ps1') 'status delta should include newly added replay-autopilot test'
Assert-True ($changedPaths -contains 'workflow-history/changes/v712-evolution-protected-root-policy.md') 'status delta should include newly added workflow history file'
Assert-True ($changedPaths -contains 'custom-skills-history/v687-replay-control-plane-powershell-harness.md') 'status delta should include newly added knowledge history file'
Assert-True ($changedPaths -contains 'CURRENT_VERSION.md') 'status delta should include exact root version file'
Assert-True ($changedPaths -contains 'workflow-history/latest.json') 'status delta should include exact workflow latest file under allowed directory'
Assert-True (-not ($changedPaths -contains 'README.md')) 'unchanged dirty protected-root files should not be treated as new agent mutations'
Assert-True (Test-ProtectedRootStatusChangeAllowed -Before $before -After $allowlistedAfter -AllowedPrefixes $evolutionPrefixes) 'evolution-repair should allow only allowlisted protected-root deltas'
Assert-True (-not (Test-ProtectedRootStatusChangeAllowed -Before $before -After $forbiddenAfter -AllowedPrefixes $evolutionPrefixes)) 'evolution-repair should reject protected-root deltas outside allowlist'
Assert-True (-not (Test-ProtectedRootStatusChangeAllowed -Before $before -After $allowlistedAfter -AllowedPrefixes $ordinaryPrefixes)) 'ordinary stages should reject the same protected-root delta'

$sourceText = Get-Content -LiteralPath $invokeAgent -Raw -Encoding UTF8
Assert-True ($sourceText -match 'protected_root_mutation_policy') 'Invoke-AgentPrompt metadata should disclose protected-root mutation policy'
Assert-True ($sourceText -match 'ProtectedRootAllowedMutationPrefixes') 'live guard should receive protected-root allowed mutation prefixes'
Assert-True ($sourceText -match 'protected_root_not_modified_or_allowlisted_tooling_mutation') 'goal spec should distinguish allowlisted tooling mutation criteria'

Write-Host ''
Write-Host 'v712 Evolution Protected Root Mutation Policy: PASS'
exit 0
