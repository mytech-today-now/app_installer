# Production pins remain empty until an immutable source and independent digest
# have both been reviewed. Never replace these values with a branch URL.
$script:RemoteHelperReleasePins = @{
    Hosts = [PSCustomObject]@{
        Uri    = $null
        Sha256 = $null
    }
    RestorePoints = [PSCustomObject]@{
        Uri    = $null
        Sha256 = $null
    }
}

function Get-RemotePowerShellHelperRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Hosts', 'RestorePoints')]
        [string]$HelperId
    )

    $pin = $script:RemoteHelperReleasePins[$HelperId]
    return [PSCustomObject]@{
        Uri    = $pin.Uri
        Sha256 = $pin.Sha256
    }
}

function Test-RemoteHelperImmutableUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Hosts', 'RestorePoints')]
        [string]$HelperId,

        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    try {
        $parsedUri = [System.Uri]::new($Uri, [System.UriKind]::Absolute)
        if ($parsedUri.Scheme -ne 'https' -or
            $parsedUri.Host -ine 'raw.githubusercontent.com' -or
            -not $parsedUri.IsDefaultPort -or
            -not [string]::IsNullOrEmpty($parsedUri.UserInfo) -or
            -not [string]::IsNullOrEmpty($parsedUri.Query) -or
            -not [string]::IsNullOrEmpty($parsedUri.Fragment)) {
            return $false
        }

        $expectedPathPattern = switch ($HelperId) {
            'Hosts' { '^/mytech-today-now/hosts/[0-9A-Fa-f]{40}/hosts\.ps1$' }
            'RestorePoints' { '^/mytech-today-now/RestorePoints/[0-9A-Fa-f]{40}/Manage-RestorePoints\.ps1$' }
        }

        return ($parsedUri.AbsolutePath -cmatch $expectedPathPattern)
    }
    catch {
        return $false
    }
}

function Get-RemoteHelperResponseBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $request = [System.Net.WebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $request.AllowAutoRedirect = $false
    $response = $null
    $responseStream = $null
    $memoryStream = $null

    try {
        $response = $request.GetResponse()
        if ($response -is [System.Net.HttpWebResponse] -and
            $response.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
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

function Get-RemoteHelperSha256FromBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha256.ComputeHash($Bytes)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-RemoteHelperSha256FromStream {
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

function New-RemoteHelperTempFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$TempRoot = [System.IO.Path]::GetTempPath()
    )

    $root = [System.IO.Path]::GetFullPath($TempRoot)
    if (-not [System.IO.Directory]::Exists($root)) {
        throw 'temporary-root-unavailable'
    }

    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $path = Join-Path $root ('app-installer-remote-helper-' + [Guid]::NewGuid().ToString('N') + '.ps1')
        $fileStream = $null
        $createdFile = $false
        try {
            $fileStream = New-Object System.IO.FileStream(
                $path,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
            $createdFile = $true
            $fileStream.Write($Bytes, 0, $Bytes.Length)
            $fileStream.Flush($true)
            $fileStream.Dispose()
            return $path
        }
        catch {
            if ($fileStream) { $fileStream.Dispose() }
            if ($createdFile) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                throw 'temporary-file-write-failed'
            }
            if ([System.IO.File]::Exists($path)) {
                continue
            }

            throw 'temporary-file-create-failed'
        }
    }

    throw 'temporary-file-collision'
}

function ConvertTo-RemoteHelperProcessArgument {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory = $true)]
        [string]$Argument
    )

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34)
    $backslashCount = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashCount++
        }
        elseif ($character -eq [char]34) {
            for ($index = 0; $index -lt (($backslashCount * 2) + 1); $index++) {
                [void]$builder.Append([char]92)
            }
            [void]$builder.Append([char]34)
            $backslashCount = 0
        }
        else {
            for ($index = 0; $index -lt $backslashCount; $index++) {
                [void]$builder.Append([char]92)
            }
            [void]$builder.Append($character)
            $backslashCount = 0
        }
    }

    for ($index = 0; $index -lt ($backslashCount * 2); $index++) {
        [void]$builder.Append([char]92)
    }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Start-VerifiedRemoteHelperProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [string[]]$ScriptArguments = @()
    )

    $hostPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    if (-not $hostPath -or -not [System.IO.File]::Exists($hostPath)) {
        throw 'powershell-host-unavailable'
    }

    $childArguments = @('-NoProfile', '-File', $LiteralPath) + $ScriptArguments
    $quotedArguments = @(
        foreach ($argument in $childArguments) {
            ConvertTo-RemoteHelperProcessArgument -Argument ([string]$argument)
        }
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $hostPath
    $startInfo.Arguments = [string]::Join(' ', [string[]]$quotedArguments)
    $startInfo.WorkingDirectory = [System.Environment]::CurrentDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal

    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw 'child-process-start-failed'
        }

        $process.WaitForExit()
        return [PSCustomObject]@{ ExitCode = [int]$process.ExitCode }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-VerifiedRemotePowerShellHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Hosts', 'RestorePoints')]
        [string]$HelperId,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Uri,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ExpectedSha256,

        [string[]]$ScriptArguments = @(),

        [string]$TempRoot,

        [scriptblock]$DownloadScript,

        [scriptblock]$BeforeExecuteScript,

        [scriptblock]$ExecutorScript
    )

    $result = [PSCustomObject]@{
        Success            = $false
        RequestStatus      = 'not-attempted'
        VerificationStatus = 'not-attempted'
        ExecutionStatus    = 'not-started'
        ExitCode            = $null
        FailureReason       = $null
        CleanupStatus       = 'not-required'
        TempScriptPath      = $null
    }
    $verifiedFileLock = $null
    $tempScriptPath = $null
    $tempRootFull = $null

    try {
        if ([string]::IsNullOrWhiteSpace($Uri) -or [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
            $result.VerificationStatus = 'unverified'
            $result.FailureReason = 'release-not-configured'
        }
        elseif ($ExpectedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            $result.VerificationStatus = 'rejected'
            $result.FailureReason = 'invalid-digest-pin'
        }
        elseif (-not (Test-RemoteHelperImmutableUri -HelperId $HelperId -Uri $Uri)) {
            $result.VerificationStatus = 'rejected'
            $result.FailureReason = 'source-not-immutable'
        }
        else {
            $effectiveTempRoot = if ($TempRoot) { $TempRoot } else { [System.IO.Path]::GetTempPath() }
            $tempRootFull = [System.IO.Path]::GetFullPath($effectiveTempRoot)
            $result.RequestStatus = 'pending'

            if ($DownloadScript) {
                $responseBytes = & $DownloadScript $Uri
            }
            else {
                $responseBytes = Get-RemoteHelperResponseBytes -Uri $Uri
            }

            if ($responseBytes -isnot [byte[]] -or $responseBytes.Length -eq 0) {
                $result.RequestStatus = 'invalid-output'
                $result.VerificationStatus = 'rejected'
                $result.FailureReason = 'invalid-download-output'
            }
            else {
                $result.RequestStatus = 'downloaded'
                $downloadDigest = Get-RemoteHelperSha256FromBytes -Bytes $responseBytes
                if (-not [string]::Equals($downloadDigest, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $result.VerificationStatus = 'rejected'
                    $result.FailureReason = 'digest-mismatch'
                }
                else {
                    $tempScriptPath = New-RemoteHelperTempFile -Bytes $responseBytes -TempRoot $effectiveTempRoot
                    $result.TempScriptPath = $tempScriptPath
                    $result.CleanupStatus = 'pending'
                    $verifiedFileLock = [System.IO.File]::Open(
                        $tempScriptPath,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::Read
                    )

                    $lockedDigest = Get-RemoteHelperSha256FromStream -Stream $verifiedFileLock
                    if (-not [string]::Equals($lockedDigest, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $result.VerificationStatus = 'rejected'
                        $result.FailureReason = 'digest-changed-before-execution'
                    }
                    else {
                        $parseErrors = $null
                        [void][System.Management.Automation.Language.Parser]::ParseFile(
                            $tempScriptPath,
                            [ref]$null,
                            [ref]$parseErrors
                        )

                        if ($parseErrors -and $parseErrors.Count -gt 0) {
                            $result.VerificationStatus = 'rejected'
                            $result.FailureReason = 'invalid-powershell-output'
                        }
                        else {
                            $result.VerificationStatus = 'verified'

                            if ($BeforeExecuteScript) {
                                $result.ExecutionStatus = 'preparing'
                                & $BeforeExecuteScript $tempScriptPath
                            }

                            $result.ExecutionStatus = 'running'
                            if ($ExecutorScript) {
                                $executionResult = & $ExecutorScript $tempScriptPath $ScriptArguments
                            }
                            else {
                                $executionResult = Start-VerifiedRemoteHelperProcess `
                                    -LiteralPath $tempScriptPath `
                                    -ScriptArguments $ScriptArguments
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
                                $result.ExecutionStatus = 'unknown'
                                $result.FailureReason = 'child-result-unavailable'
                            }
                            elseif ($result.ExitCode -eq 0) {
                                $result.ExecutionStatus = 'succeeded'
                                $result.Success = $true
                            }
                            else {
                                $result.ExecutionStatus = 'failed'
                                $result.FailureReason = 'child-nonzero-exit'
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        if ($result.RequestStatus -eq 'pending') {
            $result.RequestStatus = 'failed'
            if ($result.VerificationStatus -eq 'not-attempted') {
                $result.VerificationStatus = 'not-verified'
            }
            $result.FailureReason = 'download-failed'
        }
        elseif ($result.ExecutionStatus -eq 'preparing') {
            $result.ExecutionStatus = 'not-started'
            $result.FailureReason = 'pre-execution-setup-failed'
        }
        elseif ($result.ExecutionStatus -eq 'running') {
            $result.ExecutionStatus = 'unknown'
            $result.FailureReason = 'child-execution-failed'
        }
        elseif (-not $result.FailureReason) {
            $result.FailureReason = 'unexpected-error'
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
                if ($result.ExecutionStatus -eq 'succeeded') {
                    $result.ExecutionStatus = 'unknown'
                }
            }
        }

        if ($tempScriptPath -and [System.IO.File]::Exists($tempScriptPath)) {
            try {
                $fullTempPath = [System.IO.Path]::GetFullPath($tempScriptPath)
                $expectedLeaf = Split-Path -Leaf $fullTempPath
                $actualParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $fullTempPath))
                if ($expectedLeaf -notmatch '^app-installer-remote-helper-[0-9a-f]{32}\.ps1$' -or
                    -not [string]::Equals($actualParent, $tempRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'temporary-path-invalid'
                }

                Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction Stop
                $result.CleanupStatus = 'cleaned'
            }
            catch {
                $result.CleanupStatus = 'failed'
                $result.Success = $false
                $result.FailureReason = 'cleanup-failed'
                if ($result.ExecutionStatus -eq 'succeeded') {
                    $result.ExecutionStatus = 'unknown'
                }
            }
        }
    }

    return $result
}

Export-ModuleMember -Function Get-RemotePowerShellHelperRelease, Invoke-VerifiedRemotePowerShellHelper
