function Get-StartupHelperSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $content = [System.IO.File]::ReadAllText($LiteralPath)
    $normalizedContent = $content -replace "`r`n?", "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedContent)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        return [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Test-StartupHelperFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256
    )

    $result = [PSCustomObject]@{
        Verified = $false
        Reason   = 'unavailable'
        Path     = $null
    }

    if ($ExpectedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        $result.Reason = 'invalid-pin'
        return $result
    }

    try {
        if (-not [System.IO.File]::Exists($LiteralPath)) {
            $result.Reason = 'missing'
            return $result
        }

        $actualSha256 = Get-StartupHelperSha256 -LiteralPath $LiteralPath
        if (-not [string]::Equals($actualSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Reason = 'mismatch'
            return $result
        }

        $result.Verified = $true
        $result.Reason = 'verified'
        $result.Path = [System.IO.Path]::GetFullPath($LiteralPath)
    }
    catch {
        # Do not expose paths, content, or exception details in startup diagnostics.
        $result.Reason = 'unavailable'
    }

    return $result
}

Export-ModuleMember -Function Get-StartupHelperSha256, Test-StartupHelperFile
