# Offline decision-table coverage for the consent-gated runtime prerequisite flow.
# No package manager, network request, elevation, runtime install, or OS change is performed.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstallerRuntimeDiscovery.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstallerPrerequisitePlan.psm1') -Force -DisableNameChecking

$manifest = Get-InstallerCompatibilityManifest
$applicationPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$hostInfo = [PSCustomObject]@{
    Platform = 'Windows'
    DisplayVersion = '26H2'
    BuildNumber = 26300
    ProductType = 'WinNT'
    InstallationType = 'Client'
    EditionId = 'Core'
    Architecture = 'X64'
    DotNetFrameworkRelease = 533325
    IsAdministrator = $false
}
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('App Installer Prerequisite ' + [guid]::NewGuid().ToString('N'))))
$assertionCount = 0
$script:eventLog = New-Object 'System.Collections.Generic.List[string]'

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function New-TestCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Core', 'Desktop')]
        [string]$Engine,

        [string]$Source = 'TestFixture'
    )

    $executableName = if ($Engine -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $path = Join-Path (Join-Path $tempRoot $Name) $executableName
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [System.IO.File]::WriteAllText($path, 'test runtime executable')
    return [PSCustomObject]@{ Path = $path; Engine = $Engine; Source = $Source }
}

function New-TestProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Core', 'Desktop')]
        [string]$Edition,

        [bool]$GuiSupported = $true
    )

    return [PSCustomObject]@{
        Version = $Version
        Edition = $Edition
        ProcessArchitecture = 'X64'
        Is64BitOperatingSystem = $true
        ApartmentState = 'STA'
        GuiCapabilityIsSupported = $GuiSupported
        GuiCapabilityReasonCode = if ($GuiSupported) { 'COMPATIBILITY_SUPPORTED' } else { 'GUI_ASSEMBLY_LOAD_FAILED' }
        GuiCapabilityReason = if ($GuiSupported) { '' } else { 'Required GUI assemblies did not load.' }
    }
}

function New-ProbeResult {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Probe)
    return [PSCustomObject]@{ Success = $true; TimedOut = $false; PolicyBlocked = $false; Reason = ''; Probe = $Probe }
}

function Copy-TestManifest {
    param([string]$Digest)
    $copy = $manifest | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    if ($Digest) {
        $copy.windowsExecutable.runtimeDiscovery.provisioning.sha256 = $Digest
    }
    return $copy
}

function New-TestRuntimeArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$EntryName = 'pwsh.exe',

        [string]$Content = 'unsigned test executable'
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $archive.CreateEntry($EntryName)
        $stream = $entry.Open()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

try {
    [void][System.IO.Directory]::CreateDirectory($tempRoot)

    $core = New-TestCandidate -Name 'compatible-core' -Engine Core
    $coreProbe = New-TestProbe -Version '7.6.7' -Edition Core
    $script:eventLog.Clear()
    $script:downloadCount = 0
    $script:installCount = 0
    $script:launchCount = 0
    $compatible = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:eventLog.Add(('probe:' + $component))
        New-ProbeResult -Probe $coreProbe
    } -ConsentInvoker { $true } -DownloadInvoker {
        param($source, $destination)
        $script:downloadCount++
        [PSCustomObject]@{ Success = $true }
    } -InstallerInvoker {
        param($archive, $plan, $application, $probe, $allowTest, $hostContext, $contract)
        $script:installCount++
        [PSCustomObject]@{ Success = $true; CandidatePath = ''; RebootRequired = $false }
    } -LaunchInvoker {
        param($candidate, $target, $arguments, $component)
        $script:eventLog.Add('launch')
        $script:launchCount++
        [PSCustomObject]@{ Started = $true; ExitCode = 0; Reason = '' }
    }
    Assert-Condition -Condition ($compatible.Status -eq 'Started' -and $compatible.Candidate.Engine -eq 'Core' -and $script:downloadCount -eq 0 -and $script:installCount -eq 0 -and $script:launchCount -eq 1) -Message 'A compatible installed engine launches without download, provisioning, or elevation.'

    $guiWhatIfLaunchCount = 0
    $guiWhatIfProbeCount = 0
    $guiWhatIf = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsGui -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -WhatIf -AlwaysLaunchApplication -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:guiWhatIfProbeCount++
        New-ProbeResult -Probe (New-TestProbe -Version '7.6.7' -Edition Core -GuiSupported $true)
    } -LaunchInvoker {
        param($candidate, $target, $arguments, $component)
        $script:guiWhatIfLaunchCount++
        [PSCustomObject]@{ Started = $true; ExitCode = 0; Reason = '' }
    }
    Assert-Condition -Condition ($guiWhatIf.Status -eq 'PlanOnly' -and $guiWhatIf.Plan.Action -eq 'InspectionOnly' -and $script:guiWhatIfProbeCount -eq 0 -and $script:guiWhatIfLaunchCount -eq 0) -Message 'GUI WhatIf skips candidate discovery, runtime probing, and launching a runtime or GUI process.'

    $guiOnlyGap = Get-InstallerPrerequisitePlan -Component WindowsGui -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $guiSupported = $component -eq 'WindowsCli'
        New-ProbeResult -Probe (New-TestProbe -Version '7.6.7' -Edition Core -GuiSupported $guiSupported)
    }
    Assert-Condition -Condition ($guiOnlyGap.Action -eq 'UseCliFallback' -and $guiOnlyGap.Component -eq 'WindowsCli' -and $null -eq $guiOnlyGap.Provisioning) -Message 'A missing GUI capability selects the already compatible CLI and does not provision another runtime.'

    $invalid = New-TestCandidate -Name 'untrusted-location' -Engine Core -Source 'CoreProgramFiles'
    $invalidPlan = Get-InstallerPrerequisitePlan -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($invalid) -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        throw 'An invalid candidate must not be probed.'
    }
    $safeReason = Get-InstallerSafeCandidateReason -Attempt $invalidPlan.Attempts[0]
    Assert-Condition -Condition ($invalidPlan.Action -eq 'Provision' -and -not $safeReason.Contains($invalid.Path) -and -not $invalidPlan.Reason.Contains($invalid.Path)) -Message 'An invalid candidate is skipped and local executable paths are excluded from the plan summary.'

    $probeFailure = Get-InstallerPrerequisitePlan -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = $false; Reason = 'Probe failed at C:\\Users\\private\\secret'; Probe = $null }
    }
    $probeFailureReason = Get-InstallerSafeCandidateReason -Attempt $probeFailure.Attempts[0]
    Assert-Condition -Condition ($probeFailure.Action -eq 'Provision' -and -not $probeFailureReason.Contains('C:\\Users\\private\\secret')) -Message 'A candidate probe failure is recorded without exposing its local path.'

    $unsupportedHost = [PSCustomObject]@{
        Platform = 'Linux'
        DisplayVersion = ''
        BuildNumber = 0
        ProductType = ''
        InstallationType = ''
        EditionId = ''
        Architecture = 'X64'
        DotNetFrameworkRelease = 0
    }
    $unsupportedPlan = Get-InstallerPrerequisitePlan -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $unsupportedHost -Manifest $manifest
    Assert-Condition -Condition ($unsupportedPlan.Action -eq 'Blocked' -and $null -eq $unsupportedPlan.Provisioning) -Message 'An unsupported host is blocked before any runtime provisioning plan is offered.'
    $unsupportedWhatIf = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsGui -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $unsupportedHost -Manifest $manifest -WhatIf
    Assert-Condition -Condition ($unsupportedWhatIf.Status -eq 'Blocked') -Message 'GUI WhatIf preserves an unsupported-host block instead of reporting a successful preview.'

    $emptyPlan = Get-InstallerPrerequisitePlan -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest
    Assert-Condition -Condition ($emptyPlan.Action -eq 'Provision' -and $emptyPlan.Provisioning.InstallScope -eq 'current-user' -and -not $emptyPlan.Provisioning.RequiresAdministrator -and -not $emptyPlan.Provisioning.ModifiesPath -and -not $emptyPlan.Provisioning.ModifiesDefaultEngine) -Message 'A standard user receives a pinned current-user plan without PATH or default-engine changes.'
    $administratorHostInfo = $hostInfo | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $administratorHostInfo | Add-Member -MemberType NoteProperty -Name IsAdministrator -Value $true -Force
    $administratorPlan = Get-InstallerPrerequisitePlan -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $administratorHostInfo -Manifest $manifest
    Assert-Condition -Condition ($administratorPlan.Action -eq 'Provision' -and $administratorPlan.Provisioning.InstallScope -eq 'current-user' -and -not $administratorPlan.Provisioning.RequiresAdministrator -and -not $administratorPlan.Provisioning.ModifiesPath -and -not $administratorPlan.Provisioning.ModifiesDefaultEngine) -Message 'An administrator receives the same current-user runtime plan without PATH or default-engine changes.'

    $runtimeArchivePath = Join-Path $tempRoot 'unsigned-runtime.zip'
    $runtimeInstallRoot = Join-Path $tempRoot 'runtime-install-fixture'
    New-TestRuntimeArchive -Path $runtimeArchivePath
    $signatureRejected = Install-InstallerRuntimeArtifact -ArchivePath $runtimeArchivePath -Plan $emptyPlan -ApplicationPath $applicationPath -HostInfo $hostInfo -Manifest $manifest -RuntimeRoot $runtimeInstallRoot -ProbeInvoker {
        throw 'Signature failure must stop before compatibility probing.'
    }
    Assert-Condition -Condition (-not $signatureRejected.Success -and $signatureRejected.FailureCode -eq 'SignatureMismatch' -and -not (Test-Path -LiteralPath (Join-Path $runtimeInstallRoot 'Programs'))) -Message 'An invalid executable signature is rejected before promotion and removes the partial staging tree.'

    $missingCommandArchive = Join-Path $tempRoot 'missing-command.zip'
    New-TestRuntimeArchive -Path $missingCommandArchive -EntryName 'not-pwsh.txt'
    $missingCommand = Install-InstallerRuntimeArtifact -ArchivePath $missingCommandArchive -Plan $emptyPlan -ApplicationPath $applicationPath -HostInfo $hostInfo -Manifest $manifest -RuntimeRoot $runtimeInstallRoot
    Assert-Condition -Condition (-not $missingCommand.Success -and $missingCommand.FailureCode -eq 'RuntimeCommandMissing') -Message 'An archive without pwsh.exe is rejected before compatibility probing or app launch.'

    $traversalArchive = Join-Path $tempRoot 'path-traversal.zip'
    $traversalDestination = Join-Path $tempRoot 'safe-extract-root'
    New-TestRuntimeArchive -Path $traversalArchive -EntryName '..\escaped.txt'
    $traversalRejected = $false
    try {
        Expand-InstallerRuntimeArchiveSafely -ArchivePath $traversalArchive -DestinationPath $traversalDestination
    }
    catch {
        $traversalRejected = $true
    }
    Assert-Condition -Condition ($traversalRejected -and -not (Test-Path -LiteralPath (Join-Path $tempRoot 'escaped.txt'))) -Message 'Archive path traversal is rejected before writing outside the extraction directory.'

    $declineTemp = Join-Path $tempRoot 'declined-work'
    $script:eventLog.Clear()
    $script:declinedDownloadCount = 0
    $declined = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProvisioningTempRoot $declineTemp -ConsentInvoker {
        param($plan)
        $script:eventLog.Add('consent:no')
        return $false
    } -DownloadInvoker {
        param($source, $destination)
        $script:declinedDownloadCount++
        [PSCustomObject]@{ Success = $true }
    }
    Assert-Condition -Condition ($declined.Status -eq 'Declined' -and $script:declinedDownloadCount -eq 0 -and -not (Test-Path -LiteralPath $declineTemp)) -Message 'Declining consent makes no download or filesystem change.'

    $cancelTemp = Join-Path $tempRoot 'cancelled-work'
    $script:cancelledDownloadCount = 0
    $cancelled = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProvisioningTempRoot $cancelTemp -ConsentInvoker {
        throw [System.OperationCanceledException]::new('Simulated consent cancellation.')
    } -DownloadInvoker {
        param($source, $destination)
        $script:cancelledDownloadCount++
        [PSCustomObject]@{ Success = $true }
    }
    Assert-Condition -Condition ($cancelled.Status -eq 'Declined' -and $script:cancelledDownloadCount -eq 0 -and -not (Test-Path -LiteralPath $cancelTemp)) -Message 'A cancelled consent prompt stops before download and leaves no temporary directory.'

    $whatIfTemp = Join-Path $tempRoot 'whatif-work'
    $script:whatIfDownloadCount = 0
    $script:whatIfInstallCount = 0
    $script:whatIfElevationCount = 0
    $script:whatIfLaunchCount = 0
    $script:whatIfProbeCount = 0
    $script:whatIfConsentCount = 0
    $global:AppInstallerWhatIfPackageQueryCount = 0
    function global:Get-AppxPackage {
        [CmdletBinding()]
        param([string]$Name)
        $global:AppInstallerWhatIfPackageQueryCount++
        throw 'A package query was invoked during WhatIf.'
    }
    try {
        $whatIfResult = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProvisioningTempRoot $whatIfTemp -WhatIf -ConsentInvoker {
            $script:whatIfConsentCount++
            $true
        } -ProbeInvoker {
            param($candidate, $component, $target, $timeout)
            $script:whatIfProbeCount++
            New-ProbeResult -Probe $coreProbe
        } -DownloadInvoker {
            param($source, $destination)
            $script:whatIfDownloadCount++
            [PSCustomObject]@{ Success = $true }
        } -InstallerInvoker {
            param($archive, $plan, $application, $probe, $allowTest, $hostContext, $contract)
            $script:whatIfInstallCount++
            [PSCustomObject]@{ Success = $true; CandidatePath = ''; RebootRequired = $false }
        } -ElevationInvoker {
            param($plan)
            $script:whatIfElevationCount++
            [PSCustomObject]@{ Success = $true }
        } -LaunchInvoker {
            param($candidate, $target, $arguments, $component)
            $script:whatIfLaunchCount++
            [PSCustomObject]@{ Started = $true; ExitCode = 0; Reason = '' }
        }
    }
    finally {
        Remove-Item -LiteralPath Function:\global:Get-AppxPackage -ErrorAction SilentlyContinue
        $whatIfPackageQueryCount = [int]$global:AppInstallerWhatIfPackageQueryCount
        Remove-Variable -Name AppInstallerWhatIfPackageQueryCount -Scope Global -ErrorAction SilentlyContinue
    }
    Assert-Condition -Condition ($whatIfResult.Status -eq 'PlanOnly' -and $script:whatIfProbeCount -eq 0 -and $whatIfPackageQueryCount -eq 0 -and $script:whatIfConsentCount -eq 0 -and $script:whatIfDownloadCount -eq 0 -and $script:whatIfInstallCount -eq 0 -and $script:whatIfElevationCount -eq 0 -and $script:whatIfLaunchCount -eq 0 -and -not (Test-Path -LiteralPath $whatIfTemp)) -Message 'WhatIf starts no package query, probe, consent, download, install, elevation, or launch callback and creates no temporary files.'

    $script:policyConsentCount = 0
    $script:policyDownloadCount = 0
    $policyBlocked = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @($core) -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProvisioningTempRoot (Join-Path $tempRoot 'policy-blocked-work') -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = $true; Reason = 'Execution policy blocked the compatibility probe.'; Probe = $null }
    } -ConsentInvoker {
        $script:policyConsentCount++
        $true
    } -DownloadInvoker {
        param($source, $destination)
        $script:policyDownloadCount++
        [PSCustomObject]@{ Success = $true }
    }
    Assert-Condition -Condition ($policyBlocked.Status -eq 'Blocked' -and $script:policyConsentCount -eq 0 -and $script:policyDownloadCount -eq 0) -Message 'An execution-policy refusal blocks provisioning before consent or download.'

    $digestPath = Join-Path $tempRoot 'digest-mismatch.zip'
    $digestData = [System.Text.Encoding]::UTF8.GetBytes('not the pinned runtime')
    $digestHash = [System.Security.Cryptography.SHA256]::Create()
    try { $testDigest = ([BitConverter]::ToString($digestHash.ComputeHash($digestData))).Replace('-', '') } finally { $digestHash.Dispose() }
    $digestManifest = Copy-TestManifest -Digest ('0' * 64)
    $digestTemp = Join-Path $tempRoot 'digest-work'
    $script:digestInstallCount = 0
    $digestFailure = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $hostInfo -Manifest $digestManifest -ProvisioningTempRoot $digestTemp -ConsentInvoker { $true } -DownloadInvoker {
        param($source, $destination)
        [System.IO.File]::WriteAllBytes($destination, $digestData)
        [PSCustomObject]@{ Success = $true }
    } -InstallerInvoker {
        param($archive, $plan, $application, $probe, $allowTest, $hostContext, $contract)
        $script:digestInstallCount++
        [PSCustomObject]@{ Success = $true; CandidatePath = ''; RebootRequired = $false }
    }
    Assert-Condition -Condition ($digestFailure.Status -eq 'Failed' -and $digestFailure.Reason -match 'digest' -and $script:digestInstallCount -eq 0 -and -not (Test-Path -LiteralPath $digestTemp)) -Message 'A digest mismatch rejects the archive before installer invocation and cleans the temporary download.'

    $downloadFailureTemp = Join-Path $tempRoot 'download-failure-work'
    $script:downloadFailureInstallCount = 0
    $downloadFailure = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $hostInfo -Manifest $manifest -ProvisioningTempRoot $downloadFailureTemp -ConsentInvoker { $true } -DownloadInvoker {
        param($source, $destination)
        [PSCustomObject]@{ Success = $false }
    } -InstallerInvoker {
        param($archive, $plan, $application, $probe, $allowTest, $hostContext, $contract)
        $script:downloadFailureInstallCount++
        [PSCustomObject]@{ Success = $true; CandidatePath = ''; RebootRequired = $false }
    }
    Assert-Condition -Condition ($downloadFailure.Status -eq 'Failed' -and $script:downloadFailureInstallCount -eq 0 -and -not (Test-Path -LiteralPath $downloadFailureTemp)) -Message 'A failed download stops before installer invocation and leaves no temporary files.'

    $failedInstallCases = @(
        @{ FailureCode = 'SignatureMismatch'; RebootRequired = $false; Expected = 'signature' },
        @{ FailureCode = 'RuntimeCommandMissing'; RebootRequired = $false; Expected = 'command' },
        @{ FailureCode = 'ProvisionFailed'; RebootRequired = $false; Expected = 'provisioning' },
        @{ FailureCode = ''; RebootRequired = $true; Expected = 'reboot' }
    )
    foreach ($failureCase in $failedInstallCases) {
        $caseTemp = Join-Path $tempRoot ('failure-' + $failureCase.Expected)
        $caseArchive = Join-Path $caseTemp 'runtime.zip'
        $caseManifest = Copy-TestManifest -Digest $testDigest
        $script:caseLaunchCount = 0
        $caseResult = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsCli -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $hostInfo -Manifest $caseManifest -ProvisioningTempRoot $caseTemp -ConsentInvoker { $true } -DownloadInvoker {
            param($source, $destination)
            [System.IO.File]::WriteAllBytes($destination, $digestData)
            [PSCustomObject]@{ Success = $true }
        } -InstallerInvoker {
            param($archive, $plan, $application, $probe, $allowTest, $hostContext, $contract)
            [PSCustomObject]@{ Success = $false; FailureCode = $failureCase.FailureCode; CandidatePath = ''; RebootRequired = $failureCase.RebootRequired }
        } -LaunchInvoker {
            param($candidate, $target, $arguments, $component)
            $script:caseLaunchCount++
            [PSCustomObject]@{ Started = $true; ExitCode = 0; Reason = '' }
        }
        Assert-Condition -Condition ($caseResult.Status -eq 'Failed' -and $caseResult.Reason -match $failureCase.Expected -and $script:caseLaunchCount -eq 0 -and -not (Test-Path -LiteralPath $caseTemp)) -Message ("A {0} result stops before application launch and removes the temporary archive." -f $failureCase.Expected)
    }

    $provisioned = New-TestCandidate -Name 'new-runtime' -Engine Core
    $packageBytes = [System.Text.Encoding]::UTF8.GetBytes('offline package fixture')
    $packageHasher = [System.Security.Cryptography.SHA256]::Create()
    try { $packageDigest = ([BitConverter]::ToString($packageHasher.ComputeHash($packageBytes))).Replace('-', '') } finally { $packageHasher.Dispose() }
    $provisionedManifest = Copy-TestManifest -Digest $packageDigest
    $successTemp = Join-Path $tempRoot 'success-work'
    $script:eventLog.Clear()
    $success = Invoke-InstallerRuntimePrerequisiteFlow -Component WindowsGui -ApplicationPath $applicationPath -CandidateRecords @() -AllowTestCandidates -HostInfo $administratorHostInfo -Manifest $provisionedManifest -ProvisioningTempRoot $successTemp -AlwaysLaunchApplication -ConsentInvoker {
        param($plan)
        $script:eventLog.Add('consent:yes')
        $true
    } -DownloadInvoker {
        param($source, $destination)
        $script:eventLog.Add('download:' + $source.Source)
        [System.IO.File]::WriteAllBytes($destination, $packageBytes)
        [PSCustomObject]@{ Success = $true }
    } -InstallerInvoker {
        param($archive, $plan, $application, $probe, $allowTest, $hostContext, $contract)
        $script:eventLog.Add('install')
        [PSCustomObject]@{ Success = $true; FailureCode = ''; CandidatePath = $provisioned.Path; RebootRequired = $false }
    } -CandidateDiscoverer {
        param($contract)
        $script:eventLog.Add('rediscover')
        @($provisioned)
    } -ProbeInvoker {
        param($candidate, $component, $target, $timeout)
        $script:eventLog.Add(('validate:' + $component))
        New-ProbeResult -Probe (New-TestProbe -Version '7.6.7' -Edition Core)
    } -ElevationInvoker {
        param($plan)
        $script:eventLog.Add('elevation')
        [PSCustomObject]@{ Success = $true }
    } -LaunchInvoker {
        param($candidate, $target, $arguments, $component)
        $script:eventLog.Add(('launch:' + $component))
        [PSCustomObject]@{ Started = $true; ExitCode = 0; Reason = '' }
    }
    $rediscoverIndex = $script:eventLog.IndexOf('rediscover')
    $validationIndex = $script:eventLog.IndexOf('validate:WindowsCli')
    $launchIndex = $script:eventLog.IndexOf('launch:WindowsCli')
    Assert-Condition -Condition ($success.Status -eq 'Started' -and $success.Candidate.Path -eq $provisioned.Path -and $rediscoverIndex -ge 0 -and $validationIndex -gt $rediscoverIndex -and $launchIndex -gt $validationIndex -and $script:eventLog -notcontains 'elevation') -Message 'Successful provisioning is rediscovered and revalidated from the exact path before CLI launch without elevation.'
    Assert-Condition -Condition ($script:eventLog[0] -eq 'consent:yes' -and $script:eventLog[1] -like 'download:https://github.com/PowerShell/PowerShell/releases/download/v7.6.7/*' -and $script:eventLog[2] -eq 'install') -Message 'Consent precedes the injected exact-source download and installer operation.'
    Assert-Condition -Condition ($success.Plan.Provisioning.InstallScope -eq 'current-user' -and $success.Plan.Provisioning.InstallLocation -match '%LOCALAPPDATA%' -and -not $success.Plan.Provisioning.RequiresAdministrator -and -not $success.Plan.Provisioning.ModifiesPath -and -not $success.Plan.Provisioning.ModifiesDefaultEngine -and $script:eventLog -notcontains 'elevation') -Message 'Accepted provisioning uses the exact per-user target without elevation, PATH updates, or default-engine changes.'

    Write-Host "[OK] Runtime prerequisite planning tests passed ($assertionCount assertions)." -ForegroundColor Green
}
finally {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedTempRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
