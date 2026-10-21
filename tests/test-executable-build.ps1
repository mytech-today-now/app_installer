#Requires -Version 7.6.7
#Requires -PSEdition Core

$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$buildModulePath = Join-Path $repositoryRoot 'tools\InstallerExecutableBuild.psm1'
$payloadModulePath = Join-Path $repositoryRoot 'modules\InstallerPayload.psm1'
$configurationPath = Join-Path $repositoryRoot 'tools\installer-exe-build.json'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('InstallerExeBuildTests-' + [guid]::NewGuid().ToString('N'))

Import-Module -Name $buildModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
Import-Module -Name $payloadModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
$configuration = Get-Content -LiteralPath $configurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$sourceInventory = @(Get-AppInstallerPayloadFiles -RootPath $repositoryRoot)

function Assert-BuildCondition {
    param([bool]$Condition, [string]$Message)
    $script:AssertionCount++
    if (-not $Condition) { throw $Message }
}

function Assert-BuildFailure {
    param([scriptblock]$Action, [string]$Message)
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-BuildCondition -Condition $failed -Message $Message
}

function Copy-BuildFixtureFile {
    param([string]$SourceRoot, [string]$DestinationRoot, [string]$RelativePath)
    $sourcePath = Join-Path $SourceRoot ($RelativePath.Replace('/', '\'))
    $destinationPath = Join-Path $DestinationRoot ($RelativePath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Clean build fixture source is missing: $RelativePath" }
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force -ErrorAction Stop | Out-Null
    }
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force -ErrorAction Stop
}

function New-CleanBuildCopy {
    param([string]$DestinationRoot)

    New-Item -ItemType Directory -Path $DestinationRoot -Force -ErrorAction Stop | Out-Null
    foreach ($file in $sourceInventory) {
        Copy-BuildFixtureFile -SourceRoot $repositoryRoot -DestinationRoot $DestinationRoot -RelativePath $file.Path
    }
    foreach ($relativePath in @(
        'tools/Build-InstallerExe.ps1',
        'tools/InstallerExecutableBuild.psm1',
        'tools/InstallerExecutableVersionInfo.cs',
        'tools/Set-InstallerExeMetadata.ps1',
        'tools/installer-exe-build.json',
        'compatibility.json',
        'README.md',
        'builds/install-GUI.exe'
    )) {
        Copy-BuildFixtureFile -SourceRoot $repositoryRoot -DestinationRoot $DestinationRoot -RelativePath $relativePath
    }

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
    if ($null -eq $git) { throw 'Git is required for the clean-copy reproducibility test.' }
    & $git.Source -C $DestinationRoot -c core.autocrlf=false init -q
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the isolated build fixture repository.' }
    & $git.Source -C $DestinationRoot config core.autocrlf false
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the isolated build fixture repository.' }
    & $git.Source -C $DestinationRoot add -- .
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage the isolated build fixture source.' }

    $oldAuthorDate = $env:GIT_AUTHOR_DATE
    $oldCommitterDate = $env:GIT_COMMITTER_DATE
    try {
        $env:GIT_AUTHOR_DATE = '2000-01-01T00:00:00Z'
        $env:GIT_COMMITTER_DATE = '2000-01-01T00:00:00Z'
        & $git.Source -C $DestinationRoot -c user.name='App Installer Build Test' -c user.email='build-test@example.invalid' -c commit.gpgsign=false commit -q -m 'Clean executable build fixture'
        if ($LASTEXITCODE -ne 0) { throw 'Could not commit the isolated build fixture source.' }
    }
    finally {
        $env:GIT_AUTHOR_DATE = $oldAuthorDate
        $env:GIT_COMMITTER_DATE = $oldCommitterDate
    }
    $status = @(& $git.Source -C $DestinationRoot status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $status.Count -ne 0) { throw 'The isolated build fixture is not clean after commit.' }
}

function Invoke-CleanCopyBuild {
    param([string]$FixtureRoot, [string]$OutputName)

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) { $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue }
    if ($null -eq $pwsh) { throw 'PowerShell Core 7.6.7 is required for the executable build test.' }
    $outputDirectory = Join-Path $FixtureRoot 'builds\generated'
    New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
    $artifactPath = Join-Path $outputDirectory $OutputName
    $childBuilderPath = Join-Path $FixtureRoot 'tools\Build-InstallerExe.ps1'
    $output = @(& $pwsh.Source -NoProfile -File $childBuilderPath -OutputPath $artifactPath -Confirm:$false 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ('Clean-copy executable build failed with exit code {0}: {1}' -f $exitCode, ($output -join [Environment]::NewLine))
    }
    $manifestPath = $artifactPath + '.build.json'
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'The clean-copy build did not create both its executable and provenance manifest.'
    }
    return [PSCustomObject]@{
        ArtifactPath = $artifactPath
        ArtifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force -ErrorAction Stop | Out-Null
    if ($temporaryRoot -match '[^\x20-\x7E]') {
        throw 'The Windows cabinet test requires an ASCII-only temporary path for Expand.exe.'
    }

    $context = Get-InstallerExeBuildContext -Configuration $configuration -RepositoryRoot $repositoryRoot -SeedPath (Join-Path $repositoryRoot 'builds\install-GUI.exe')
    $contextResult = Test-InstallerExeBuildContext -Configuration $configuration -Context $context
    Assert-BuildCondition -Condition $contextResult.IsValid -Message ('The pinned build context must validate: ' + ($contextResult.Errors -join '; '))

    # GitHub's standard x64 windows-2025 runner uses Windows Server 2025 build 26100.
    $hostedRunnerContext = $context | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $hostedRunnerContext.Host.WindowsBuild = 26100
    $hostedRunnerResult = Test-InstallerExeBuildContext -Configuration $configuration -Context $hostedRunnerContext
    Assert-BuildCondition -Condition $hostedRunnerResult.IsValid -Message ('The pinned toolchain configuration must allow the standard Windows Server 2025 runner build: ' + ($hostedRunnerResult.Errors -join '; '))

    $versionText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Raw
    $guiSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer.ps1') -Raw
    $cliSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer-cli.ps1') -Raw
    $readmeText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
    $versionResult = Test-InstallerExeVersionContract -VersionText $versionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $readmeText
    Assert-BuildCondition -Condition $versionResult.IsValid -Message ('VERSION, script headers and assignments, and README versions must agree: ' + ($versionResult.Errors -join '; '))
    Assert-BuildCondition -Condition ($versionResult.GuiVersion -ceq '2.0.6' -and $versionResult.CliVersion -ceq '2.0.2') -Message 'The release product version must remain the GUI version while the CLI keeps its separate current version.'
    Assert-BuildCondition -Condition ($guiSource -match '(?m)^Write-Host "Version: \$script:ScriptVersion"' -and $cliSource -match '(?m)^Write-Host "Version: \$script:ScriptVersion"') -Message 'Both startup banners must display the validated script version.'
    Assert-BuildCondition -Condition ($configuration.artifact.identity -ceq 'app-installer-versioned-release-v1') -Message 'The build configuration must name the current versioned release artifact.'
    $protectedLegacyPaths = New-Object 'System.Collections.Generic.List[string]'
    $legacyHashesBefore = @{}
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
    if ($null -eq $gitCommand) { throw 'Git is required to verify tracked legacy artifact inventory.' }
    foreach ($legacyArtifact in @($configuration.legacyArtifacts)) {
        $legacyRelativePath = ([string]$legacyArtifact.path).Replace('/', '\')
        $legacyPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $legacyRelativePath))
        if (-not (Test-Path -LiteralPath $legacyPath -PathType Leaf)) { throw ('A configured legacy artifact is missing: {0}' -f $legacyRelativePath) }
        $trackedOutput = @(& $gitCommand.Source -C $repositoryRoot ls-files --error-unmatch -- $legacyRelativePath 2>&1)
        $trackedExitCode = $LASTEXITCODE
        Assert-BuildCondition -Condition ($trackedExitCode -eq 0 -and [string]::Join('', $trackedOutput).Trim() -ceq $legacyRelativePath.Replace('\', '/')) -Message ('The legacy artifact must remain Git tracked: {0}' -f $legacyRelativePath)
        $legacyHash = (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        $legacyInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($legacyPath)
        $legacySignature = Get-AuthenticodeSignature -FilePath $legacyPath -ErrorAction Stop
        Assert-BuildCondition -Condition ($legacyHash -ceq [string]$legacyArtifact.sha256 -and [string]$legacyInfo.FileVersion -ceq [string]$legacyArtifact.fileVersion) -Message ('The recorded legacy hash and file version must match: {0}' -f $legacyRelativePath)
        Assert-BuildCondition -Condition ([bool]$legacyArtifact.gitTracked -and [string]$legacyInfo.ProductName -ceq [string]$legacyArtifact.productName -and [string]$legacySignature.Status -ceq [string]$legacyArtifact.authenticodeStatus -and -not [bool]$legacyArtifact.releaseEligible) -Message ('Legacy metadata must match the inventory and remain tracked and release-ineligible: {0}' -f $legacyRelativePath)
        Assert-BuildCondition -Condition ([string]$legacyArtifact.provenanceStatus -ceq 'unknown' -and [string]$legacyArtifact.identity -ne [string]$configuration.artifact.identity) -Message ('Legacy provenance must remain explicitly unknown and distinct: {0}' -f $legacyRelativePath)
        $protectedLegacyPaths.Add($legacyPath)
        $legacyHashesBefore[$legacyPath] = $legacyHash
    }
    $badGuiSource = [regex]::Replace($guiSource, '(?m)^(\$script:ScriptVersion\s*=\s*)[''"]2\.0\.6[''"]', '$script:ScriptVersion = ''9.9.9''', 1)
    $badVersionResult = Test-InstallerExeVersionContract -VersionText $versionText -GuiSource $badGuiSource -CliSource $cliSource -ReadmeText $readmeText
    Assert-BuildCondition -Condition (-not $badVersionResult.IsValid) -Message 'A stale GUI script version must be rejected.'
    $badHeaderSource = $guiSource.Replace('Version        : 2.0.6', 'Version        : 2.0.0')
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $versionText -GuiSource $badHeaderSource -CliSource $cliSource -ReadmeText $readmeText).IsValid) -Message 'A stale script header version must be rejected.'
    $malformedVersionText = $versionText.Replace('**GUI Version:** 2.0.6', '**GUI Version:** 02.0.6')
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $malformedVersionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $readmeText).IsValid) -Message 'A malformed semantic version must be rejected.'
    $prereleaseVersionText = $versionText.Replace('**GUI Version:** 2.0.6', '**GUI Version:** 2.0.6-rc.1')
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $prereleaseVersionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $readmeText).IsValid) -Message 'Prerelease versions must be rejected because the release workflow supports stable tags only.'
    $missingVersionText = [regex]::Replace($versionText, '(?m)^\*\*CLI Version:\*\*.*\r?\n', '', 1)
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $missingVersionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $readmeText).IsValid) -Message 'A missing CLI version must be rejected.'
    $emptyVersionText = $versionText.Replace('**GUI Version:** 2.0.6', '**GUI Version:**')
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $emptyVersionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $readmeText).IsValid) -Message 'An empty canonical version must be rejected.'
    $duplicateVersionText = $versionText + [Environment]::NewLine + '**GUI Version:** 9.9.9'
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $duplicateVersionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $readmeText).IsValid) -Message 'Duplicate current version declarations must be rejected.'
    $duplicateGuiSource = $guiSource + [Environment]::NewLine + '$script:ScriptVersion = ''9.9.9'''
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $versionText -GuiSource $duplicateGuiSource -CliSource $cliSource -ReadmeText $readmeText).IsValid) -Message 'Duplicate competing script version assignments must be rejected.'
    $staleReadme = $readmeText.Replace('**Version:** 2.0.6 (GUI) / 2.0.2 (CLI)', '**Version:** 2.0.5 (GUI) / 2.0.2 (CLI)')
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $versionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $staleReadme).IsValid) -Message 'Stale README current-version declarations must be rejected.'
    $staleReleaseMapping = $readmeText.Replace('**Release version mapping:** GUI 2.0.6 / CLI 2.0.2', '**Release version mapping:** GUI 2.0.5 / CLI 2.0.2')
    Assert-BuildCondition -Condition (-not (Test-InstallerExeVersionContract -VersionText $versionText -GuiSource $guiSource -CliSource $cliSource -ReadmeText $staleReleaseMapping).IsValid) -Message 'A stale release-version mapping in README must be rejected.'

    $compatibility = Get-Content -LiteralPath (Join-Path $repositoryRoot 'compatibility.json') -Raw | ConvertFrom-Json
    $compatibilityResult = Test-InstallerExeCompatibilityContract -Compatibility $compatibility -Configuration $configuration
    Assert-BuildCondition -Condition $compatibilityResult.IsValid -Message 'The compatibility contract must match the pinned build configuration.'
    $badCompatibility = $compatibility | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badCompatibility.windowsExecutable.entryPoint = 'unexpected.exe'
    $badCompatibilityResult = Test-InstallerExeCompatibilityContract -Compatibility $badCompatibility -Configuration $configuration
    Assert-BuildCondition -Condition (-not $badCompatibilityResult.IsValid) -Message 'A stale executable format or entry point must be rejected.'

    $badArchitectureContext = $context | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badArchitectureContext.Host.ProcessArchitecture = 'ARM64'
    $badArchitectureResult = Test-InstallerExeBuildContext -Configuration $configuration -Context $badArchitectureContext
    Assert-BuildCondition -Condition (-not $badArchitectureResult.IsValid) -Message 'An architecture mismatch must fail build configuration validation.'
    $missingToolContext = $context | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $missingToolContext.Packager.MakeCab.Exists = $false
    $missingToolResult = Test-InstallerExeBuildContext -Configuration $configuration -Context $missingToolContext
    Assert-BuildCondition -Condition (-not $missingToolResult.IsValid) -Message 'A missing pinned packager must fail build configuration validation.'
    $corruptSeedContext = $context | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $corruptSeedContext.Seed.File.Sha256 = ('0' * 64)
    $corruptSeedResult = Test-InstallerExeBuildContext -Configuration $configuration -Context $corruptSeedContext
    Assert-BuildCondition -Condition (-not $corruptSeedResult.IsValid) -Message 'A changed seed hash must fail build configuration validation.'
    $missingCompilerContext = $context | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $missingCompilerContext.Compiler.Assemblies[0].Exists = $false
    $missingCompilerResult = Test-InstallerExeBuildContext -Configuration $configuration -Context $missingCompilerContext
    Assert-BuildCondition -Condition (-not $missingCompilerResult.IsValid) -Message 'A missing pinned Roslyn assembly must fail build configuration validation.'
    Assert-BuildCondition -Condition (@($configuration.host.PSObject.Properties.Name) -notcontains 'dotnetSdk') -Message 'The build must not add a separate .NET SDK dependency.'

    $orderedInventory = @(New-InstallerExeBuildInventory -Files $sourceInventory)
    $reversedFiles = @($sourceInventory)
    [Array]::Reverse($reversedFiles)
    $reversedInventory = @(New-InstallerExeBuildInventory -Files $reversedFiles)
    $orderedJson = ConvertTo-Json -InputObject $orderedInventory -Depth 5 -Compress
    $reversedJson = ConvertTo-Json -InputObject $reversedInventory -Depth 5 -Compress
    Assert-BuildCondition -Condition ($orderedJson -ceq $reversedJson) -Message 'Payload file inventory order must be deterministic.'
    $inventoryHash = Get-InstallerExeBuildInventorySha256 -Inventory $orderedInventory
    Assert-BuildCondition -Condition ($inventoryHash -match '^[0-9a-f]{64}$') -Message 'The normalized payload inventory must have a SHA-256 digest.'
    $versionRecord = @($orderedInventory | Where-Object { $_.path -ceq 'VERSION' }) | Select-Object -First 1
    Assert-BuildCondition -Condition ($versionRecord.sha256 -ceq (Get-FileHash -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Algorithm SHA256).Hash.ToLowerInvariant()) -Message 'The hash manifest must contain the source digest for every runtime file.'
    Assert-BuildCondition -Condition ([long]$versionRecord.length -eq (Get-Item -LiteralPath (Join-Path $repositoryRoot 'VERSION')).Length) -Message 'The hash manifest must record exact source file lengths.'

    Assert-InstallerExeUnsignedArtifact -SignatureStatus 'NotSigned' -SignerSubject ''
    Assert-BuildFailure -Action { Assert-InstallerExeUnsignedArtifact -SignatureStatus 'Valid' -SignerSubject 'CN=Publisher' } -Message 'A signed executable must be rejected.'

    $staleOutputPath = Join-Path $temporaryRoot 'stale-output.exe'
    [System.IO.File]::WriteAllText($staleOutputPath, 'stale')
    Assert-BuildFailure -Action { Assert-InstallerExeBuildOutputPath -OutputPath $staleOutputPath -SeedPath (Join-Path $repositoryRoot 'builds\install-GUI.exe') } -Message 'A stale executable output must not be overwritten.'
    $staleManifestOutputPath = Join-Path $temporaryRoot 'stale-manifest.exe'
    [System.IO.File]::WriteAllText(($staleManifestOutputPath + '.build.json'), '{}')
    Assert-BuildFailure -Action { Assert-InstallerExeBuildOutputPath -OutputPath $staleManifestOutputPath -SeedPath (Join-Path $repositoryRoot 'builds\install-GUI.exe') } -Message 'A stale provenance manifest must not be overwritten.'
    foreach ($legacyPath in @($protectedLegacyPaths.ToArray())) {
        Assert-BuildFailure -Action {
            Assert-InstallerExeBuildOutputPath -OutputPath $legacyPath -SeedPath (Join-Path $repositoryRoot 'builds\install-GUI.exe') -ProtectedOutputPaths @($protectedLegacyPaths.ToArray())
        } -Message ('A tracked legacy executable must never be selected as output: {0}' -f $legacyPath)
    }

    $fixtureRoot = Join-Path $temporaryRoot 'InventoryFixture'
    foreach ($relativeDirectory in @('apps', 'modules', 'profiles', 'apps\dev', 'apps\test-fixtures', 'builds\generated', 'tests')) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $relativeDirectory) -Force -ErrorAction Stop | Out-Null
    }
    $fixtureManifest = [ordered]@{
        formatVersion = 1
        productVersionFile = 'VERSION'
        generatedIntegrityFile = 'payload-integrity.json'
        requiredFiles = @('app-installer.ps1', 'payload-manifest.json', 'VERSION')
        fileSets = @(
            [ordered]@{ path = 'apps'; extensions = @('.ps1') },
            [ordered]@{ path = 'modules'; extensions = @('.psm1') },
            [ordered]@{ path = 'profiles'; extensions = @('.json'); fileNames = @('profile-default.json') }
        )
        features = [ordered]@{ cli = @('apps/install.ps1'); gui = @() }
        exclusions = [ordered]@{
            directoryNames = @('tests', 'fixtures', 'dev', 'test-fixtures')
            fileNamePrefixes = @('.env')
            extensions = @('.exe', '.log', '.tmp', '.pfx', '.pem', '.key')
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'payload-manifest.json'), (ConvertTo-Json -InputObject $fixtureManifest -Depth 8), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'app-installer.ps1'), '# fixture')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'VERSION'), '**GUI Version:** 1.0.0')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'apps\install.ps1'), '# fixture')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'modules\core.psm1'), '# fixture')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'profiles\profile-default.json'), '{}')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'apps\dev\local.ps1'), '# private dev script')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'apps\test-fixtures\fixture.ps1'), '# fixture')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'apps\tool.exe'), 'unrelated binary')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'apps\.env'), 'secret')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'profiles\profile-user.json'), '{}')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'builds\generated\stale.exe'), 'stale')
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'tests\fixture.ps1'), '# test')
    $fixtureFiles = @(Get-AppInstallerPayloadFiles -RootPath $fixtureRoot)
    $fixturePaths = @($fixtureFiles | ForEach-Object { $_.Path } | Sort-Object)
    Assert-BuildCondition -Condition ($fixturePaths.Count -eq 6) -Message 'The explicit fixture payload should contain only required runtime files.'
    Assert-BuildCondition -Condition ($fixturePaths -notcontains 'apps/dev/local.ps1' -and $fixturePaths -notcontains 'apps/test-fixtures/fixture.ps1' -and $fixturePaths -notcontains 'apps/tool.exe' -and $fixturePaths -notcontains 'apps/.env' -and $fixturePaths -notcontains 'profiles/profile-user.json') -Message 'Unexpected payload files, local secrets, user profiles, and stale outputs must be excluded.'

    $missingSourceRoot = Join-Path $temporaryRoot 'MissingSource'
    New-Item -ItemType Directory -Path $missingSourceRoot -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'payload-manifest.json') -Destination $missingSourceRoot
    Assert-BuildFailure -Action { Get-AppInstallerPayloadFiles -RootPath $missingSourceRoot } -Message 'A missing required source file must fail payload inventory validation.'

    $sdkList = @()
    $dotnetCommand = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($null -eq $dotnetCommand) { $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue }
    if ($null -ne $dotnetCommand) { $sdkList = @(& $dotnetCommand.Source --list-sdks 2>$null) }
    if ($sdkList.Count -eq 0) {
        Assert-BuildCondition -Condition ($contextResult.IsValid -and [string]$configuration.host.compiler.name -match 'Roslyn' -and -not [bool]$configuration.host.compiler.dotnetSdkRequired) -Message 'The pinned Roslyn compiler must build without a separate .NET SDK.'
        Write-Output '[OK] No separate .NET SDK is installed or required; the compiler is bundled with the pinned PowerShell distribution.'
    }

    $cleanCopyA = Join-Path $temporaryRoot 'CleanCopyA'
    $cleanCopyB = Join-Path $temporaryRoot 'CleanCopyB'
    $corruptSeedCopy = Join-Path $temporaryRoot 'CorruptSeedCopy'
    New-CleanBuildCopy -DestinationRoot $cleanCopyA
    New-CleanBuildCopy -DestinationRoot $cleanCopyB

    New-CleanBuildCopy -DestinationRoot $corruptSeedCopy
    $corruptSeedPath = Join-Path $corruptSeedCopy 'builds\install-GUI.exe'
    $corruptSeedBytes = [System.IO.File]::ReadAllBytes($corruptSeedPath)
    $corruptSeedBytes[$corruptSeedBytes.Length - 1] = [byte]($corruptSeedBytes[$corruptSeedBytes.Length - 1] -bxor 0xFF)
    [System.IO.File]::WriteAllBytes($corruptSeedPath, $corruptSeedBytes)
    $corruptOutputDirectory = Join-Path $corruptSeedCopy 'builds\generated'
    New-Item -ItemType Directory -Path $corruptOutputDirectory -Force -ErrorAction Stop | Out-Null
    $corruptArtifactPath = Join-Path $corruptOutputDirectory 'AppInstaller-corrupt-seed.exe'
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) { $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue }
    if ($null -eq $pwsh) { throw 'PowerShell Core 7.6.7 is required for the corrupted-input build test.' }
    $corruptBuilderPath = Join-Path $corruptSeedCopy 'tools\Build-InstallerExe.ps1'
    $corruptBuildOutput = @(& $pwsh.Source -NoProfile -File $corruptBuilderPath -OutputPath $corruptArtifactPath -Confirm:$false 2>&1)
    $corruptBuildExitCode = $LASTEXITCODE
    Assert-BuildCondition -Condition ($corruptBuildExitCode -ne 0) -Message 'The builder must reject a corrupted pinned IExpress seed.'
    Assert-BuildCondition -Condition (-not (Test-Path -LiteralPath $corruptArtifactPath) -and -not (Test-Path -LiteralPath ($corruptArtifactPath + '.build.json'))) -Message 'A corrupted build input must be rejected before any output is published.'
    Write-Output '[OK] A corrupted pinned seed was rejected before output publication.'

    $releaseExecutableName = ([string]$configuration.artifact.outputNamePattern).Replace('{guiVersion}', $versionResult.GuiVersion)
    $expectedReleasePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $repositoryRoot ([string]$configuration.artifact.defaultOutputDirectory)) $releaseExecutableName))
    Assert-BuildCondition -Condition ([System.IO.Path]::GetFileName($expectedReleasePath) -ceq $releaseExecutableName -and $expectedReleasePath -notin @($protectedLegacyPaths.ToArray())) -Message 'The current build must use a distinct versioned output path.'
    $buildA = Invoke-CleanCopyBuild -FixtureRoot $cleanCopyA -OutputName $releaseExecutableName
    $buildB = Invoke-CleanCopyBuild -FixtureRoot $cleanCopyB -OutputName $releaseExecutableName
    & (Join-Path $PSScriptRoot 'test-installer-release-assets.ps1') -RepositoryRoot $cleanCopyA -ExecutablePath $buildA.ArtifactPath
    $buildVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($buildA.ArtifactPath)
    Assert-BuildCondition -Condition ($buildVersionInfo.OriginalFilename -ceq $releaseExecutableName) -Message 'The generated executable resource metadata must identify the versioned release filename.'
    Assert-BuildCondition -Condition ($buildA.Manifest.source.worktreeClean -and $buildB.Manifest.source.worktreeClean) -Message 'Both executable builds must originate from clean source copies.'
    Assert-BuildCondition -Condition ($buildA.Manifest.source.revision -ceq $buildB.Manifest.source.revision) -Message 'Both clean copies must have the same source revision.'
    Assert-BuildCondition -Condition ($buildA.Manifest.payload.inventorySha256 -ceq $buildB.Manifest.payload.inventorySha256) -Message 'Clean builds must produce the same normalized payload inventory digest.'
    Assert-BuildCondition -Condition ($buildA.Manifest.payload.files.Count -eq $sourceInventory.Count -and $buildB.Manifest.payload.files.Count -eq $sourceInventory.Count) -Message 'Build manifests must contain every source runtime file.'
    Assert-BuildCondition -Condition ($buildA.Manifest.artifact.sha256 -ceq $buildA.ArtifactHash -and $buildB.Manifest.artifact.sha256 -ceq $buildB.ArtifactHash) -Message 'Each provenance manifest must contain the generated artifact digest.'
    Assert-BuildCondition -Condition ($buildA.Manifest.artifact.identity -ceq $configuration.artifact.identity -and $buildB.Manifest.artifact.identity -ceq $configuration.artifact.identity) -Message 'Both current builds must carry the configured release artifact identity.'
    Assert-BuildCondition -Condition ($buildA.Manifest.artifact.fileName -ceq $releaseExecutableName -and $buildB.Manifest.artifact.fileName -ceq $releaseExecutableName) -Message 'Both current builds must use the exact versioned filename.'
    Assert-BuildCondition -Condition ($buildA.Manifest.artifact.authenticodeStatus -ceq 'NotSigned' -and $buildB.Manifest.artifact.authenticodeStatus -ceq 'NotSigned') -Message 'Both generated executable files must remain unsigned.'
    Assert-BuildCondition -Condition ($buildA.Manifest.artifact.architecture -ceq 'X64' -and $buildB.Manifest.artifact.architecture -ceq 'X64') -Message 'Both generated executable files must target x64.'
    $manifestText = ConvertTo-Json -InputObject $buildA.Manifest -Depth 16 -Compress
    Assert-BuildCondition -Condition ($manifestText -notmatch '(?i)([A-Z]:\\|\\\\)') -Message 'The provenance manifest must not embed machine-local absolute paths.'
    Assert-BuildCondition -Condition (-not [bool]$buildA.Manifest.reproducibility.buildTimestampRecorded -and -not [bool]$buildA.Manifest.toolchain.compiler.dotnetSdkRequired) -Message 'The provenance manifest must omit build timestamps and confirm no separate .NET SDK was used.'
    if ($buildA.ArtifactHash -ne $buildB.ArtifactHash) {
        throw ('Clean builds produced different executable hashes ({0} and {1}) despite identical payload inventory and toolchain.' -f $buildA.ArtifactHash, $buildB.ArtifactHash)
    }
    foreach ($legacyPath in $legacyHashesBefore.Keys) {
        $legacyHashAfter = (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        Assert-BuildCondition -Condition ($legacyHashAfter -ceq $legacyHashesBefore[$legacyPath]) -Message ('The build must leave legacy bytes unchanged: {0}' -f $legacyPath)
    }
    Write-Output ('[OK] Two clean-copy builds matched byte-for-byte: {0}' -f $buildA.ArtifactHash)
    Write-Output ('[OK] Executable build tests passed: assertions={0}; payloadFiles={1}' -f $script:AssertionCount, $sourceInventory.Count)
}
finally {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@([char]92, [char]47)) + [System.IO.Path]::DirectorySeparatorChar
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    if ($resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
