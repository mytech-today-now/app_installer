#Requires -Version 5.1

# No Belarc release is enabled until its immutable source, SHA-256 digest, and
# Authenticode signer thumbprint are independently reviewed and recorded here.
$script:BelarcInstallerRelease = [PSCustomObject]@{
    Version          = $null
    Uri              = $null
    Sha256           = $null
    SignerThumbprint = $null
}

function Get-BelarcInstallerPinnedRelease {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Version          = $script:BelarcInstallerRelease.Version
        Uri              = $script:BelarcInstallerRelease.Uri
        Sha256           = $script:BelarcInstallerRelease.Sha256
        SignerThumbprint = $script:BelarcInstallerRelease.SignerThumbprint
    }
}

function Test-BelarcImmutableReleaseUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    try {
        $parsedUri = [System.Uri]::new($Uri, [System.UriKind]::Absolute)
        if ($parsedUri.Scheme -cne 'https' -or
            $parsedUri.Host -ine 'downloads.belarc.com' -or
            $parsedUri.Port -ne 443 -or
            $parsedUri.UserInfo -or
            $parsedUri.Query -or
            $parsedUri.Fragment) {
            return $false
        }

        $pathMatch = [regex]::Match(
            $parsedUri.AbsolutePath,
            '^/advisor/releases/(?<release>[A-Za-z0-9][A-Za-z0-9._-]*)/advisorinstaller\.exe$'
        )
        if (-not $pathMatch.Success) {
            return $false
        }

        return $pathMatch.Groups['release'].Value -notmatch '^(?i:latest|current|stable)$'
    }
    catch {
        return $false
    }
}

function Set-BelarcPrivateDirectoryAcl {
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

function New-BelarcPrivateTempDirectory {
    [CmdletBinding()]
    param(
        [string]$TempRoot = [System.IO.Path]::GetTempPath()
    )

    $root = [System.IO.Path]::GetFullPath($TempRoot)
    if (-not [System.IO.Directory]::Exists($root)) {
        throw 'temporary-root-unavailable'
    }

    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $directoryPath = Join-Path $root ('app-installer-belarc-' + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $directoryPath -ErrorAction Stop | Out-Null
        }
        catch {
            if ([System.IO.Directory]::Exists($directoryPath)) {
                continue
            }

            throw 'temporary-directory-create-failed'
        }

        try {
            Set-BelarcPrivateDirectoryAcl -LiteralPath $directoryPath
            return $directoryPath
        }
        catch {
            try {
                [System.IO.Directory]::Delete($directoryPath, $false)
            }
            catch {
            }
            throw 'temporary-directory-protection-failed'
        }
    }

    throw 'temporary-directory-collision'
}

function Get-BelarcResponseBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.AllowAutoRedirect = $false
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $response = $null
    $responseStream = $null
    $memoryStream = $null

    try {
        $response = $request.GetResponse()
        if ($response -is [System.Net.HttpWebResponse] -and
            $response.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw 'http-status-failed'
        }
        if (-not [string]::Equals(
                $response.ResponseUri.AbsoluteUri,
                ([System.Uri]::new($Uri, [System.UriKind]::Absolute)).AbsoluteUri,
                [System.StringComparison]::Ordinal
            )) {
            throw 'source-changed-during-download'
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

function Write-BelarcFileCreateNew {
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

function Get-BelarcFileSha256 {
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

function Get-BelarcFileSha256FromStream {
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

function Test-BelarcAuthenticodeSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedThumbprint
    )

    try {
        $signature = Get-AuthenticodeSignature -FilePath $LiteralPath -ErrorAction Stop
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

function Start-BelarcVerifiedChildProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [string[]]$InstallerArguments = @('/S')
    )

    $process = Start-Process -FilePath $LiteralPath -ArgumentList $InstallerArguments -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
    return [PSCustomObject]@{ ExitCode = [int]$process.ExitCode }
}

function Invoke-VerifiedBelarcInstaller {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Uri,

        [AllowEmptyString()]
        [string]$ExpectedSha256,

        [AllowEmptyString()]
        [string]$ExpectedSignerThumbprint,

        [string]$TempRoot,

        [scriptblock]$DownloadScript,

        [scriptblock]$SignatureVerifier,

        [scriptblock]$ExecutorScript
    )

    $result = [PSCustomObject]@{
        Success                = $false
        DownloadStatus         = 'not-attempted'
        VerificationStatus     = 'not-verified'
        InstallationStatus     = 'not-started'
        ExitCode               = $null
        FailureReason          = $null
        CleanupStatus          = 'not-required'
        TempDirectory          = $null
        StagedFilePath         = $null
        Message                = $null
    }
    $tempDirectory = $null
    $stagedFilePath = $null
    $verifiedFileLock = $null
    $tempRootFull = $null

    try {
        if ([string]::IsNullOrWhiteSpace($Uri) -or
            [string]::IsNullOrWhiteSpace($ExpectedSha256) -or
            [string]::IsNullOrWhiteSpace($ExpectedSignerThumbprint)) {
            $result.FailureReason = 'release-not-configured'
            $result.Message = 'Belarc installer is not verified. No download or installation was attempted.'
        }
        elseif ($ExpectedSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
            $ExpectedSignerThumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
            $result.VerificationStatus = 'rejected'
            $result.FailureReason = 'invalid-trust-pin'
            $result.Message = 'Belarc installer trust pins are invalid. No download or installation was attempted.'
        }
        elseif (-not (Test-BelarcImmutableReleaseUri -Uri $Uri)) {
            $result.VerificationStatus = 'rejected'
            $result.FailureReason = 'source-not-immutable'
            $result.Message = 'Belarc installer source is not an immutable release URL. No download or installation was attempted.'
        }
        else {
            $effectiveTempRoot = if ($TempRoot) { $TempRoot } else { [System.IO.Path]::GetTempPath() }
            $tempRootFull = [System.IO.Path]::GetFullPath($effectiveTempRoot)
            $tempDirectory = New-BelarcPrivateTempDirectory -TempRoot $tempRootFull
            $result.TempDirectory = $tempDirectory
            $result.CleanupStatus = 'pending'
            $result.DownloadStatus = 'pending'
            $stagedFilePath = Join-Path $tempDirectory 'BelarcAdvisorInstaller.exe'
            $result.StagedFilePath = $stagedFilePath

            $responseBytes = if ($DownloadScript) {
                & $DownloadScript $Uri
            }
            else {
                Get-BelarcResponseBytes -Uri $Uri
            }

            if ($responseBytes -isnot [byte[]] -or $responseBytes.Length -eq 0) {
                $result.DownloadStatus = 'invalid-output'
                $result.VerificationStatus = 'rejected'
                $result.FailureReason = 'invalid-download-output'
                $result.Message = 'Belarc installer download returned no verifiable bytes.'
            }
            else {
                Write-BelarcFileCreateNew -Bytes $responseBytes -LiteralPath $stagedFilePath
                $result.DownloadStatus = 'downloaded'

                $fileAttributes = [System.IO.File]::GetAttributes($stagedFilePath)
                if (($fileAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    ($fileAttributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    $result.VerificationStatus = 'rejected'
                    $result.FailureReason = 'staged-file-not-regular'
                    $result.Message = 'Belarc installer staging was changed before verification. No installer was launched.'
                }
                else {
                    $actualSha256 = Get-BelarcFileSha256 -LiteralPath $stagedFilePath
                    if (-not [string]::Equals($actualSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $result.VerificationStatus = 'rejected'
                        $result.FailureReason = 'digest-mismatch'
                        $result.Message = 'Belarc installer digest verification failed. No installer was launched.'
                    }
                    else {
                        $verifiedFileLock = [System.IO.File]::Open(
                            $stagedFilePath,
                            [System.IO.FileMode]::Open,
                            [System.IO.FileAccess]::Read,
                            [System.IO.FileShare]::Read
                        )
                        $lockedSha256 = Get-BelarcFileSha256FromStream -Stream $verifiedFileLock
                        if (-not [string]::Equals($lockedSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $result.VerificationStatus = 'rejected'
                            $result.FailureReason = 'digest-changed-before-execution'
                            $result.Message = 'Belarc installer bytes changed before launch. No installer was launched.'
                        }
                        else {
                            $signatureValid = if ($SignatureVerifier) {
                                [bool](& $SignatureVerifier $stagedFilePath $ExpectedSignerThumbprint)
                            }
                            else {
                                Test-BelarcAuthenticodeSignature -LiteralPath $stagedFilePath -ExpectedThumbprint $ExpectedSignerThumbprint
                            }

                            if (-not $signatureValid) {
                                $result.VerificationStatus = 'rejected'
                                $result.FailureReason = 'signer-mismatch'
                                $result.Message = 'Belarc installer Authenticode signer did not match the reviewed identity. No installer was launched.'
                            }
                            else {
                                $result.VerificationStatus = 'verified'
                                $result.InstallationStatus = 'running'
                                $installerArguments = @('/S')
                                $executionResult = if ($ExecutorScript) {
                                    & $ExecutorScript $stagedFilePath $installerArguments
                                }
                                else {
                                    Start-BelarcVerifiedChildProcess -LiteralPath $stagedFilePath -InstallerArguments $installerArguments
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

                                if ($null -eq $result.ExitCode) {
                                    $result.InstallationStatus = 'unknown'
                                    $result.FailureReason = 'child-result-unavailable'
                                    $result.Message = 'Belarc installer launch returned no child exit code.'
                                }
                                elseif ($result.ExitCode -eq 0) {
                                    $result.InstallationStatus = 'succeeded'
                                    $result.Success = $true
                                    $result.Message = 'Belarc installer completed successfully.'
                                }
                                else {
                                    $result.InstallationStatus = 'failed'
                                    $result.FailureReason = 'child-nonzero-exit'
                                    $result.Message = "Belarc installer exited with code $($result.ExitCode)."
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        if ($result.DownloadStatus -eq 'pending') {
            $result.DownloadStatus = 'failed'
            $result.FailureReason = 'download-failed'
            $result.Message = 'Belarc installer download or staging failed. No installer was launched.'
        }
        elseif ($result.InstallationStatus -eq 'running') {
            $result.InstallationStatus = 'unknown'
            $result.FailureReason = 'child-execution-failed'
            $result.Message = 'Belarc installer execution failed and its result is unknown.'
        }
        elseif ($result.DownloadStatus -eq 'downloaded') {
            $result.VerificationStatus = 'rejected'
            $result.FailureReason = 'verification-failed'
            $result.Message = 'Belarc installer verification failed. No installer was launched.'
        }
        else {
            $result.FailureReason = 'temporary-workspace-unavailable'
            $result.Message = 'Belarc installer staging could not be protected. No installer was launched.'
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
                $result.Message = 'Belarc installer staging cleanup failed after execution.'
            }
        }

        if ($tempDirectory) {
            try {
                $fullDirectory = [System.IO.Path]::GetFullPath($tempDirectory)
                $expectedLeaf = Split-Path -Leaf $fullDirectory
                $actualParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $fullDirectory))
                if ($expectedLeaf -notmatch '^app-installer-belarc-[0-9a-f]{32}$' -or
                    -not [string]::Equals($actualParent, $tempRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'temporary-path-invalid'
                }

                if ($stagedFilePath) {
                    $fullStagedFile = [System.IO.Path]::GetFullPath($stagedFilePath)
                    $expectedFile = [System.IO.Path]::GetFullPath((Join-Path $fullDirectory 'BelarcAdvisorInstaller.exe'))
                    if (-not [string]::Equals($fullStagedFile, $expectedFile, [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw 'staged-path-invalid'
                    }
                    if ([System.IO.Directory]::Exists($fullStagedFile)) {
                        throw 'staged-path-is-directory'
                    }
                    if ([System.IO.File]::Exists($fullStagedFile)) {
                        [System.IO.File]::Delete($fullStagedFile)
                    }
                }

                if ([System.IO.Directory]::Exists($fullDirectory)) {
                    [System.IO.Directory]::Delete($fullDirectory, $false)
                }
                $result.CleanupStatus = 'cleaned'
            }
            catch {
                $result.CleanupStatus = 'failed'
                $result.Success = $false
                $result.FailureReason = 'cleanup-failed'
                if ($result.InstallationStatus -eq 'succeeded') {
                    $result.InstallationStatus = 'unknown'
                }
                $result.Message = 'Belarc installer staging cleanup failed. Only the owned staged installer was removed.'
            }
        }
    }

    return $result
}

Export-ModuleMember -Function Get-BelarcInstallerPinnedRelease, Invoke-VerifiedBelarcInstaller
