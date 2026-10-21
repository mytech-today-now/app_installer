#Requires -Version 7.6.7
#Requires -PSEdition Core

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryRoot,

    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath
)

$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0
$root = [System.IO.Path]::GetFullPath($RepositoryRoot)
$executable = [System.IO.Path]::GetFullPath($ExecutablePath)
$buildManifestPath = $executable + '.build.json'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\InstallerRelease.psm1'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@([char]92, [char]47)) + [System.IO.Path]::DirectorySeparatorChar
$tempRoot = Join-Path $tempBase ('InstallerReleaseTests-' + [guid]::NewGuid().ToString('N'))

function Assert-ReleaseCondition {
    param([bool]$Condition, [string]$Message)
    $script:AssertionCount++
    if (-not $Condition) { throw $Message }
}

function Assert-ReleaseFailure {
    param([scriptblock]$Action, [string]$Message)
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-ReleaseCondition -Condition $failed -Message $Message
}

function Copy-ReleaseInputVariant {
    param([string]$VariantName, [object]$Manifest)
    $variantRoot = Join-Path $tempRoot $VariantName
    New-Item -ItemType Directory -Path $variantRoot -Force -ErrorAction Stop | Out-Null
    $variantExecutable = Join-Path $variantRoot ([System.IO.Path]::GetFileName($executable))
    Copy-Item -LiteralPath $executable -Destination $variantExecutable -ErrorAction Stop
    $variantManifestPath = $variantExecutable + '.build.json'
    $manifestJson = ConvertTo-Json -InputObject $Manifest -Depth 32
    [System.IO.File]::WriteAllText($variantManifestPath, $manifestJson + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    return [PSCustomObject]@{ Root = $variantRoot; Executable = $variantExecutable; Manifest = $variantManifestPath }
}

Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
if (-not (Test-Path -LiteralPath $root -PathType Container) -or
    -not (Test-Path -LiteralPath $executable -PathType Leaf) -or
    -not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
    throw 'The release asset test requires a clean build fixture with its adjacent provenance manifest.'
}

$buildManifest = Get-Content -LiteralPath $buildManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$buildConfiguration = Get-Content -LiteralPath (Join-Path $root 'tools\installer-exe-build.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$versionContract = Get-InstallerReleaseVersionContract -RepositoryRoot $root -TagName ('v' + [string]$buildManifest.artifact.fileVersion -replace '\.0$', '')
$tagName = $versionContract.TagName
$sourceCommit = [string]$buildManifest.source.revision
$outputDirectory = Join-Path $tempRoot 'release-assets'
$workflowName = 'Windows Build and PowerShell Compatibility'
$testEngines = @('Desktop-5.1', 'Core-7.6.7')
$runId = '123456789'

try {
    New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction Stop | Out-Null

    Assert-ReleaseCondition -Condition ($versionContract.ProductVersion -ceq '2.0.6') -Message 'The release version must be derived from the GUI version source.'
    Assert-ReleaseCondition -Condition ($buildManifest.artifact.identity -ceq $buildConfiguration.artifact.identity) -Message 'The builder manifest must identify the configured current release artifact.'
    $releasePreparationText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\New-InstallerReleaseAssets.ps1') -Raw -ErrorAction Stop
    $adjacentManifestPattern = "\`$buildManifestPath\s*=\s*\`$executablePath\s*\+\s*'\.build\.json'"
    Assert-ReleaseCondition -Condition ($releasePreparationText.Contains('artifact.defaultOutputDirectory') -and $releasePreparationText.Contains('artifact.outputNamePattern') -and $releasePreparationText -match $adjacentManifestPattern -and $releasePreparationText -notmatch '(?i)Get-ChildItem') -Message 'Release preparation must select the configured versioned path and adjacent manifest without scanning EXE files.'
    $readmeText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'README.md') -Raw -ErrorAction Stop
    Assert-ReleaseCondition -Condition ($readmeText -notmatch '(?im)^\s*&\s*\.\\builds\\(?:new\\)?install-gui\.exe\s*$' -and $readmeText.Contains('AppInstaller-<GUI-version>-win-x64.exe')) -Message 'README examples must not launch either legacy executable and must identify the versioned release asset.'
    foreach ($badTag in @('2.0.6', 'v02.0.6', 'v2.0.6-rc.1', 'v9.9.9')) {
        Assert-ReleaseFailure -Action { Get-InstallerReleaseVersionContract -RepositoryRoot $root -TagName $badTag } -Message ('The release validator must reject tag {0}.' -f $badTag)
    }
    Assert-ReleaseFailure -Action {
        New-InstallerReleaseAssets -RepositoryRoot $root -ExecutablePath $executable -BuildManifestPath $buildManifestPath `
            -OutputDirectory (Join-Path $tempRoot 'bad-engines') -TagName $tagName -SourceCommit $sourceCommit `
            -DefaultBranch 'main' -WorkflowName $workflowName -RunId $runId -PassedEngines @('Desktop-5.1', 'Desktop-5.1')
    } -Message 'Duplicate or incomplete test evidence must block release asset preparation.'

    Assert-InstallerReleaseSourceGate -SourceCommit $sourceCommit -RemoteTagCommit $sourceCommit -IsDefaultBranchAncestor $true -WorkflowFilesMatchDefaultBranch $true
    Assert-ReleaseFailure -Action {
        Assert-InstallerReleaseSourceGate -SourceCommit $sourceCommit -RemoteTagCommit ('0' * 40) -IsDefaultBranchAncestor $true -WorkflowFilesMatchDefaultBranch $true
    } -Message 'A moved or missing remote tag must fail source verification.'
    Assert-ReleaseFailure -Action {
        Assert-InstallerReleaseSourceGate -SourceCommit $sourceCommit -RemoteTagCommit $sourceCommit -IsDefaultBranchAncestor $false -WorkflowFilesMatchDefaultBranch $true
    } -Message 'A source commit outside the default branch must fail release verification.'
    Assert-ReleaseFailure -Action {
        Assert-InstallerReleaseSourceGate -SourceCommit $sourceCommit -RemoteTagCommit $sourceCommit -IsDefaultBranchAncestor $true -WorkflowFilesMatchDefaultBranch $false
    } -Message 'Changed workflow files must fail the contents-only release token gate.'

    $releaseAssets = New-InstallerReleaseAssets `
        -RepositoryRoot $root `
        -ExecutablePath $executable `
        -BuildManifestPath $buildManifestPath `
        -OutputDirectory $outputDirectory `
        -TagName $tagName `
        -SourceCommit $sourceCommit `
        -DefaultBranch 'main' `
        -WorkflowName $workflowName `
        -RunId $runId `
        -PassedEngines $testEngines
    $expectedExecutable = 'AppInstaller-2.0.6-win-x64.exe'
    $expectedAssets = @(
        $expectedExecutable,
        ($expectedExecutable + '.sha256'),
        ($expectedExecutable + '.build.json'),
        'AppInstaller-2.0.6-win-x64.release.json'
    )
    Assert-ReleaseCondition -Condition ((@($releaseAssets.AssetPaths | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join '|') -ceq ($expectedAssets -join '|')) -Message 'The release must stage one versioned x64 executable and exactly its three provenance assets.'
    Assert-ReleaseCondition -Condition ((Get-InstallerExecutableArchitecture -Path $releaseAssets.ExecutablePath) -ceq 'X64') -Message 'The staged release executable must be a real x64 PE.'

    $stagedHash = (Get-FileHash -LiteralPath $releaseAssets.ExecutablePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumText = Get-Content -LiteralPath $releaseAssets.ChecksumPath -Raw
    Assert-ReleaseCondition -Condition ($checksumText -match ('^' + $stagedHash + '\s{2}' + [regex]::Escape($expectedExecutable) + '\r?\n$')) -Message 'The SHA-256 sidecar must contain the exact digest and executable name.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.artifact.sha256 -ceq $stagedHash) -Message 'The release manifest digest must match the staged executable bytes.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.artifact.authenticodeStatus -ceq 'NotSigned' -and [string]::IsNullOrEmpty([string]$releaseAssets.Manifest.artifact.signerSubject)) -Message 'Release metadata must identify the artifact as unsigned.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.artifact.identity -ceq $buildConfiguration.artifact.identity) -Message 'Release metadata must retain the current versioned artifact identity.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.artifact.architecture -ceq 'X64' -and $releaseAssets.Manifest.artifact.fileName -ceq $expectedExecutable) -Message 'Release metadata must match the x64 artifact name and target.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.product.guiVersion -ceq '2.0.6' -and $releaseAssets.Manifest.product.cliVersion -ceq '2.0.2') -Message 'Release metadata must preserve the separate documented GUI and CLI versions.'
    $executableVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
    Assert-ReleaseCondition -Condition ($executableVersionInfo.FileVersion -ceq ($versionContract.ProductVersion + '.0') -and $executableVersionInfo.ProductVersion -ceq ($versionContract.ProductVersion + '.0') -and [System.IO.Path]::GetFileName($executable) -ceq $expectedExecutable) -Message 'The EXE file properties, product version, and versioned artifact name must match the canonical GUI release version.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.release.tag -ceq $tagName -and $releaseAssets.Manifest.release.sourceCommit -ceq $sourceCommit) -Message 'Release metadata must identify the exact source tag and commit.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.payloadInventory.fileCount -eq @($buildManifest.payload.files).Count -and @($releaseAssets.Manifest.payloadInventory.files).Count -eq @($buildManifest.payload.files).Count) -Message 'The release manifest must include the complete payload inventory.'
    Assert-ReleaseCondition -Condition (@($releaseAssets.Manifest.release.testEvidence | Where-Object { $_.result -ceq 'passed' }).Count -eq 2) -Message 'The release manifest must record both passing PowerShell engines.'
    Assert-ReleaseCondition -Condition ($releaseAssets.Manifest.buildToolchain.powerShell.version -ceq '7.6.7' -and $releaseAssets.Manifest.compatibility.sha256 -match '^[0-9a-f]{64}$') -Message 'The release manifest must include the pinned build toolchain and compatibility digest.'
    $releaseNotesText = Get-Content -LiteralPath $releaseAssets.ReleaseNotesPath -Raw
    Assert-ReleaseCondition -Condition ($releaseNotesText.Contains($expectedExecutable) -and $releaseNotesText.Contains('GUI script version 2.0.6; the bundled CLI keeps its separate script version 2.0.2')) -Message 'Release notes must name the exact executable and preserve the GUI to CLI version mapping.'
    Assert-ReleaseCondition -Condition (-not $releaseNotesText.Contains([string][char]0x2014)) -Message 'Release notes must not contain an em dash.'

    Assert-ReleaseFailure -Action {
        New-InstallerReleaseAssets -RepositoryRoot $root -ExecutablePath $executable -BuildManifestPath $buildManifestPath `
            -OutputDirectory $outputDirectory -TagName $tagName -SourceCommit $sourceCommit `
            -DefaultBranch 'main' -WorkflowName $workflowName -RunId $runId -PassedEngines $testEngines
    } -Message 'A duplicate asset output directory must not be overwritten.'
    Assert-ReleaseFailure -Action {
        New-InstallerReleaseAssets -RepositoryRoot $root -ExecutablePath $executable -BuildManifestPath ($buildManifestPath + '.missing') `
            -OutputDirectory (Join-Path $tempRoot 'missing-provenance-assets') -TagName $tagName -SourceCommit $sourceCommit `
            -DefaultBranch 'main' -WorkflowName $workflowName -RunId $runId -PassedEngines $testEngines
    } -Message 'Missing builder provenance must block release asset preparation.'

    $duplicateManifest = $buildManifest | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    $duplicateManifest.payload.files = @($duplicateManifest.payload.files) + @($duplicateManifest.payload.files[0])
    $duplicateManifest.payload.fileCount = [int]$duplicateManifest.payload.fileCount + 1
    $duplicateInput = Copy-ReleaseInputVariant -VariantName 'duplicate-inventory' -Manifest $duplicateManifest
    Assert-ReleaseFailure -Action {
        New-InstallerReleaseAssets -RepositoryRoot $root -ExecutablePath $duplicateInput.Executable -BuildManifestPath $duplicateInput.Manifest `
            -OutputDirectory (Join-Path $tempRoot 'duplicate-inventory-assets') -TagName $tagName -SourceCommit $sourceCommit `
            -DefaultBranch 'main' -WorkflowName $workflowName -RunId $runId -PassedEngines $testEngines
    } -Message 'Duplicate payload inventory paths must block release asset preparation.'

    $mismatchedManifest = $buildManifest | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    $mismatchedManifest.artifact.fileVersion = '9.9.9.0'
    $mismatchedInput = Copy-ReleaseInputVariant -VariantName 'mismatched-version' -Manifest $mismatchedManifest
    Assert-ReleaseFailure -Action {
        New-InstallerReleaseAssets -RepositoryRoot $root -ExecutablePath $mismatchedInput.Executable -BuildManifestPath $mismatchedInput.Manifest `
            -OutputDirectory (Join-Path $tempRoot 'mismatched-version-assets') -TagName $tagName -SourceCommit $sourceCommit `
            -DefaultBranch 'main' -WorkflowName $workflowName -RunId $runId -PassedEngines $testEngines
    } -Message 'A version-mismatched builder manifest must block release asset preparation.'

    $differentCommitManifest = $buildManifest | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    $differentCommitManifest.source.revision = ('0' * 40)
    $differentCommitInput = Copy-ReleaseInputVariant -VariantName 'different-source-commit' -Manifest $differentCommitManifest
    $differentCommitArguments = @{
        RepositoryRoot = $root
        ExecutablePath = $differentCommitInput.Executable
        BuildManifestPath = $differentCommitInput.Manifest
        OutputDirectory = (Join-Path $tempRoot 'different-source-commit-assets')
        TagName = $tagName
        SourceCommit = $sourceCommit
        DefaultBranch = 'main'
        WorkflowName = $workflowName
        RunId = $runId
        PassedEngines = $testEngines
    }
    Assert-ReleaseFailure -Action { New-InstallerReleaseAssets @differentCommitArguments } -Message 'A script payload built from a different commit must block release asset preparation.'

    $legacyIdentityManifest = $buildManifest | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    $legacyIdentityManifest.artifact.identity = 'legacy-iexpress-seed'
    $legacyIdentityInput = Copy-ReleaseInputVariant -VariantName 'legacy-artifact-identity' -Manifest $legacyIdentityManifest
    Assert-ReleaseFailure -Action {
        New-InstallerReleaseAssets -RepositoryRoot $root -ExecutablePath $legacyIdentityInput.Executable -BuildManifestPath $legacyIdentityInput.Manifest `
            -OutputDirectory (Join-Path $tempRoot 'legacy-artifact-assets') -TagName $tagName -SourceCommit $sourceCommit `
            -DefaultBranch 'main' -WorkflowName $workflowName -RunId $runId -PassedEngines $testEngines
    } -Message 'A legacy artifact identity must never be staged as the current release.'

    $signedManifest = $buildManifest | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    $signedManifest.artifact.authenticodeStatus = 'Valid'
    $signedInput = Copy-ReleaseInputVariant -VariantName 'signed-output' -Manifest $signedManifest
    Assert-ReleaseFailure -Action {
        New-InstallerReleaseAssets -RepositoryRoot $root -ExecutablePath $signedInput.Executable -BuildManifestPath $signedInput.Manifest `
            -OutputDirectory (Join-Path $tempRoot 'signed-output-assets') -TagName $tagName -SourceCommit $sourceCommit `
            -DefaultBranch 'main' -WorkflowName $workflowName -RunId $runId -PassedEngines $testEngines
    } -Message 'Signed output must be rejected before release publication.'

    $unexpectedSignature = Get-AuthenticodeSignature -FilePath $releaseAssets.ExecutablePath
    Assert-ReleaseCondition -Condition ([string]$unexpectedSignature.Status -ceq 'NotSigned' -and $null -eq $unexpectedSignature.SignerCertificate) -Message 'The fixture executable must be unsigned according to Authenticode inspection.'

    $apiCalls = New-Object 'System.Collections.Generic.List[object]'
    $forbiddenApiRequest = { throw 'A dry run must not call the release API.' }
    $dryRun = Publish-InstallerRelease `
        -Repository 'mytech-today-now/app_installer' -TagName $tagName -SourceCommit $sourceCommit -RemoteTagCommit $sourceCommit `
        -AssetsDirectory $outputDirectory -AssetPaths $releaseAssets.AssetPaths -ReleaseNotesPath $releaseAssets.ReleaseNotesPath `
        -DryRun -ApiRequest $forbiddenApiRequest
    Assert-ReleaseCondition -Condition ($dryRun.Status -ceq 'DryRun' -and $dryRun.ApiRequests -eq 0) -Message 'Dry-run mode must validate the asset set without making API requests.'

    $duplicateReleaseApi = {
        param($Method, $Uri, $Token, $Body, $FilePath)
        $apiCalls.Add([PSCustomObject]@{ Method = $Method; Uri = $Uri; Body = $Body; FilePath = $FilePath })
        return [PSCustomObject]@{ StatusCode = 200; Body = [PSCustomObject]@{ tag_name = $tagName; draft = $false } }
    }
    Assert-ReleaseFailure -Action {
        Publish-InstallerRelease -Repository 'mytech-today-now/app_installer' -TagName $tagName -SourceCommit $sourceCommit `
            -RemoteTagCommit $sourceCommit -AssetsDirectory $outputDirectory -AssetPaths $releaseAssets.AssetPaths `
            -ReleaseNotesPath $releaseAssets.ReleaseNotesPath -Token 'fixture-token' -ApiRequest $duplicateReleaseApi
    } -Message 'An existing release must be rejected without replacing it.'
    Assert-ReleaseCondition -Condition ($apiCalls.Count -eq 1 -and $apiCalls[0].Method -ceq 'GET') -Message 'Duplicate detection must stop before draft creation or asset upload.'

    $apiCalls.Clear()
    $script:uploadNumber = 0
    $successfulReleaseApi = {
        param($Method, $Uri, $Token, $Body, $FilePath)
        $apiCalls.Add([PSCustomObject]@{ Method = $Method; Uri = $Uri; Body = $Body; FilePath = $FilePath })
        if ($Method -ceq 'GET') { return [PSCustomObject]@{ StatusCode = 404; Body = $null } }
        if ($Method -ceq 'POST' -and $null -ne $Body) {
            return [PSCustomObject]@{ StatusCode = 201; Body = [PSCustomObject]@{ id = 57; tag_name = $tagName; draft = $true; upload_url = 'https://uploads.github.com/repos/mytech-today-now/app_installer/releases/57/assets{?name,label}' } }
        }
        if ($Method -ceq 'POST' -and $null -ne $FilePath) {
            $fileName = [System.IO.Path]::GetFileName($FilePath)
            return [PSCustomObject]@{ StatusCode = 201; Body = [PSCustomObject]@{ name = $fileName } }
        }
        if ($Method -ceq 'PATCH') { return [PSCustomObject]@{ StatusCode = 200; Body = [PSCustomObject]@{ tag_name = $tagName; draft = $false } } }
        throw ('Unexpected fixture API call: {0} {1}' -f $Method, $Uri)
    }
    $published = Publish-InstallerRelease `
        -Repository 'mytech-today-now/app_installer' -TagName $tagName -SourceCommit $sourceCommit -RemoteTagCommit $sourceCommit `
        -AssetsDirectory $outputDirectory -AssetPaths $releaseAssets.AssetPaths -ReleaseNotesPath $releaseAssets.ReleaseNotesPath `
        -Token 'fixture-token' -ApiRequest $successfulReleaseApi
    Assert-ReleaseCondition -Condition ($published.Status -ceq 'Published' -and $published.AssetNames.Count -eq 4) -Message 'A complete mock release sequence must publish exactly four allowlisted assets.'
    Assert-ReleaseCondition -Condition ($apiCalls[0].Method -ceq 'GET' -and $apiCalls[1].Method -ceq 'POST' -and $apiCalls[-1].Method -ceq 'PATCH') -Message 'The mock release sequence must check duplicates, create a draft, upload, then publish.'
    Assert-ReleaseCondition -Condition (@($apiCalls | Where-Object { $_.FilePath }).Count -eq 4) -Message 'The mock release must upload the exact four versioned release assets.'
    Assert-ReleaseCondition -Condition ([bool]$apiCalls[1].Body.draft -and [string]$apiCalls[1].Body.target_commitish -ceq $sourceCommit -and -not [bool]$apiCalls[-1].Body.draft) -Message 'The release must remain a draft until all assets upload, then publish at the tagged commit.'

    $apiCalls.Clear()
    $script:failedUploadNumber = 0
    $failingReleaseApi = {
        param($Method, $Uri, $Token, $Body, $FilePath)
        $apiCalls.Add([PSCustomObject]@{ Method = $Method; Uri = $Uri; Body = $Body; FilePath = $FilePath })
        if ($Method -ceq 'GET') { return [PSCustomObject]@{ StatusCode = 404; Body = $null } }
        if ($Method -ceq 'POST' -and $null -ne $Body) {
            return [PSCustomObject]@{ StatusCode = 201; Body = [PSCustomObject]@{ id = 58; tag_name = $tagName; draft = $true; upload_url = 'https://uploads.github.com/repos/mytech-today-now/app_installer/releases/58/assets{?name,label}' } }
        }
        if ($Method -ceq 'POST' -and $null -ne $FilePath) {
            $script:failedUploadNumber++
            if ($script:failedUploadNumber -eq 2) { return [PSCustomObject]@{ StatusCode = 422; Body = $null } }
            return [PSCustomObject]@{ StatusCode = 201; Body = [PSCustomObject]@{ name = [System.IO.Path]::GetFileName($FilePath) } }
        }
        if ($Method -ceq 'PATCH') { return [PSCustomObject]@{ StatusCode = 200; Body = [PSCustomObject]@{ tag_name = $tagName; draft = $false } } }
        throw ('Unexpected fixture API call: {0} {1}' -f $Method, $Uri)
    }
    Assert-ReleaseFailure -Action {
        Publish-InstallerRelease -Repository 'mytech-today-now/app_installer' -TagName $tagName -SourceCommit $sourceCommit `
            -RemoteTagCommit $sourceCommit -AssetsDirectory $outputDirectory -AssetPaths $releaseAssets.AssetPaths `
            -ReleaseNotesPath $releaseAssets.ReleaseNotesPath -Token 'fixture-token' -ApiRequest $failingReleaseApi
    } -Message 'A failed upload must block publication.'
    Assert-ReleaseCondition -Condition (@($apiCalls | Where-Object { $_.Method -ceq 'PATCH' }).Count -eq 0) -Message 'A failed upload must leave the draft unpublished.'

    $signingReferences = @(
        (Get-Content -LiteralPath $modulePath -Raw),
        (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\Publish-InstallerRelease.ps1') -Raw)
    ) -join "`n"
    Assert-ReleaseCondition -Condition ($signingReferences -notmatch '(?i)\b(?:signtool(?:\.exe)?|Set-AuthenticodeSignature|codesign|osslsigncode)\b') -Message 'Release tooling must not invoke a signing tool.'
    Write-Output ('[OK] Installer release asset tests passed: assertions={0}; assets=4; fixtureApi=no network; signed=false.' -f $script:AssertionCount)
}
finally {
    $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolvedRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
