$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Invoke-PreflightTestCompilation.ps1'
$content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Contains $content 'function\s+Convert-ToWorktreeEquivalentPath' 'Missing worktree path remap helper.'
Assert-Contains $content 'Convert-ToWorktreeEquivalentPath\s+-PathValue\s+\$rootPom\s+-ProjectRootFull\s+\$projectRootFull\s+-WorktreeFull\s+\$worktreeFull' 'root_pom is not passed through the worktree remap helper.'
Assert-Contains $content 'profile_root_pom_remapped_to_worktree' 'Missing audit warning for remapped profile root_pom.'
Assert-Contains $content '\$result\.root_pom_used\s*=\s*if\s*\(\$rootPom\)' 'Preflight result must record the remapped root_pom.'
Assert-Contains $content '\$mavenArgs\s*=\s*@\(''-f'',\s*\$rootPom\)\s*\+\s*\$mavenArgs' 'Maven -f argument must use the remapped root_pom variable.'

Write-Host 'Test-v411-PreflightWorktreePomRemap: PASS'
