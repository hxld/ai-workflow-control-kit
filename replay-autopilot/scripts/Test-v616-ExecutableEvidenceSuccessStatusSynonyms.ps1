param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
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
    return [pscustomobject]@{ ReplayRoot = $replayRoot; Worktree = $worktree }
}

function Invoke-Gate {
    param([string]$ReplayRoot, [string]$Worktree, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $ReplayRoot `
        -Worktree $Worktree `
        -SliceResultPath $SliceResultPath `
        -SliceIndex 1 | Out-Null
    return $LASTEXITCODE
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v616-evidence-status-synonyms-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $scenario1 = New-ScenarioRoot -Root $tempRoot -Name 'completed-without-command'
    $slice1 = Join-Path $scenario1.ReplayRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slice1 ([ordered]@{
        slice_index = 1
        slice_status = 'COMPLETED'
        slice_type = 'field_contract_slice'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'payload_shape_behavior'
        touched_requirement_families = @()
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        tests = @()
    })
    $exit1 = Invoke-Gate -ReplayRoot $scenario1.ReplayRoot -Worktree $scenario1.Worktree -SliceResultPath $slice1
    Assert-True ($exit1 -ne 0) 'COMPLETED slice without executable command evidence must fail'
    $gate1 = Read-JsonFile (Join-Path $scenario1.ReplayRoot 'EXECUTABLE_EVIDENCE_GATE_01.json')
    Assert-True (@($gate1.issues) -contains 'behavior_evidence_missing:no_executable_command_evidence') 'COMPLETED no-command failure must include behavior evidence issue'

    $scenario2 = New-ScenarioRoot -Root $tempRoot -Name 'done-without-command'
    $slice2 = Join-Path $scenario2.ReplayRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slice2 ([ordered]@{
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
        tests = @()
    })
    $exit2 = Invoke-Gate -ReplayRoot $scenario2.ReplayRoot -Worktree $scenario2.Worktree -SliceResultPath $slice2
    Assert-True ($exit2 -ne 0) 'DONE slice without executable command evidence must fail'

    $scenario3 = New-ScenarioRoot -Root $tempRoot -Name 'completed-with-test-command'
    $slice3 = Join-Path $scenario3.ReplayRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slice3 ([ordered]@{
        slice_index = 1
        slice_status = 'COMPLETED'
        slice_type = 'field_contract_slice'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'payload_shape_behavior'
        touched_requirement_families = @()
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        tests = @(
            @{
                phase = 'GREEN'
                result = 'pass'
                command = 'mvn -pl app -am -Dtest=ExampleControllerTest#shouldSave test'
                evidence = 'Surefire reports 1 test, 0 failures'
            }
        )
    })
    $exit3 = Invoke-Gate -ReplayRoot $scenario3.ReplayRoot -Worktree $scenario3.Worktree -SliceResultPath $slice3
    Assert-True ($exit3 -eq 0) 'COMPLETED slice with executable GREEN command evidence must pass'

    $validatorText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1') -Raw -Encoding UTF8
    Assert-True ($validatorText.Contains("@('DONE', 'COMPLETED') -contains `$sliceStatus")) 'validator must treat DONE and COMPLETED as success-shaped status values'
    Assert-True ($validatorText.Contains('Success-shaped slice missing test_execution_command/exit_code')) 'validator warning must not be DONE-only'

    Write-Host 'Test-v616-ExecutableEvidenceSuccessStatusSynonyms PASS'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
