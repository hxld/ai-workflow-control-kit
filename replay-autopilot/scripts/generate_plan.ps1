# generate_plan.ps1
# Experiment 3 from NEXT_EXPERIMENT_PLAN.md: Executable Contract Template for Plan Validation

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$PlanPrompt,

    [Parameter(Mandatory = $false)]
    [string]$PlanPromptPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPlanPath,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Get-ExecutableContractTemplate {
    <#
    .SYNOPSIS
    Reads EXECUTABLE_CONTRACT_TEMPLATE.md from templates directory.

    .DESCRIPTION
    Loads the executable contract template that provides structure for plan generation.
    Returns template content.
    #>
    param()

    $templatePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'templates\EXECUTABLE_CONTRACT_TEMPLATE.md'

    if (-not (Test-Path -LiteralPath $templatePath)) {
        Write-Host "ERROR: EXECUTABLE_CONTRACT_TEMPLATE.md not found at $templatePath" -ForegroundColor Red
        return $null
    }

    return Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
}

function Add-ExecutableContractToPrompt {
    <#
    .SYNOPSIS
    Injects executable contract template into plan generation prompt.

    .DESCRIPTION
    Adds the executable contract template to the plan prompt with clear
    requirements for all sections.
    #>
    param(
        [string]$PlanPrompt,
        [string]$Template
    )

    $contractSection = @"

## REQUIRED PLAN SECTIONS

Your plan MUST include all sections from the executable contract template below.
Missing sections will cause verification failure.

$Template
"@

    return $PlanPrompt + $contractSection
}

function Invoke-GenerateExecutablePlan {
    <#
    .SYNOPSIS
    Main function for generating executable plan with contract template.

    .DESCRIPTION
    Loads the executable contract template and augments the plan prompt.
    Writes result to PLAN_CONTRACT_GENERATION.json.
    #>
    param(
        [string]$ReplayRoot,
        [string]$PlanPrompt,
        [string]$PlanPromptPath
    )

    Write-Host "INFO: Processing executable plan generation..." -ForegroundColor Cyan

    # Get executable contract template
    $template = Get-ExecutableContractTemplate

    $result = [ordered]@{
        stage = 'Plan_Contract_Generation'
        template_available = ($null -ne $template)
        template_path = if ($null -ne $template) { Join-Path (Split-Path $PSScriptRoot -Parent) 'templates\EXECUTABLE_CONTRACT_TEMPLATE.md' } else { '' }
        processed_at = (Get-Date).ToString('s')
    }

    if ($null -eq $template) {
        Write-Host "ERROR: Executable contract template not found" -ForegroundColor Red
        $result.generation_status = 'TEMPLATE_MISSING'
        $result.error = 'EXECUTABLE_CONTRACT_TEMPLATE.md not found'
    } else {
        Write-Host "INFO: Executable contract template loaded successfully" -ForegroundColor Green

        # Augment plan prompt with template. Prefer file input so large prompts do not
        # exceed the Windows command-line length limit when invoked from the runner.
        if ([string]::IsNullOrWhiteSpace($PlanPrompt) -and -not [string]::IsNullOrWhiteSpace($PlanPromptPath)) {
            if (-not (Test-Path -LiteralPath $PlanPromptPath)) {
                throw "plan_prompt_path_not_found: $PlanPromptPath"
            }
            $PlanPrompt = Get-Content -LiteralPath $PlanPromptPath -Raw -Encoding UTF8
            $result.plan_prompt_path = $PlanPromptPath
        }

        if (-not [string]::IsNullOrWhiteSpace($PlanPrompt)) {
            $augmentedPrompt = Add-ExecutableContractToPrompt -PlanPrompt $PlanPrompt -Template $template

            # Write augmented prompt
            $augmentedPath = Join-Path $ReplayRoot 'PLAN_PROMPT_WITH_CONTRACT.md'
            $augmentedPrompt | Set-Content -LiteralPath $augmentedPath -Encoding UTF8

            $result.augmented_prompt_path = $augmentedPath
            $result.generation_status = 'SUCCESS'

            Write-Host "INFO: Plan prompt augmented with executable contract template" -ForegroundColor Green
        } else {
            $result.generation_status = 'NO_PROMPT_PROVIDED'
            Write-Host "WARN: No plan prompt provided for augmentation" -ForegroundColor Yellow
        }
    }

    # Write result
    $resultPath = Join-Path $ReplayRoot 'PLAN_CONTRACT_GENERATION.json'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    Write-Host "Plan contract generation result written to $resultPath" -ForegroundColor Green
    return $result
}

function Test-PlanExecutableContract {
    <#
    .SYNOPSIS
    Validates that a generated plan includes executable contract sections.

    .DESCRIPTION
    Checks if plan contains required executable contract elements:
    - Exact field contract
    - State transition ledger
    - Side effect ledger
    - Test assertion template
    #>
    param(
        [string]$ReplayRoot,
        [string]$PlanPath
    )

    if (-not (Test-Path -LiteralPath $PlanPath)) {
        return @{
            valid = $false
            reason = 'plan_file_not_found'
        }
    }

    $plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8

    $requiredSections = @(
        'Exact Field Contract',
        'State Transition Ledger',
        'Side Effect Ledger',
        'Test Assertion Template'
    )

    $missingSections = @()
    foreach ($section in $requiredSections) {
        if ($plan -notmatch [regex]::Escape($section)) {
            $missingSections += $section
        }
    }

    return @{
        valid = ($missingSections.Count -eq 0)
        missing_sections = $missingSections
        required_sections = $requiredSections
        total_sections_found = ($requiredSections.Count - $missingSections.Count)
    }
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Description = 'Experiment 3: Executable Contract Template for Plan Validation'
        ValidationCommands = @(
            'Load EXECUTABLE_CONTRACT_TEMPLATE.md',
            'Augment plan prompt with template',
            'Write PLAN_PROMPT_WITH_CONTRACT.md',
            'Validate generated plan includes required sections'
        )
        ExpectedMetrics = @{
            plan_verification_pass_rate = '80%'
            expected_diff_missing_closure = '0'
            rounds_blocked_at_plan = '≤2/12'
            plans_with_executable_contracts = '≥80%'
        }
        TemplateSections = @(
            'Exact Field Contract',
            'State Transition Ledger',
            'Side Effect Ledger',
            'Test Assertion Template'
        )
    }
    $result | Format-List
    exit 0
}

# Main execution
$result = Invoke-GenerateExecutablePlan -ReplayRoot $ReplayRoot -PlanPrompt $PlanPrompt -PlanPromptPath $PlanPromptPath

exit 0
