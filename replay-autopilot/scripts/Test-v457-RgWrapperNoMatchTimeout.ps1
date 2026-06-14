param(
    [string]$RepoRoot = "D:\opt\claim",
    [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rgCmd = Join-Path $toolRoot 'tools\rg.cmd'
if (-not (Test-Path -LiteralPath $rgCmd)) {
    throw "rg.cmd not found: $rgCmd"
}
if (-not (Test-Path -LiteralPath $RepoRoot)) {
    throw "RepoRoot not found: $RepoRoot"
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
$psi.Arguments = ('/d /s /c ""{0}" "__definitely_no_match_v457__" --glob "*.java" -l"' -f $rgCmd)
$psi.WorkingDirectory = $RepoRoot
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    throw "rg.cmd no-match invocation did not exit within $TimeoutSeconds seconds"
}

$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()

$assertions = @()
$assertions += [pscustomobject]@{
    name = 'no_match_exits_with_code_1'
    pass = ($proc.ExitCode -eq 1)
    detail = "exit=$($proc.ExitCode)"
}
$assertions += [pscustomobject]@{
    name = 'no_match_stdout_is_empty'
    pass = ([string]::IsNullOrWhiteSpace($stdout))
    detail = "stdout_length=$($stdout.Length)"
}
$assertions += [pscustomobject]@{
    name = 'no_match_stderr_is_empty_or_nonblocking'
    pass = ($stderr.Length -lt 2000)
    detail = "stderr_length=$($stderr.Length)"
}

$failed = @($assertions | Where-Object { -not $_.pass })
if ($failed.Count -gt 0) {
    $assertions | ConvertTo-Json -Depth 4
    throw "Test-v457-RgWrapperNoMatchTimeout failed"
}

$assertions | ConvertTo-Json -Depth 4
