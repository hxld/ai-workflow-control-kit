param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw "FAIL: $Message" }
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 12)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function New-ScenarioRoot {
    param([string]$Root, [string]$Name)
    $replayRoot = Join-Path $Root $Name
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    & git -C $worktree init 2>$null | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src/main/java') | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'src/main/java/ExampleController.java') -Value 'class ExampleController {}' -Encoding UTF8
    & git -C $worktree add -A 2>$null | Out-Null
    & git -C $worktree commit -m init --allow-empty 2>$null | Out-Null
    return [pscustomobject]@{ ReplayRoot = $replayRoot; Worktree = $worktree }
}

function Invoke-Normalizer {
    param([string]$ReplayRoot, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Normalize-SliceResultSchema.ps1') `
        -SliceResultPath $SliceResultPath `
        -ReplayRoot $ReplayRoot `
        -SliceIndex 1 `
        -InPlace | Out-Null
    return $LASTEXITCODE
}

function Invoke-SliceVerifier {
    param([string]$ReplayRoot, [string]$Worktree, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SliceVerifier.ps1') `
        -ReplayRoot $ReplayRoot `
        -Worktree $Worktree `
        -SliceResult $SliceResultPath `
        -SliceIndex 1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-EvidenceGate {
    param([string]$ReplayRoot, [string]$Worktree, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $ReplayRoot `
        -Worktree $Worktree `
        -SliceResultPath $SliceResultPath `
        -SliceIndex 1 | Out-Null
    return $LASTEXITCODE
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v618-slice-schema-normalization-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $scenario1 = New-ScenarioRoot -Root $tempRoot -Name 'agent-status-flat-test-results'
    $slice1 = Join-Path $scenario1.ReplayRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slice1 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_type = 'field_contract_slice'
        status = 'COMPLETED'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'payload_shape_behavior'
        touched_requirement_families = @()
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        test_result = 'PASSED'
        test_results = [ordered]@{
            tests_run = 1
            failures = 0
            errors = 0
        }
        maven_command = 'mvn -pl app -am -Dtest=ExampleControllerTest#shouldSave test'
    })

    Assert-True ((Invoke-Normalizer -ReplayRoot $scenario1.ReplayRoot -SliceResultPath $slice1) -eq 0) 'normalizer must exit 0'
    $normalized1 = Read-JsonFile $slice1
    Assert-True ([string]$normalized1.slice_status -eq 'DONE') 'COMPLETED status must normalize to DONE'
    Assert-True ([string]$normalized1.agent_original_slice_status -eq 'COMPLETED') 'normalizer must preserve original agent status'
    Assert-True (@($normalized1.gap_flags) -contains 'agent_result_schema_normalized') 'normalizer must add traceability flag'
    Assert-True (@($normalized1.tests).Count -eq 1) 'flat test_results must become one structured test'
    Assert-True ([string]$normalized1.tests[0].command -match '-Dtest=ExampleControllerTest#shouldSave') 'synthetic test must preserve Maven command'
    Assert-True (Test-Path -LiteralPath (Join-Path $scenario1.ReplayRoot 'SLICE_RESULT_01.before_schema_normalization.json')) 'in-place normalization must create raw backup'

    Assert-True ((Invoke-SliceVerifier -ReplayRoot $scenario1.ReplayRoot -Worktree $scenario1.Worktree -SliceResultPath $slice1) -eq 0) 'SliceVerifier must consume normalized result'
    $verify1 = Read-JsonFile (Join-Path $scenario1.ReplayRoot 'SLICE_VERIFY_01.json')
    Assert-False (@($verify1.issues) -contains 'slice_status_missing') 'schema-normalized slice must not produce slice_status_missing'
    Assert-True ([string]$verify1.slice_status -eq 'DONE') 'SLICE_VERIFY must report canonical DONE status'

    Assert-True ((Invoke-EvidenceGate -ReplayRoot $scenario1.ReplayRoot -Worktree $scenario1.Worktree -SliceResultPath $slice1) -eq 0) 'executable evidence gate must consume normalized tests command'
    $gate1 = Read-JsonFile (Join-Path $scenario1.ReplayRoot 'EXECUTABLE_EVIDENCE_GATE_01.json')
    Assert-True ([string]$gate1.validation_status -eq 'PASS') 'evidence gate report must pass after normalization'

    $scenario2 = New-ScenarioRoot -Root $tempRoot -Name 'agent-status-without-command'
    $slice2 = Join-Path $scenario2.ReplayRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slice2 ([ordered]@{
        slice_index = 1
        slice_type = 'field_contract_slice'
        status = 'COMPLETED'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'payload_shape_behavior'
        touched_requirement_families = @()
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        test_result = 'PASSED'
        test_results = [ordered]@{
            tests_run = 1
            failures = 0
            errors = 0
        }
    })

    Assert-True ((Invoke-Normalizer -ReplayRoot $scenario2.ReplayRoot -SliceResultPath $slice2) -eq 0) 'normalizer must handle missing Maven command'
    $normalized2 = Read-JsonFile $slice2
    Assert-True ([string]$normalized2.slice_status -eq 'DONE') 'status-only agent result must still canonicalize status'
    Assert-True (@($normalized2.tests).Count -eq 1) 'flat test result must still become structured test'
    Assert-False ($normalized2.tests[0].PSObject.Properties.Name -contains 'command') 'normalizer must not fabricate a command'
    $exitGate2 = Invoke-EvidenceGate -ReplayRoot $scenario2.ReplayRoot -Worktree $scenario2.Worktree -SliceResultPath $slice2
    Assert-True ($exitGate2 -ne 0) 'success-shaped normalized slice without command evidence must fail evidence gate'
    $gate2 = Read-JsonFile (Join-Path $scenario2.ReplayRoot 'EXECUTABLE_EVIDENCE_GATE_01.json')
    Assert-True (@($gate2.issues) -contains 'behavior_evidence_missing:no_executable_command_evidence') 'missing command failure must be explicit'

    $scenario3 = New-ScenarioRoot -Root $tempRoot -Name 'native-done'
    $slice3 = Join-Path $scenario3.ReplayRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slice3 ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'field_contract_slice'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'payload_shape_behavior'
        touched_requirement_families = @()
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        tests = @(
            [ordered]@{
                phase = 'GREEN'
                result = 'pass'
                command = 'mvn -pl app -am -Dtest=ExampleControllerTest#shouldSave test'
            }
        )
    })
    Assert-True ((Invoke-Normalizer -ReplayRoot $scenario3.ReplayRoot -SliceResultPath $slice3) -eq 0) 'native schema normalizer must exit 0'
    $normalized3 = Read-JsonFile $slice3
    Assert-False (@($normalized3.gap_flags) -contains 'agent_result_schema_normalized') 'native schema must not get normalization flag'
    Assert-False (Test-Path -LiteralPath (Join-Path $scenario3.ReplayRoot 'SLICE_RESULT_01.before_schema_normalization.json')) 'native schema must not create backup'

    $sliceVerifierText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SliceVerifier.ps1') -Raw -Encoding UTF8
    Assert-True ($sliceVerifierText.Contains('Normalize-SliceResultSchema.ps1')) 'SliceVerifier must invoke schema normalizer before Verify-SliceClosure'
    $runSliceLoopText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runSliceLoopText.Contains('Validate-ExecutableEvidenceGate.ps1')) 'Run-SliceLoop must still invoke executable evidence gate after verifier'
    $evidenceGateText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1') -Raw -Encoding UTF8
    Assert-True ($evidenceGateText.Contains('SliceResultSchemaNormalizer.ps1')) 'executable evidence gate must load schema normalizer'

    Write-Host 'Test-v618-SliceResultSchemaNormalization PASS'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
