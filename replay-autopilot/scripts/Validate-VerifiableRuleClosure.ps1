param(
    [string]$ReplayRoot = '',
    [string]$RulesPath = '',
    [string]$EvolutionResultPath = '',
    [string]$EvolutionVerifyPath = '',
    [string]$OutputPath = '',
    [string]$ControlRoot = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Read-JsonIfExists {
    param([string]$Path)
    $text = Read-TextIfExists -Path $Path
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    return $text | ConvertFrom-Json
}

function Convert-ToBoolValue {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    return @('1', 'true', 'yes', 'y', 'on') -contains ([string]$Value).Trim().ToLowerInvariant()
}

function Test-TextContainsToken {
    param(
        [string]$Text,
        [string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }
    return $Text -match [regex]::Escape($Token)
}

function Write-ClosureResult {
    param(
        [string]$Path,
        [string]$ControlRootPath,
        [object]$Result
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8

    $mdPath = [System.IO.Path]::ChangeExtension($Path, '.md')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Verifiable Rule Closure') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("- status: $($Result.status)") | Out-Null
    $lines.Add("- required: $($Result.required)") | Out-Null
    $lines.Add("- rules_path: $($Result.rules_path)") | Out-Null
    $lines.Add("- must_fix_count: $($Result.must_fix_count)") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Issues') | Out-Null
    if (@($Result.issues).Count -eq 0) {
        $lines.Add('- none') | Out-Null
    } else {
        foreach ($issue in @($Result.issues)) {
            $lines.Add("- $issue") | Out-Null
        }
    }
    Set-Content -LiteralPath $mdPath -Encoding UTF8 -Value ($lines -join "`n")

    if (-not [string]::IsNullOrWhiteSpace($ControlRootPath) -and (Test-Path -LiteralPath $ControlRootPath -PathType Container)) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $ControlRootPath 'VERIFIABLE_RULE_CLOSURE_LATEST.json') -Force
        Copy-Item -LiteralPath $mdPath -Destination (Join-Path $ControlRootPath 'VERIFIABLE_RULE_CLOSURE_LATEST.md') -Force
    }
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        schema = 'verifiable_rule_closure_validator.v1'
        requires_replay_root = $true
        output = 'VERIFIABLE_RULE_CLOSURE.json'
    } | ConvertTo-Json -Depth 4
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ReplayRoot)) {
    if ([string]::IsNullOrWhiteSpace($RulesPath)) {
        throw 'ReplayRoot or RulesPath is required.'
    }
    $ReplayRoot = Split-Path -Parent (Resolve-AbsolutePath $RulesPath)
}

$root = Resolve-AbsolutePath $ReplayRoot
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Replay root not found: $root"
}

if ([string]::IsNullOrWhiteSpace($RulesPath)) {
    $RulesPath = Join-Path $root 'VERIFIABLE_RULES.json'
}
$rulesPathFull = Resolve-AbsolutePath $RulesPath
if ([string]::IsNullOrWhiteSpace($EvolutionResultPath)) {
    $EvolutionResultPath = Join-Path $root 'EVOLUTION_RESULT.md'
}
if ([string]::IsNullOrWhiteSpace($EvolutionVerifyPath)) {
    $EvolutionVerifyPath = Join-Path $root 'EVOLUTION_RESULT_VERIFY.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root 'VERIFIABLE_RULE_CLOSURE.json'
}
$outputPathFull = Resolve-AbsolutePath $OutputPath

if (-not (Test-Path -LiteralPath $rulesPathFull -PathType Leaf)) {
    $proposalText = Read-TextIfExists -Path (Join-Path $root 'EVOLUTION_PROPOSAL.md')
    $stopDecisionText = Read-TextIfExists -Path (Join-Path $root 'STOP_OR_CONTINUE_DECISION.md')
    $planVerify = $null
    try {
        $planVerify = Read-JsonIfExists -Path (Join-Path $root 'PLAN_CONTRACT_VERIFY.json')
    } catch {
        $planVerify = $null
    }
    $planVerifyFailed = $null -ne $planVerify -and (
        [string]$planVerify.verification_status -eq 'FAIL' -or
        @($planVerify.issues).Count -gt 0
    )
    $evolutionRequiredWithoutRules = (
        $proposalText -match '(?im)^\s*-\s*should_evolve\s*:\s*True\s*$' -or
        $stopDecisionText -match '(?i)STOP_AND_EVOLVE' -or
        $planVerifyFailed
    )
    if ($evolutionRequiredWithoutRules) {
        $result = [ordered]@{
            schema = 'verifiable_rule_closure.v1'
            status = 'FAIL'
            required = $true
            reason = 'verifiable_rules_missing_for_required_evolution'
            replay_root = $root
            rules_path = $rulesPathFull
            must_fix_count = 1
            closed_rules = @()
            open_rules = @()
            issues = @('verifiable_rules_missing_for_required_evolution')
            generated_at = (Get-Date).ToString('s')
        }
        Write-ClosureResult -Path $outputPathFull -ControlRootPath $ControlRoot -Result $result
        Write-Host "Verifiable rule closure FAIL: $outputPathFull"
        Write-Host ' - verifiable_rules_missing_for_required_evolution'
        exit 1
    }
    $result = [ordered]@{
        schema = 'verifiable_rule_closure.v1'
        status = 'PASS'
        required = $false
        reason = 'verifiable_rules_missing'
        replay_root = $root
        rules_path = $rulesPathFull
        must_fix_count = 0
        closed_rules = @()
        open_rules = @()
        issues = @()
        generated_at = (Get-Date).ToString('s')
    }
    Write-ClosureResult -Path $outputPathFull -ControlRootPath $ControlRoot -Result $result
    Write-Host "Verifiable rule closure PASS: $outputPathFull"
    exit 0
}

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$closedRules = New-Object System.Collections.Generic.List[object]
$openRules = New-Object System.Collections.Generic.List[object]

$rulePack = $null
try {
    $rulePack = Read-JsonIfExists -Path $rulesPathFull
} catch {
    $issues.Add("verifiable_rules_parse_error:$($_.Exception.Message)") | Out-Null
}

if ($null -eq $rulePack) {
    $issues.Add('verifiable_rules_empty_or_unreadable') | Out-Null
}

$rules = if ($null -ne $rulePack) { @($rulePack.rules) } else { @() }
$mustFixRules = @($rules | Where-Object { Convert-ToBoolValue $_.must_fix })
$evolutionText = Read-TextIfExists -Path $EvolutionResultPath
$evolutionVerify = $null
try {
    $evolutionVerify = Read-JsonIfExists -Path $EvolutionVerifyPath
} catch {
    $warnings.Add("evolution_verify_parse_error:$($_.Exception.Message)") | Out-Null
}
$evolutionVerifyPass = ($null -ne $evolutionVerify -and [string]$evolutionVerify.status -eq 'PASS')
$hasRegressionEvidence = $evolutionText -match '(?im)(verification_results?\s*:\s*`?[^`\r\n]*(PASS|VALIDATED)|regression[^`\r\n]*(PASS|passed)|test[^`\r\n]*(PASS|passed))'

foreach ($rule in $mustFixRules) {
    $id = [string]$rule.id
    $fingerprint = [string]$rule.fingerprint
    $machineGate = [string]$rule.machine_gate
    $sourceStatus = ([string]$rule.verification_status).Trim().ToUpperInvariant()
    $alreadyClosed = @('PASS', 'CLOSED', 'VERIFIED') -contains $sourceStatus
    $ruleIssues = New-Object System.Collections.Generic.List[string]

    if (-not $alreadyClosed) {
        if ([string]::IsNullOrWhiteSpace($evolutionText)) {
            $ruleIssues.Add('evolution_result_missing') | Out-Null
        }
        if (-not $evolutionVerifyPass) {
            $ruleIssues.Add('evolution_result_verify_not_pass') | Out-Null
        }
        if (-not (Test-TextContainsToken -Text $evolutionText -Token $machineGate)) {
            $ruleIssues.Add("machine_gate_not_referenced:$machineGate") | Out-Null
        }
        if (-not $hasRegressionEvidence) {
            $ruleIssues.Add('regression_or_verification_evidence_missing') | Out-Null
        }
    }

    $ruleResult = [ordered]@{
        id = $id
        fingerprint = $fingerprint
        machine_gate = $machineGate
        source_verification_status = $sourceStatus
        closure_status = if ($alreadyClosed -or $ruleIssues.Count -eq 0) { 'CLOSED' } else { 'OPEN' }
        issues = @($ruleIssues.ToArray())
    }
    if ($ruleResult.closure_status -eq 'CLOSED') {
        $closedRules.Add([pscustomobject]$ruleResult) | Out-Null
    } else {
        $openRules.Add([pscustomobject]$ruleResult) | Out-Null
        foreach ($issue in @($ruleIssues.ToArray())) {
            $issues.Add("${id}:$issue") | Out-Null
        }
    }
}

$required = $mustFixRules.Count -gt 0
$pass = $issues.Count -eq 0
$result = [ordered]@{
    schema = 'verifiable_rule_closure.v1'
    status = if ($pass) { 'PASS' } else { 'FAIL' }
    required = $required
    reason = if (-not $required) { 'no_must_fix_rules' } elseif ($pass) { 'all_must_fix_rules_closed' } else { 'must_fix_rules_open' }
    replay_root = $root
    rules_path = $rulesPathFull
    evolution_result_path = (Resolve-AbsolutePath $EvolutionResultPath)
    evolution_verify_path = (Resolve-AbsolutePath $EvolutionVerifyPath)
    evolution_verify_pass = $evolutionVerifyPass
    must_fix_count = $mustFixRules.Count
    closed_rules = @($closedRules.ToArray())
    open_rules = @($openRules.ToArray())
    issues = @($issues.ToArray())
    warnings = @($warnings.ToArray())
    generated_at = (Get-Date).ToString('s')
}
Write-ClosureResult -Path $outputPathFull -ControlRootPath $ControlRoot -Result $result

if ($pass) {
    Write-Host "Verifiable rule closure PASS: $outputPathFull"
    exit 0
}

Write-Host "Verifiable rule closure FAIL: $outputPathFull"
foreach ($issue in @($issues.ToArray())) {
    Write-Host " - $issue"
}
exit 1
