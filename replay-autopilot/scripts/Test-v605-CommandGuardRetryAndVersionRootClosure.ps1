param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$controlScript = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$sliceLoopScript = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$failureAuditScript = Join-Path $scriptRoot 'Write-FailureAuditPack.ps1'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v605-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $controlText = Get-Content -LiteralPath $controlScript -Raw -Encoding UTF8
    Assert-True 'resolver_has_replay_root_version_parser' ($controlText.Contains('function Get-VersionNumberFromReplayRootName'))
    Assert-True 'resolver_filters_fallback_below_base_version' ($controlText -match '\$baseVersionNumber\s+-lt\s+0\s+-or\s+\$_\.Version\s+-ge\s+\$baseVersionNumber')
    Assert-True 'resolver_sorts_by_version_round_updated' ($controlText -match 'Sort-Object\s+Version,\s*Round,\s*Updated\s+-Descending')

    $sliceLoopText = Get-Content -LiteralPath $sliceLoopScript -Raw -Encoding UTF8
    Assert-True 'slice_loop_has_command_guard_retry_guidance' ($sliceLoopText.Contains('function Get-CommandGuardRetryGuidance'))
    Assert-True 'retry_prompt_mentions_maven_guard_reason' ($sliceLoopText.Contains('maven_pl_without_am_forbidden'))
    Assert-True 'retry_prompt_requires_project_list_also_make' ($sliceLoopText.Contains('-pl <test-module> -am'))
    Assert-True 'retry_prompt_writes_command_guard_blocker' ($sliceLoopText.Contains('command_guard_blocker'))

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $replayRoot = Join-Path $evidenceRoot 'example-feature\claim-codex-replay-v605-autopilot-20260517-r01'
    $controlRoot = Join-Path $evidenceRoot '_control'
    $logDir = Join-Path $replayRoot 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logDir, $controlRoot | Out-Null

    Write-JsonFile (Join-Path $replayRoot 'RUN_CONTROL_SUMMARY.json') ([ordered]@{
        latest = [ordered]@{
            feature = 'example-feature'
            verification_capped_coverage = 0
            oracle_adjusted_coverage = $null
            fingerprints = @('protected_root_isolation_violation', 'low_verification_cap')
        }
    })
    Write-JsonFile (Join-Path $replayRoot 'BLOCKER_FINGERPRINTS.json') ([ordered]@{
        fingerprints = @('protected_root_isolation_violation', 'low_verification_cap')
        repeated_blockers = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'STAGNATION_DECISION.json') ([ordered]@{
        repeated_blockers = @()
    })
    Write-JsonFile (Join-Path $controlRoot 'RUN_CONTROL_LATEST.json') ([ordered]@{
        latest = [ordered]@{
            replay_root = $replayRoot
            feature = 'example-feature'
            verification_capped_coverage = 0
            oracle_adjusted_coverage = $null
            fingerprints = @('protected_root_isolation_violation', 'low_verification_cap')
        }
        control_decision = [ordered]@{
            repeated_blockers = @()
        }
    })
    Write-JsonFile (Join-Path $controlRoot 'BLOCKER_REGISTRY.json') ([ordered]@{
        blockers = [ordered]@{}
    })
    Write-JsonFile (Join-Path $logDir 'phase1-slice01.exec.json') ([ordered]@{
        failure_category = 'command_guard_violation'
        command_guard_reasons = 'maven_pl_without_am_forbidden:pid=1234'
    })

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $failureAuditScript `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $replayRoot `
        -ControlSummaryPath (Join-Path $controlRoot 'RUN_CONTROL_LATEST.json') `
        -BlockerRegistryPath (Join-Path $controlRoot 'BLOCKER_REGISTRY.json') `
        -Quiet
    Assert-True 'failure_audit_exit_zero' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

    $rules = Get-Content -LiteralPath (Join-Path $replayRoot 'VERIFIABLE_RULES.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $rule = @($rules.rules | Where-Object { [string]$_.fingerprint -eq 'maven_pl_without_am_command_guard' }) | Select-Object -First 1
    Assert-True 'maven_guard_rule_emitted' ($null -ne $rule)
    Assert-True 'maven_guard_machine_gate' ([string]$rule.machine_gate -eq 'maven_project_list_also_make_required') ([string]$rule.machine_gate)
    Assert-True 'maven_guard_rule_must_fix' ([bool]$rule.must_fix)

    foreach ($script in @($controlScript, $sliceLoopScript, $failureAuditScript)) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert-True "parse_$([System.IO.Path]::GetFileName($script))" (-not $parseErrors -or $parseErrors.Count -eq 0) (($parseErrors | ForEach-Object { $_.Message }) -join '; ')
    }

    [ordered]@{
        status = 'PASS'
        version = 'v605'
        assertions = @(
            'cycle_summary_root_never_falls_back_below_cycle_version',
            'phase1_retry_prompt_injects_command_guard_correction',
            'maven_pl_without_am_generates_verifiable_machine_gate'
        )
    } | ConvertTo-Json -Depth 5
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
