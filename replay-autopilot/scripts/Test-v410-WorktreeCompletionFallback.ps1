param()

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'
$scriptText = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

$checks = @(
    [pscustomobject]@{
        Name = 'completion_ready_uses_workdir_fallback'
        Pass = $scriptText -match [regex]::Escape('Join-Path $script:workDirFull (Split-Path -Leaf $full)')
    },
    [pscustomobject]@{
        Name = 'fallback_copies_to_primary_completion_path'
        Pass = $scriptText -match 'Copy-Item\s+-LiteralPath\s+\$fallback\s+-Destination\s+\$full\s+-Force'
    },
    [pscustomobject]@{
        Name = 'receive_job_completion_check_delegates_to_fallback_helper'
        Pass = $scriptText -match 'return\s+\(Test-AgentCompletionFileReady\s+-Path\s+\$Path\)'
    },
    [pscustomobject]@{
        Name = 'missing_completion_final_gate_uses_same_helper'
        Pass = $scriptText -match 'Test-AgentCompletionFileReady\s+\$CompletionPath'
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
$checks | ConvertTo-Json -Depth 3

if ($failed.Count -gt 0) {
    Write-Host "FAILED checks: $($failed.Name -join ', ')"
    exit 1
}

Write-Host 'v410 worktree completion fallback checks passed.'
exit 0
