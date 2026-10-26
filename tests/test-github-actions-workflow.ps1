#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$script:assertionCount = 0
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$workflowPath = Join-Path $repositoryRoot '.github\workflows\windows-build-compatibility.yml'
$releaseWorkflowPath = Join-Path $repositoryRoot '.github\workflows\versioned-unsigned-release.yml'
$suitePath = Join-Path $PSScriptRoot 'Invoke-CIRegressionSuite.ps1'
$failurePropagationTestPath = Join-Path $PSScriptRoot 'test-ci-regression-suite-failure.ps1'
$buildTestPath = Join-Path $PSScriptRoot 'test-executable-build.ps1'
$releaseAssetTestPath = Join-Path $PSScriptRoot 'test-installer-release-assets.ps1'
$buildConfigurationPath = Join-Path $repositoryRoot 'tools\installer-exe-build.json'
$compatibilityPath = Join-Path $repositoryRoot 'compatibility.json'
$releaseAssetPreparationPath = Join-Path $repositoryRoot 'tools\New-InstallerReleaseAssets.ps1'

function Assert-WorkflowCondition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) {
        throw $Message
    }
}

if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
    throw 'The GitHub Actions build and compatibility workflow is missing.'
}
$workflowText = Get-Content -LiteralPath $workflowPath -Raw -ErrorAction Stop
$releaseWorkflowText = Get-Content -LiteralPath $releaseWorkflowPath -Raw -ErrorAction Stop
$suiteText = Get-Content -LiteralPath $suitePath -Raw -ErrorAction Stop
$failurePropagationTestText = Get-Content -LiteralPath $failurePropagationTestPath -Raw -ErrorAction Stop
$monthlySchedulingTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-monthly-update-scheduling.ps1') -Raw -ErrorAction Stop
$monthlyResultsTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-monthly-update-results.ps1') -Raw -ErrorAction Stop
$packageManagerTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-package-manager-command-security.ps1') -Raw -ErrorAction Stop
$startupTrustTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-startup-helper-trust.ps1') -Raw -ErrorAction Stop
$ooTrustTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-ooshutup10-trust.ps1') -Raw -ErrorAction Stop
$runtimeEngineDiscoveryTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-runtime-engine-discovery-offline.ps1') -Raw -ErrorAction Stop
$startupEntrypointTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-startup-entrypoints-offline.ps1') -Raw -ErrorAction Stop
$cliWhatIfTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-cli-whatif.ps1') -Raw -ErrorAction Stop
$buildTestText = Get-Content -LiteralPath $buildTestPath -Raw -ErrorAction Stop
$releaseAssetTestText = Get-Content -LiteralPath $releaseAssetTestPath -Raw -ErrorAction Stop
$releaseModuleText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\InstallerRelease.psm1') -Raw -ErrorAction Stop
$releasePublisherText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\Publish-InstallerRelease.ps1') -Raw -ErrorAction Stop
$releaseAssetPreparationText = Get-Content -LiteralPath $releaseAssetPreparationPath -Raw -ErrorAction Stop
$buildConfiguration = Get-Content -LiteralPath $buildConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$compatibility = Get-Content -LiteralPath $compatibilityPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^  push:\r?\n    branches:\r?\n      - main$') -Message 'The workflow must run on pushes to main.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^  pull_request:\r?\n    branches:\r?\n      - main$') -Message 'The workflow must run on pull requests targeting main.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^  workflow_dispatch:$') -Message 'The workflow must support manual builds.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?ms)publish_artifact:\s*\r?\n\s+description:.*\r?\n\s+required: true\r?\n\s+default: false\r?\n\s+type: boolean') -Message 'Artifact publication must be an explicit manual opt-in that defaults off.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^permissions:\r?\n  contents: read$') -Message 'The workflow must grant only read access to repository contents.'
Assert-WorkflowCondition -Condition ($workflowText -match 'github\.event\.repository\.private == false') -Message 'The hosted job must skip private repositories to prevent unverified runner charges.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^\s+runs-on: windows-2025$') -Message 'The workflow must use the standard Windows Server 2025 hosted runner.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^\s+cancel-in-progress: true$') -Message 'The workflow must cancel superseded runs.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?ms)matrix:\s*\r?\n\s+engine:\s*\r?\n\s+- Desktop-5\.1\r?\n\s+- Core-7\.6\.7') -Message 'The workflow must include Windows PowerShell 5.1 and PowerShell Core 7.6.7.'
Assert-WorkflowCondition -Condition ($workflowText -match 'Build-InstallerExe\.ps1\s+-Confirm:\$false') -Message 'The workflow must invoke the repository-local executable build command without an interactive prompt.'
Assert-WorkflowCondition -Condition ($workflowText -match "(?s)Get-ChildItem.*?-Filter '\*\.exe\.build\.json'") -Message 'The workflow must discover builder manifests, not arbitrary executable files.'
Assert-WorkflowCondition -Condition ($workflowText -match 'manifest\.artifact\.identity' -and $workflowText -match 'manifest\.artifact\.fileName' -and $workflowText -match 'APP_INSTALLER_ARTIFACT_PATH') -Message 'The workflow must select and validate the executable named by the current builder manifest.'
Assert-WorkflowCondition -Condition ($workflowText -notmatch "(?i)Filter\s+'AppInstaller-\*-win-x64\.exe'") -Message 'The workflow must not select executables with a broad filename wildcard.'
Assert-WorkflowCondition -Condition ($suiteText -match 'test-syntax\.ps1') -Message 'The regression suite must include the repository syntax check.'
Assert-WorkflowCondition -Condition ($suiteText -match 'test-ci-regression-suite-failure\.ps1' -and $failurePropagationTestText -match '-InjectFailureForTest' -and $failurePropagationTestText -match 'probeExitCode -ne 31') -Message 'The normal suite must prove that an injected child failure propagates as nonzero.'
$requiredOfflineTests = @(
    'test-startup-helper-trust.ps1',
    'test-ooshutup10-trust.ps1',
    'test-package-manager-command-security.ps1',
    'test-monthly-update-scheduling.ps1',
    'test-monthly-update-results.ps1',
    'test-execution-policy-launchers.ps1',
    'test-startup-entrypoints-offline.ps1'
)
foreach ($testName in $requiredOfflineTests) {
    Assert-WorkflowCondition -Condition ($suiteText.Contains($testName)) -Message ('The CI regression suite must include the offline safety harness: {0}' -f $testName)
}
Assert-WorkflowCondition -Condition ($suiteText -match '\$testExitCode\s*-eq\s*77' -and $suiteText -match '\[SKIP\]' -and $suiteText -match '\$skippedTestCount\+\+') -Message 'A platform skip must be explicit and must not be counted as a passing test.'
Assert-WorkflowCondition -Condition ($monthlySchedulingTestText -match '\[SKIP\].*Windows CLI behavior' -and $monthlySchedulingTestText -match 'exit 77') -Message 'Monthly scheduling reports unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($monthlyResultsTestText -match '\[SKIP\].*Windows command resolution' -and $monthlyResultsTestText -match 'exit 77') -Message 'Monthly update result checks report unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($runtimeEngineDiscoveryTestText -match '\[SKIP\].*require Windows registry' -and $runtimeEngineDiscoveryTestText -match 'exit 77') -Message 'Runtime discovery reports unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($startupEntrypointTestText -match '\[SKIP\].*requires Windows Forms' -and $startupEntrypointTestText -match 'exit 77') -Message 'Startup entrypoint checks report unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($cliWhatIfTestText -match '\[SKIP\].*require Windows command resolution' -and $cliWhatIfTestText -match 'exit 77') -Message 'CLI WhatIf checks report unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($packageManagerTestText -match 'foreach \(\$name in @\(''winget'', ''brew'', ''sudo''\)\)' -and $packageManagerTestText.Contains('PACKAGE_MANAGER_CAPTURE_PATH') -and $packageManagerTestText.Contains("Manager = 'pacman'")) -Message 'Package command coverage routes each platform adapter through fake executables and captures every provider command.'
Assert-WorkflowCondition -Condition ($monthlySchedulingTestText.Contains('function global:schtasks.exe') -and $monthlySchedulingTestText.Contains('function global:winget') -and $monthlySchedulingTestText -match '\$environment\[''USERPROFILE''\]\s*=\s*\$Scenario\.UserProfile' -and $monthlySchedulingTestText -notmatch '\bRegister-ScheduledTask\b|\bUnregister-ScheduledTask\b') -Message 'Monthly scheduling uses fake scheduler/package commands and an isolated profile instead of real tasks.'
Assert-WorkflowCondition -Condition ($monthlySchedulingTestText.Contains('InstallerPayload.psm1') -and $monthlySchedulingTestText.Contains('payload-manifest.json') -and $monthlySchedulingTestText.Contains('Join-Path $checkoutRoot ''.git''')) -Message 'The scheduling fixture validates CLI startup as a source checkout with its payload guard dependencies present.'
Assert-WorkflowCondition -Condition ($monthlySchedulingTestText -match "New-Scenario -Name 'status' -Action 'Status' -InputText") -Message 'Interactive status coverage receives a quit response so it cannot hang the regression suite.'
Assert-WorkflowCondition -Condition ($monthlyResultsTestText.Contains('New-FakeWinget') -and $monthlyResultsTestText.Contains('winget.cmd') -and $monthlyResultsTestText.Contains('FAKE_WINGET_BIN')) -Message 'Monthly update results use only the fixture winget executable.'
Assert-WorkflowCondition -Condition ($startupTrustTestText -match 'Invoke-WebRequest' -and $startupTrustTestText -match 'Helper fallback path does not invoke a package manager') -Message 'Startup helper trust checks block network startup and package-manager fallback.'
Assert-WorkflowCondition -Condition ($ooTrustTestText.Contains('New-FakeDownloadScript') -and $ooTrustTestText.Contains('-DownloadScript $fakeDownload') -and $ooTrustTestText.Contains('-ExecutorScript')) -Message 'O&O trust coverage injects fake download bytes and child execution.'
Assert-WorkflowCondition -Condition ($startupEntrypointTestText.Contains('function global:Invoke-WebRequest') -and $startupEntrypointTestText.Contains('function global:Invoke-RestMethod') -and $startupEntrypointTestText.Contains('[''USERPROFILE''] = $UserProfile')) -Message 'Entrypoint tests block network calls and redirect user-profile writes into temporary roots.'
Assert-WorkflowCondition -Condition ($suiteText -match 'ci-intentional-failure\.ps1' -and $suiteText -match 'exit \$testExitCode') -Message 'The runner must execute only its fixed failure fixture in injection mode and preserve a failing exit code.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^\s+retention-days: 3$') -Message 'Uploaded artifacts must have a bounded three-day retention.'
Assert-WorkflowCondition -Condition ($workflowText -match '\$\{\{ env\.APP_INSTALLER_ARTIFACT_PATH \}\}' -and $workflowText -match '\$\{\{ env\.APP_INSTALLER_BUILD_MANIFEST_PATH \}\}') -Message 'Artifact publication must upload only the manifest-listed executable and its adjacent provenance.'
Assert-WorkflowCondition -Condition ($workflowText -notmatch 'AppInstaller-\*-win-x64\.exe') -Message 'Artifact publication must not include a broad executable filename wildcard.'
Assert-WorkflowCondition -Condition ($releaseAssetPreparationText -match 'artifact\.defaultOutputDirectory' -and $releaseAssetPreparationText -match 'artifact\.outputNamePattern' -and $releaseAssetPreparationText -match '\$buildManifestPath\s*=\s*\$executablePath\s*\+\s*''\.build\.json''') -Message 'Release preparation must use the configured versioned output path and adjacent build manifest.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^\s+compression-level: 0$') -Message 'The already-compressed executable artifact must not spend runner time on compression.'
Assert-WorkflowCondition -Condition ($workflowText -notmatch '(?i)\$\{\{\s*secrets\.') -Message 'The workflow must not reference repository or organization secrets.'
Assert-WorkflowCondition -Condition ($workflowText -notmatch '(?i)pull_request_target|self-hosted|signtool|Set-AuthenticodeSignature|codesign') -Message 'The workflow must not use privileged PR triggers, self-hosted runners, or signing.'

$actionReferences = [regex]::Matches($workflowText, '(?m)^\s*uses:\s*([^\s#]+)')
Assert-WorkflowCondition -Condition ($actionReferences.Count -eq 2) -Message 'Only checkout and artifact upload actions should be used.'
foreach ($actionReference in $actionReferences) {
    $value = $actionReference.Groups[1].Value
    Assert-WorkflowCondition -Condition ($value -match '^actions/(checkout|upload-artifact)@[0-9a-f]{40}$') -Message ('Every action must use an immutable full SHA from an official actions repository: {0}' -f $value)
}
Assert-WorkflowCondition -Condition ($workflowText.Contains('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1')) -Message 'Checkout must use the reviewed immutable release commit.'
Assert-WorkflowCondition -Condition ($workflowText.Contains('actions/upload-artifact@c2acdedd35a8824a1552c7137f8c18288c3ea469')) -Message 'Artifact upload must use the reviewed immutable release commit.'

Assert-WorkflowCondition -Condition (-not $suiteText.Contains('test-winget-bootstrap.ps1')) -Message 'The CI suite must not run the separate WinGet bootstrap workflow.'
Assert-WorkflowCondition -Condition ($suiteText.Contains('tests/test-executable-build.ps1') -and $suiteText.Contains('tests/test-executable-payload.ps1')) -Message 'PowerShell Core must run the executable build and payload regression tests.'
Assert-WorkflowCondition -Condition ($suiteText.Contains('test-compatibility-runtime-current-host.ps1') -and $suiteText.Contains('[UNAVAILABLE]')) -Message 'The suite must identify the Windows-client-only runtime test as unavailable on the Server runner.'

$regressionStepMatch = [regex]::Match($workflowText, '(?ms)^      - name: Run syntax and offline regression checks(?<body>.*?)(?=^      - name:|\z)')
$artifactStepIndex = $workflowText.IndexOf('      - name: Publish versioned unsigned artifact and provenance', [System.StringComparison]::Ordinal)
$regressionStepIndex = $workflowText.IndexOf('      - name: Run syntax and offline regression checks', [System.StringComparison]::Ordinal)
Assert-WorkflowCondition -Condition ($regressionStepMatch.Success -and $regressionStepMatch.Groups['body'].Value.Contains('Invoke-CIRegressionSuite.ps1') -and $regressionStepMatch.Groups['body'].Value.Contains('exit $LASTEXITCODE')) -Message 'The GitHub Actions step must return the regression suite exit code.'
Assert-WorkflowCondition -Condition ($regressionStepIndex -ge 0 -and $artifactStepIndex -gt $regressionStepIndex -and $workflowText -notmatch '(?i)continue-on-error:\s*true|if:\s*\$\{\{\s*always\(\)') -Message 'Artifact publication must remain after and gated by the regression step.'
Assert-WorkflowCondition -Condition (@($buildConfiguration.host.windowsBuilds | ForEach-Object { [int]$_ }) -contains 26100) -Message 'The pinned build-host contract must include Windows Server 2025 build 26100.'
Assert-WorkflowCondition -Condition (@($buildConfiguration.host.windowsBuilds | ForEach-Object { [int]$_ }) -contains 26300) -Message 'The pinned build-host contract must retain Windows 11 build 26300.'
$serverContract = @($compatibility.windowsClient.unsupportedFamilies | Where-Object { [string]$_.name -eq 'Windows Server' })
Assert-WorkflowCondition -Condition ($serverContract.Count -eq 1) -Message 'Allowing Windows Server as a build host must not add it to the App Installer runtime support matrix.'

Assert-WorkflowCondition -Condition ($workflowText -match '(?ms)^  workflow_call:\r?\n    inputs:\r?\n      validate_release_tag:\r?\n        description:.*?\r?\n        required: false\r?\n        default: false\r?\n        type: boolean') -Message 'The compatibility workflow must expose an opt-in release-tag validation input for reuse.'
Assert-WorkflowCondition -Condition ($workflowText -match 'matrix\.engine == ''Core-7\.6\.7'' && inputs\.validate_release_tag') -Message 'The reusable workflow must validate release tags before its pinned executable build.'
Assert-WorkflowCondition -Condition ($workflowText -match 'tools[\\/]Test-InstallerReleaseTag\.ps1') -Message 'The reusable workflow must use the shared release tag validator.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^      - name: Publish versioned unsigned artifact and provenance\r?\n        if: \$\{\{ matrix\.engine == ''Core-7\.6\.7'' && github\.event_name == ''workflow_dispatch'' && inputs\.publish_artifact \}\}') -Message 'Release workflow reuse must not enable the manual Actions artifact upload path.'

Assert-WorkflowCondition -Condition ($releaseWorkflowText -match '(?ms)^on:\r?\n  push:\r?\n    tags:\r?\n      - ''v\*''') -Message 'The release workflow must trigger only from version-style tag pushes.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match 'github\.ref_protected') -Message 'The release workflow must reject unprotected tags.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match 'github\.event\.repository\.default_branch') -Message 'The release workflow must use the repository event payload for its actual default branch.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match 'uses: \.\/\.github\/workflows\/windows-build-compatibility\.yml') -Message 'The release workflow must reuse the existing two-engine compatibility workflow.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match 'validate_release_tag: true') -Message 'The release workflow must enable tag-to-VERSION validation in the reusable matrix.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match '(?ms)^  publish_release:.*?needs:\r?\n      - validate_release_tag\r?\n      - compatibility') -Message 'Release publication must depend on tag validation and the complete compatibility workflow.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match "needs\.validate_release_tag\.result == 'success'.*needs\.compatibility\.result == 'success'") -Message 'The publisher must be gated on successful validation and compatibility results.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match '(?m)^permissions:\r?\n  contents: read$') -Message 'Release validation must default to read-only repository contents access.'
$publishJobMatch = [regex]::Match($releaseWorkflowText, '(?ms)^  publish_release:(?<body>.*?)(?=^  [a-z0-9_-]+:|\z)')
Assert-WorkflowCondition -Condition ($publishJobMatch.Success -and $publishJobMatch.Groups['body'].Value -match '(?m)^    permissions:\r?\n      contents: write$') -Message 'Only the final release publishing job may write repository contents.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -notmatch '(?i)actions/(upload-artifact|download-artifact)|workflow_run') -Message 'The release path must not use artifact storage or rely on a separate workflow run.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -notmatch '(?i)\$\{\{\s*secrets\.') -Message 'The release workflow must not require a repository-defined secret.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText.Contains('${{ github.token }}')) -Message 'Release publication must use the automatically provided workflow token.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -notmatch '(?i)git\s+tag|git\s+push|signtool|Set-AuthenticodeSignature|codesign') -Message 'The workflow must not create or push tags or sign the executable.'
$releaseActionReferences = [regex]::Matches($releaseWorkflowText, '(?m)^\s*uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40})')
Assert-WorkflowCondition -Condition ($releaseActionReferences.Count -eq 2) -Message 'The release workflow must use only its two pinned checkout actions.'
foreach ($actionReference in $releaseActionReferences) {
    Assert-WorkflowCondition -Condition ($actionReference.Groups[1].Value -ceq 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1') -Message 'Every third-party release action must use the verified immutable checkout commit.'
}
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match '(?m)^  compatibility:\r?\n    needs: validate_release_tag\r?\n    if:.*?\r?\n    uses: \.\/\.github\/workflows\/windows-build-compatibility\.yml') -Message 'The release matrix job must use the local reusable workflow after tag validation.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match 'Build-InstallerExe\.ps1' -and $releaseWorkflowText -match 'New-InstallerReleaseAssets\.ps1' -and $releaseWorkflowText -match 'Publish-InstallerRelease\.ps1') -Message 'The release must reuse the pinned builder and the shared asset and publication tooling.'
Assert-WorkflowCondition -Condition ($releaseModuleText -match 'outputNamePattern' -and $releaseModuleText -match 'artifact\.identity' -and $releaseModuleText -match '\.sha256' -and $releaseModuleText -match "authenticodeStatus = 'NotSigned'") -Message 'Release tooling must enforce the current artifact identity, versioned x64 name, digest, and unsigned status.'
Assert-WorkflowCondition -Condition ($releaseModuleText -match "'/releases/tags/'" -and $releasePublisherText -match 'RELEASE_REF_PROTECTED') -Message 'The publisher must check for duplicate releases and protected tags.'
Assert-WorkflowCondition -Condition ($buildTestText -match 'test-installer-release-assets\.ps1') -Message 'The clean executable fixture test must run the focused release asset simulation.'
Assert-WorkflowCondition -Condition ($releaseAssetTestText -match 'DryRun' -and $releaseAssetTestText -match 'failed upload must block publication' -and $releaseAssetTestText -match 'existing release must be rejected') -Message 'The focused release test must cover dry-run, duplicate release, and failed upload gates.'
$releaseSigningReferences = ($releaseWorkflowText + $releaseModuleText + $releasePublisherText) -match '(?i)\b(?:signtool(?:\.exe)?|Set-AuthenticodeSignature|codesign|osslsigncode)\b'
Assert-WorkflowCondition -Condition (-not $releaseSigningReferences) -Message 'No release workflow or publisher step may invoke a signing tool.'

Write-Output ('[OK] GitHub Actions workflow contract passed: assertions={0}; immutableActions={1}; engines=2; releaseGates=protected-tag+tests.' -f $script:assertionCount, $actionReferences.Count)
