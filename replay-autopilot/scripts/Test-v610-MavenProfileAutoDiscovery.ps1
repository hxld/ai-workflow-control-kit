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

function New-FakeMaven {
    param([string]$ToolsRoot)

    New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
    $capturePath = Join-Path $ToolsRoot 'mvn-args.log'
    @(
        '@echo off',
        'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-mvn.ps1" %*',
        'exit /b %ERRORLEVEL%'
    ) -join "`r`n" | Set-Content -LiteralPath (Join-Path $ToolsRoot 'mvn.cmd') -Encoding ASCII
    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
$ErrorActionPreference = 'Stop'
$capture = Join-Path $PSScriptRoot 'mvn-args.log'
($Args -join "`n") + "`n---" | Add-Content -LiteralPath $capture -Encoding UTF8
Write-Output '[INFO] BUILD SUCCESS'
exit 0
'@ | Set-Content -LiteralPath (Join-Path $ToolsRoot 'fake-mvn.ps1') -Encoding UTF8
    return $capturePath
}

function New-PlanFixture {
    param([string]$Root)

    $replayRoot = Join-Path $Root 'replay'
    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Encoding UTF8
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-server\src\test\java\sample') | Out-Null
    'class ExistingHarnessTest {}' | Set-Content -LiteralPath (Join-Path $worktree 'example-server\src\test\java\sample\ExistingHarnessTest.java') -Encoding UTF8

    Write-JsonFile (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'example-core/src/main/java/com/acme/Carrier.java'
        target_carrier_line_number = 12
        expected_test_class = 'ExistingHarnessTest'
        expected_test_method = 'shouldCompile'
        side_effects = @('stateful proof row')
        expected_assertions = @('assert side effect')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'example-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 1
            compilation_dry_run_command = "mvn -f $worktree\pom.xml -pl example-server -am test-compile"
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    return [pscustomobject]@{
        ReplayRoot = $replayRoot
        Worktree = $worktree
        PlanResultPath = (Join-Path $replayRoot 'PLAN_RESULT.json')
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runReplayLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$phase0Precheck = Join-Path $scriptRoot 'phase0-precheck.ps1'
$preflightCompilation = Join-Path $scriptRoot 'Invoke-PreflightTestCompilation.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v610-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
$oldAiSettings = $env:AI_WORKFLOW_MAVEN_SETTINGS
$oldMavenSettings = $env:MAVEN_SETTINGS

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $toolsRoot = Join-Path $tempRoot 'tools'
    $settingsPath = Join-Path $tempRoot 'settings.xml'
    '<settings />' | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    $capturePath = New-FakeMaven -ToolsRoot $toolsRoot
    $env:PATH = "$toolsRoot;$oldPath"
    $env:AI_WORKFLOW_MAVEN_SETTINGS = $settingsPath
    $env:MAVEN_SETTINGS = ''

    $runnerText = Get-Content -LiteralPath $runReplayLoop -Raw -Encoding UTF8
    Assert-True 'runner_has_maven_settings_auto_discovery' ($runnerText.Contains('function Resolve-MavenSettingsPath') -and $runnerText.Contains('env:AI_WORKFLOW_MAVEN_SETTINGS')) $runnerText
    Assert-True 'runner_maven_helper_adds_utf8_properties' ($runnerText.Contains("'-Dproject.build.sourceEncoding=UTF-8', '-Dfile.encoding=UTF-8'")) $runnerText
    Assert-True 'runner_plan_materializer_uses_helper' ($runnerText.Contains('$mvnArgs = @(Get-MavenArgumentList -MavenSettings $MavenSettings)')) $runnerText
    Assert-True 'runner_resolves_config_maven_settings' ($runnerText.Contains('$mavenSettings = Resolve-MavenSettingsPath -ConfiguredValue $mavenSettings')) $runnerText
    Assert-True 'runner_has_no_machine_specific_maven_path' (-not $runnerText.Contains('D:\maven\settings\settings.xml')) $runnerText

    Set-Content -LiteralPath $capturePath -Value '' -Encoding UTF8
    $phaseRoot = Join-Path $tempRoot 'phase0\replay'
    $phaseWorktree = Join-Path $tempRoot 'phase0\worktree'
    New-Item -ItemType Directory -Force -Path $phaseRoot, $phaseWorktree | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $phaseWorktree 'pom.xml') -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $phase0Precheck -ReplayRoot $phaseRoot -Worktree $phaseWorktree | Out-Null
    Assert-True 'phase0_precheck_exits_zero' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $captured = Get-Content -LiteralPath $capturePath -Raw -Encoding UTF8
    Assert-True 'phase0_precheck_uses_settings' ($captured.Contains("-s`n$settingsPath")) $captured
    Assert-True 'phase0_precheck_test_compile_uses_am' ($captured.Contains("test-compile`n-pl`nexample-server`n-am")) $captured
    Assert-True 'phase0_precheck_uses_utf8_properties' ($captured.Contains('-Dproject.build.sourceEncoding=UTF-8') -and $captured.Contains('-Dfile.encoding=UTF-8')) $captured

    Set-Content -LiteralPath $capturePath -Value '' -Encoding UTF8
    $preflightRoot = Join-Path $tempRoot 'preflight\replay'
    $preflightWorktree = Join-Path $tempRoot 'preflight\worktree'
    New-Item -ItemType Directory -Force -Path $preflightRoot, $preflightWorktree | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $preflightWorktree 'pom.xml') -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $preflightCompilation -ReplayRoot $preflightRoot -Worktree $preflightWorktree -ProjectRoot $preflightWorktree -MavenCommand (Join-Path $toolsRoot 'mvn.cmd') -TimeoutSeconds 30 | Out-Null
    Assert-True 'preflight_compilation_exits_zero' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $preflight = Get-Content -LiteralPath (Join-Path $preflightRoot 'PREFLIGHT_TEST_COMPILATION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'preflight_records_settings_source' ([string]$preflight.maven_settings_source -eq 'env:AI_WORKFLOW_MAVEN_SETTINGS') ($preflight | ConvertTo-Json -Depth 8)
    $captured = Get-Content -LiteralPath $capturePath -Raw -Encoding UTF8
    Assert-True 'preflight_compilation_uses_settings' ($captured.Contains("-s`n$settingsPath")) $captured
    Assert-True 'preflight_compilation_uses_utf8_properties' ($captured.Contains('-Dproject.build.sourceEncoding=UTF-8') -and $captured.Contains('-Dfile.encoding=UTF-8')) $captured

    $sliceText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
    Assert-True 'slice_prompt_uses_maven_argument_segment' ($sliceText.Contains('MAVEN_SETTINGS_ARG = Get-MavenSettingsCommandSegment -MavenSettings $MavenSettings'))

    [ordered]@{
        status = 'PASS'
        version = 'v610'
        assertions = @(
            'plan_materializer_discovers_maven_settings_and_utf8',
            'phase0_precheck_uses_am_settings_utf8',
            'preflight_compilation_discovers_settings_and_utf8'
        )
    } | ConvertTo-Json -Depth 5
}
finally {
    $env:PATH = $oldPath
    $env:AI_WORKFLOW_MAVEN_SETTINGS = $oldAiSettings
    $env:MAVEN_SETTINGS = $oldMavenSettings
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
