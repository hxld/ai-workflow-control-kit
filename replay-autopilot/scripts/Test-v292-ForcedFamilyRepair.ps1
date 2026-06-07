param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runnerPath = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$promptPath = Join-Path $scriptRoot '..\prompts\phase1-slice-executor.prompt.md'
$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($runner, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) "Run-SliceLoop.ps1 must parse after v292 forced-family repair changes"

Assert-True ($runner.Contains('Invoke-ForcedFamilyRepair')) "Run-SliceLoop must define forced-family repair function"
Assert-True ($runner.Contains('PHASE1_SLICE_{0:D2}_FORCED_FAMILY_REPAIR_PROMPT.md')) "Run-SliceLoop must write a dedicated forced-family repair prompt"
Assert-True ($runner.Contains('before_forced_family_repair')) "Run-SliceLoop must preserve the wrong-family SLICE_RESULT before repair"
Assert-True ($runner.Contains('Do not keep a helper/supporting-family slice as DONE or PARTIAL evidence')) "Repair prompt must forbid keeping helper/supporting-family evidence"
Assert-True ($runner.Contains('Executable evidence gate passed for repaired slice')) "Run-SliceLoop must re-run executable evidence gate after repair"

$updateIndex = $runner.LastIndexOf('Update-FamilyLedgerFromSlice -Path $familyLedgerPath')
$repairIndex = $runner.IndexOf('Starting forced-family repair')
Assert-True ($repairIndex -gt 0 -and $updateIndex -gt $repairIndex) "Forced-family repair must happen before family ledger update to avoid polluting the ledger"

Assert-True ($prompt.Contains('machine_command_forced_family')) "Slice prompt must state forced family is a machine command"
Assert-True ($prompt.Contains('DONE/PARTIAL')) "Slice prompt must reject non-forced family DONE/PARTIAL evidence"

[ordered]@{
    status = 'PASS'
    assertions = 9
    cases = @(
        'runner_parse',
        'forced_family_repair_function',
        'dedicated_repair_prompt',
        'preserve_wrong_result',
        'forbid_helper_as_evidence',
        'rerun_evidence_gate',
        'repair_before_ledger_update',
        'prompt_machine_command',
        'prompt_reject_non_forced_done'
    )
} | ConvertTo-Json -Depth 5
