$runtimeModulePath = Join-Path $PSScriptRoot 'InstallerRuntimeDiscovery.psm1'
if (-not (Get-Command -Name Resolve-InstallerRuntime -ErrorAction SilentlyContinue)) {
    Import-Module -Name $runtimeModulePath -Force -DisableNameChecking -ErrorAction Stop
}

if (-not (Get-Command -Name Get-InstallerCompatibilityManifest -ErrorAction SilentlyContinue)) {
    $compatibilityModulePath = Join-Path $PSScriptRoot 'InstallerCompatibility.psm1'
    Import-Module -Name $compatibilityModulePath -Force -DisableNameChecking -ErrorAction Stop
}

function Get-InstallerSafeCandidateReason {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Attempt
    )

    $reason = [string]$Attempt.Reason
    if ([string]::IsNullOrWhiteSpace($reason)) {
        return 'The candidate did not pass the application compatibility check.'
    }
    if ($reason -match '(?i)execution policy|running scripts is disabled|not digitally signed') {
        return 'The execution policy blocked this candidate. No policy setting was changed.'
    }
    if ($reason -match '(?i)timed out|timeout') {
        return 'The compatibility probe timed out.'
    }
    if ($reason -match '(?i)architecture|x64|64-bit') {
        return 'The candidate does not meet the required x64 architecture.'
    }
    if ($reason -match '(?i)\b(GUI|Forms|Drawing|Framework|desktop runtime|assembly|STA)\b') {
        return 'A required GUI component or capability is missing or could not be loaded.'
    }
    if ($reason -match '(?i)version|edition|support contract') {
        return 'The installed PowerShell edition or version is outside the supported contract.'
    }
    if ($null -eq $Attempt.Probe) {
        return 'The compatibility probe could not verify this candidate. Local details were withheld.'
    }
    return 'The candidate did not pass the application compatibility check.'
}

function Get-InstallerPrerequisitePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsCli', 'WindowsGui')]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$ApplicationPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CandidateRecords,

        [Parameter()]
        [scriptblock]$ProbeInvoker,

        [Parameter()]
        [scriptblock]$WingetAvailabilityProbe,

        [Parameter()]
        [switch]$AllowTestCandidates,

        [Parameter()]
        [PSCustomObject]$HostInfo = (Get-InstallerHostInfo),

        [Parameter()]
        [PSCustomObject]$Manifest = (Get-InstallerCompatibilityManifest)
    )

    if ($null -eq $CandidateRecords) {
        $CandidateRecords = @(Get-InstallerRuntimeCandidates -Manifest $Manifest)
    }

    $hostDecision = Get-InstallerHostPreflight -Component WindowsHost -HostInfo $HostInfo -Manifest $Manifest -WingetAvailabilityProbe $WingetAvailabilityProbe
    if (-not $hostDecision.IsSupported) {
        return [PSCustomObject]@{
            Action = 'Blocked'
            RequestedComponent = $Component
            Component = $Component
            CandidateRecords = @($CandidateRecords)
            Attempts = @()
            Selected = $null
            Provisioning = $null
            HostPreflight = $hostDecision
            Reason = if ($hostDecision.Message) { [string]$hostDecision.Message } else { [string]$hostDecision.Reason }
        }
    }

    $requestedDecision = Resolve-InstallerRuntime -Component $Component -ApplicationPath $ApplicationPath -CandidateRecords $CandidateRecords -ProbeInvoker $ProbeInvoker -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
    if ($requestedDecision.IsSupported) {
        return [PSCustomObject]@{
            Action = 'UseExisting'
            RequestedComponent = $Component
            Component = $Component
            CandidateRecords = @($CandidateRecords)
            Attempts = @($requestedDecision.Attempts)
            Selected = $requestedDecision.Selected
            Provisioning = $null
            Reason = ''
        }
    }
    if ($requestedDecision.PolicyBlocked) {
        return [PSCustomObject]@{
            Action = 'Blocked'
            RequestedComponent = $Component
            Component = $Component
            CandidateRecords = @($CandidateRecords)
            Attempts = @($requestedDecision.Attempts)
            Selected = $null
            Provisioning = $null
            Reason = 'Execution policy prevented a candidate probe. No alternate engine was started and no policy setting was changed.'
        }
    }

    $attempts = New-Object 'System.Collections.Generic.List[object]'
    foreach ($attempt in $requestedDecision.Attempts) {
        $attempts.Add($attempt)
    }

    if ($Component -eq 'WindowsGui') {
        $cliDecision = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $ApplicationPath -CandidateRecords $CandidateRecords -ProbeInvoker $ProbeInvoker -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
        foreach ($attempt in $cliDecision.Attempts) {
            $attempts.Add($attempt)
        }
        if ($cliDecision.IsSupported) {
            return [PSCustomObject]@{
                Action = 'UseCliFallback'
                RequestedComponent = $Component
                Component = 'WindowsCli'
                CandidateRecords = @($CandidateRecords)
                Attempts = $attempts.ToArray()
                Selected = $cliDecision.Selected
                Provisioning = $null
                Reason = 'No compatible GUI capability was found. A compatible installed PowerShell engine can run the CLI.'
            }
        }
        if ($cliDecision.PolicyBlocked) {
            return [PSCustomObject]@{
                Action = 'Blocked'
                RequestedComponent = $Component
                Component = 'WindowsCli'
                CandidateRecords = @($CandidateRecords)
                Attempts = $attempts.ToArray()
                Selected = $null
                Provisioning = $null
                Reason = 'Execution policy prevented a candidate probe. No alternate engine was started and no policy setting was changed.'
            }
        }
    }

    $provisioning = $Manifest.windowsExecutable.runtimeDiscovery.provisioning
    $runtimeDiscovery = $Manifest.windowsExecutable.runtimeDiscovery
    $coreVersion = [string]$Manifest.engines.powerShellCore.version
    $selectedArchitecture = [string]$hostDecision.SelectedPackageArchitecture
    $expectedName = 'PowerShell-{0}-win-{1}.zip' -f $coreVersion, $selectedArchitecture.ToLowerInvariant()
    $expectedUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v{0}/{1}' -f $coreVersion, $expectedName
    $expectedInstallLocation = '%LOCALAPPDATA%\Programs\myTech.Today\AppInstaller\PowerShell\{0}' -f $coreVersion
    $sourceUri = $null
    $provisioningIsPinned = ($null -ne $provisioning) -and
        ($runtimeDiscovery.automaticProvisioning -eq $false) -and
        ($runtimeDiscovery.consentRequiredProvisioning -eq $true) -and
        ([string]$provisioning.engine -eq 'Core') -and
        ([string]$provisioning.version -eq $coreVersion) -and
        ([string]$provisioning.architecture -ceq $selectedArchitecture) -and
        ([string]$provisioning.artifactName -ceq $expectedName) -and
        ([string]$provisioning.source -ceq $expectedUrl) -and
        ([string]$provisioning.installLocation -ceq $expectedInstallLocation) -and
        ([string]$provisioning.sha256 -match '^[A-Fa-f0-9]{64}$') -and
        ([string]$provisioning.signer -match '(?i)^Microsoft Corporation$') -and
        ([string]$provisioning.installScope -eq 'current-user') -and
        ($provisioning.requiresAdministrator -eq $false) -and
        ($provisioning.modifiesPath -eq $false) -and
        ($provisioning.modifiesDefaultEngine -eq $false) -and
        [System.Uri]::TryCreate([string]$provisioning.source, [System.UriKind]::Absolute, [ref]$sourceUri) -and
        ($sourceUri.Scheme -eq 'https') -and
        ($sourceUri.Host -eq 'github.com')

    if (-not $provisioningIsPinned) {
        return [PSCustomObject]@{
            Action = 'Blocked'
            RequestedComponent = $Component
            Component = 'WindowsCli'
            CandidateRecords = @($CandidateRecords)
            Attempts = $attempts.ToArray()
            Selected = $null
            Provisioning = $null
            Reason = 'A complete, pinned PowerShell provisioning source is not available. No download or install was attempted.'
        }
    }

    return [PSCustomObject]@{
        Action = 'Provision'
        RequestedComponent = $Component
        Component = 'WindowsCli'
        CandidateRecords = @($CandidateRecords)
        Attempts = $attempts.ToArray()
        Selected = $null
        Provisioning = [PSCustomObject]@{
            Engine = 'Core'
            Version = $coreVersion
            Architecture = $selectedArchitecture
            ArtifactName = [string]$provisioning.artifactName
            Source = [string]$provisioning.source
            Sha256 = ([string]$provisioning.sha256).ToUpperInvariant()
            Signer = [string]$provisioning.signer
            InstallScope = [string]$provisioning.installScope
            RequiresAdministrator = [bool]$provisioning.requiresAdministrator
            ModifiesPath = [bool]$provisioning.modifiesPath
            ModifiesDefaultEngine = [bool]$provisioning.modifiesDefaultEngine
            InstallLocation = [string]$provisioning.installLocation
        }
        Reason = 'No installed PowerShell candidate satisfies the CLI support contract.'
    }
}

function Write-InstallerPrerequisitePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Plan
    )

    if ($Plan.Action -eq 'InspectionOnly') {
        Write-Host '[PLAN] WhatIf skipped package and runtime candidate discovery, compatibility probes, and launcher handoff.' -ForegroundColor Yellow
        Write-Host '[PLAN] Runtime compatibility and the need for provisioning remain unverified. No runtime or application process will be started.' -ForegroundColor Yellow
        return
    }

    Write-Host '[PREFLIGHT] PowerShell candidates were checked before provisioning.' -ForegroundColor Cyan
    if (@($Plan.Attempts).Count -eq 0) {
        Write-Host '[PREFLIGHT] No documented PowerShell candidate was found.' -ForegroundColor Yellow
    }
    foreach ($attempt in $Plan.Attempts) {
        $engine = if ([string]$attempt.Candidate.Engine -eq 'Core') { 'PowerShell Core' } else { 'Windows PowerShell' }
        $version = 'version unverified'
        if ($null -ne $attempt.Probe -and $attempt.Probe.Version) {
            try { $version = ([version][string]$attempt.Probe.Version).ToString() } catch { }
        }
        $status = if ($attempt.IsCompatible) { 'compatible' } else { 'not compatible' }
        if ($attempt.IsCompatible -and $null -ne $Plan.Selected -and [string]$attempt.Candidate.Path -ieq [string]$Plan.Selected.Path) {
            $status += ' and selected'
        }
        $line = '[PREFLIGHT] {0} {1}: {2}' -f $engine, $version, $status
        if (-not $attempt.IsCompatible) {
            $line += '. ' + (Get-InstallerSafeCandidateReason -Attempt $attempt)
        }
        Write-Host $line
    }

    if ($Plan.Action -eq 'UseCliFallback') {
        Write-Host '[PLAN] The GUI requirements are not available. The compatible installed CLI will be used.' -ForegroundColor Yellow
    }
    elseif ($Plan.Action -eq 'Provision') {
        $provisioning = $Plan.Provisioning
        Write-Host ('[PLAN] PowerShell Core {0} {1} will be downloaded from {2}.' -f $provisioning.Version, $provisioning.Architecture, $provisioning.Source) -ForegroundColor Yellow
        Write-Host ('[PLAN] SHA-256 must match {0}; the extracted PowerShell executable must have a valid {1} signature.' -f $provisioning.Sha256, $provisioning.Signer) -ForegroundColor Yellow
        Write-Host ('[PLAN] Install scope: {0}; destination: {1}. Administrator privileges are not required.' -f $provisioning.InstallScope, $provisioning.InstallLocation) -ForegroundColor Yellow
        Write-Host '[PLAN] The installer will not change PATH, the default PowerShell engine, or other PowerShell versions.' -ForegroundColor Yellow
    }
    elseif ($Plan.Action -eq 'Blocked' -and $Plan.Reason) {
        Write-Host ('[PLAN] {0}' -f [string]$Plan.Reason) -ForegroundColor Red
    }
}

function Test-InstallerRuntimeSigner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSigner
    )

    try {
        $signature = Get-AuthenticodeSignature -FilePath $LiteralPath -ErrorAction Stop
        if ($null -eq $signature -or [string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
            return $false
        }
        $subject = [string]$signature.SignerCertificate.Subject
        return ($subject -match ('(?i)(?:^|,\s*)CN={0}(?:,|$)' -f [regex]::Escape($ExpectedSigner)))
    }
    catch {
        return $false
    }
}

function Expand-InstallerRuntimeArchiveSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd('\') + '\'
    [void][System.IO.Directory]::CreateDirectory($destinationFullPath)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -gt 5000) {
            throw 'The runtime archive contains too many files.'
        }
        $totalExpandedBytes = [long]0
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrWhiteSpace([string]$entry.FullName) -or $entry.FullName -match '[\x00-\x1F]') {
                throw 'The runtime archive contains an invalid entry name.'
            }
            $destination = [System.IO.Path]::GetFullPath((Join-Path $destinationFullPath $entry.FullName))
            if (-not $destination.StartsWith($destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'The runtime archive contains an entry outside the staging directory.'
            }
            $unixFileType = ([int]$entry.ExternalAttributes -shr 16) -band 0xF000
            if ($unixFileType -eq 0xA000) {
                throw 'The runtime archive contains an unsupported symbolic link.'
            }
            $totalExpandedBytes += [long]$entry.Length
            if ($totalExpandedBytes -gt 800000000) {
                throw 'The runtime archive exceeds the allowed expanded size.'
            }
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                [void][System.IO.Directory]::CreateDirectory($destination)
                continue
            }
            $parentPath = [System.IO.Path]::GetDirectoryName($destination)
            [void][System.IO.Directory]::CreateDirectory($parentPath)
            $inputStream = $entry.Open()
            try {
                $outputStream = New-Object System.IO.FileStream($destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try {
                    $inputStream.CopyTo($outputStream)
                }
                finally {
                    $outputStream.Dispose()
                }
            }
            finally {
                $inputStream.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Install-InstallerRuntimeArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Plan,

        [Parameter(Mandatory = $true)]
        [string]$ApplicationPath,

        [Parameter()]
        [scriptblock]$ProbeInvoker,

        [Parameter()]
        [scriptblock]$WingetAvailabilityProbe,

        [Parameter()]
        [switch]$AllowTestCandidates,

        [Parameter()]
        [PSCustomObject]$HostInfo = (Get-InstallerHostInfo),

        [Parameter()]
        [string]$RuntimeRoot = [string]$env:LOCALAPPDATA,

        [Parameter()]
        [PSCustomObject]$Manifest = (Get-InstallerCompatibilityManifest)
    )

    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
        return [PSCustomObject]@{ Success = $false; FailureCode = 'InstallLocationUnavailable'; CandidatePath = ''; RebootRequired = $false }
    }
    $installRoot = Join-Path $RuntimeRoot 'Programs\myTech.Today\AppInstaller\PowerShell'
    $targetPath = Join-Path $installRoot ([string]$Plan.Provisioning.Version)
    $stageRoot = Join-Path $installRoot ('.stage-' + [guid]::NewGuid().ToString('N'))
    $payloadPath = Join-Path $stageRoot 'payload'
    $backupPath = ''
    $promoted = $false
    $markerName = '.app-installer-runtime.json'
    $runtimeRootFullPath = [System.IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\')
    $cleanupDirectories = New-Object 'System.Collections.Generic.List[string]'
    $directoriesPresentBeforeInstall = New-Object 'System.Collections.Generic.List[string]'
    $directoryCursor = [System.IO.Path]::GetFullPath($installRoot)
    while ($directoryCursor.StartsWith(($runtimeRootFullPath + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        $cleanupDirectories.Add($directoryCursor)
        if ([System.IO.Directory]::Exists($directoryCursor)) {
            $directoriesPresentBeforeInstall.Add($directoryCursor)
        }
        $parentCursor = [System.IO.Path]::GetDirectoryName($directoryCursor)
        if ([string]::IsNullOrWhiteSpace($parentCursor) -or $parentCursor.Equals($runtimeRootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $directoryCursor = $parentCursor
    }

    try {
        [void][System.IO.Directory]::CreateDirectory($stageRoot)
        Expand-InstallerRuntimeArchiveSafely -ArchivePath $ArchivePath -DestinationPath $payloadPath
        $stagedExecutable = Join-Path $payloadPath 'pwsh.exe'
        if (-not [System.IO.File]::Exists($stagedExecutable)) {
            return [PSCustomObject]@{ Success = $false; FailureCode = 'RuntimeCommandMissing'; CandidatePath = ''; RebootRequired = $false }
        }
        if (-not (Test-InstallerRuntimeSigner -LiteralPath $stagedExecutable -ExpectedSigner $Plan.Provisioning.Signer)) {
            return [PSCustomObject]@{ Success = $false; FailureCode = 'SignatureMismatch'; CandidatePath = ''; RebootRequired = $false }
        }

        $marker = [PSCustomObject]@{ Product = 'AppInstaller'; Engine = 'Core'; Version = [string]$Plan.Provisioning.Version; Sha256 = [string]$Plan.Provisioning.Sha256 }
        [System.IO.File]::WriteAllText((Join-Path $payloadPath $markerName), ($marker | ConvertTo-Json -Compress), [System.Text.Encoding]::UTF8)

        $stageCandidate = [PSCustomObject]@{ Path = $stagedExecutable; Engine = 'Core'; Source = 'AppInstallerManaged' }
        $stageDecision = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $ApplicationPath -CandidateRecords @($stageCandidate) -ProbeInvoker $ProbeInvoker -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
        if (-not $stageDecision.IsSupported) {
            return [PSCustomObject]@{ Success = $false; FailureCode = 'StagedRuntimeIncompatible'; CandidatePath = ''; RebootRequired = $false }
        }

        [void][System.IO.Directory]::CreateDirectory($installRoot)
        if ([System.IO.Directory]::Exists($targetPath)) {
            $existingMarkerPath = Join-Path $targetPath $markerName
            $ownedTarget = $false
            if ([System.IO.File]::Exists($existingMarkerPath)) {
                try {
                    $existingMarker = Get-Content -LiteralPath $existingMarkerPath -Raw | ConvertFrom-Json -ErrorAction Stop
                    $ownedTarget = ([string]$existingMarker.Product -eq 'AppInstaller') -and ([string]$existingMarker.Version -eq [string]$Plan.Provisioning.Version) -and ([string]$existingMarker.Sha256 -eq [string]$Plan.Provisioning.Sha256)
                }
                catch {
                    $ownedTarget = $false
                }
            }
            if (-not $ownedTarget) {
                return [PSCustomObject]@{ Success = $false; FailureCode = 'InstallLocationOccupied'; CandidatePath = ''; RebootRequired = $false }
            }
            $recoveryRoot = Join-Path $installRoot '.recovery'
            [void][System.IO.Directory]::CreateDirectory($recoveryRoot)
            $backupPath = Join-Path $recoveryRoot ('runtime-' + [guid]::NewGuid().ToString('N'))
            [System.IO.Directory]::Move($targetPath, $backupPath)
        }

        [System.IO.Directory]::Move($payloadPath, $targetPath)
        $promoted = $true
        return [PSCustomObject]@{
            Success = $true
            FailureCode = ''
            CandidatePath = (Join-Path $targetPath 'pwsh.exe')
            RebootRequired = $false
            PreviousRuntimeRecoveryAvailable = (-not [string]::IsNullOrWhiteSpace($backupPath))
        }
    }
    catch {
        if (-not $promoted -and -not [string]::IsNullOrWhiteSpace($backupPath) -and [System.IO.Directory]::Exists($backupPath) -and -not [System.IO.Directory]::Exists($targetPath)) {
            try { [System.IO.Directory]::Move($backupPath, $targetPath) } catch {}
        }
        return [PSCustomObject]@{ Success = $false; FailureCode = 'ProvisionFailed'; CandidatePath = ''; RebootRequired = $false }
    }
    finally {
        if ([System.IO.Directory]::Exists($stageRoot)) {
            try {
                Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction Stop
            }
            catch {
            }
        }
        foreach ($cleanupDirectory in $cleanupDirectories) {
            if ($directoriesPresentBeforeInstall -contains $cleanupDirectory) {
                break
            }
            if (-not [System.IO.Directory]::Exists($cleanupDirectory)) {
                continue
            }
            try {
                if ([System.IO.Directory]::GetFileSystemEntries($cleanupDirectory).Length -ne 0) {
                    break
                }
                [System.IO.Directory]::Delete($cleanupDirectory)
            }
            catch {
                break
            }
        }
    }
}

function Invoke-InstallerRuntimePrerequisiteFlow {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsCli', 'WindowsGui')]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$ApplicationPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ScriptArguments = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CandidateRecords,

        [Parameter()]
        [scriptblock]$ProbeInvoker,

        [Parameter()]
        [scriptblock]$WingetAvailabilityProbe,

        [Parameter()]
        [scriptblock]$CandidateDiscoverer,

        [Parameter()]
        [scriptblock]$ConsentInvoker,

        [Parameter()]
        [scriptblock]$DownloadInvoker,

        [Parameter()]
        [scriptblock]$InstallerInvoker,

        [Parameter()]
        [scriptblock]$ElevationInvoker,

        [Parameter()]
        [scriptblock]$LaunchInvoker,

        [Parameter()]
        [switch]$AllowGuiCliFallback,

        [Parameter()]
        [switch]$AlwaysLaunchApplication,

        [Parameter()]
        [switch]$AllowTestCandidates,

        [Parameter()]
        [string]$ProvisioningTempRoot = [System.IO.Path]::GetTempPath(),

        [Parameter()]
        [PSCustomObject]$HostInfo = (Get-InstallerHostInfo),

        [Parameter()]
        [PSCustomObject]$Manifest = (Get-InstallerCompatibilityManifest)
    )

    if ($WhatIfPreference) {
        $previewHostDecision = Get-InstallerHostPreflight -Component WindowsHost -HostInfo $HostInfo -Manifest $Manifest -WingetAvailabilityProbe $WingetAvailabilityProbe
        $previewReason = 'WhatIf skips runtime and package discovery, so compatibility and provisioning need were not verified.'
        $previewStatus = 'PlanOnly'
        $previewAction = 'InspectionOnly'

        if (-not $previewHostDecision.IsSupported) {
            $previewAction = 'Blocked'
            $previewStatus = 'Blocked'
            $previewReason = if ($previewHostDecision.Message) { [string]$previewHostDecision.Message } else { [string]$previewHostDecision.Reason }
        }
        $previewPlan = [PSCustomObject]@{
            Action = $previewAction
            RequestedComponent = $Component
            Component = $Component
            CandidateRecords = @()
            Attempts = @()
            Selected = $null
            Provisioning = $null
            Reason = $previewReason
        }
        Write-InstallerPrerequisitePlan -Plan $previewPlan
        return [PSCustomObject]@{ Status = $previewStatus; Plan = $previewPlan; RuntimeDecision = $null; Candidate = $null; Reason = $previewReason }
    }

    $plan = Get-InstallerPrerequisitePlan -Component $Component -ApplicationPath $ApplicationPath -CandidateRecords $CandidateRecords -ProbeInvoker $ProbeInvoker -WingetAvailabilityProbe $WingetAvailabilityProbe -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
    Write-InstallerPrerequisitePlan -Plan $plan

    if ($plan.Action -eq 'Blocked') {
        return [PSCustomObject]@{ Status = 'Blocked'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = [string]$plan.Reason }
    }

    if ($plan.Action -ne 'Provision') {
        $runtimeDecision = Invoke-InstallerRuntimeEntry -Component $Component -ApplicationPath $ApplicationPath -ScriptArguments $ScriptArguments -AllowGuiCliFallback:$AllowGuiCliFallback -AlwaysLaunchApplication:$AlwaysLaunchApplication -CandidateRecords $plan.CandidateRecords -ProbeInvoker $ProbeInvoker -LaunchInvoker $LaunchInvoker -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
        $status = if ($runtimeDecision.Action -eq 'Failure') { 'Failed' } else { 'Started' }
        $reason = if ($status -eq 'Failed') { 'The selected PowerShell engine could not start the installer. No application package action was started.' } else { '' }
        return [PSCustomObject]@{ Status = $status; Plan = $plan; RuntimeDecision = $runtimeDecision; Candidate = $runtimeDecision.Selected; Reason = $reason }
    }

    $consented = $false
    if ($ConsentInvoker) {
        try {
            $consented = [bool](& $ConsentInvoker $plan)
        }
        catch {
            $consented = $false
        }
    }
    else {
        try {
            $answer = Read-Host ('Install PowerShell Core {0} {1} into the current-user App Installer directory shown above? Enter Y to continue' -f $plan.Provisioning.Version, $plan.Provisioning.Architecture)
            $consented = [string]::Equals([string]$answer, 'Y', [System.StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            $consented = $false
        }
    }
    if (-not $consented) {
        return [PSCustomObject]@{ Status = 'Declined'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'Runtime installation was declined. No download or installation was started.' }
    }

    $consentTarget = 'PowerShell Core {0} {1} for the current user at {2}' -f $plan.Provisioning.Version, $plan.Provisioning.Architecture, $plan.Provisioning.InstallLocation
    $consentAction = 'Download from {0}, verify SHA-256 {1} and the {2} signature, then extract. No administrator privileges, PATH update, or default-engine change.' -f $plan.Provisioning.Source, $plan.Provisioning.Sha256, $plan.Provisioning.Signer
    if (-not $PSCmdlet.ShouldProcess($consentTarget, $consentAction)) {
        return [PSCustomObject]@{ Status = 'PlanOnly'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'ShouldProcess prevented download and installation.' }
    }

    if ([bool]$plan.Provisioning.RequiresAdministrator) {
        if (-not $ElevationInvoker) {
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'The selected provisioning plan requires elevation, but no verified elevation flow is available.' }
        }
        try {
            $elevationResult = & $ElevationInvoker $plan
        }
        catch {
            $elevationResult = $null
        }
        if ($null -eq $elevationResult -or -not [bool]$elevationResult.Success) {
            return [PSCustomObject]@{ Status = 'ElevationDeclined'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'Administrator elevation was not approved or could not be confirmed. No application package action was started.' }
        }
    }

    $provisioningTempRootExisted = [System.IO.Directory]::Exists($ProvisioningTempRoot)
    $tempRoot = Join-Path $ProvisioningTempRoot ('app-installer-runtime-' + [guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $tempRoot ([string]$plan.Provisioning.ArtifactName)
    try {
        [void][System.IO.Directory]::CreateDirectory($tempRoot)
        $downloadResult = $null
        if ($DownloadInvoker) {
            $downloadResult = & $DownloadInvoker $plan.Provisioning $archivePath
        }
        else {
            Invoke-WebRequest -Uri $plan.Provisioning.Source -OutFile $archivePath -UseBasicParsing -ErrorAction Stop
            $downloadResult = [PSCustomObject]@{ Success = $true }
        }
        if ($null -eq $downloadResult -or -not [bool]$downloadResult.Success -or -not [System.IO.File]::Exists($archivePath)) {
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'The pinned runtime download did not complete. No application package action was started.' }
        }

        $archiveInfo = New-Object -TypeName System.IO.FileInfo -ArgumentList $archivePath
        if ($archiveInfo.Length -le 0 -or $archiveInfo.Length -gt 300000000) {
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'The downloaded runtime size is outside the allowed range. No application package action was started.' }
        }
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        if ($actualHash -ne $plan.Provisioning.Sha256) {
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'The runtime digest did not match the compatibility contract. The archive was rejected.' }
        }

        $installResult = if ($InstallerInvoker) {
            & $InstallerInvoker $archivePath $plan $ApplicationPath $ProbeInvoker $AllowTestCandidates $HostInfo $Manifest
        }
        else {
            Install-InstallerRuntimeArtifact -ArchivePath $archivePath -Plan $plan -ApplicationPath $ApplicationPath -ProbeInvoker $ProbeInvoker -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
        }
        if ($null -eq $installResult -or [bool]$installResult.RebootRequired -or -not [bool]$installResult.Success -or [string]::IsNullOrWhiteSpace([string]$installResult.CandidatePath)) {
            $failureReason = if ($null -ne $installResult -and [bool]$installResult.RebootRequired) {
                'The runtime installation reported that a reboot is required. The installer stopped before application package actions.'
            }
            elseif ($null -ne $installResult -and [string]$installResult.FailureCode -eq 'SignatureMismatch') {
                'The extracted PowerShell executable signature did not match the pinned Microsoft publisher. The runtime was rejected.'
            }
            elseif ($null -ne $installResult -and [string]$installResult.FailureCode -eq 'RuntimeCommandMissing') {
                'The runtime archive did not contain the expected PowerShell command. The runtime was rejected.'
            }
            elseif ($null -ne $installResult -and [string]$installResult.FailureCode -eq 'InstallLocationOccupied') {
                'The current-user runtime destination contains files that are not identified as App Installer managed. No files were replaced.'
            }
            else {
                'Runtime provisioning did not complete. The installer stopped before application package actions.'
            }
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = $failureReason }
        }

        $discoveredCandidates = if ($CandidateDiscoverer) {
            @(& $CandidateDiscoverer $Manifest)
        }
        else {
            @(Get-InstallerRuntimeCandidates -Manifest $Manifest)
        }
        $exactPath = [System.IO.Path]::GetFullPath([string]$installResult.CandidatePath)
        $exactCandidates = @($discoveredCandidates | Where-Object {
            try { [System.IO.Path]::GetFullPath([string]$_.Path).Equals($exactPath, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
        })
        if ($exactCandidates.Count -ne 1) {
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'The installed PowerShell command was not rediscovered from its exact path. No application package action was started.' }
        }

        $postInstallDecision = Resolve-InstallerRuntime -Component WindowsCli -ApplicationPath $ApplicationPath -CandidateRecords $exactCandidates -ProbeInvoker $ProbeInvoker -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
        if (-not $postInstallDecision.IsSupported -or -not [System.IO.Path]::GetFullPath([string]$postInstallDecision.Selected.Path).Equals($exactPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $recoveryText = if ([bool]$installResult.PreviousRuntimeRecoveryAvailable) { ' A prior App Installer managed runtime was retained in recovery storage.' } else { '' }
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = ('The newly installed PowerShell command did not pass compatibility revalidation. No application package action was started.{0}' -f $recoveryText) }
        }

        $launchArguments = @($ScriptArguments)
        if ($Component -eq 'WindowsGui' -and @($launchArguments | Where-Object { $_ -match '^(?i)-ForceCLI$' }).Count -eq 0) {
            $launchArguments += '-ForceCLI'
        }
        if ($WhatIfPreference -and @($launchArguments | Where-Object { $_ -match '^(?i)-WhatIf$' }).Count -eq 0) {
            $launchArguments += '-WhatIf'
        }
        $runtimeDecision = Invoke-InstallerRuntimeEntry -Component WindowsCli -ApplicationPath $ApplicationPath -ScriptArguments $launchArguments -CandidateRecords $exactCandidates -ProbeInvoker $ProbeInvoker -LaunchInvoker $LaunchInvoker -AllowTestCandidates:$AllowTestCandidates -AlwaysLaunchApplication:$AlwaysLaunchApplication -HostInfo $HostInfo -Manifest $Manifest
        if ($runtimeDecision.Action -eq 'Failure') {
            return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $runtimeDecision; Candidate = $null; Reason = 'The revalidated PowerShell command could not start the installer. No application package action was started.' }
        }
        return [PSCustomObject]@{ Status = 'Started'; Plan = $plan; RuntimeDecision = $runtimeDecision; Candidate = $postInstallDecision.Selected; Reason = '' }
    }
    catch {
        return [PSCustomObject]@{ Status = 'Failed'; Plan = $plan; RuntimeDecision = $null; Candidate = $null; Reason = 'Runtime provisioning failed. Review the current-user App Installer runtime files before retrying. No application package action was started.' }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            try { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop } catch {}
        }
        if (-not $provisioningTempRootExisted -and [System.IO.Directory]::Exists($ProvisioningTempRoot)) {
            $remainingEntries = @(Get-ChildItem -LiteralPath $ProvisioningTempRoot -Force -ErrorAction SilentlyContinue)
            if ($remainingEntries.Count -eq 0) {
                try { Remove-Item -LiteralPath $ProvisioningTempRoot -Force -ErrorAction Stop } catch {}
            }
        }
    }
}

Export-ModuleMember -Function Get-InstallerSafeCandidateReason, Get-InstallerPrerequisitePlan, Write-InstallerPrerequisitePlan, Test-InstallerRuntimeSigner, Expand-InstallerRuntimeArchiveSafely, Install-InstallerRuntimeArtifact, Invoke-InstallerRuntimePrerequisiteFlow
