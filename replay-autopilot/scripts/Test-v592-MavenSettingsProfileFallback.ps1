#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test v592: Maven settings profile fallback remains project-neutral.

.DESCRIPTION
This regression keeps Maven settings discovery portable:
- config.yaml exposes an optional maven_settings key.
- Run-ReplayLoop.ps1 falls back to project .memory\build-test-profile.yaml.
- The shared runner and this test do not hardcode machine or business-project paths.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ''
    )
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$replayAutopilotRoot = Resolve-Path (Join-Path $scriptRoot '..')
$runnerPath = Join-Path $replayAutopilotRoot 'scripts\Run-ReplayLoop.ps1'
$configPath = Join-Path $replayAutopilotRoot 'config.yaml'
$testPath = $MyInvocation.MyCommand.Path

Write-Host "========================================"
Write-Host "Test v592: Maven Settings Profile Fallback"
Write-Host "========================================"
Write-Host ""

$configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$testText = Get-Content -LiteralPath $testPath -Raw -Encoding UTF8

Write-Host "[Test 1] Verifying config.yaml exposes optional maven_settings..."
$hasMavenSettingsKey = $configText -match '(?m)^maven_settings:\s*'
Assert-True 'config_yaml_exposes_maven_settings' $hasMavenSettingsKey
Write-Host "  PASS: config.yaml exposes maven_settings"

Write-Host "[Test 2] Verifying runner has build-test-profile.yaml fallback..."
$hasProfileFallback = $runnerText.Contains('build-test-profile.yaml')
$readsProjectMemory = $runnerText.Contains(".memory\build-test-profile.yaml")
$readsUtf8 = $runnerText.Contains('-Raw -Encoding UTF8')
Assert-True 'runner_has_profile_fallback' $hasProfileFallback
Assert-True 'runner_reads_project_memory_profile' $readsProjectMemory
Assert-True 'runner_reads_profile_as_utf8' $readsUtf8
Write-Host "  PASS: Runner reads project build-test-profile.yaml fallback as UTF-8"

Write-Host "[Test 3] Verifying runner keeps fallback after explicit config/env resolution..."
$configResolve = $runnerText.IndexOf("Get-ConfigValueOrDefault -Config `$config -Key 'maven_settings'")
$initialResolve = $runnerText.IndexOf('Resolve-MavenSettingsPath -ConfiguredValue $mavenSettings')
$fallbackIndex = $runnerText.IndexOf("profile:build-test-profile.yaml")
Assert-True 'runner_has_config_resolution' ($configResolve -ge 0)
Assert-True 'runner_has_initial_resolve' ($initialResolve -ge 0)
Assert-True 'runner_has_profile_source_marker' ($fallbackIndex -ge 0)
Assert-True 'runner_profile_fallback_after_config_resolution' ($fallbackIndex -gt $initialResolve)
Write-Host "  PASS: Profile fallback occurs after config/env resolution"

Write-Host "[Test 4] Verifying runner still resolves Maven settings and MAVEN_SETTINGS_ARG..."
$hasResolveFunction = $runnerText.Contains('function Resolve-MavenSettingsPath')
$hasResolverCall = $runnerText.Contains('Resolve-MavenSettingsPath -ConfiguredValue')
$hasMavenSegment = $runnerText.Contains('function Get-MavenSettingsCommandSegment')
$hasUtf8Properties = $runnerText.Contains('-Dproject.build.sourceEncoding=UTF-8') -and $runnerText.Contains('-Dfile.encoding=UTF-8')
Assert-True 'runner_has_resolve_function' $hasResolveFunction
Assert-True 'runner_calls_resolve' $hasResolverCall
Assert-True 'runner_has_maven_segment' $hasMavenSegment
Assert-True 'runner_has_utf8_properties' $hasUtf8Properties
Write-Host "  PASS: Runner resolves Maven settings and emits UTF-8 Maven properties"

Write-Host "[Test 5] Verifying shared artifacts do not hardcode machine/project paths..."
$forbiddenPatterns = @(
    ([string]::Concat('D:', '\maven\')),
    ([string]::Concat('D:', '\\maven\\')),
    ([string]::Concat('D:', '\opt\', 'lipei\', 'claim')),
    ([string]::Concat('D:', '\\opt\\', 'lipei\\', 'claim')),
    ([string]::Concat('claim-codex-', 'replay-'))
)
foreach ($pattern in $forbiddenPatterns) {
    Assert-True "runner_no_forbidden_path_$pattern" (-not $runnerText.Contains($pattern))
    Assert-True "test_no_forbidden_path_$pattern" (-not $testText.Contains($pattern))
}
Write-Host "  PASS: Runner and test remain project-neutral"

Write-Host ""
Write-Host "========================================"
Write-Host "All v592 tests PASSED"
Write-Host "========================================"
Write-Host ""

[ordered]@{
    status = 'PASS'
    version = 'v592'
    assertions = @(
        'config_yaml_exposes_maven_settings',
        'runner_has_profile_fallback',
        'runner_profile_fallback_after_config_resolution',
        'runner_has_maven_segment',
        'runner_no_hardcoded_machine_paths'
    )
} | ConvertTo-Json -Depth 5

exit 0
