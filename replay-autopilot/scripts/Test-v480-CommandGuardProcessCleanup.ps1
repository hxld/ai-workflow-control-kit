param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$invokeAgentPath = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("command-guard-process-test-" + [guid]::NewGuid().ToString('N'))
$children = New-Object System.Collections.Generic.List[int]

try {
    $invokeText = Get-Content -LiteralPath $invokeAgentPath -Raw -Encoding UTF8
    $functionBlock = [regex]::Match(
        $invokeText,
        '(?s)function ConvertTo-NormalizedPathText.+?(?=function Test-AgentCompletionFileReady)'
    ).Value
    Assert-True 'guard_functions_extractable' (-not [string]::IsNullOrWhiteSpace($functionBlock))
    Invoke-Expression $functionBlock

    $protectedRoot = Join-Path $tempRoot 'protected-root'
    $worktree = Join-Path $tempRoot 'worktree'
    $guardLog = Join-Path $tempRoot 'command-guard.jsonl'
    New-Item -ItemType Directory -Force -Path $protectedRoot, $worktree | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $protectedRoot 'pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Encoding UTF8

    $protectedPom = Join-Path $protectedRoot 'pom.xml'
    $protectedPomCommand = "Start-Sleep -Seconds 120 # mvn -s D:\maven\settings\settings.xml -f `"$protectedPom`" -pl claim-server -am test"
    $protectedPomProcess = Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $protectedPomCommand) -WindowStyle Hidden -PassThru
    $children.Add([int]$protectedPomProcess.Id) | Out-Null
    Start-Sleep -Seconds 1
    Assert-True 'protected_pom_fixture_started' ($null -ne (Get-Process -Id $protectedPomProcess.Id -ErrorAction SilentlyContinue))

    $protectedPomViolations = @(Invoke-ReplayCommandGuardCleanup -WorkDir $worktree -ProtectedRoot $protectedRoot -GuardLogPath $guardLog -Attempts 4)
    Assert-True 'protected_pom_violation_detected' ((@($protectedPomViolations.reason) -join ' ') -match 'protected_root_pom_forbidden')
    Start-Sleep -Seconds 1
    Assert-True 'protected_pom_process_killed' ($null -eq (Get-Process -Id $protectedPomProcess.Id -ErrorAction SilentlyContinue))

    $deployCommand = "Start-Sleep -Seconds 120 # mvn deploy -DskipTests"
    $deployProcess = Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $deployCommand) -WindowStyle Hidden -PassThru
    $children.Add([int]$deployProcess.Id) | Out-Null
    Start-Sleep -Seconds 1
    Assert-True 'deploy_fixture_started' ($null -ne (Get-Process -Id $deployProcess.Id -ErrorAction SilentlyContinue))

    $deployViolations = @(Invoke-ReplayCommandGuardCleanup -WorkDir $worktree -ProtectedRoot $protectedRoot -GuardLogPath $guardLog -Attempts 4)
    Assert-True 'deploy_violation_detected' ((@($deployViolations.reason) -join ' ') -match 'maven_deploy_forbidden')
    Start-Sleep -Seconds 1
    Assert-True 'deploy_process_killed' ($null -eq (Get-Process -Id $deployProcess.Id -ErrorAction SilentlyContinue))

    $guardLogText = Get-Content -LiteralPath $guardLog -Raw -Encoding UTF8
    Assert-True 'guard_log_records_protected_pom' ($guardLogText -match 'protected_root_pom_forbidden')
    Assert-True 'guard_log_records_deploy' ($guardLogText -match 'maven_deploy_forbidden')

    [ordered]@{
        status = 'PASS'
        assertions = 9
        guard_log = $guardLog
    } | ConvertTo-Json -Depth 4
} finally {
    foreach ($childId in @($children.ToArray())) {
        $proc = Get-Process -Id $childId -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $childId -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
