#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for unconditional Phase1 Maven -pl/-am guard guidance.

.DESCRIPTION
The r05 retry failed because the first attempt ended by max-turns, so retry did
not inherit command-guard-specific guidance before running a forbidden
`mvn compile -pl ...` command. Retry prompts must always include the baseline
Maven guard guidance, and the slice executor prompt must name the common
forbidden quick-compile shape explicitly.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$sliceLoopPath = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$phase1PromptPath = Join-Path $autopilotRoot 'prompts\phase1-slice-executor.prompt.md'

$sliceLoopText = Get-Content -LiteralPath $sliceLoopPath -Raw -Encoding UTF8
$phase1PromptText = Get-Content -LiteralPath $phase1PromptPath -Raw -Encoding UTF8

Assert-True 'default_maven_guard_function_exists' ($sliceLoopText -match 'function\s+Get-DefaultMavenCommandGuardGuidance')
Assert-True 'default_guard_names_forbidden_compile_shape' ($sliceLoopText -match 'mvn compile -pl <module>')
Assert-True 'default_guard_requires_am' ($sliceLoopText -match 'MUST include `-am`')
Assert-True 'retry_builds_default_guard_section' ($sliceLoopText -match '\$defaultMavenGuardSection\s*=\s*Get-DefaultMavenCommandGuardGuidance')
Assert-True 'retry_preamble_places_default_guard_before_previous_guard_section' ($sliceLoopText -match '\$defaultMavenGuardSection,\s*\r?\n\s*\$guardSection,')

Assert-True 'phase1_prompt_names_forbidden_compile_shape' ($phase1PromptText -match 'mvn compile -pl <module>')
Assert-True 'phase1_prompt_names_forbidden_test_compile_shape' ($phase1PromptText -match 'mvn test-compile -pl <module>')
Assert-True 'phase1_prompt_provides_safe_am_shape' ($phase1PromptText -match '-pl <module> -am test-compile')

Write-Host 'PASS: v628 phase1 Maven guard preamble'
