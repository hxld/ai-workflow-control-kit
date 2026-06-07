param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Test-WriteFails {
    param([string]$Path)
    try {
        'blocked' | Set-Content -LiteralPath (Join-Path $Path 'blocked.txt') -Encoding UTF8
        return $false
    } catch {
        return $true
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bridgeScript = Join-Path $scriptRoot 'Start-AgentBridge.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('protected-root-write-deny-{0}' -f ([guid]::NewGuid().ToString('N')))
$protectedRoot = Join-Path $tempRoot 'protected-root'
$bridgeRoot = Join-Path $tempRoot 'bridge'
$archiveRoot = Join-Path $tempRoot 'runs'
$promptPath = Join-Path $tempRoot 'initial.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        bridge_script = $bridgeScript
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $protectedRoot | Out-Null
    & git -C $protectedRoot init | Out-Null
    'tracked' | Set-Content -LiteralPath (Join-Path $protectedRoot 'tracked.txt') -Encoding UTF8
    & git -C $protectedRoot add tracked.txt | Out-Null
    & git -C $protectedRoot -c user.name=test -c user.email=test@example.com commit -m init | Out-Null
    Set-Content -LiteralPath $promptPath -Value 'No-op prompt.' -Encoding UTF8

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = "${identity}:(OI)(CI)(W,D)"
    & icacls $protectedRoot /deny $rule | Out-Null
    Assert-True (Test-WriteFails -Path $protectedRoot) 'Explicit deny should block writes'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $promptPath | Out-Null

    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action RestoreProtectedAccess `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ProtectedGitRoots $protectedRoot `
        -ForceUnlock | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'RestoreProtectedAccess should exit 0'

    'allowed' | Set-Content -LiteralPath (Join-Path $protectedRoot 'allowed.txt') -Encoding UTF8
    Assert-True (Test-Path -LiteralPath (Join-Path $protectedRoot 'allowed.txt')) 'Write should pass after restore'

    $validateOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action ValidateOnly `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ProtectedGitRoots $protectedRoot `
        -UseProtectedRootWriteDeny
    $validateJson = ($validateOutput | Out-String) | ConvertFrom-Json
    Assert-True ($validateJson.protected_root_write_deny -eq 'blocked_requires_allow') 'ValidateOnly should block unsafe write-deny without explicit allow'

    $validateAllowedOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action ValidateOnly `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ProtectedGitRoots $protectedRoot `
        -UseProtectedRootWriteDeny `
        -AllowUnsafeProtectedRootWriteDeny
    $validateAllowedJson = ($validateAllowedOutput | Out-String) | ConvertFrom-Json
    Assert-True ($validateAllowedJson.protected_root_write_deny -eq 'enabled') 'ValidateOnly should expose enabled write-deny only with explicit allow'

    [ordered]@{
        status = 'PASS'
        assertions = 5
        cases = @(
            'icacls_write_deny_blocks_current_user',
            'restore_protected_access_removes_deny',
            'validate_only_blocks_unsafe_write_deny_without_allow',
            'validate_only_reports_write_deny_enabled_with_allow'
        )
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 8
} finally {
    if (Test-Path -LiteralPath $protectedRoot) {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls $protectedRoot /remove:d $identity *> $null
    }
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolved = Resolve-AbsolutePath $tempRoot
        $tempBase = Resolve-AbsolutePath ([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refuse to delete temp outside temp root: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
