$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$payloadModulePath = Join-Path $repositoryRoot 'modules\InstallerPayload.psm1'
Import-Module -Name $payloadModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
$script:assertionCount = 0

function Assert-LifecycleCondition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Set-LifecycleTestHook {
    param([scriptblock]$Hook)

    $modules = @(Get-Module -Name InstallerPayload)
    if ($modules.Count -eq 0) { throw 'The InstallerPayload module is not loaded.' }
    foreach ($module in $modules) {
        $module.SessionState.PSVariable.Set('AppInstallerLifecycleTestHook', $Hook)
    }
}

function New-LifecyclePackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    New-Item -ItemType Directory -Path (Join-Path $PackagePath 'apps'), (Join-Path $PackagePath 'modules'), (Join-Path $PackagePath 'profiles'), (Join-Path $PackagePath 'tools') -Force -ErrorAction Stop | Out-Null
    $payloadManifest = [PSCustomObject]@{
        formatVersion = 1
        productVersionFile = 'VERSION'
        generatedIntegrityFile = 'payload-integrity.json'
        requiredFiles = @('app-installer.ps1', 'app-installer-cli.ps1', 'apps-manifest.json', 'compatibility.json', 'payload-manifest.json', 'platform-detect.ps1', 'tools/Manage-AppInstallerInstall.ps1', 'VERSION')
        fileSets = @(
            [PSCustomObject]@{ path = 'apps'; extensions = @('.ps1'); fileNames = @('7zip.ps1') },
            [PSCustomObject]@{ path = 'modules'; extensions = @('.psm1'); fileNames = @('InstallerPayload.psm1') },
            [PSCustomObject]@{ path = 'profiles'; extensions = @('.json'); fileNames = @('profile-default.json') }
        )
        features = [PSCustomObject]@{
            cli = @('app-installer-cli.ps1', 'apps-manifest.json', 'modules/InstallerPayload.psm1', 'platform-detect.ps1')
            gui = @('app-installer.ps1', 'apps-manifest.json', 'modules/InstallerPayload.psm1', 'platform-detect.ps1')
        }
        exclusions = [PSCustomObject]@{
            directoryNames = @('tests')
            fileNamePrefixes = @('.env')
            extensions = @('.log', '.tmp', '.bak', '.exe', '.dll')
        }
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'payload-manifest.json'), (ConvertTo-Json -InputObject $payloadManifest -Depth 8), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'apps-manifest.json'), '{"apps":[{"name":"7zip","scriptName":"7zip.ps1"}]}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'compatibility.json'), '{}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'app-installer.ps1'), "# GUI fixture $Marker", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'app-installer-cli.ps1'), "# CLI fixture $Marker", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'platform-detect.ps1'), "# platform fixture $Marker", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'apps\7zip.ps1'), "# app fixture $Marker", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'profiles\profile-default.json'), '{"profile":"default"}', $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PackagePath 'VERSION'), ("**GUI Version:** {0}`r`n**CLI Version:** 2.0.2`r`n" -f $Version), $utf8NoBom)
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'modules\InstallerPayload.psm1') -Destination (Join-Path $PackagePath 'modules\InstallerPayload.psm1') -Force -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'tools\Manage-AppInstallerInstall.ps1') -Destination (Join-Path $PackagePath 'tools\Manage-AppInstallerInstall.ps1') -Force -ErrorAction Stop

    $defaultProfileFixture = Join-Path $PackagePath 'profiles\profile-default.json'
    Assert-LifecycleCondition -Condition (Test-Path -LiteralPath $defaultProfileFixture -PathType Leaf) -Message "Fixture package $Version includes the seeded default profile path"
    Write-AppInstallerPayloadIntegrity -RootPath $PackagePath | Out-Null
    $packageStatus = Test-AppInstallerPayload -RootPath $PackagePath -RequirePackage
    Assert-LifecycleCondition -Condition ($packageStatus.IsValid -and $packageStatus.Version -eq $Version) -Message "Fixture package $Version validates before use"
    return $PackagePath
}

function Get-FileHashValue {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@([char]92, [char]47))
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('AIL-' + [guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The lifecycle test directory resolved outside the operating system temporary directory.'
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force -ErrorAction Stop | Out-Null
    $packageV1 = New-LifecyclePackage -PackagePath (Join-Path $testRoot 'package v1') -Version '8.1.0' -Marker 'v1'
    $packageV2 = New-LifecyclePackage -PackagePath (Join-Path $testRoot 'package v2') -Version '8.1.1' -Marker 'v2'
    $packageV3 = New-LifecyclePackage -PackagePath (Join-Path $testRoot 'package v3') -Version '8.1.2' -Marker 'v3'
    $packageV4 = New-LifecyclePackage -PackagePath (Join-Path $testRoot 'package v4') -Version '8.1.3' -Marker 'v4'
    $managerScript = Join-Path $repositoryRoot 'tools\Manage-AppInstallerInstall.ps1'
    $whatIfInstallRoot = Join-Path $testRoot 'what-if install'
    Write-Output '[lifecycle] management command WhatIf'
    $managerInstallPreview = & $managerScript -Action Install -SourceRoot $packageV1 -InstallRoot $whatIfInstallRoot -WhatIf
    Assert-LifecycleCondition -Condition ($managerInstallPreview.Status -eq 'WhatIf' -and -not (Test-Path -LiteralPath $whatIfInstallRoot)) -Message 'Management command WhatIf does not create an install root'

    $userRoot = Join-Path $testRoot 'profile with spaces'
    $installParent = Join-Path $userRoot 'myTech.Today'
    $installRoot = Join-Path $installParent 'AppInstaller'
    $logRoot = Join-Path $installParent 'logs'
    $shortcutRoot = Join-Path $userRoot 'Start Menu'
    $runtimeRoot = Join-Path $userRoot 'Shared Runtime'
    New-Item -ItemType Directory -Path $userRoot, $logRoot, $shortcutRoot, $runtimeRoot -Force -ErrorAction Stop | Out-Null
    $shortcutPath = Join-Path $shortcutRoot 'User Created App Installer.lnk'
    $logPath = Join-Path $logRoot 'user.log'
    $runtimePath = Join-Path $runtimeRoot 'pwsh.exe'
    [System.IO.File]::WriteAllText($shortcutPath, 'user shortcut bytes')
    [System.IO.File]::WriteAllText($logPath, 'user log bytes')
    [System.IO.File]::WriteAllText($runtimePath, 'runtime shared by another application')
    $shortcutHash = Get-FileHashValue $shortcutPath
    $logHash = Get-FileHashValue $logPath
    $runtimeHash = Get-FileHashValue $runtimePath

    Write-Output '[lifecycle] fresh install'
    $freshResult = Copy-AppInstallerPayload -SourceRoot $packageV1 -DestinationRoot $installRoot -Operation Install -Confirm:$false
    Assert-LifecycleCondition -Condition ($freshResult.Status -eq 'Installed') -Message 'Fresh install creates the per-user payload'
    $installManifest = Get-AppInstallerInstallManifest -RootPath $installRoot
    Assert-LifecycleCondition -Condition ($installManifest.installScope -eq 'current-user' -and $installManifest.version -eq '8.1.0') -Message 'Install manifest records current-user scope and version'
    Assert-LifecycleCondition -Condition (@($installManifest.ownedFiles | Where-Object { $_.path -eq 'tools/Manage-AppInstallerInstall.ps1' }).Count -eq 1) -Message 'Install manifest lists the packaged lifecycle entry point'
    Assert-LifecycleCondition -Condition (@($installManifest.ownedFiles | Where-Object { $_.path -eq 'queue-state.json' }).Count -eq 0) -Message 'Install manifest excludes queue user data'

    Write-Output '[lifecycle] launch from installed root'
    $installedRootRepair = Copy-AppInstallerPayload -SourceRoot $installRoot -DestinationRoot $installRoot -Operation Repair -Confirm:$false
    Assert-LifecycleCondition -Condition ($installedRootRepair.Status -eq 'AlreadyCurrent') -Message 'A healthy install can launch from its own root without replacing itself'

    Write-Output '[lifecycle] repeated install'
    $repeatResult = Copy-AppInstallerPayload -SourceRoot $packageV1 -DestinationRoot $installRoot -Operation Install -Confirm:$false
    Assert-LifecycleCondition -Condition ($repeatResult.Status -eq 'AlreadyCurrent') -Message 'Repeated install is idempotent'

    $queuePath = Join-Path $installRoot 'queue-state.json'
    $queueBackupPath = Join-Path $installRoot 'queue-state.json.bak'
    $profilesPath = Join-Path $installRoot 'profiles'
    $defaultProfile = Get-ChildItem -LiteralPath $profilesPath -File -Filter 'profile-*.json' | Select-Object -First 1
    $customProfilePath = Join-Path $profilesPath 'profile-user-created.json'
    $userConfigPath = Join-Path $installRoot 'user-settings.json'
    $unrelatedFilePath = Join-Path $installRoot 'operator-notes.txt'
    $emptyUserDirectory = Join-Path $installRoot 'user-created-empty-directory'
    [System.IO.File]::WriteAllText($queuePath, '{"queue":"preserve"}')
    [System.IO.File]::WriteAllText($queueBackupPath, '{"queue":"backup-preserve"}')
    [System.IO.File]::WriteAllText($defaultProfile.FullName, '{"profile":"user-edited-default"}')
    [System.IO.File]::WriteAllText($customProfilePath, '{"profile":"user-created"}')
    [System.IO.File]::WriteAllText($userConfigPath, '{"theme":"custom"}')
    [System.IO.File]::WriteAllText($unrelatedFilePath, 'unrelated user file')
    New-Item -ItemType Directory -Path $emptyUserDirectory -Force -ErrorAction Stop | Out-Null
    $defaultProfileHash = Get-FileHashValue $defaultProfile.FullName
    $unrelatedAclSddl = if ($env:OS -eq 'Windows_NT') { (Get-Acl -LiteralPath $unrelatedFilePath).Sddl } else { $null }

    Write-Output '[lifecycle] upgrade with seeded user state'
    $upgradeResult = Copy-AppInstallerPayload -SourceRoot $packageV2 -DestinationRoot $installRoot -Operation Upgrade -Confirm:$false
    Assert-LifecycleCondition -Condition ($upgradeResult.Status -eq 'Upgraded') -Message 'Upgrade activates the new package version'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $queuePath -Raw) -eq '{"queue":"preserve"}') -Message 'Upgrade preserves queue state'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $queueBackupPath -Raw) -eq '{"queue":"backup-preserve"}') -Message 'Upgrade preserves queue recovery backup'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $defaultProfile.FullName -Raw) -eq '{"profile":"user-edited-default"}') -Message 'Upgrade preserves an edited default profile at its original path'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $customProfilePath -Raw) -eq '{"profile":"user-created"}') -Message 'Upgrade preserves user-created profiles'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $userConfigPath -Raw) -eq '{"theme":"custom"}') -Message 'Upgrade preserves application configuration outside the payload'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $unrelatedFilePath -Raw) -eq 'unrelated user file') -Message 'Upgrade preserves unrelated files'
    Assert-LifecycleCondition -Condition (Test-Path -LiteralPath $emptyUserDirectory -PathType Container) -Message 'Upgrade preserves empty user-created directories'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $logPath) -eq $logHash) -Message 'Upgrade leaves logs outside the install root unchanged'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $shortcutPath) -eq $shortcutHash) -Message 'Upgrade leaves user-created shortcuts unchanged'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $runtimePath) -eq $runtimeHash) -Message 'Upgrade leaves a shared runtime used by another application unchanged'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $defaultProfile.FullName) -eq $defaultProfileHash) -Message 'Upgrade keeps the exact bytes of the edited profile'
    if ($env:OS -eq 'Windows_NT') {
        Assert-LifecycleCondition -Condition ((Get-Acl -LiteralPath $unrelatedFilePath).Sddl -eq $unrelatedAclSddl) -Message 'Upgrade preserves the ACL on an unrelated user file'
    }

    Write-Output '[lifecycle] repeat launch'
    $repeatUpgrade = Copy-AppInstallerPayload -SourceRoot $packageV2 -DestinationRoot $installRoot -Operation Auto -Confirm:$false
    Assert-LifecycleCondition -Condition ($repeatUpgrade.Status -eq 'AlreadyCurrent') -Message 'Repeated current-version launch does not replace the install'

    $missingOwnedFile = Join-Path $installRoot 'apps\7zip.ps1'
    Remove-Item -LiteralPath $missingOwnedFile -Force -ErrorAction Stop
    Write-Output '[lifecycle] repair missing file'
    $repairResult = Copy-AppInstallerPayload -SourceRoot $packageV2 -DestinationRoot $installRoot -Operation Repair -Confirm:$false
    Assert-LifecycleCondition -Condition ($repairResult.Status -eq 'Repaired' -and (Test-Path -LiteralPath $missingOwnedFile -PathType Leaf)) -Message 'Repair restores a missing owned payload file'
    Assert-LifecycleCondition -Condition ((Test-AppInstallerPayload -RootPath $installRoot -RequirePackage).IsValid) -Message 'Repaired package passes payload integrity validation'

    $modifiedOwnedFile = Join-Path $installRoot 'platform-detect.ps1'
    [System.IO.File]::AppendAllText($modifiedOwnedFile, "`r`n# local modification for lifecycle test`r`n")
    $modifiedHash = Get-FileHashValue $modifiedOwnedFile
    $autoUpgradeBlocked = $false
    try { Copy-AppInstallerPayload -SourceRoot $packageV2 -DestinationRoot $installRoot -Operation Auto -Confirm:$false | Out-Null } catch { $autoUpgradeBlocked = $_.Exception.Message -match 'local changes' }
    Assert-LifecycleCondition -Condition $autoUpgradeBlocked -Message 'Automatic launch refuses to replace a modified owned code file'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $modifiedOwnedFile) -eq $modifiedHash) -Message 'Blocked automatic upgrade leaves the modified file at its original path'
    $selfRepairBlocked = $false
    try { Copy-AppInstallerPayload -SourceRoot $installRoot -DestinationRoot $installRoot -Operation Repair -Confirm:$false | Out-Null } catch { $selfRepairBlocked = $_.Exception.Message -match 'separate verified package source' }
    Assert-LifecycleCondition -Condition $selfRepairBlocked -Message 'A damaged install cannot repair itself without a separate verified package source'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $modifiedOwnedFile) -eq $modifiedHash) -Message 'A blocked self-repair leaves the modified file unchanged'
    Write-Output '[lifecycle] repair modified code'
    $modifiedRepair = Copy-AppInstallerPayload -SourceRoot $packageV2 -DestinationRoot $installRoot -Operation Repair -Confirm:$false
    $preservedModified = @($modifiedRepair.PreservedFiles | Where-Object { $_.originalPath -eq 'platform-detect.ps1' } | Select-Object -First 1)
    Assert-LifecycleCondition -Condition ($preservedModified.Count -eq 1) -Message 'Explicit repair reports a preserved local code modification'
    $preservedModifiedPath = Join-Path $installRoot ($preservedModified[0].preservedPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $preservedModifiedPath) -eq $modifiedHash) -Message 'Explicit repair keeps the exact local code bytes in a recovery path'
    $preservationManifestPath = Join-Path (Split-Path -Parent $preservedModifiedPath) 'preservation-manifest.json'
    Assert-LifecycleCondition -Condition (Test-Path -LiteralPath $preservationManifestPath -PathType Leaf) -Message 'Explicit repair records the preserved file in a recovery manifest'

    $stageInterruption = $false
    Set-LifecycleTestHook { param($point, $context) if ($point -eq 'AfterStageValidated') { throw 'simulated interrupted staging' } }
    Write-Output '[lifecycle] interrupted staging'
    try { Copy-AppInstallerPayload -SourceRoot $packageV3 -DestinationRoot $installRoot -Operation Upgrade -Confirm:$false | Out-Null } catch { $stageInterruption = $_.Exception.Message -match 'simulated interrupted staging' }
    finally { Set-LifecycleTestHook $null }
    Assert-LifecycleCondition -Condition $stageInterruption -Message 'Interrupted staging returns a failure'
    Assert-LifecycleCondition -Condition ((Test-AppInstallerPayload -RootPath $installRoot -RequirePackage).Version -eq '8.1.1') -Message 'Interrupted staging leaves the previous install valid'
    Assert-LifecycleCondition -Condition (@(Get-ChildItem -LiteralPath $installParent -Directory -Force | Where-Object { $_.Name -like '.AppInstaller.staging-*' }).Count -eq 0) -Message 'Interrupted staging removes only its own temporary directory'

    $permissionDenied = $false
    Set-LifecycleTestHook { param($point, $context) if ($point -eq 'AfterPreviousMoved') { throw [System.UnauthorizedAccessException]::new('simulated permission denial') } }
    Write-Output '[lifecycle] simulated permission denial'
    try { Copy-AppInstallerPayload -SourceRoot $packageV3 -DestinationRoot $installRoot -Operation Upgrade -Confirm:$false | Out-Null } catch { $permissionDenied = $_.Exception.Message -match 'simulated permission denial' }
    finally { Set-LifecycleTestHook $null }
    Assert-LifecycleCondition -Condition $permissionDenied -Message 'A simulated permission denial aborts activation'
    Assert-LifecycleCondition -Condition ((Test-AppInstallerPayload -RootPath $installRoot -RequirePackage).Version -eq '8.1.1') -Message 'Permission denial restores the previous install'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $queuePath -Raw) -eq '{"queue":"preserve"}') -Message 'Permission rollback preserves queue state'

    $rollbackError = ''
    Set-LifecycleTestHook {
        param($point, $context)
        if ($point -eq 'AfterActivation') {
            [System.IO.File]::WriteAllText((Join-Path $context.DestinationRoot 'late-user-file.txt'), 'written after activation')
            throw 'simulated post-activation failure'
        }
    }
    Write-Output '[lifecycle] rollback after activation'
    try { Copy-AppInstallerPayload -SourceRoot $packageV3 -DestinationRoot $installRoot -Operation Upgrade -Confirm:$false | Out-Null } catch { $rollbackError = $_.Exception.Message }
    finally { Set-LifecycleTestHook $null }
    Assert-LifecycleCondition -Condition ($rollbackError -match 'simulated post-activation failure' -and $rollbackError -match 'failed new payload') -Message 'Post-activation failure reports the preserved failed payload path'
    Assert-LifecycleCondition -Condition ((Test-AppInstallerPayload -RootPath $installRoot -RequirePackage).Version -eq '8.1.1') -Message 'Rollback restores the previous working version'
    $failedInstallRoots = @(Get-ChildItem -LiteralPath $installParent -Directory -Force | Where-Object { $_.Name -like '.AppInstaller.failed-*' })
    Assert-LifecycleCondition -Condition ($failedInstallRoots.Count -eq 1) -Message 'Rollback retains one failed new tree for recovery'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath (Join-Path $failedInstallRoots[0].FullName 'late-user-file.txt') -Raw) -eq 'written after activation') -Message 'Rollback does not overwrite a file written after activation'

    Set-LifecycleTestHook { param($point, $context) if ($point -eq 'BeforeBackupCleanup') { throw 'simulated backup cleanup denial' } }
    Write-Output '[lifecycle] cleanup failure'
    try { $cleanupResult = Copy-AppInstallerPayload -SourceRoot $packageV4 -DestinationRoot $installRoot -Operation Upgrade -Confirm:$false }
    finally { Set-LifecycleTestHook $null }
    Assert-LifecycleCondition -Condition ($cleanupResult.Status -eq 'Upgraded' -and $cleanupResult.CleanupStatus -eq 'Retained') -Message 'Cleanup failure does not undo a validated new install'
    Assert-LifecycleCondition -Condition ((Test-Path -LiteralPath $cleanupResult.BackupPath -PathType Container) -and $cleanupResult.CleanupError -match 'simulated backup cleanup denial') -Message 'Cleanup failure reports the exact retained backup and reason'
    Assert-LifecycleCondition -Condition ((Test-AppInstallerPayload -RootPath $installRoot -RequirePackage).Version -eq '8.1.3') -Message 'The new package remains valid after backup cleanup failure'

    $legacyRoot = Join-Path $testRoot 'legacy script install'
    Copy-AppInstallerPayload -SourceRoot $packageV1 -DestinationRoot $legacyRoot -Operation Install -Confirm:$false | Out-Null
    Remove-Item -LiteralPath (Join-Path $legacyRoot '.app-installer-install.json') -Force -ErrorAction Stop
    [System.IO.File]::WriteAllText((Join-Path $legacyRoot 'legacy-user-config.json'), '{"legacy":true}')
    $legacyUserScript = Join-Path $legacyRoot 'apps\legacy-user-tool.ps1'
    [System.IO.File]::WriteAllText($legacyUserScript, '# user script outside the current package')
    Write-Output '[lifecycle] legacy script migration'
    $legacyUpgrade = Copy-AppInstallerPayload -SourceRoot $packageV2 -DestinationRoot $legacyRoot -Operation Auto -Confirm:$false
    Assert-LifecycleCondition -Condition ($legacyUpgrade.Status -eq 'Upgraded') -Message 'A current script install without the new ownership manifest upgrades'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath (Join-Path $legacyRoot 'legacy-user-config.json') -Raw) -eq '{"legacy":true}') -Message 'Legacy migration preserves unrelated user configuration'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $legacyUserScript -Raw) -eq '# user script outside the current package') -Message 'Legacy migration preserves added scripts that are absent from the incoming package'

    $unverifiedLegacyRoot = Join-Path $testRoot 'legacy install without integrity baseline'
    Copy-AppInstallerPayload -SourceRoot $packageV1 -DestinationRoot $unverifiedLegacyRoot -Operation Install -Confirm:$false | Out-Null
    Remove-Item -LiteralPath (Join-Path $unverifiedLegacyRoot '.app-installer-install.json') -Force -ErrorAction Stop
    Remove-Item -LiteralPath (Join-Path $unverifiedLegacyRoot 'payload-integrity.json') -Force -ErrorAction Stop
    $unverifiedEntryPoint = Join-Path $unverifiedLegacyRoot 'app-installer.ps1'
    $unverifiedEntryPointHash = Get-FileHashValue $unverifiedEntryPoint
    $unverifiedUninstallBlocked = $false
    try {
        Uninstall-AppInstallerPayload -InstallRoot $unverifiedLegacyRoot -KeepData -RemoveOwnedFiles -Confirm:$false | Out-Null
    }
    catch {
        $unverifiedUninstallBlocked = $_.Exception.Message -match 'no valid ownership or payload-integrity baseline'
    }
    Assert-LifecycleCondition -Condition $unverifiedUninstallBlocked -Message 'Uninstall fails closed when a legacy install has no trusted ownership hashes'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $unverifiedEntryPoint) -eq $unverifiedEntryPointHash) -Message 'A blocked legacy uninstall leaves product files untouched'

    $conflictPackage = New-LifecyclePackage -PackagePath (Join-Path $testRoot 'package with directory conflict') -Version '8.1.4' -Marker 'directory-conflict'
    $conflictPayloadManifestPath = Join-Path $conflictPackage 'payload-manifest.json'
    $conflictPayloadManifest = Get-Content -LiteralPath $conflictPayloadManifestPath -Raw | ConvertFrom-Json
    $conflictPayloadManifest.fileSets += [PSCustomObject]@{ path = 'apps/user-tools'; extensions = @('.ps1'); fileNames = @('nested.ps1') }
    $conflictPayloadManifestJson = ConvertTo-Json -InputObject $conflictPayloadManifest -Depth 8
    [System.IO.File]::WriteAllText($conflictPayloadManifestPath, $conflictPayloadManifestJson, [System.Text.UTF8Encoding]::new($false))
    $incomingDirectory = Join-Path $conflictPackage 'apps\user-tools'
    New-Item -ItemType Directory -Path $incomingDirectory -Force -ErrorAction Stop | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $incomingDirectory 'nested.ps1'), '# package directory fixture')
    Write-AppInstallerPayloadIntegrity -RootPath $conflictPackage | Out-Null
    $conflictInstallRoot = Join-Path $testRoot 'file-directory conflict install'
    Copy-AppInstallerPayload -SourceRoot $packageV1 -DestinationRoot $conflictInstallRoot -Operation Install -Confirm:$false | Out-Null
    $blockingFile = Join-Path $conflictInstallRoot 'apps\user-tools'
    [System.IO.File]::WriteAllText($blockingFile, 'unowned file blocks the incoming directory')
    $blockingFileHash = Get-FileHashValue $blockingFile
    $directoryConflictRejected = $false
    Write-Output '[lifecycle] unowned file conflicts with packaged directory'
    try { Copy-AppInstallerPayload -SourceRoot $conflictPackage -DestinationRoot $conflictInstallRoot -Operation Upgrade -Confirm:$false | Out-Null } catch { $directoryConflictRejected = $_.Exception.Message -match 'unowned file conflicts' }
    Assert-LifecycleCondition -Condition $directoryConflictRejected -Message 'An unowned file blocking a packaged directory prevents activation'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $blockingFile) -eq $blockingFileHash) -Message 'A package directory conflict leaves the user file unchanged'
    Assert-LifecycleCondition -Condition ((Test-AppInstallerPayload -RootPath $conflictInstallRoot -RequirePackage).Version -eq '8.1.0') -Message 'A package directory conflict retains the current working version'

    $corruptPackage = New-LifecyclePackage -PackagePath (Join-Path $testRoot 'corrupt package') -Version '8.1.4' -Marker 'corrupt'
    [System.IO.File]::AppendAllText((Join-Path $corruptPackage 'apps\7zip.ps1'), "`r`n# corrupt after manifest creation`r`n")
    $corruptRejected = $false
    try { Copy-AppInstallerPayload -SourceRoot $corruptPackage -DestinationRoot $installRoot -Operation Upgrade -Confirm:$false | Out-Null } catch { $corruptRejected = $true }
    Assert-LifecycleCondition -Condition $corruptRejected -Message 'A corrupt package is rejected before replacing the installed payload'
    Assert-LifecycleCondition -Condition ((Test-AppInstallerPayload -RootPath $installRoot -RequirePackage).Version -eq '8.1.3') -Message 'Corrupt package rejection leaves the current install unchanged'

    $previewUninstall = & $managerScript -Action Uninstall -InstallRoot $installRoot -KeepData
    Assert-LifecycleCondition -Condition ($previewUninstall.Status -eq 'PreviewOnly' -and (Test-Path -LiteralPath (Join-Path $installRoot 'app-installer.ps1') -PathType Leaf)) -Message 'Management command uninstall preview makes no changes'
    $whatIfUninstall = & $managerScript -Action Uninstall -InstallRoot $installRoot -KeepData -RemoveOwnedFiles -WhatIf
    Assert-LifecycleCondition -Condition ($whatIfUninstall.Status -eq 'WhatIf' -and (Test-Path -LiteralPath (Join-Path $installRoot 'app-installer.ps1') -PathType Leaf)) -Message 'Management command uninstall WhatIf makes no changes'
    [System.IO.File]::AppendAllText($modifiedOwnedFile, "`r`n# changed before uninstall`r`n")
    Write-Output '[lifecycle] uninstall with keep-data'
    $uninstallResult = Uninstall-AppInstallerPayload -InstallRoot $installRoot -KeepData -RemoveOwnedFiles -Confirm:$false
    Assert-LifecycleCondition -Condition ($uninstallResult.Status -eq 'Uninstalled' -and $uninstallResult.UserDataRetained) -Message 'Uninstall removes owned files and retains user data'
    Assert-LifecycleCondition -Condition (-not (Test-Path -LiteralPath (Join-Path $installRoot 'app-installer.ps1') -PathType Leaf)) -Message 'Uninstall removes an unchanged owned application entry point'
    Assert-LifecycleCondition -Condition (Test-Path -LiteralPath $modifiedOwnedFile -PathType Leaf) -Message 'Uninstall retains a locally modified owned file'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $queuePath -Raw) -eq '{"queue":"preserve"}') -Message 'Uninstall retains queue state'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $queueBackupPath -Raw) -eq '{"queue":"backup-preserve"}') -Message 'Uninstall retains queue recovery data'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $defaultProfile.FullName -Raw) -eq '{"profile":"user-edited-default"}') -Message 'Uninstall retains user-edited profiles'
    Assert-LifecycleCondition -Condition (Test-Path -LiteralPath $customProfilePath -PathType Leaf) -Message 'Uninstall retains user-created profiles'
    Assert-LifecycleCondition -Condition (Test-Path -LiteralPath $userConfigPath -PathType Leaf) -Message 'Uninstall retains app configuration'
    Assert-LifecycleCondition -Condition (Test-Path -LiteralPath $unrelatedFilePath -PathType Leaf) -Message 'Uninstall retains unrelated files'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $logPath) -eq $logHash) -Message 'Uninstall leaves logs in the user log directory unchanged'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $shortcutPath) -eq $shortcutHash) -Message 'Uninstall leaves user-created shortcuts unchanged'
    Assert-LifecycleCondition -Condition ((Get-FileHashValue $runtimePath) -eq $runtimeHash) -Message 'Uninstall leaves another application shared runtime unchanged'
    Assert-LifecycleCondition -Condition ((Get-AppInstallerInstallManifest -RootPath $installRoot).state -eq 'uninstalled') -Message 'Uninstall records its state for later reinstall'

    Write-Output '[lifecycle] reinstall after uninstall'
    $reinstallResult = Copy-AppInstallerPayload -SourceRoot $packageV4 -DestinationRoot $installRoot -Operation Install -Confirm:$false
    Assert-LifecycleCondition -Condition ($reinstallResult.Status -eq 'Installed') -Message 'A user-data-only uninstall root can be reinstalled'
    Assert-LifecycleCondition -Condition ((Get-Content -LiteralPath $queuePath -Raw) -eq '{"queue":"preserve"}') -Message 'Reinstall after uninstall still preserves user state'

    Write-Output ("PASS: executable lifecycle accepted {0} assertions in temporary directories." -f $script:assertionCount)
}
finally {
    Set-LifecycleTestHook $null
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction Stop
    }
}
