function Resolve-PythonLauncher {
    $candidates = @(
        [pscustomobject]@{ Command = 'python'; Arguments = @() },
        [pscustomobject]@{ Command = 'py'; Arguments = @('-3') },
        [pscustomobject]@{ Command = 'python3'; Arguments = @() }
    )

    foreach ($candidate in $candidates) {
        $commandInfo = Get-Command $candidate.Command -ErrorAction SilentlyContinue
        if ($null -eq $commandInfo) { continue }

        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $versionOutput = & $candidate.Command @($candidate.Arguments + @('--version')) 2>&1
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference

        $versionText = ($versionOutput | Out-String).Trim()
        if ($exitCode -eq 0 -and $versionText -match '^Python\s+3\.') {
            return [pscustomobject]@{
                Command = $candidate.Command
                Arguments = @($candidate.Arguments)
                Version = $versionText
            }
        }
    }

    throw 'No usable Python 3 launcher found. Tried python, py -3, python3.'
}
