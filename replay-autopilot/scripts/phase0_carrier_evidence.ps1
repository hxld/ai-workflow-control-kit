# phase0_carrier_evidence.ps1
# Experiment 1 from NEXT_EXPERIMENT_PLAN.md: Oracle Contract Hints for Carrier Selection

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$Phase0PromptPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputHintPath,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Get-OracleEntryHint {
    <#
    .SYNOPSIS
    Reads ORACLE_ENTRY_HINT.md from replay root if available.

    .DESCRIPTION
    This function checks for the presence of ORACLE_ENTRY_HINT.md in the replay root.
    If found, it returns the hint content for carrier selection guidance.

    Returns hashtable with:
    - exists: boolean indicating if hint file exists
    - content: hint content if exists
    - entry_class: parsed entry class name
    - entry_method: parsed entry method signature
    #>
    param([string]$ReplayRoot)

        $hintPath = Join-Path $ReplayRoot 'ORACLE_ENTRY_HINT.md'
        $result = @{
            exists = $false
            content = ''
            entry_class = ''
            entry_method = ''
        }

        if (Test-Path -LiteralPath $hintPath) {
            $hint = Get-Content -LiteralPath $hintPath -Raw -Encoding UTF8
            $result.exists = $true
            $result.content = $hint

            # Parse entry class and method if present
            if ($hint -match 'class\s+(\w+)') {
                $result.entry_class = $matches[1]
            }
            if ($hint -match 'method\s+(\w+\(.*?\))') {
                $result.entry_method = $matches[1]
            }
        }

        return $result
}

function Add-CarrierHintToPrompt {
    <#
    .SYNOPSIS
    Injects oracle entry hint into Phase 0 prompt.

    .DESCRIPTION
    If ORACLE_ENTRY_HINT.md exists, this function adds the hint content
    to the Phase 0 prompt to guide carrier selection.

    Returns modified prompt content.
    #>
    param(
        [string]$Phase0Prompt,
        [string]$HintContent
    )

    $hintSection = @"

## Oracle Entry Point Guidance

If ORACLE_ENTRY_HINT.md is provided, the hint contains the correct entry point signature.
Use this hint to validate your carrier selection. Your selected carrier must match the hint.

ORACLE ENTRY HINT:
$HintContent
"@

    return $Phase0Prompt + $hintSection
}

function Invoke-Phase0CarrierEvidence {
    <#
    .SYNOPSIS
    Main function for Phase 0 carrier evidence processing.

    .DESCRIPTION
    Processes oracle entry hints and updates Phase 0 prompt accordingly.
    Writes result to PHASE0_CARRIER_EVIDENCE.json.
    #>
    param(
        [string]$ReplayRoot,
        [string]$Phase0PromptPath
    )

    Write-Host "INFO: Processing Phase 0 carrier evidence..." -ForegroundColor Cyan

    # Get oracle entry hint
    $hint = Get-OracleEntryHint -ReplayRoot $ReplayRoot

    $result = [ordered]@{
        stage = 'Phase0_Carrier_Evidence'
        hint_available = $hint.exists
        hint_content = if ($hint.exists) { $hint.content } else { '' }
        entry_class = $hint.entry_class
        entry_method = $hint.entry_method
        processed_at = (Get-Date).ToString('s')
    }

    # If hint exists and Phase 0 prompt provided, augment it
    if ($hint.exists -and -not [string]::IsNullOrWhiteSpace($Phase0PromptPath)) {
        Write-Host "INFO: Oracle entry hint found, augmenting Phase 0 prompt" -ForegroundColor Green

        $phase0Prompt = Get-Content -LiteralPath $Phase0PromptPath -Raw -Encoding UTF8
        $augmentedPrompt = Add-CarrierHintToPrompt -Phase0Prompt $phase0Prompt -HintContent $hint.content

        # Write augmented prompt
        $augmentedPath = Join-Path $ReplayRoot 'PHASE0_PROMPT_AUGMENTED.md'
        $augmentedPrompt | Set-Content -LiteralPath $augmentedPath -Encoding UTF8

        $result.augmented_prompt_path = $augmentedPath
        $result.augmentation_status = 'SUCCESS'
    } elseif (-not $hint.exists) {
        Write-Host "INFO: No oracle entry hint found, proceeding without hint" -ForegroundColor Yellow
        $result.augmentation_status = 'NO_HINT'
    } else {
        Write-Host "WARN: Hint exists but no Phase 0 prompt path provided" -ForegroundColor Yellow
        $result.augmentation_status = 'NO_PROMPT_PATH'
    }

    # Write result
    $resultPath = Join-Path $ReplayRoot 'PHASE0_CARRIER_EVIDENCE.json'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    Write-Host "Phase 0 carrier evidence result written to $resultPath" -ForegroundColor Green
    return $result
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Description = 'Experiment 1: Oracle Contract Hints for Carrier Selection'
        ValidationCommands = @(
            'Check ORACLE_ENTRY_HINT.md exists in replay root',
            'Parse hint for entry class and method',
            'Augment Phase 0 prompt with hint content',
            'Write PHASE0_CARRIER_EVIDENCE.json result'
        )
        ExpectedMetrics = @{
            correct_carrier_selection_rate = '100%'
            phase0_blocker_selected_real_entry_missing = '0 occurrences'
            rounds_to_carrier_selection = '1'
        }
    }
    $result | Format-List
    exit 0
}

# Main execution
$result = Invoke-Phase0CarrierEvidence -ReplayRoot $ReplayRoot -Phase0PromptPath $Phase0PromptPath

exit 0
