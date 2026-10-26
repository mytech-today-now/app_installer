# Offline tests for immutable remote PowerShell helper verification.
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\modules\RemotePowerShellTrust.psm1'
$modulePath = [System.IO.Path]::GetFullPath($modulePath)
$checkCount = 0
$policyBefore = [string]::Join('|', (Get-ExecutionPolicy -List | ForEach-Object { '{0}={1}' -f $_.Scope, $_.ExecutionPolicy }))
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('app-installer-remote-helper-tests-' + [Guid]::NewGuid().ToString('N'))
$bytesEncoding = New-Object System.Text.UTF8Encoding($false)
$state = [PSCustomObject]@{
    DownloadCalls = 0
    ProcessCalls = 0
    SetupCalls = 0
    Arguments = @()
    SeenUri = $null
    SeenPath = $null
    Bytes = $null
}

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    $script:checkCount++
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Get-TestSha256 {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha256.ComputeHash($Bytes)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function New-FakeDownload {
    param([byte[]]$Bytes)

    $payload = $Bytes
    $downloadState = $state
    return {
        param($RequestedUri)
        $downloadState.DownloadCalls++
        $downloadState.SeenUri = $RequestedUri
        return ,$payload
    }.GetNewClosure()
}

try {
    New-Item -ItemType Directory -Path $tempRoot -ErrorAction Stop | Out-Null
    Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop

    $hostsRelease = Get-RemotePowerShellHelperRelease -HelperId Hosts
    $restoreRelease = Get-RemotePowerShellHelperRelease -HelperId RestorePoints
    Assert-Condition -Condition ($null -eq $hostsRelease.Uri -and $null -eq $hostsRelease.Sha256) -Message 'The production hosts release has no source or digest pin.'
    Assert-Condition -Condition ($null -eq $restoreRelease.Uri -and $null -eq $restoreRelease.Sha256) -Message 'The production restore-point release has no source or digest pin.'

    $commit = '0123456789abcdef0123456789abcdef01234567'
    $hostsUri = "https://raw.githubusercontent.com/mytech-today-now/hosts/$commit/hosts.ps1"
    $restoreUri = "https://raw.githubusercontent.com/mytech-today-now/RestorePoints/$commit/Manage-RestorePoints.ps1"
    $acceptedBytes = $bytesEncoding.GetBytes("`$script:RemoteHelperAcceptedSentinel = 'verified'`r`n")
    $acceptedDigest = Get-TestSha256 -Bytes $acceptedBytes
    $state.Bytes = $acceptedBytes
    $fakeDownload = New-FakeDownload -Bytes $acceptedBytes
    $fakeExecutor = {
        param($VerifiedPath, $PassedArguments)
        $state.ProcessCalls++
        $state.SeenPath = $VerifiedPath
        $state.Arguments = @($PassedArguments)
        $state.Bytes = [System.IO.File]::ReadAllBytes($VerifiedPath)
        return [PSCustomObject]@{ ExitCode = 0 }
    }.GetNewClosure()
    $fakeSetup = {
        param($VerifiedPath)
        $state.SetupCalls++
        $state.SeenPath = $VerifiedPath
    }.GetNewClosure()

    $missingPin = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $null `
        -ExpectedSha256 $null `
        -DownloadScript $fakeDownload `
        -ExecutorScript $fakeExecutor `
        -BeforeExecuteScript $fakeSetup `
        -TempRoot $tempRoot
    Assert-Condition -Condition ($missingPin.FailureReason -eq 'release-not-configured' -and $missingPin.RequestStatus -eq 'not-attempted') -Message 'A missing source or pin fails before a request.'
    Assert-Condition -Condition ($state.DownloadCalls -eq 0 -and $state.ProcessCalls -eq 0 -and $state.SetupCalls -eq 0) -Message 'Missing pins call neither downloader, setup, nor process boundary.'

    $invalidPin = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $hostsUri `
        -ExpectedSha256 '1234' `
        -DownloadScript $fakeDownload `
        -ExecutorScript $fakeExecutor `
        -TempRoot $tempRoot
    Assert-Condition -Condition ($invalidPin.FailureReason -eq 'invalid-digest-pin' -and $invalidPin.RequestStatus -eq 'not-attempted') -Message 'A malformed digest pin fails before a request.'
    Assert-Condition -Condition ($state.DownloadCalls -eq 0 -and $state.ProcessCalls -eq 0) -Message 'Malformed pins cannot reach the fake downloader or executor.'

    $invalidSources = @(
        'https://raw.githubusercontent.com/mytech-today-now/hosts/refs/heads/main/hosts.ps1',
        "https://raw.githubusercontent.com/mytech-today-now/other/$commit/hosts.ps1",
        "https://raw.githubusercontent.com/mytech-today-now/hosts/$commit/other.ps1",
        "https://user@raw.githubusercontent.com/mytech-today-now/hosts/$commit/hosts.ps1",
        "https://raw.githubusercontent.com/mytech-today-now/hosts/$commit/hosts.ps1?download=1"
    )
    foreach ($invalidUri in $invalidSources) {
        $sourceRejected = Invoke-VerifiedRemotePowerShellHelper `
            -HelperId Hosts `
            -Uri $invalidUri `
            -ExpectedSha256 $acceptedDigest `
            -DownloadScript $fakeDownload `
            -ExecutorScript $fakeExecutor `
            -TempRoot $tempRoot
        Assert-Condition -Condition ($sourceRejected.FailureReason -eq 'source-not-immutable' -and $sourceRejected.RequestStatus -eq 'not-attempted') -Message "Invalid source is rejected before network access: $invalidUri"
    }
    Assert-Condition -Condition ($state.DownloadCalls -eq 0 -and $state.ProcessCalls -eq 0) -Message 'Invalid source shapes never reach the downloader or process boundary.'

    $unavailableDownload = {
        param($RequestedUri)
        $state.DownloadCalls++
        $state.SeenUri = $RequestedUri
        throw 'simulated unavailable origin'
    }.GetNewClosure()
    $unavailable = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $hostsUri `
        -ExpectedSha256 $acceptedDigest `
        -DownloadScript $unavailableDownload `
        -ExecutorScript $fakeExecutor `
        -TempRoot $tempRoot
    Assert-Condition -Condition ($unavailable.FailureReason -eq 'download-failed' -and $unavailable.RequestStatus -eq 'failed') -Message 'An unavailable source is reported as a download failure.'
    Assert-Condition -Condition ($state.ProcessCalls -eq 0 -and $state.SetupCalls -eq 0) -Message 'An unavailable source cannot launch or run install setup.'

    $rejectedSentinel = 'RemoteHelperRejectedSentinel'
    Remove-Variable -Name $rejectedSentinel -Scope Global -ErrorAction SilentlyContinue
    $changedBytes = $bytesEncoding.GetBytes("`$global:$rejectedSentinel = 'executed'`r`n")
    $changed = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $hostsUri `
        -ExpectedSha256 $acceptedDigest `
        -DownloadScript (New-FakeDownload -Bytes $changedBytes) `
        -ExecutorScript $fakeExecutor `
        -TempRoot $tempRoot
    Assert-Condition -Condition ($changed.FailureReason -eq 'digest-mismatch' -and $changed.VerificationStatus -eq 'rejected') -Message 'Changed response bytes are rejected.'
    Assert-Condition -Condition ($state.ProcessCalls -eq 0 -and $state.SetupCalls -eq 0) -Message 'Changed bytes cannot reach the process or setup boundary.'
    Assert-Condition -Condition ($null -eq (Get-Variable -Name $rejectedSentinel -Scope Global -ErrorAction SilentlyContinue)) -Message 'Rejected content never executes its sentinel.'

    $invalidPowerShellBytes = $bytesEncoding.GetBytes('function Broken {')
    $invalidPowerShell = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId RestorePoints `
        -Uri $restoreUri `
        -ExpectedSha256 (Get-TestSha256 -Bytes $invalidPowerShellBytes) `
        -DownloadScript (New-FakeDownload -Bytes $invalidPowerShellBytes) `
        -ExecutorScript $fakeExecutor `
        -TempRoot $tempRoot
    Assert-Condition -Condition ($invalidPowerShell.FailureReason -eq 'invalid-powershell-output' -and $invalidPowerShell.VerificationStatus -eq 'rejected') -Message 'Digest-matching invalid PowerShell is rejected before execution.'
    Assert-Condition -Condition ($state.ProcessCalls -eq 0) -Message 'Invalid parsed content never reaches the process boundary.'

    $expectedArguments = @('-Action', 'Create', '-Description', 'Backup copy with spaces', '-ConfigPath', 'C:\Temp\Restore Config.json')
    $state.ProcessCalls = 0
    $state.SetupCalls = 0
    $state.Arguments = @()
    $state.Bytes = $null
    $verified = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId RestorePoints `
        -Uri $restoreUri `
        -ExpectedSha256 $acceptedDigest `
        -ScriptArguments $expectedArguments `
        -DownloadScript (New-FakeDownload -Bytes $acceptedBytes) `
        -BeforeExecuteScript $fakeSetup `
        -ExecutorScript $fakeExecutor `
        -TempRoot $tempRoot
    Assert-Condition -Condition ($verified.Success -and $verified.ExecutionStatus -eq 'succeeded' -and $verified.ExitCode -eq 0) -Message 'Digest-matching content succeeds only after the fake process reports native exit zero.'
    Assert-Condition -Condition ($state.ProcessCalls -eq 1 -and $state.SetupCalls -eq 1) -Message 'Verified content reaches setup and exactly one fake process.'
    Assert-Condition -Condition ([string]::Join('|', [string[]]$state.Arguments) -ceq [string]::Join('|', $expectedArguments)) -Message 'The exact action, description, config path, and spaces reach the process boundary unchanged.'
    Assert-Condition -Condition ((Get-TestSha256 -Bytes $state.Bytes) -eq $acceptedDigest) -Message 'The process boundary sees the exact verified byte sequence.'
    Assert-Condition -Condition ($verified.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $verified.TempScriptPath)) -Message 'The temporary verified file is removed after child completion.'

    $blockedState = [PSCustomObject]@{ DownloadCalls = 0; ProcessCalls = 0 }
    $blockedDownload = {
        param($RequestedUri)
        $blockedState.DownloadCalls++
        return ,$acceptedBytes
    }.GetNewClosure()
    $blockedExecutor = {
        param($VerifiedPath, $PassedArguments)
        $blockedState.ProcessCalls++
        return [PSCustomObject]@{ ExitCode = 1 }
    }.GetNewClosure()
    $blockedPolicy = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $hostsUri `
        -ExpectedSha256 $acceptedDigest `
        -DownloadScript $blockedDownload `
        -ExecutorScript $blockedExecutor `
        -TempRoot $tempRoot
    Assert-Condition -Condition (-not $blockedPolicy.Success -and $blockedPolicy.ExitCode -eq 1 -and $blockedPolicy.ExecutionStatus -eq 'failed') -Message 'A simulated execution-policy block remains a nonzero child failure.'
    Assert-Condition -Condition ($blockedState.DownloadCalls -eq 1 -and $blockedState.ProcessCalls -eq 1) -Message 'A policy-blocked child is not silently retried.'

    $nativeFailure = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId RestorePoints `
        -Uri $restoreUri `
        -ExpectedSha256 $acceptedDigest `
        -DownloadScript (New-FakeDownload -Bytes $acceptedBytes) `
        -ExecutorScript { param($VerifiedPath, $PassedArguments) return [PSCustomObject]@{ ExitCode = 23 } }.GetNewClosure() `
        -TempRoot $tempRoot
    Assert-Condition -Condition (-not $nativeFailure.Success -and $nativeFailure.ExitCode -eq 23 -and $nativeFailure.ExecutionStatus -eq 'failed') -Message 'An arbitrary native child exit code is propagated without a success result.'

    $unknownProcess = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $hostsUri `
        -ExpectedSha256 $acceptedDigest `
        -DownloadScript (New-FakeDownload -Bytes $acceptedBytes) `
        -ExecutorScript { param($VerifiedPath, $PassedArguments) return $null }.GetNewClosure() `
        -TempRoot $tempRoot
    Assert-Condition -Condition (-not $unknownProcess.Success -and $unknownProcess.ExecutionStatus -eq 'unknown' -and $unknownProcess.FailureReason -eq 'child-result-unavailable') -Message 'A missing process result is unknown and never success.'

    $throwingProcess = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId Hosts `
        -Uri $hostsUri `
        -ExpectedSha256 $acceptedDigest `
        -DownloadScript (New-FakeDownload -Bytes $acceptedBytes) `
        -ExecutorScript { param($VerifiedPath, $PassedArguments) throw 'simulated process failure' }.GetNewClosure() `
        -TempRoot $tempRoot
    Assert-Condition -Condition (-not $throwingProcess.Success -and $throwingProcess.ExecutionStatus -eq 'unknown' -and $throwingProcess.FailureReason -eq 'child-execution-failed') -Message 'A process exception is reported as unknown and is not retried.'

    $hostsUriForRestore = Invoke-VerifiedRemotePowerShellHelper `
        -HelperId RestorePoints `
        -Uri $hostsUri `
        -ExpectedSha256 $acceptedDigest `
        -DownloadScript $fakeDownload `
        -ExecutorScript $fakeExecutor `
        -TempRoot $tempRoot
    Assert-Condition -Condition ($hostsUriForRestore.FailureReason -eq 'source-not-immutable' -and $hostsUriForRestore.RequestStatus -eq 'not-attempted') -Message 'A hosts source cannot be used as a restore-point release.'

    $sourceFiles = @(
        (Join-Path $PSScriptRoot '..\apps\hosts.ps1'),
        (Join-Path $PSScriptRoot '..\apps\managerestorepoints.ps1'),
        (Join-Path $PSScriptRoot '..\modules\RemotePowerShellTrust.psm1')
    )
    foreach ($sourceFile in $sourceFiles) {
        $sourceText = Get-Content -LiteralPath $sourceFile -Raw
        Assert-Condition -Condition ($sourceText -notmatch '(?i)-ExecutionPolicy\b' -and $sourceText -notmatch 'Invoke-Expression') -Message "Production helper source has no process policy option or downloaded-text evaluation: $(Split-Path $sourceFile -Leaf)"
    }

    $trustModuleText = Get-Content -LiteralPath $modulePath -Raw
    $expectedProcessArgumentConstruction = '$childArguments = @(''-NoProfile'', ''-File'', $LiteralPath) + $ScriptArguments'
    Assert-Condition -Condition ($trustModuleText.Contains($expectedProcessArgumentConstruction)) -Message 'The child process receives direct NoProfile and File arguments.'
    $trustModule = Get-Module -Name RemotePowerShellTrust
    $quotedPath = & $trustModule { ConvertTo-RemoteHelperProcessArgument -Argument 'C:\Program Files\Restore Config.json' }
    $quotedText = & $trustModule { ConvertTo-RemoteHelperProcessArgument -Argument 'A "quoted" value' }
    $quotedTrailingSlash = & $trustModule { ConvertTo-RemoteHelperProcessArgument -Argument 'C:\Folder with space\' }
    Assert-Condition -Condition ($quotedPath -ceq '"C:\Program Files\Restore Config.json"') -Message 'A path with spaces is quoted as one native argument.'
    Assert-Condition -Condition ($quotedText -ceq '"A \"quoted\" value"') -Message 'Embedded quotes are escaped for the Windows process boundary.'
    Assert-Condition -Condition ($quotedTrailingSlash -ceq '"C:\Folder with space\\"') -Message 'Trailing backslashes are escaped before a closing quote.'

    $hostsText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\apps\hosts.ps1') -Raw
    $restoreText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\apps\managerestorepoints.ps1') -Raw
    $readmeText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\README.md') -Raw
    $changelogText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\CHANGELOG.md') -Raw
    Assert-Condition -Condition ($hostsText.Contains('-NoProfile -File') -and $hostsText.Contains('Hosts File Manager.lnk')) -Message 'Hosts shortcut launch uses a direct file launch and keeps its name.'
    Assert-Condition -Condition ($restoreText.Contains('-NoProfile -File') -and $restoreText.Contains('-Action List') -and $restoreText.Contains('Manage Restore Points.lnk')) -Message 'Restore-point shortcut uses a direct file launch and keeps List behavior.'
    Assert-Condition -Condition ($readmeText.Contains('hosts') -and $readmeText.Contains('restore-point') -and $changelogText.Contains('SHA-256')) -Message 'README and changelog document the remote helper trust status.'
    Assert-Condition -Condition ([string]::Join('|', (Get-ExecutionPolicy -List | ForEach-Object { '{0}={1}' -f $_.Scope, $_.ExecutionPolicy })) -ceq $policyBefore) -Message 'Offline trust checks leave all execution policy scopes unchanged.'

    $mcafeeRelease = Get-RemoteExecutableHelperRelease -HelperId McAfee
    $mcafeeUri = 'https://download.mcafee.com/molbin/iss-loc/SupportTools/MCPR/MCPR.exe'
    Assert-Condition -Condition ($mcafeeRelease.Uri -ceq $mcafeeUri -and $null -eq $mcafeeRelease.Sha256 -and $null -eq $mcafeeRelease.SignerThumbprint) -Message 'McAfee source is only a locator; its production digest and signer pins remain unset.'

    $executableState = [PSCustomObject]@{
        DownloadCalls = 0
        SignatureCalls = 0
        ProcessCalls = 0
        ExitCode = 0
        SignerThumbprint = ('A' * 40)
        SeenPath = $null
        SeenDirectories = @()
        Arguments = @()
        Bytes = $null
        AclProtected = $false
        AccessRuleSids = @()
    }
    $mcafeeBytes = [byte[]]@(77, 90, 0, 1, 2, 3, 4, 5)
    $mcafeeDigest = Get-TestSha256 -Bytes $mcafeeBytes
    $expectedSigner = 'A' * 40
    $executableDownload = {
        param($RequestedUri)
        $executableState.DownloadCalls++
        if ($RequestedUri -cne $mcafeeUri) {
            throw 'unexpected fake transport source'
        }
        return ,$mcafeeBytes
    }.GetNewClosure()
    $signatureVerifier = {
        param($LiteralPath, $ExpectedThumbprint)
        $executableState.SignatureCalls++
        return [PSCustomObject]@{
            Status = 'Valid'
            Thumbprint = $executableState.SignerThumbprint
        }
    }.GetNewClosure()
    $executableExecutor = {
        param($LiteralPath, $ProcessArguments)
        $executableState.ProcessCalls++
        $executableState.SeenPath = $LiteralPath
        $executableState.SeenDirectories = @($executableState.SeenDirectories + (Split-Path -Parent $LiteralPath))
        $executableState.Arguments = @($ProcessArguments)
        $executableState.Bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
        try {
            $stagingAcl = Get-Acl -LiteralPath (Split-Path -Parent $LiteralPath) -ErrorAction Stop
            $executableState.AclProtected = [bool]$stagingAcl.AreAccessRulesProtected
            $executableState.AccessRuleSids = @(
                $stagingAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) |
                    ForEach-Object { $_.IdentityReference.Value }
            )
        }
        catch {
            $executableState.AclProtected = $false
            $executableState.AccessRuleSids = @()
        }
        return [PSCustomObject]@{ ExitCode = $executableState.ExitCode }
    }.GetNewClosure()

    $missingMcafeePin = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeRelease.Uri -ExpectedSha256 $mcafeeRelease.Sha256 -ExpectedSignerThumbprint $mcafeeRelease.SignerThumbprint -DownloadScript $executableDownload -SignatureVerifierScript $signatureVerifier -ExecutorScript $executableExecutor -TempRoot $tempRoot
    Assert-Condition -Condition (-not $missingMcafeePin.Success -and $missingMcafeePin.FailureReason -eq 'release-not-configured' -and $missingMcafeePin.RequestStatus -eq 'not-attempted' -and $missingMcafeePin.VerificationStatus -eq 'unverified') -Message 'Missing McAfee identity pins return an unverified blocked result before a request.'
    Assert-Condition -Condition ($executableState.DownloadCalls -eq 0 -and $executableState.SignatureCalls -eq 0 -and $executableState.ProcessCalls -eq 0) -Message 'Missing McAfee pins reach neither fake transport, signature check, nor process executor.'

    $failedTransfer = {
        param($RequestedUri)
        $executableState.DownloadCalls++
        throw 'simulated MCPR transfer failure'
    }.GetNewClosure()
    $transferFailure = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeUri -ExpectedSha256 $mcafeeDigest -DownloadScript $failedTransfer -ExecutorScript $executableExecutor -TempRoot $tempRoot
    Assert-Condition -Condition (-not $transferFailure.Success -and $transferFailure.RequestStatus -eq 'failed' -and $transferFailure.FailureReason -eq 'download-failed') -Message 'A failed MCPR transfer returns a distinct failure result.'
    Assert-Condition -Condition ($executableState.ProcessCalls -eq 0 -and $transferFailure.CleanupStatus -eq 'not-required') -Message 'A failed MCPR transfer does not execute or create a staging artifact.'

    $changedExecutableBytes = [byte[]]@(77, 90, 8, 7, 6, 5, 4, 3)
    $changedExecutableDownload = {
        param($RequestedUri)
        $executableState.DownloadCalls++
        return ,$changedExecutableBytes
    }.GetNewClosure()
    $digestMismatch = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeUri -ExpectedSha256 $mcafeeDigest -DownloadScript $changedExecutableDownload -ExecutorScript $executableExecutor -TempRoot $tempRoot
    Assert-Condition -Condition (-not $digestMismatch.Success -and $digestMismatch.VerificationStatus -eq 'rejected' -and $digestMismatch.FailureReason -eq 'digest-mismatch') -Message 'MCPR bytes that do not match the approved digest are rejected.'
    Assert-Condition -Condition ($executableState.ProcessCalls -eq 0 -and $digestMismatch.CleanupStatus -eq 'not-required') -Message 'A digest mismatch cannot reach the executor or create a staging artifact.'

    $executableState.DownloadCalls = 0
    $unapprovedSource = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri ($mcafeeUri + '?download=1') -ExpectedSha256 $mcafeeDigest -DownloadScript $executableDownload -ExecutorScript $executableExecutor -TempRoot $tempRoot
    Assert-Condition -Condition (-not $unapprovedSource.Success -and $unapprovedSource.RequestStatus -eq 'not-attempted' -and $unapprovedSource.FailureReason -eq 'source-not-allowed') -Message 'A modified MCPR source URL is rejected before transport.'
    Assert-Condition -Condition ($executableState.DownloadCalls -eq 0 -and $executableState.ProcessCalls -eq 0) -Message 'Rejected MCPR source metadata reaches neither the fake transport nor executor.'

    $aclProbe = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeUri -ExpectedSha256 $mcafeeDigest -ExpectedSignerThumbprint $expectedSigner -DownloadScript $executableDownload -SignatureVerifierScript $signatureVerifier -ExecutorScript $executableExecutor -TempRoot $tempRoot
    if ($aclProbe.Success) {
        Assert-Condition -Condition ($aclProbe.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $aclProbe.TempDirectory)) -Message 'The production executable boundary stages and cleans MCPR when protected ACL setup is available.'
        Assert-Condition -Condition ($executableState.AclProtected -and @($executableState.AccessRuleSids | Where-Object { $_ -notin @([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544') }).Count -eq 0) -Message 'Production executable staging has a protected DACL limited to the user, SYSTEM, and Administrators.'
    }
    elseif ($aclProbe.FailureReason -eq 'staging-protection-failed') {
        Assert-Condition -Condition (-not $aclProbe.Success -and $aclProbe.ExecutionStatus -eq 'not-started' -and $executableState.ProcessCalls -eq 0) -Message 'Production fails closed when the host blocks private ACL setup.'
        $moduleSource = [System.IO.File]::ReadAllText($modulePath)
        $aclCall = 'Set-RemoteHelperPrivateDirectoryAcl -LiteralPath $directoryPath'
        if ($moduleSource.Split(@($aclCall), [System.StringSplitOptions]::None).Length -ne 2) {
            throw 'Expected exactly one production executable-helper ACL boundary.'
        }
        $testModulePath = Join-Path $tempRoot 'RemotePowerShellTrust.psm1'
        $testModuleSource = $moduleSource.Replace($aclCall, '# Test harness stub: this host blocks ACL updates.')
        [System.IO.File]::WriteAllText($testModulePath, $testModuleSource, $bytesEncoding)
        Import-Module -Name $testModulePath -Force -DisableNameChecking -ErrorAction Stop
        Write-Host '[SKIP] Runtime private-ACL setup is blocked by this host; remaining executable-helper cases use a test-only ACL boundary stub.' -ForegroundColor Yellow
    }
    else {
        throw "Unexpected MCPR private-staging probe result: $($aclProbe.FailureReason)"
    }

    $executableState.DownloadCalls = 0
    $executableState.SignatureCalls = 0
    $executableState.ProcessCalls = 0
    $executableState.SeenDirectories = @()
    $signerMismatchIdentity = {
        param($LiteralPath, $ExpectedThumbprint)
        $executableState.SignatureCalls++
        return [PSCustomObject]@{ Status = 'Valid'; Thumbprint = ('B' * 40) }
    }.GetNewClosure()
    $signerMismatch = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeUri -ExpectedSha256 $mcafeeDigest -ExpectedSignerThumbprint $expectedSigner -DownloadScript $executableDownload -SignatureVerifierScript $signerMismatchIdentity -ExecutorScript $executableExecutor -TempRoot $tempRoot
    Assert-Condition -Condition (-not $signerMismatch.Success -and $signerMismatch.FailureReason -eq 'signer-mismatch' -and $signerMismatch.VerificationStatus -eq 'rejected') -Message 'A valid but unexpected MCPR signer is rejected before execution.'
    Assert-Condition -Condition ($executableState.ProcessCalls -eq 0 -and $signerMismatch.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $signerMismatch.TempDirectory)) -Message 'Signer mismatch cannot execute and removes only its owned staged file and directory.'

    $executableState.ExitCode = $null
    $unknownChild = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeUri -ExpectedSha256 $mcafeeDigest -DownloadScript $executableDownload -ExecutorScript $executableExecutor -TempRoot $tempRoot
    Assert-Condition -Condition (-not $unknownChild.Success -and $unknownChild.ExecutionStatus -eq 'unknown' -and $null -eq $unknownChild.ExitCode -and $unknownChild.FailureReason -eq 'child-result-unavailable') -Message 'A child that provides no exit code remains unknown rather than success.'
    Assert-Condition -Condition ($unknownChild.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $unknownChild.TempDirectory)) -Message 'An unknown MCPR child outcome still cleans its owned staging artifacts.'

    $executableState.ProcessCalls = 0
    $executableState.SeenDirectories = @()
    $executableState.ExitCode = 23
    $childFailure = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeUri -ExpectedSha256 $mcafeeDigest -DownloadScript $executableDownload -ExecutorScript $executableExecutor -TempRoot $tempRoot -ProcessArguments @('-p')
    Assert-Condition -Condition (-not $childFailure.Success -and $childFailure.ExecutionStatus -eq 'failed' -and $childFailure.ExitCode -eq 23 -and $childFailure.FailureReason -eq 'child-nonzero-exit') -Message 'A verified MCPR child failure preserves its exact nonzero exit code.'
    Assert-Condition -Condition ($childFailure.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $childFailure.TempDirectory)) -Message 'A failed MCPR child still cleans its owned staged file and directory.'

    $executableState.ExitCode = 0
    $verifiedExecutable = Invoke-VerifiedRemoteExecutableHelper -HelperId McAfee -Uri $mcafeeUri -ExpectedSha256 $mcafeeDigest -ExpectedSignerThumbprint $expectedSigner -DownloadScript $executableDownload -SignatureVerifierScript $signatureVerifier -ExecutorScript $executableExecutor -TempRoot $tempRoot -ProcessArguments @('-p')
    Assert-Condition -Condition ($verifiedExecutable.Success -and $verifiedExecutable.VerificationStatus -eq 'verified' -and $verifiedExecutable.ExecutionStatus -eq 'succeeded' -and $verifiedExecutable.ExitCode -eq 0) -Message 'Digest- and signer-matching MCPR bytes reach the fake executor and return success.'
    Assert-Condition -Condition ($executableState.ProcessCalls -eq 2 -and [string]::Join('|', [string[]]$executableState.Arguments) -ceq '-p') -Message 'Only verified MCPR reaches the executor with the selected -p argument.'
    Assert-Condition -Condition ((Get-TestSha256 -Bytes $executableState.Bytes) -eq $mcafeeDigest -and $verifiedExecutable.ActualSha256 -eq $mcafeeDigest) -Message 'The executor receives the staged bytes whose hash was verified.'
    Assert-Condition -Condition ($verifiedExecutable.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $verifiedExecutable.TempDirectory)) -Message 'The successful MCPR child leaves no owned staging file or directory.'
    $uniqueExecutedStageDirectories = @($executableState.SeenDirectories | Sort-Object -Unique)
    Assert-Condition -Condition ($executableState.SeenDirectories.Count -eq 2 -and $uniqueExecutedStageDirectories.Count -eq 2) -Message 'Separate MCPR executions use distinct randomized staging directories.'

    $remainingExecutableStages = @(Get-ChildItem -LiteralPath $tempRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^app-installer-executable-helper-' })
    Assert-Condition -Condition ($remainingExecutableStages.Count -eq 0) -Message 'All MCPR temporary staging directories owned by the fake scenarios were removed.'
    $remoteHelperSourceFiles = @(
        (Join-Path $PSScriptRoot '..\apps\uninstall-mcafee.ps1'),
        (Join-Path $PSScriptRoot '..\modules\RemotePowerShellTrust.psm1')
    )
    foreach ($sourceFile in $remoteHelperSourceFiles) {
        $sourceText = Get-Content -LiteralPath $sourceFile -Raw
        Assert-Condition -Condition ($sourceText -notmatch '(?i)Invoke-WebRequest|Start-Process\s+-FilePath\s+\$mcprPath' -and $sourceText -notmatch '(?i)-ExecutionPolicy\b' -and $sourceText -notmatch 'Invoke-Expression') -Message "McAfee production helper code uses the verified boundary without direct unverified launch: $(Split-Path $sourceFile -Leaf)"
    }
    $productionTrustSource = [System.IO.File]::ReadAllText($modulePath)
    Assert-Condition -Condition ($productionTrustSource.Contains('$directorySecurity.SetAccessRuleProtection($true, $false)') -and $productionTrustSource.Contains('S-1-5-18') -and $productionTrustSource.Contains('S-1-5-32-544') -and $productionTrustSource.Contains('Set-Acl -LiteralPath $LiteralPath') -and $productionTrustSource.Contains('$request.AllowAutoRedirect = $false')) -Message 'Production executable staging retains protected DACL checks, restricted principals, and disabled HTTP redirects.'

    Write-Host "Remote helper trust checks passed ($checkCount assertions)." -ForegroundColor Cyan
}
finally {
    Remove-Module -Name RemotePowerShellTrust -ErrorAction SilentlyContinue
    Remove-Variable -Name RemoteHelperRejectedSentinel -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
