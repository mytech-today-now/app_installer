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

    Write-Host "Remote helper trust checks passed ($checkCount assertions)." -ForegroundColor Cyan
}
finally {
    Remove-Module -Name RemotePowerShellTrust -ErrorAction SilentlyContinue
    Remove-Variable -Name RemoteHelperRejectedSentinel -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
