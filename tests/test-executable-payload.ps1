#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$payloadModulePath = Join-Path $repositoryRoot 'modules\InstallerPayload.psm1'
Import-Module -Name $payloadModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null

$script:AssertionCount = 0

function Assert-PayloadCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
    $script:AssertionCount++
}

function Invoke-PayloadEntryPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $processPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $processPath
    $startInfo.Arguments = '-NoProfile -File "{0}" -ValidatePayloadOnly' -f $ScriptPath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Could not start payload validation process for $ScriptPath"
    }
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StandardOutput = $standardOutput
        StandardError = $standardError
        Text = $standardOutput + [Environment]::NewLine + $standardError
    }
}

function Invoke-ExpectedPayloadFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Scenario
    )

    $result = Invoke-PayloadEntryPoint -ScriptPath $ScriptPath -WorkingDirectory $WorkingDirectory
    Assert-PayloadCondition -Condition ($result.ExitCode -ne 0) -Message "$Scenario must fail with a nonzero exit code."
    Assert-PayloadCondition -Condition ($result.Text -notmatch 'Payload valid:') -Message "$Scenario must not report a valid payload."
    return $result
}

function Invoke-PayloadMutationCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Mutation,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Scenario
    )

    $path = Join-Path $PackageRoot ($RelativePath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Test fixture file is missing: $RelativePath"
    }
    $originalBytes = [System.IO.File]::ReadAllBytes($path)
    try {
        & $Mutation $path
        return Invoke-ExpectedPayloadFailure `
            -ScriptPath (Join-Path $PackageRoot 'app-installer-cli.ps1') `
            -WorkingDirectory $WorkingDirectory `
            -Scenario $Scenario
    }
    finally {
        [System.IO.File]::WriteAllBytes($path, $originalBytes)
    }
}

function Get-PayloadRelativeFileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]@([char]92, [char]47))
    $prefix = $rootFullPath + [System.IO.Path]::DirectorySeparatorChar
    return @(
        Get-ChildItem -LiteralPath $rootFullPath -File -Recurse -Force -ErrorAction Stop |
            ForEach-Object { $_.FullName.Substring($prefix.Length).Replace('\', '/') } |
            Sort-Object
    )
}

$unicodeSuffix = [string][char]0x00E9 + '-' + [string][char]0x65E5 + [string][char]0x672C + [string][char]0x8A9E
$testRootName = 'AppInstaller-Payload-Tests-' + [guid]::NewGuid().ToString('N') + '-' + $unicodeSuffix
$testRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) $testRootName))
$workingDirectory = Join-Path $testRoot ('Caller Current Directory With Spaces-' + $unicodeSuffix)
$packageRoot = Join-Path $testRoot ('Extracted Payload With Spaces-' + $unicodeSuffix)
$userInstallRoot = Join-Path $testRoot ('Per User Install With Spaces-' + $unicodeSuffix)
$buildDirectory = Join-Path $testRoot ('Build Output With Spaces-' + $unicodeSuffix)
$extractedBuildRoot = Join-Path $testRoot ('Verified Cabinet With Spaces-' + $unicodeSuffix)
$cabinetInspectionRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('Issue7CabinetInspect-' + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot -Force -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $workingDirectory -Force -ErrorAction Stop | Out-Null

    $sourceStatus = Test-AppInstallerPayload -RootPath $repositoryRoot
    Assert-PayloadCondition -Condition ($sourceStatus.Mode -eq 'source') -Message 'A complete source checkout must validate without package metadata.'
    $sourceInventory = @(Get-AppInstallerPayloadFiles -RootPath $repositoryRoot)
    $payloadManifest = Get-AppInstallerPayloadManifest -RootPath $repositoryRoot
    $applicationManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'apps-manifest.json') -Raw | ConvertFrom-Json
    $applicationCount = @($applicationManifest.apps).Count
    $appScriptCount = @($sourceInventory | Where-Object { $_.Path -like 'apps/*.ps1' }).Count
    $profileFiles = @($sourceInventory | Where-Object { $_.Path -like 'profiles/*.json' })
    $profileFileSet = @($payloadManifest.fileSets | Where-Object { $_.path -eq 'profiles' })[0]
    $listedProfileCount = @($profileFileSet.fileNames).Count

    Assert-PayloadCondition -Condition ($sourceInventory.Count -gt 300) -Message 'The runtime inventory must include the complete application payload.'
    Assert-PayloadCondition -Condition ($applicationCount -gt 271) -Message 'The full application catalog must be present.'
    Assert-PayloadCondition -Condition ($appScriptCount -eq @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'apps') -Filter '*.ps1' -File).Count) -Message 'Every shipped app script must be inventoried.'
    Assert-PayloadCondition -Condition ($profileFiles.Count -eq $listedProfileCount) -Message 'Every explicitly listed default profile must be inventoried.'

    $inventoryPaths = @{}
    foreach ($file in $sourceInventory) {
        $inventoryPaths[$file.Path.ToLowerInvariant()] = $true
    }
    foreach ($featureName in @($payloadManifest.features.PSObject.Properties.Name)) {
        foreach ($featurePath in @($payloadManifest.features.$featureName)) {
            Assert-PayloadCondition -Condition $inventoryPaths.ContainsKey(([string]$featurePath).ToLowerInvariant()) -Message "The $featureName dependency $featurePath must be included."
        }
    }
    foreach ($application in @($applicationManifest.apps)) {
        $scriptNameProperty = $application.PSObject.Properties['scriptName']
        $scriptProperty = $application.PSObject.Properties['script']
        $scriptName = if ($null -ne $scriptNameProperty) { [string]$scriptNameProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($scriptName) -and $null -ne $scriptProperty) {
            $scriptName = [string]$scriptProperty.Value
        }
        if (-not [string]::IsNullOrWhiteSpace($scriptName)) {
            Assert-PayloadCondition -Condition $inventoryPaths.ContainsKey(('apps/' + $scriptName).ToLowerInvariant()) -Message "Catalog custom script $scriptName must be included."
        }
    }

    $sourceCli = Invoke-PayloadEntryPoint -ScriptPath (Join-Path $repositoryRoot 'app-installer-cli.ps1') -WorkingDirectory $workingDirectory
    Assert-PayloadCondition -Condition ($sourceCli.ExitCode -eq 0 -and $sourceCli.Text -match 'mode=source') -Message 'The source CLI must resolve and validate from an arbitrary current directory.'
    $sourceGui = Invoke-PayloadEntryPoint -ScriptPath (Join-Path $repositoryRoot 'app-installer.ps1') -WorkingDirectory $workingDirectory
    Assert-PayloadCondition -Condition ($sourceGui.ExitCode -eq 0 -and $sourceGui.Text -match 'mode=source') -Message 'The source GUI entry point must validate from an arbitrary current directory.'

    $copyResult = Copy-AppInstallerPayload -SourceRoot $repositoryRoot -DestinationRoot $packageRoot
    $packageStatus = Test-AppInstallerPayload -RootPath $packageRoot -RequirePackage
    Assert-PayloadCondition -Condition ($copyResult.Status -eq 'Installed' -and $packageStatus.Mode -eq 'packaged') -Message 'A source checkout must stage into a versioned, hashed package.'
    Assert-PayloadCondition -Condition ($packageStatus.FileCount -eq $sourceInventory.Count) -Message 'The staged package file count must equal the declared payload inventory.'

    $unexpectedProfile = Join-Path (Join-Path $packageRoot 'profiles') 'profile-local-export.json'
    [System.IO.File]::WriteAllText($unexpectedProfile, '{"applications":[]}', (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
    $packageInventory = @(Get-AppInstallerPayloadFiles -RootPath $packageRoot)
    Assert-PayloadCondition -Condition (@($packageInventory | Where-Object { $_.Path -eq 'profiles/profile-local-export.json' }).Count -eq 0) -Message 'Unlisted user profile JSON must not enter the package inventory.'
    Remove-Item -LiteralPath $unexpectedProfile -Force

    $payloadManifestPath = Join-Path $packageRoot 'payload-manifest.json'
    $originalManifest = [System.IO.File]::ReadAllBytes($payloadManifestPath)
    try {
        $manifestWithTraversal = [System.IO.File]::ReadAllText($payloadManifestPath) | ConvertFrom-Json -ErrorAction Stop
        $manifestWithTraversal.requiredFiles = @($manifestWithTraversal.requiredFiles) + @('../outside-issue7-traversal.txt')
        $mutatedManifestJson = ConvertTo-Json -InputObject $manifestWithTraversal -Depth 20
        [System.IO.File]::WriteAllText($payloadManifestPath, $mutatedManifestJson, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        $traversalRejected = $false
        try {
            Get-AppInstallerPayloadFiles -RootPath $packageRoot | Out-Null
        }
        catch {
            $traversalRejected = $_.Exception.Message -match 'unsafe path|escapes its root'
        }
        Assert-PayloadCondition -Condition $traversalRejected -Message 'The payload inventory must reject manifest paths that escape the payload root.'
    }
    finally {
        [System.IO.File]::WriteAllBytes($payloadManifestPath, $originalManifest)
    }

    $packagedCli = Invoke-PayloadEntryPoint -ScriptPath (Join-Path $packageRoot 'app-installer-cli.ps1') -WorkingDirectory $workingDirectory
    Assert-PayloadCondition -Condition ($packagedCli.ExitCode -eq 0 -and $packagedCli.Text -match 'mode=packaged') -Message 'The packaged CLI must load its payload from its script root when the current directory differs.'
    $packagedGui = Invoke-PayloadEntryPoint -ScriptPath (Join-Path $packageRoot 'app-installer.ps1') -WorkingDirectory $workingDirectory
    Assert-PayloadCondition -Condition ($packagedGui.ExitCode -eq 0 -and $packagedGui.Text -match 'mode=packaged') -Message 'The packaged GUI entry point must load its payload from its script root when the current directory differs.'

    $null = Invoke-PayloadMutationCase -PackageRoot $packageRoot -RelativePath 'payload-manifest.json' -Mutation {
        param($path)
        Remove-Item -LiteralPath $path -Force
    } -WorkingDirectory $workingDirectory -Scenario 'Missing payload manifest'
    $null = Invoke-PayloadMutationCase -PackageRoot $packageRoot -RelativePath 'payload-manifest.json' -Mutation {
        param($path)
        [System.IO.File]::WriteAllText($path, '{invalid json', (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
    } -WorkingDirectory $workingDirectory -Scenario 'Corrupt payload manifest'
    $null = Invoke-PayloadMutationCase -PackageRoot $packageRoot -RelativePath 'apps-manifest.json' -Mutation {
        param($path)
        Remove-Item -LiteralPath $path -Force
    } -WorkingDirectory $workingDirectory -Scenario 'Missing application catalog'
    $null = Invoke-PayloadMutationCase -PackageRoot $packageRoot -RelativePath 'apps-manifest.json' -Mutation {
        param($path)
        [System.IO.File]::WriteAllText($path, '{invalid json', (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
    } -WorkingDirectory $workingDirectory -Scenario 'Corrupt application catalog'
    $null = Invoke-PayloadMutationCase -PackageRoot $packageRoot -RelativePath 'modules/AppInstallerCore.psm1' -Mutation {
        param($path)
        Remove-Item -LiteralPath $path -Force
    } -WorkingDirectory $workingDirectory -Scenario 'Missing shared module'
    $null = Invoke-PayloadMutationCase -PackageRoot $packageRoot -RelativePath 'platform-detect.ps1' -Mutation {
        param($path)
        [System.IO.File]::AppendAllText($path, "`r`n# damaged payload`r`n")
    } -WorkingDirectory $workingDirectory -Scenario 'Modified payload file'
    $null = Invoke-PayloadMutationCase -PackageRoot $packageRoot -RelativePath 'VERSION' -Mutation {
        param($path)
        $content = Get-Content -LiteralPath $path -Raw
        $updated = [regex]::Replace($content, '(?m)^\*\*GUI Version:\*\*\s*[0-9]+\.[0-9]+\.[0-9]+\s*$', '**GUI Version:** 9.9.9', 1)
        if ($updated -eq $content) {
            throw 'Could not create the mismatched version fixture.'
        }
        [System.IO.File]::WriteAllText($path, $updated, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
    } -WorkingDirectory $workingDirectory -Scenario 'Mismatched package version'

    $queueStatePath = Join-Path $userInstallRoot 'queue-state.json'
    $queueBackupPath = Join-Path $userInstallRoot 'queue-state.json.bak'
    $userProfilesPath = Join-Path $userInstallRoot 'profiles'
    New-Item -ItemType Directory -Path $userProfilesPath -Force -ErrorAction Stop | Out-Null
    [System.IO.File]::WriteAllText($queueStatePath, '{"state":"preserve-queue"}')
    [System.IO.File]::WriteAllText($queueBackupPath, '{"state":"preserve-backup"}')
    $customProfilePath = Join-Path $userProfilesPath 'profile-custom-user.json'
    [System.IO.File]::WriteAllText($customProfilePath, '{"applications":["custom-user-profile"]}')

    $installResult = Copy-AppInstallerPayload -SourceRoot $packageRoot -DestinationRoot $userInstallRoot
    Assert-PayloadCondition -Condition ($installResult.Status -eq 'Installed') -Message 'A complete payload must install into a persistent user-scoped path.'
    Assert-PayloadCondition -Condition ((Get-Content -LiteralPath $queueStatePath -Raw) -eq '{"state":"preserve-queue"}') -Message 'Queue state must survive payload replacement.'
    Assert-PayloadCondition -Condition ((Get-Content -LiteralPath $queueBackupPath -Raw) -eq '{"state":"preserve-backup"}') -Message 'Queue recovery backup must survive payload replacement.'
    Assert-PayloadCondition -Condition ((Get-Content -LiteralPath $customProfilePath -Raw) -eq '{"applications":["custom-user-profile"]}') -Message 'User-created profiles must survive payload replacement.'
    $installedStatus = Test-AppInstallerPayload -RootPath $userInstallRoot -RequirePackage
    Assert-PayloadCondition -Condition ($installedStatus.IsValid) -Message 'User data outside the payload inventory must not invalidate installed code.'

    $failedInstallParent = Join-Path $testRoot 'Failed Extraction Parent'
    $failedInstallRoot = Join-Path $failedInstallParent 'AppInstaller'
    New-Item -ItemType Directory -Path $failedInstallParent -Force -ErrorAction Stop | Out-Null
    Copy-AppInstallerPayload -SourceRoot $packageRoot -DestinationRoot $failedInstallRoot | Out-Null
    $failedQueueState = Join-Path $failedInstallRoot 'queue-state.json'
    $failedCustomProfile = Join-Path (Join-Path $failedInstallRoot 'profiles') 'profile-custom-user.json'
    [System.IO.File]::WriteAllText($failedQueueState, '{"state":"preserve-after-stage-failure"}')
    [System.IO.File]::WriteAllText($failedCustomProfile, '{"applications":["preserve-after-stage-failure"]}')
    $lockedInstalledFile = Join-Path $failedInstallRoot 'apps\7zip.ps1'
    $payloadLock = [System.IO.File]::Open($lockedInstalledFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $stageCommitBlocked = $false
    $stageFailureText = ''
    try {
        try {
            Copy-AppInstallerPayload -SourceRoot $packageRoot -DestinationRoot $failedInstallRoot | Out-Null
        }
        catch {
            $stageCommitBlocked = $true
            $stageFailureText = $_.Exception.Message
        }
    }
    finally {
        $payloadLock.Dispose()
    }
    Assert-PayloadCondition -Condition $stageCommitBlocked -Message 'A locked installed file must stop replacement after the new payload has been staged.'
    if (-not (Test-Path -LiteralPath $failedQueueState -PathType Leaf)) {
        $remainingInstallItems = @(Get-ChildItem -LiteralPath $failedInstallParent -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        throw "Failed replacement did not preserve the installed root. Lock failure: $stageFailureText. Parent entries: $($remainingInstallItems -join ', ')"
    }
    Assert-PayloadCondition -Condition ((Get-Content -LiteralPath $failedQueueState -Raw) -eq '{"state":"preserve-after-stage-failure"}') -Message 'A failed staged replacement must preserve the previous queue state.'
    Assert-PayloadCondition -Condition ((Get-Content -LiteralPath $failedCustomProfile -Raw) -eq '{"applications":["preserve-after-stage-failure"]}') -Message 'A failed staged replacement must preserve user-created profiles.'
    $failedInstallStatus = Test-AppInstallerPayload -RootPath $failedInstallRoot -RequirePackage
    Assert-PayloadCondition -Condition ($failedInstallStatus.IsValid) -Message 'A failed staged replacement must leave the previous payload valid.'
    $unexpectedStageDirectories = @(Get-ChildItem -LiteralPath $failedInstallParent -Directory -Force -ErrorAction Stop | Where-Object { $_.Name -like '.AppInstaller.staging-*' })
    Assert-PayloadCondition -Condition ($unexpectedStageDirectories.Count -eq 0) -Message 'A failed staged replacement must not leave a partial staging directory.'

    $integrityPath = Join-Path $packageRoot 'payload-integrity.json'
    $originalIntegrity = [System.IO.File]::ReadAllBytes($integrityPath)
    try {
        [System.IO.File]::WriteAllText($integrityPath, '{invalid package metadata', (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        $copyFailed = $false
        try {
            Copy-AppInstallerPayload -SourceRoot $packageRoot -DestinationRoot $userInstallRoot | Out-Null
        }
        catch {
            $copyFailed = $true
        }
        Assert-PayloadCondition -Condition $copyFailed -Message 'A corrupt source package must fail before replacing the installed payload.'
        Assert-PayloadCondition -Condition ((Get-Content -LiteralPath $queueStatePath -Raw) -eq '{"state":"preserve-queue"}') -Message 'Failed package staging must leave existing queue data unchanged.'
        Assert-PayloadCondition -Condition ((Get-Content -LiteralPath $customProfilePath -Raw) -eq '{"applications":["custom-user-profile"]}') -Message 'Failed package staging must leave existing user profiles unchanged.'
    }
    finally {
        [System.IO.File]::WriteAllBytes($integrityPath, $originalIntegrity)
    }

    $windowsBuildAvailable = $env:OS -match 'Windows' -and
        (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\makecab.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\expand.exe') -PathType Leaf)
    if ($windowsBuildAvailable) {
        New-Item -ItemType Directory -Path $buildDirectory -Force -ErrorAction Stop | Out-Null
        New-Item -ItemType Directory -Path $cabinetInspectionRoot -Force -ErrorAction Stop | Out-Null
        $asciiInspectionRoot = [System.IO.Path]::GetFullPath($cabinetInspectionRoot)
        if ($asciiInspectionRoot -match '[^\x20-\x7E]') {
            throw 'The Windows cabinet inspection scratch path must be ASCII because Expand.exe does not preserve Unicode command-line paths.'
        }
        $executablePath = Join-Path $buildDirectory 'install-GUI.exe'
        & (Join-Path $repositoryRoot 'tools\Build-InstallerExe.ps1') -OutputPath $executablePath -Confirm:$false
        Assert-PayloadCondition -Condition (Test-Path -LiteralPath $executablePath -PathType Leaf) -Message 'The Windows builder must produce the requested executable.'

        if (-not ('InstallerExecutableVersionInfo' -as [type])) {
            Add-Type -Path (Join-Path $repositoryRoot 'tools\InstallerExecutableVersionInfo.cs') -ErrorAction Stop
        }
        $cabinetBytes = [InstallerExecutableVersionInfo]::ReadCabinetResource($executablePath)
        Assert-PayloadCondition -Condition ($cabinetBytes.Length -gt 0) -Message 'The executable must contain a nonempty payload cabinet.'
        $cabinetPath = Join-Path $cabinetInspectionRoot 'payload.cab'
        [System.IO.File]::WriteAllBytes($cabinetPath, $cabinetBytes)
        $expandPath = Join-Path $env:WINDIR 'System32\expand.exe'
        $expandOutput = Join-Path $cabinetInspectionRoot 'expand.out'
        $expandError = Join-Path $cabinetInspectionRoot 'expand.err'
        $cabinetExtractRoot = Join-Path $cabinetInspectionRoot 'expanded'
        New-Item -ItemType Directory -Path $cabinetExtractRoot -Force -ErrorAction Stop | Out-Null
        $expandArguments = '-r "{0}" -F:* "{1}"' -f $cabinetPath, $cabinetExtractRoot
        $expandProcess = Start-Process -FilePath $expandPath -ArgumentList $expandArguments -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $expandOutput -RedirectStandardError $expandError
        if ($expandProcess.ExitCode -ne 0) {
            $details = (Get-Content -LiteralPath $expandOutput -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $expandError -Raw -ErrorAction SilentlyContinue)
            throw "The built executable cabinet did not extract successfully. Exit code $($expandProcess.ExitCode). $details"
        }

        Copy-Item -LiteralPath $cabinetExtractRoot -Destination $extractedBuildRoot -Recurse -Force -ErrorAction Stop
        $expectedPaths = @($sourceInventory | ForEach-Object { $_.Path }) + @('payload-integrity.json')
        $actualPaths = @(Get-PayloadRelativeFileList -RootPath $extractedBuildRoot)
        $differences = @(Compare-Object -ReferenceObject @($expectedPaths | Sort-Object) -DifferenceObject @($actualPaths | Sort-Object))
        Assert-PayloadCondition -Condition ($differences.Count -eq 0) -Message 'The embedded cabinet inventory must exactly match the required manifest.'
        $forbiddenFiles = @($actualPaths | Where-Object {
            $_ -match '(^|/)(\.git|tests?|test-fixtures|fixtures|logs?|temp|tmp|node_modules)(/|$)' -or
            $_ -match '(^|/)\.env([^/]*$)' -or
            [System.IO.Path]::GetExtension($_) -match '(?i)^\.(exe|dll|log|tmp|bak|pfx|p12|pem|key)$'
        })
        Assert-PayloadCondition -Condition ($forbiddenFiles.Count -eq 0) -Message 'The embedded cabinet must not include development data, secrets, temporary files, logs, or unrelated binaries.'
        $extractedStatus = Test-AppInstallerPayload -RootPath $extractedBuildRoot -RequirePackage
        Assert-PayloadCondition -Condition ($extractedStatus.IsValid -and $extractedStatus.Mode -eq 'packaged') -Message 'The extracted executable payload must validate its version and file hashes.'

        $cabCli = Invoke-PayloadEntryPoint -ScriptPath (Join-Path $extractedBuildRoot 'app-installer-cli.ps1') -WorkingDirectory $workingDirectory
        Assert-PayloadCondition -Condition ($cabCli.ExitCode -eq 0 -and $cabCli.Text -match 'mode=packaged') -Message 'The cabinet CLI must run its payload check from a different current directory.'
        $cabGui = Invoke-PayloadEntryPoint -ScriptPath (Join-Path $extractedBuildRoot 'app-installer.ps1') -WorkingDirectory $workingDirectory
        Assert-PayloadCondition -Condition ($cabGui.ExitCode -eq 0 -and $cabGui.Text -match 'mode=packaged') -Message 'The cabinet GUI entry point must run its payload check from a different current directory.'
        Write-Output ('[OK] Built and inspected an unsigned IExpress payload with {0} runtime files.' -f $actualPaths.Count)
    }
    else {
        Write-Output '[Not run] Windows cabinet build and extraction require Windows, MakeCab, and Expand.'
    }

    Write-Output ('[OK] Payload tests passed: assertions={0}; catalog={1}; appScripts={2}; defaultProfiles={3}; sourceFiles={4}' -f $script:AssertionCount, $applicationCount, $appScriptCount, $profileFiles.Count, $sourceInventory.Count)
}
finally {
    $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@([char]92, [char]47)) + [System.IO.Path]::DirectorySeparatorChar
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $resolvedInspectionRoot = [System.IO.Path]::GetFullPath($cabinetInspectionRoot)
    if ($resolvedInspectionRoot.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedInspectionRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
