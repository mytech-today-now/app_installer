#Requires -Version 5.1

# No O&O helper release is enabled until an immutable source and a separately
# reviewed digest or signer are recorded here. The upstream helper inspected also
# evaluates a mutable logging script and downloads an executable without verifying its signature.
$script:OOShutUp10Release = [PSCustomObject]@{
    Version         = $null
    Uri             = $null
    Sha256          = $null
    SignerThumbprint = $null
}
$script:OOExecutionPolicyRecoveryMessage = 'PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator.'

function Get-OOShutUp10PinnedRelease {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Version         = $script:OOShutUp10Release.Version
        Uri             = $script:OOShutUp10Release.Uri
        Sha256          = $script:OOShutUp10Release.Sha256
        SignerThumbprint = $script:OOShutUp10Release.SignerThumbprint
    }
}

function Test-OOImmutableReleaseUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    try {
        $parsedUri = [System.Uri]::new($Uri, [System.UriKind]::Absolute)
        if ($parsedUri.Scheme -ne 'https' -or $parsedUri.Host -ne 'raw.githubusercontent.com') {
            return $false
        }

        if ($parsedUri.Query -or $parsedUri.Fragment) {
            return $false
        }

        return $parsedUri.AbsolutePath -match '^/mytech-today-now/OO/[0-9A-Fa-f]{40}/Install-OOShutUp10\.ps1$'
    }
    catch {
        return $false
    }
}

function Set-OOPrivateDirectoryAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'private-directory-acl-unavailable'
    }

    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $directorySecurity = New-Object System.Security.AccessControl.DirectorySecurity
    $directorySecurity.SetAccessRuleProtection($true, $false)

    $inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow

    $principals = @(
        $currentIdentity.User,
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')),
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544'))
    )

    foreach ($principal in $principals) {
        if ($principal) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $principal,
                $rights,
                $inheritance,
                $propagation,
                $allow
            )
            [void]$directorySecurity.AddAccessRule($rule)
        }
    }

    $directorySecurity.SetOwner($currentIdentity.User)
    Set-Acl -LiteralPath $LiteralPath -AclObject $directorySecurity -ErrorAction Stop

    $verifiedSecurity = Get-Acl -LiteralPath $LiteralPath -ErrorAction Stop
    if (-not $verifiedSecurity.AreAccessRulesProtected) {
        throw 'temporary-directory-acl-not-protected'
    }

    $allowedSids = @($currentIdentity.User.Value, 'S-1-5-18', 'S-1-5-32-544')
    $verifiedRules = $verifiedSecurity.GetAccessRules(
        $true,
        $true,
        [System.Security.Principal.SecurityIdentifier]
    )
    foreach ($rule in $verifiedRules) {
        if ($rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
            $rule.IdentityReference.Value -notin $allowedSids) {
            throw 'temporary-directory-acl-has-unapproved-principal'
        }
    }
}

function New-OOPrivateTempDirectory {
    [CmdletBinding()]
    param(
        [string]$TempRoot = [System.IO.Path]::GetTempPath()
    )

    $root = [System.IO.Path]::GetFullPath($TempRoot)
    if (-not [System.IO.Directory]::Exists($root)) {
        throw 'temporary-root-unavailable'
    }

    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $directoryPath = Join-Path $root ('app-installer-ooshutup10-' + [Guid]::NewGuid().ToString('N'))
        try {
            # New-Item without -Force fails if another invocation already owns this name.
            New-Item -ItemType Directory -Path $directoryPath -ErrorAction Stop | Out-Null
        }
        catch {
            if ([System.IO.Directory]::Exists($directoryPath)) {
                continue
            }

            throw 'temporary-directory-create-failed'
        }

        try {
            Set-OOPrivateDirectoryAcl -LiteralPath $directoryPath
            return $directoryPath
        }
        catch {
            Remove-Item -LiteralPath $directoryPath -Recurse -Force -ErrorAction SilentlyContinue
            throw 'temporary-directory-protection-failed'
        }
    }

    throw 'temporary-directory-collision'
}

function Get-OOResponseBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $request = [System.Net.WebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $response = $null
    $responseStream = $null
    $memoryStream = $null

    try {
        $response = $request.GetResponse()
        if ($response -is [System.Net.HttpWebResponse] -and $response.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw 'http-status-failed'
        }

        $responseStream = $response.GetResponseStream()
        $memoryStream = New-Object System.IO.MemoryStream
        $responseStream.CopyTo($memoryStream)
        return ,$memoryStream.ToArray()
    }
    finally {
        if ($memoryStream) { $memoryStream.Dispose() }
        if ($responseStream) { $responseStream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Write-OOFileCreateNew {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $fileStream = New-Object System.IO.FileStream(
        $LiteralPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )

    try {
        $fileStream.Write($Bytes, 0, $Bytes.Length)
        $fileStream.Flush($true)
    }
    finally {
        $fileStream.Dispose()
    }
}

function Get-OOFileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $stream = [System.IO.File]::OpenRead($LiteralPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-', '')
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function Get-OOFileSha256FromStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        return [System.BitConverter]::ToString($sha256.ComputeHash($Stream)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
        $Stream.Position = 0
    }
}

function Test-OOAuthenticodeSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedThumbprint
    )

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $LiteralPath -ErrorAction Stop
        return ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid -and
            $signature.SignerCertificate -and
            [string]::Equals(
                ($signature.SignerCertificate.Thumbprint -replace '\s', ''),
                ($ExpectedThumbprint -replace '\s', ''),
                [System.StringComparison]::OrdinalIgnoreCase
            ))
    }
    catch {
        return $false
    }
}

function Start-OOVerifiedChildProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [string[]]$ScriptArguments = @('-NonInteractive')
    )

    foreach ($argument in $ScriptArguments) {
        if ($argument -notmatch '^-[A-Za-z][A-Za-z0-9-]*$') {
            throw 'child-argument-invalid'
        }
    }

    $hostPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    if (-not $hostPath -or -not [System.IO.File]::Exists($hostPath)) {
        throw 'powershell-host-unavailable'
    }

    $quotedScriptPath = '"' + $LiteralPath.Replace('"', '\"') + '"'
    $argumentString = '-NoProfile -NonInteractive -File ' + $quotedScriptPath
    if ($ScriptArguments.Count -gt 0) {
        $argumentString += ' ' + ($ScriptArguments -join ' ')
    }

    $standardErrorPath = Join-Path (Split-Path -Parent $LiteralPath) ('.ooshutup-child-stderr-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $child = Start-Process -FilePath $hostPath -ArgumentList $argumentString -WindowStyle Hidden -Wait -PassThru -RedirectStandardError $standardErrorPath -ErrorAction Stop
        $standardError = if ([System.IO.File]::Exists($standardErrorPath)) {
            [System.IO.File]::ReadAllText($standardErrorPath)
        }
        else {
            ''
        }
        $policyBlocked = ($child.ExitCode -ne 0) -and ($standardError -match '(?im)(execution policy|running scripts is disabled|not digitally signed)')

        return [PSCustomObject]@{
            ExitCode      = [int]$child.ExitCode
            PolicyBlocked = [bool]$policyBlocked
        }
    }
    finally {
        if ([System.IO.File]::Exists($standardErrorPath)) {
            Remove-Item -LiteralPath $standardErrorPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-VerifiedOOShutUp10Script {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Uri,

        [AllowEmptyString()]
        [string]$ExpectedSha256,

        [string]$ExpectedSignerThumbprint,

        [string[]]$ScriptArguments = @('-NonInteractive'),

        [string]$TempRoot,

        [scriptblock]$DownloadScript,

        [scriptblock]$ExecutorScript,

        [scriptblock]$SignatureVerifier
    )

    $result = [PSCustomObject]@{
        Success             = $false
        DownloadStatus      = 'not-attempted'
        VerificationStatus  = 'not-attempted'
        InstallationStatus  = 'not-started'
        ExitCode            = $null
        FailureReason       = $null
        PolicyBlocked       = $false
        RecoveryMessage     = $null
        CleanupStatus       = 'not-required'
        TempDirectory       = $null
    }
    $tempDirectory = $null
    $verifiedFileLock = $null
    $tempRootFull = $null

    try {
        if ([string]::IsNullOrWhiteSpace($Uri) -or $ExpectedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            $result.VerificationStatus = 'unverified'
            $result.FailureReason = 'release-not-configured'
        }
        elseif (-not (Test-OOImmutableReleaseUri -Uri $Uri)) {
            $result.VerificationStatus = 'rejected'
            $result.FailureReason = 'source-not-immutable'
        }
        elseif ($ExpectedSignerThumbprint -and $ExpectedSignerThumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
            $result.VerificationStatus = 'rejected'
            $result.FailureReason = 'invalid-signer-pin'
        }
        else {
            $effectiveTempRoot = if ($TempRoot) { $TempRoot } else { [System.IO.Path]::GetTempPath() }
            $tempRootFull = [System.IO.Path]::GetFullPath($effectiveTempRoot)
            $tempArguments = @{}
            $tempArguments.TempRoot = $tempRootFull
            $tempDirectory = New-OOPrivateTempDirectory @tempArguments
            $result.TempDirectory = $tempDirectory
            $result.CleanupStatus = 'pending'
            $result.DownloadStatus = 'pending'

            if ($DownloadScript) {
                $responseBytes = & $DownloadScript $Uri
            }
            else {
                $responseBytes = Get-OOResponseBytes -Uri $Uri
            }

            if ($responseBytes -isnot [byte[]] -or $responseBytes.Length -eq 0) {
                $result.DownloadStatus = 'invalid-output'
                $result.VerificationStatus = 'rejected'
                $result.FailureReason = 'invalid-download-output'
            }
            else {
                $scriptPath = Join-Path $tempDirectory 'Install-OOShutUp10.ps1'
                Write-OOFileCreateNew -Bytes $responseBytes -LiteralPath $scriptPath
                $result.DownloadStatus = 'downloaded'

                $actualSha256 = Get-OOFileSha256 -LiteralPath $scriptPath
                if (-not [string]::Equals($actualSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $result.VerificationStatus = 'rejected'
                    $result.FailureReason = 'digest-mismatch'
                }
                else {
                    # Hold a read-only handle through child completion to prevent a
                    # same-user process from replacing or deleting the verified file.
                    $verifiedFileLock = [System.IO.File]::Open(
                        $scriptPath,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::Read
                    )
                    $lockedSha256 = Get-OOFileSha256FromStream -Stream $verifiedFileLock
                    if (-not [string]::Equals($lockedSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $result.VerificationStatus = 'rejected'
                        $result.FailureReason = 'digest-changed-before-execution'
                    }
                    else {
                        $signatureValid = $true
                        if ($ExpectedSignerThumbprint) {
                            if ($SignatureVerifier) {
                                $signatureValid = [bool](& $SignatureVerifier $scriptPath $ExpectedSignerThumbprint)
                            }
                            else {
                                $signatureValid = Test-OOAuthenticodeSignature -LiteralPath $scriptPath -ExpectedThumbprint $ExpectedSignerThumbprint
                            }
                        }

                        if (-not $signatureValid) {
                            $result.VerificationStatus = 'rejected'
                            $result.FailureReason = 'signature-invalid'
                        }
                        else {
                            $parseErrors = $null
                            [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
                            if ($parseErrors -and $parseErrors.Count -gt 0) {
                                $result.VerificationStatus = 'rejected'
                                $result.FailureReason = 'invalid-powershell-output'
                            }
                            else {
                                $result.VerificationStatus = 'verified'
                                $result.InstallationStatus = 'running'

                                if ($ExecutorScript) {
                                    $executionResult = & $ExecutorScript $scriptPath $ScriptArguments
                                }
                                else {
                                    $executionResult = Start-OOVerifiedChildProcess -LiteralPath $scriptPath -ScriptArguments $ScriptArguments
                                }

                                $exitCodeProperty = if ($executionResult -and $executionResult.PSObject) {
                                    $executionResult.PSObject.Properties['ExitCode']
                                }
                                else {
                                    $null
                                }
                                if ($null -ne $exitCodeProperty) {
                                    $result.ExitCode = [int]$exitCodeProperty.Value
                                }
                                elseif ($executionResult -is [int]) {
                                    $result.ExitCode = $executionResult
                                }
                                $policyBlockedProperty = if ($executionResult -and $executionResult.PSObject) {
                                    $executionResult.PSObject.Properties['PolicyBlocked']
                                }
                                else {
                                    $null
                                }
                                if ($null -ne $policyBlockedProperty -and [bool]$policyBlockedProperty.Value) {
                                    $result.PolicyBlocked = $true
                                }

                                if ($null -eq $result.ExitCode) {
                                    $result.InstallationStatus = 'unknown'
                                    $result.FailureReason = 'child-result-unavailable'
                                }
                                elseif ($result.ExitCode -eq 0 -or $result.ExitCode -eq 30) {
                                    $result.InstallationStatus = 'succeeded'
                                    $result.Success = $true
                                }
                                else {
                                    $result.InstallationStatus = 'failed'
                                    if ($result.PolicyBlocked) {
                                        $result.FailureReason = 'execution-policy-blocked'
                                        $result.RecoveryMessage = $script:OOExecutionPolicyRecoveryMessage
                                    }
                                    else {
                                        $result.FailureReason = 'child-nonzero-exit'
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    catch [System.OperationCanceledException] {
        if ($result.DownloadStatus -eq 'pending') { $result.DownloadStatus = 'cancelled' }
        if ($result.VerificationStatus -eq 'not-attempted') { $result.VerificationStatus = 'not-verified' }
        if ($result.InstallationStatus -eq 'running') {
            $result.InstallationStatus = 'unknown'
            $result.FailureReason = 'child-execution-cancelled'
        }
        else {
            $result.FailureReason = 'cancelled'
        }
    }
    catch {
        if ($result.DownloadStatus -eq 'pending') {
            $result.DownloadStatus = 'failed'
            if ($result.VerificationStatus -eq 'not-attempted') { $result.VerificationStatus = 'not-verified' }
            $result.FailureReason = 'download-failed'
        }
        elseif ($result.InstallationStatus -eq 'running') {
            $result.InstallationStatus = 'unknown'
            $result.FailureReason = 'child-execution-failed'
        }
        else {
            if ($_.Exception.Message -eq 'temporary-directory-protection-failed' -or
                $_.Exception.Message -eq 'temporary-root-unavailable' -or
                $_.Exception.Message -eq 'temporary-directory-create-failed') {
                $result.FailureReason = 'temporary-workspace-unavailable'
            }
            else {
                $result.FailureReason = 'unexpected-error'
            }
        }
    }
    finally {
        if ($verifiedFileLock) {
            try {
                $verifiedFileLock.Dispose()
            }
            catch {
                $result.CleanupStatus = 'failed'
                $result.Success = $false
                $result.FailureReason = 'cleanup-failed'
                if ($result.InstallationStatus -eq 'succeeded') {
                    $result.InstallationStatus = 'unknown'
                }
            }
        }

        if ($tempDirectory) {
            try {
                $fullDirectory = [System.IO.Path]::GetFullPath($tempDirectory)
                $expectedLeaf = Split-Path -Leaf $fullDirectory
                $actualParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $fullDirectory))
                if ($expectedLeaf -notmatch '^app-installer-ooshutup10-[0-9a-f]{32}$' -or
                    -not [string]::Equals($actualParent, $tempRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'temporary-path-invalid'
                }

                Remove-Item -LiteralPath $fullDirectory -Recurse -Force -ErrorAction Stop
                $result.CleanupStatus = 'cleaned'
            }
            catch {
                $result.CleanupStatus = 'failed'
                $result.Success = $false
                $result.FailureReason = 'cleanup-failed'
                if ($result.InstallationStatus -eq 'succeeded') {
                    $result.InstallationStatus = 'unknown'
                }
            }
        }
    }

    return $result
}

Export-ModuleMember -Function Get-OOShutUp10PinnedRelease, Invoke-VerifiedOOShutUp10Script
