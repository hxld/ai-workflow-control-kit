param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) {
            throw $Name
        }
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

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$authorizeScript = Join-Path $scriptRoot 'Authorize-PreSliceEvidence.ps1'
$controlScript = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$sliceVerifier = Join-Path $scriptRoot 'SliceVerifier.ps1'
$sliceClosure = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v604-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $replayRoot = Join-Path $tempRoot 'mixed-oracle'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-JsonFile (Join-Path $replayRoot 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{
                path = 'example-api/src/main/java/com/example/api/ExampleFacade.java'
                is_production = $true
                weight = 'HIGH'
                layer = 'Controller'
            }
            [ordered]@{
                path = 'example-core/src/main/java/com/example/core/task/ExampleBackendTaskProcessor.java'
                is_production = $true
                weight = 'HIGH'
                layer = 'Service'
            }
        )
    })

    Write-JsonFile (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
        authorization = 'ALLOW'
        selected_carrier = 'ExampleBackendTaskProcessor'
        production_boundary = 'example-core/src/main/java/com/example/core/task/ExampleBackendTaskProcessor.java'
        downstream_side_effect_or_output = 'backend task state is updated through task response handling'
        red_expectation = 'entry invokes backend side effect when task response is handled'
    })
    Write-JsonFile (Join-Path $replayRoot 'SIDE_EFFECT_EVIDENCE_01.json') ([ordered]@{
        status = 'READY'
        red_result = 'PENDING_BUSINESS_ASSERTION'
        green_result = 'PENDING'
        test_name = 'ExampleBackendTaskProcessorTest.handleTaskResponse_InvokesBackendFlow'
        entry_call = 'com.example.core.task.ExampleBackendTaskProcessor.handleTaskResponse(ExampleTask,ExampleTaskResponse)'
    })
    Write-JsonFile (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $false
        rows = @()
    })
    'baseline fixture' | Set-Content -LiteralPath (Join-Path $replayRoot 'BASELINE_INDEX.md') -Encoding UTF8
    @"
selected_carrier: ExampleBackendTaskProcessor
selected_real_entry: ExampleBackendTaskProcessor.handleTaskResponse
first_red_test: ExampleBackendTaskProcessorTest.handleTaskResponse_InvokesBackendFlow
"@ | Set-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $authorizeScript `
        -ReplayRoot $replayRoot `
        -SliceIndex 1 `
        -ForcedRequirementFamily 'core_entry' `
        -ForcedSliceType 'tracer_bullet' `
        -ForcedSiblingSurface 'ExampleBackendTaskProcessor.handleTaskResponse' | Out-Null
    Assert-True 'mixed_oracle_auth_file_written' (Test-Path -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_01.json'))
    $auth = Read-JsonFile (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_01.json')
    $issues = @($auth.issues | ForEach-Object { [string]$_ })
    Assert-True 'mixed_oracle_taskprocessor_allowed' ([string]$auth.decision -eq 'ALLOW') "decision=$($auth.decision); issues=$($issues -join ';')"
    Assert-True 'mixed_oracle_backend_exception_recorded' ([bool]$auth.surface_validation.backend_oracle_exception) ($auth.surface_validation | ConvertTo-Json -Depth 5)
    Assert-True 'mixed_oracle_wrong_surface_absent' (($issues -join ';') -notmatch 'wrong_test_surface') ($issues -join ';')

    $controlText = Get-Content -LiteralPath $controlScript -Raw -Encoding UTF8
    Assert-True 'control_has_cycle_root_resolver' ($controlText.Contains('function Resolve-CycleReplayRootForSummary'))
    Assert-True 'control_passes_replay_root_to_summary' ($controlText.Contains("'-ReplayRoot', `$currentReplayRoot"))
    Assert-True 'control_resolver_all_versions_same_cycle' ($controlText.Contains('$allCandidates = @($candidates + $fallback'))
    Assert-True 'control_resolver_sorts_highest_round' ($controlText -match 'Sort-Object\s+Round,\s*Updated\s+-Descending')

    $sliceVerifierText = Get-Content -LiteralPath $sliceVerifier -Raw -Encoding UTF8
    Assert-True 'slice_verifier_uses_meta_authorizing_flags' ($sliceVerifierText.Contains('$metaAuthorizingFlags'))
    Assert-True 'slice_verifier_blocks_side_effect_ledger_gap' ($sliceVerifierText -match "'side_effect_ledger_gap'")

    $sliceClosureText = Get-Content -LiteralPath $sliceClosure -Raw -Encoding UTF8
    Assert-True 'slice_closure_non_authorizing_side_effect_ledger_gap' ($sliceClosureText -match "side_effect_ledger_gap'\)\s*\{\s*\$nonAuthorizingReasons\.Add|side_effect_red_not_business_assertion', 'side_effect_ledger_gap'")
    $hardFlagsPattern = [regex]::Escape('$hardAuthorizationGapFlags') + "[\s\S]*'side_effect_ledger_gap'"
    Assert-True 'slice_closure_hard_flags_side_effect_ledger_gap' ($sliceClosureText -match $hardFlagsPattern)

    foreach ($script in @($authorizeScript, $controlScript, $sliceVerifier, $sliceClosure)) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert-True "parse_$([System.IO.Path]::GetFileName($script))" (-not $parseErrors -or $parseErrors.Count -eq 0) (($parseErrors | ForEach-Object { $_.Message }) -join '; ')
    }

    [ordered]@{
        status = 'PASS'
        version = 'v604'
        assertions = @(
            'mixed_layer_oracle_collects_taskprocessor_after_public_surface',
            'control_summary_uses_actual_cycle_latest_root',
            'side_effect_ledger_gap_is_hard_authorization_signal'
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
