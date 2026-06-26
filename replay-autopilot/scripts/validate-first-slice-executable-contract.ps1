param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$Slice = 1,
    [string]$Worktree = '',
    [string]$MavenSettings = '',
    [string]$Contract = '',
    [switch]$Regenerate
)

$argsList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'validate-first-slice-contract.ps1'),
    '-ReplayRoot', $ReplayRoot,
    '-Slice', [string]$Slice
)
if (-not [string]::IsNullOrWhiteSpace($Worktree)) { $argsList += @('-Worktree', $Worktree) }
if (-not [string]::IsNullOrWhiteSpace($MavenSettings)) { $argsList += @('-MavenSettings', $MavenSettings) }
if (-not [string]::IsNullOrWhiteSpace($Contract)) { $argsList += @('-Contract', $Contract) }
if ($Regenerate) { $argsList += '-Regenerate' }

& powershell @argsList
exit $LASTEXITCODE
