#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$script:assertionCount = 0
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$workflowPath = Join-Path $repositoryRoot '.github\workflows\windows-build-compatibility.yml'
$releaseWorkflowPath = Join-Path $repositoryRoot '.github\workflows\versioned-unsigned-release.yml'
$suitePath = Join-Path $PSScriptRoot 'Invoke-CIRegressionSuite.ps1'
$inventoryPath = Join-Path $PSScriptRoot 'ci-regression-inventory.json'
$failurePropagationTestPath = Join-Path $PSScriptRoot 'test-ci-regression-suite-failure.ps1'
$buildTestPath = Join-Path $PSScriptRoot 'test-executable-build.ps1'
$releaseAssetTestPath = Join-Path $PSScriptRoot 'test-installer-release-assets.ps1'
$buildConfigurationPath = Join-Path $repositoryRoot 'tools\installer-exe-build.json'
$compatibilityPath = Join-Path $repositoryRoot 'compatibility.json'
$releaseAssetPreparationPath = Join-Path $repositoryRoot 'tools\New-InstallerReleaseAssets.ps1'
$clientGuiChecklistPath = Join-Path $repositoryRoot 'WINDOWS_CLIENT_GUI_RELEASE_CHECKLIST.md'
$clientGuiEvidencePath = Join-Path $repositoryRoot 'WINDOWS_CLIENT_GUI_RELEASE_EVIDENCE.json'
$clientGuiEvidenceModulePath = Join-Path $repositoryRoot 'modules\InstallerClientGuiReleaseEvidence.psm1'
$releaseProtectionVerificationPath = Join-Path $repositoryRoot 'RELEASE_PROTECTION_VERIFICATION.md'
$releaseProtectionVerificationRecordPath = Join-Path $repositoryRoot 'RELEASE_PROTECTION_VERIFICATION.json'
$releaseProtectionReadinessModulePath = Join-Path $repositoryRoot 'modules\InstallerReleaseProtectionReadiness.psm1'

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

function Get-WorkflowInventoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InventoryTests,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $matches = @($InventoryTests | Where-Object { [System.IO.Path]::GetFileName([string]$_.path) -ceq $FileName })
    if ($matches.Count -ne 1) {
        throw ('Expected exactly one CI inventory entry for {0}; found {1}.' -f $FileName, $matches.Count)
    }

    return $matches[0]
}

function Assert-WorkflowInventoryDisposition {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InventoryTests,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedStatus
    )

    $entry = Get-WorkflowInventoryEntry -InventoryTests $InventoryTests -FileName $FileName
    $engineProperty = $entry.engines.PSObject.Properties[$Engine]
    Assert-WorkflowCondition -Condition ($null -ne $engineProperty -and [string]$engineProperty.Value.status -ceq $ExpectedStatus) -Message ('{0} has {1} status for {2} in the central runner inventory.' -f $FileName, $ExpectedStatus, $Engine)
}

if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
    throw 'The GitHub Actions build and compatibility workflow is missing.'
}
$inventory = Get-Content -LiteralPath $inventoryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$inventoryTests = @($inventory.tests)
$workflowText = Get-Content -LiteralPath $workflowPath -Raw -ErrorAction Stop
$releaseWorkflowText = Get-Content -LiteralPath $releaseWorkflowPath -Raw -ErrorAction Stop
$suiteText = Get-Content -LiteralPath $suitePath -Raw -ErrorAction Stop
$failurePropagationTestText = Get-Content -LiteralPath $failurePropagationTestPath -Raw -ErrorAction Stop
$bootstrapTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-winget-bootstrap.ps1') -Raw -ErrorAction Stop
$monthlySchedulingTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-monthly-update-scheduling.ps1') -Raw -ErrorAction Stop
$monthlyResultsTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-monthly-update-results.ps1') -Raw -ErrorAction Stop
$packageManagerTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-package-manager-command-security.ps1') -Raw -ErrorAction Stop
$nativeBoundaryTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-native-cli-boundaries.ps1') -Raw -ErrorAction Stop
$startupTrustTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-startup-helper-trust.ps1') -Raw -ErrorAction Stop
$ooTrustTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-ooshutup10-trust.ps1') -Raw -ErrorAction Stop
$runtimeEngineDiscoveryTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-runtime-engine-discovery-offline.ps1') -Raw -ErrorAction Stop
$startupEntrypointTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-startup-entrypoints-offline.ps1') -Raw -ErrorAction Stop
$cliWhatIfTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-cli-whatif.ps1') -Raw -ErrorAction Stop
$buildTestText = Get-Content -LiteralPath $buildTestPath -Raw -ErrorAction Stop
$releaseAssetTestText = Get-Content -LiteralPath $releaseAssetTestPath -Raw -ErrorAction Stop
$buildScriptText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\Build-InstallerExe.ps1') -Raw -ErrorAction Stop
$releaseModuleText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\InstallerRelease.psm1') -Raw -ErrorAction Stop
$releasePublisherText = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools\Publish-InstallerRelease.ps1') -Raw -ErrorAction Stop
$releaseAssetPreparationText = Get-Content -LiteralPath $releaseAssetPreparationPath -Raw -ErrorAction Stop
$clientGuiChecklistText = Get-Content -LiteralPath $clientGuiChecklistPath -Raw -ErrorAction Stop
$clientGuiEvidenceText = Get-Content -LiteralPath $clientGuiEvidencePath -Raw -ErrorAction Stop
$clientGuiEvidence = $clientGuiEvidenceText | ConvertFrom-Json -ErrorAction Stop
$clientGuiEvidenceModuleText = Get-Content -LiteralPath $clientGuiEvidenceModulePath -Raw -ErrorAction Stop
$clientGuiEvidenceTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-windows-client-gui-release-evidence.ps1') -Raw -ErrorAction Stop
$releaseProtectionVerificationText = Get-Content -LiteralPath $releaseProtectionVerificationPath -Raw -ErrorAction Stop
$releaseProtectionVerificationRecordText = Get-Content -LiteralPath $releaseProtectionVerificationRecordPath -Raw -ErrorAction Stop
$releaseProtectionVerificationRecord = $releaseProtectionVerificationRecordText | ConvertFrom-Json -ErrorAction Stop
$releaseProtectionReadinessModuleText = Get-Content -LiteralPath $releaseProtectionReadinessModulePath -Raw -ErrorAction Stop
$releaseProtectionReadinessTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-release-protection-readiness.ps1') -Raw -ErrorAction Stop
$clientRuntimeTestText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-compatibility-runtime-current-host.ps1') -Raw -ErrorAction Stop
$buildConfiguration = Get-Content -LiteralPath $buildConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$compatibility = Get-Content -LiteralPath $compatibilityPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$coreVersion = [string]$compatibility.engines.powerShellCore.version

Assert-WorkflowCondition -Condition ($workflowText.Contains("- Core-$coreVersion") -and $workflowText.Contains("Confirm pinned PowerShell Core $coreVersion") -and $workflowText.Contains("`$actualVersion -cne '$coreVersion'") -and $workflowText.Contains("[UNAVAILABLE] PowerShell Core $coreVersion is required") -and $workflowText -notmatch '(?i)actions/setup-powershell|Install-CompatiblePowerShell\.ps1') -Message 'The Windows Core job follows the exact contract pin and fails closed without provisioning a different runner runtime.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText.Contains("`$actualPowerShell -cne '$coreVersion'") -and $releaseWorkflowText.Contains("Core-$coreVersion")) -Message 'Release packaging requires the same exact PowerShell Core version as compatibility.json.'

Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^  push:\r?\n    branches:\r?\n      - main$') -Message 'The workflow must run on pushes to main.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^  pull_request:\r?\n    branches:\r?\n      - main$') -Message 'The workflow must run on pull requests targeting main.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^  workflow_dispatch:$') -Message 'The workflow must support manual builds.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?ms)publish_artifact:\s*\r?\n\s+description:.*\r?\n\s+required: true\r?\n\s+default: false\r?\n\s+type: boolean') -Message 'Artifact publication must be an explicit manual opt-in that defaults off.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^permissions:\r?\n  contents: read$') -Message 'The workflow must grant only read access to repository contents.'
Assert-WorkflowCondition -Condition ($workflowText -match 'github\.event\.repository\.private == false') -Message 'The hosted job must skip private repositories to prevent unverified runner charges.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^\s+runs-on: windows-2025$') -Message 'The workflow must use the standard Windows Server 2025 hosted runner.'
Assert-WorkflowCondition -Condition ($workflowText.Contains('ProductType -ne 3') -and $workflowText.Contains('build 26100, product type 3')) -Message 'The Windows build job identifies its host as Server 2025 and cannot classify it as a supported client.'
Assert-WorkflowCondition -Condition ($workflowText.Contains('SERVER_HOST_OUTCOME: ${{ steps.server_host.outcome }}') -and $workflowText.Contains('OFFLINE_REGRESSION_OUTCOME: ${{ steps.offline_regressions.outcome }}') -and $workflowText.Contains('Supported Windows client GUI capability/startup: `NOT RUN`') -and $workflowText.Contains('Server build success and Server engine results are not client GUI validation')) -Message 'The workflow summary reports Server, engine/offline, and client GUI evidence separately and marks Server client GUI validation NOT RUN.'
Assert-WorkflowCondition -Condition ($clientRuntimeTestText.Contains('$hostInfo.ProductType -ne ''WinNT''') -and $clientRuntimeTestText.Contains('cannot count as client GUI validation') -and $startupEntrypointTestText.Contains('cannot count as client validation') -and $startupEntrypointTestText.Contains('$hostInfo.ProductType -ne ''WinNT''')) -Message 'Both client-only runtime and GUI startup tests reject Server hosts as client evidence.'
Assert-WorkflowCondition -Condition ($clientGuiChecklistText.Contains('Windows 11 25H2') -and $clientGuiChecklistText.Contains('Windows 11 26H2') -and $clientGuiChecklistText.Contains('Windows PowerShell 5.1') -and $clientGuiChecklistText.Contains('PowerShell Core 7.6.9') -and $clientGuiChecklistText.Contains('System.Windows.Forms') -and $clientGuiChecklistText.Contains('System.Drawing') -and $clientGuiChecklistText.Contains('System.Web') -and $clientGuiChecklistText.Contains('GUI startup result')) -Message 'The client release checklist captures the supported host, both exact engines, required assemblies, and GUI startup result.'
Assert-WorkflowCondition -Condition ([int]$clientGuiEvidence.schemaVersion -eq 1 -and $clientGuiEvidence.records.Count -eq 1 -and [string]$clientGuiEvidence.records[0].sourceRevision -ceq 'NOT RUN' -and [string]$clientGuiEvidence.records[0].engines.'Desktop-5.1'.capabilityResult -ceq 'NOT RUN' -and [string]$clientGuiEvidence.records[0].engines.'Core-7.6.9'.isolatedStartupResult -ceq 'NOT RUN') -Message 'The checked-in client evidence template keeps both engine rows NOT RUN until revision-bound results are recorded.'
Assert-WorkflowCondition -Condition ($clientGuiChecklistText.Contains('WINDOWS_CLIENT_GUI_RELEASE_EVIDENCE.json') -and $clientGuiChecklistText.Contains('sourceRevision must equal the commit that will receive the release tag') -and $clientGuiChecklistText.Contains('committed separately on the default branch')) -Message 'The checklist documents the manual default-branch evidence path and exact release-revision binding.'
Assert-WorkflowCondition -Condition ($clientGuiEvidenceModuleText.Contains('consumerEndOfSupport') -and $clientGuiEvidenceModuleText.Contains('minimumRelease') -and $clientGuiEvidenceModuleText.Contains('runtimeFamily') -and $clientGuiEvidenceModuleText.Contains('isolatedStartupResult') -and $clientGuiEvidenceModuleText.Contains('Server evidence is rejected')) -Message 'The release evidence validator enforces current Windows servicing, GUI runtime, client host, and isolated startup requirements.'
Assert-WorkflowCondition -Condition ($clientGuiEvidenceTestText.Contains('wrong-host') -and $clientGuiEvidenceTestText.Contains('wrong-engine') -and $clientGuiEvidenceTestText.Contains('stale-revision') -and $clientGuiEvidenceTestText.Contains('expired-release') -and $clientGuiEvidenceTestText.Contains('NOT RUN')) -Message 'The client evidence fixture test covers invalid hosts, engines, stale revisions, expired releases, and NOT RUN results.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^\s+cancel-in-progress: true$') -Message 'The workflow must cancel superseded runs.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?ms)matrix:\s*\r?\n\s+engine:\s*\r?\n\s+- Desktop-5\.1\r?\n\s+- Core-7\.6\.9') -Message 'The workflow must include Windows PowerShell 5.1 and PowerShell Core 7.6.9.'
Assert-WorkflowCondition -Condition ($workflowText -match 'Build-InstallerExe\.ps1\s+-Confirm:\$false') -Message 'The workflow must invoke the repository-local executable build command without an interactive prompt.'
Assert-WorkflowCondition -Condition ($workflowText -match "(?s)Get-ChildItem.*?-Filter '\*\.exe\.build\.json'") -Message 'The workflow must discover builder manifests, not arbitrary executable files.'
Assert-WorkflowCondition -Condition ($workflowText -match 'manifest\.artifact\.identity' -and $workflowText -match 'manifest\.artifact\.fileName' -and $workflowText -match 'APP_INSTALLER_ARTIFACT_PATH') -Message 'The workflow must select and validate the executable named by the current builder manifest.'
Assert-WorkflowCondition -Condition ($workflowText -notmatch "(?i)Filter\s+'AppInstaller-\*-win-x64\.exe'") -Message 'The workflow must not select executables with a broad filename wildcard.'
Assert-WorkflowCondition -Condition ($suiteText -match 'test-syntax\.ps1') -Message 'The regression suite must include the repository syntax check.'
Assert-WorkflowCondition -Condition ($suiteText.Contains('ci-regression-inventory.json') -and $suiteText.Contains('$entry.engines.PSObject.Properties[$Engine]')) -Message 'The central runner must select tests from the explicit per-engine inventory.'
Assert-WorkflowCondition -Condition ($failurePropagationTestText -match '-InjectFailureForTest' -and $failurePropagationTestText -match 'probeExitCode -ne 31') -Message 'The included failure-propagation test must verify that an injected child failure exits nonzero.'
$failureEntry = Get-WorkflowInventoryEntry -InventoryTests $inventoryTests -FileName 'test-ci-regression-suite-failure.ps1'
foreach ($engine in @('Desktop-5.1', 'Core-7.6.9')) {
    Assert-WorkflowCondition -Condition ([string]$failureEntry.engines.PSObject.Properties[$engine].Value.status -ceq 'included') -Message ('Failure propagation is included for {0}.' -f $engine)
}
$requiredOfflineTests = @(
    'test-ci-regression-inventory.ps1',
    'test-compatibility-review-freshness.ps1',
    'test-belarc-installer-trust.ps1',
    'test-cli-runtime-handoff.ps1',
    'test-custom-app-script-results.ps1',
    'test-executable-install-lifecycle.ps1',
    'test-gui-queue-state.ps1',
    'test-gui-startup-capability.ps1',
    'test-install-bat-elevation.ps1',
    'test-package-dependency-outcomes.ps1',
    'test-remote-helper-trust.ps1',
    'test-update-scan-status.ps1',
    'test-winget-bootstrap.ps1',
    'test-startup-helper-trust.ps1',
    'test-ooshutup10-trust.ps1',
    'test-package-manager-command-security.ps1',
    'test-monthly-update-scheduling.ps1',
    'test-monthly-update-results.ps1',
    'test-execution-policy-launchers.ps1',
    'test-runtime-engine-discovery-offline.ps1',
    'test-windows-client-gui-release-evidence.ps1',
    'test-release-protection-readiness.ps1'
)
foreach ($testName in $requiredOfflineTests) {
    foreach ($engine in @('Desktop-5.1', 'Core-7.6.9')) {
        Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName $testName -Engine $engine -ExpectedStatus 'included'
    }
}
Assert-WorkflowCondition -Condition ($suiteText -match '\$testExitCode\s*-eq\s*77' -and $suiteText -match '\[SKIP\]' -and $suiteText -match '\$skippedTestCount\+\+') -Message 'A platform skip must be explicit and must not be counted as a passing test.'
Assert-WorkflowCondition -Condition ($monthlySchedulingTestText -match '\[SKIP\].*Windows CLI behavior' -and $monthlySchedulingTestText -match 'exit 77') -Message 'Monthly scheduling reports unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($monthlyResultsTestText -match '\[SKIP\].*Windows command resolution' -and $monthlyResultsTestText -match 'exit 77') -Message 'Monthly update result checks report unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($runtimeEngineDiscoveryTestText -match '\[SKIP\].*require Windows registry' -and $runtimeEngineDiscoveryTestText -match 'exit 77') -Message 'Runtime discovery reports unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($startupEntrypointTestText -match '\[UNAVAILABLE\].*supported Windows client' -and $startupEntrypointTestText -match 'exit 77') -Message 'Startup entrypoint checks report unsupported hosts as unavailable with the suite exit code.'
Assert-WorkflowCondition -Condition ($cliWhatIfTestText -match '\[SKIP\].*require Windows command resolution' -and $cliWhatIfTestText -match 'exit 77') -Message 'CLI WhatIf checks report unsupported platforms with the suite skip exit code.'
Assert-WorkflowCondition -Condition ($packageManagerTestText -match 'foreach \(\$name in @\(''winget'', ''brew'', ''sudo''\)\)' -and $packageManagerTestText.Contains('PACKAGE_MANAGER_CAPTURE_PATH') -and $packageManagerTestText.Contains("Manager = 'pacman'")) -Message 'Package command coverage routes each platform adapter through fake executables and captures every provider command.'
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-native-cli-boundaries.ps1' -Engine 'Desktop-5.1' -ExpectedStatus 'skipped'
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-native-cli-boundaries.ps1' -Engine 'Core-7.6.9' -ExpectedStatus 'skipped'
Assert-WorkflowCondition -Condition ($nativeBoundaryTestText.Contains("#!/bin/sh") -and $nativeBoundaryTestText.Contains("'apt', 'apt-get', 'brew', 'dnf', 'pacman', 'snap', 'sudo', 'winget', 'pwsh'") -and $nativeBoundaryTestText.Contains('$env:PATH = $fakeManagerRoot') -and $nativeBoundaryTestText.Contains('AppInstallerCorePath') -and $nativeBoundaryTestText.Contains('Invoke-PackageManagerProcess') -and $nativeBoundaryTestText.Contains('Install-Application -App $app -WhatIf') -and $nativeBoundaryTestText.Contains('captured-arguments.json') -and $nativeBoundaryTestText.Contains('fakePwshPath.StartsWith($fakeManagerRoot') -and $nativeBoundaryTestText.Contains('& bash $launcherPath') -and $nativeBoundaryTestText.Contains('install.sh forwards native argv')) -Message 'Native CLI checks capture package-manager and install.sh argv through temporary executable stubs, preserve WhatIf, and avoid provider execution.'
Assert-WorkflowCondition -Condition ($nativeBoundaryTestText -notmatch '(?im)^\s*(?:&\s*)?(?:apt(?:-get)?|brew|dnf|pacman|snap|sudo)\s+(?:install|upgrade|remove|uninstall)\b') -Message 'The native boundary test contains no direct package-manager install or removal command.'
$nativeLinuxMatch = [regex]::Match($workflowText, '(?ms)^  native-cli-linux:(?<body>.*?)(?=^  [a-z0-9_-]+:|\z)')
$nativeMacMatch = [regex]::Match($workflowText, '(?ms)^  native-cli-macos:(?<body>.*?)(?=^  [a-z0-9_-]+:|\z)')
$requiredCliGateMatch = [regex]::Match($workflowText, '(?ms)^  required-shared-cli-compatibility:(?<body>.*?)(?=^  [a-z0-9_-]+:|\z)')
Assert-WorkflowCondition -Condition ($nativeLinuxMatch.Success -and $nativeLinuxMatch.Groups['body'].Value -match '(?m)^    runs-on: ubuntu-24\.04$' -and $nativeLinuxMatch.Groups['body'].Value.Contains('-ExpectedPlatform Linux')) -Message 'A native Linux job runs on ubuntu-24.04 and asserts the detected Linux host.'
Assert-WorkflowCondition -Condition ($nativeMacMatch.Success -and $nativeMacMatch.Groups['body'].Value -match '(?m)^    runs-on: macos-15$' -and $nativeMacMatch.Groups['body'].Value.Contains('-ExpectedPlatform macOS')) -Message 'A native macOS job runs on macos-15 and asserts the detected macOS host.'
foreach ($nativeJobBody in @($nativeLinuxMatch.Groups['body'].Value, $nativeMacMatch.Groups['body'].Value)) {
    foreach ($nativeCheck in @('test-syntax.ps1', 'test-compatibility-contract.ps1', 'test-compatibility-review-freshness.ps1', 'test-package-manager-command-security.ps1', 'test-native-cli-boundaries.ps1')) {
        Assert-WorkflowCondition -Condition ($nativeJobBody.Contains($nativeCheck)) -Message ("Native jobs run the required offline check: {0}" -f $nativeCheck)
    }
    Assert-WorkflowCondition -Condition ($nativeJobBody.Contains('supported_version: ${{ steps.runtime.outputs.supported_version }}') -and $nativeJobBody.Contains('pwsh_version: ${{ steps.runtime.outputs.version }}') -and $nativeJobBody.Contains('no alternate engine will be installed')) -Message 'Native jobs expose the preinstalled PowerShell version and report missing runtimes explicitly.'
    Assert-WorkflowCondition -Condition ($nativeJobBody.Contains('::warning title=PowerShell version mismatch::') -and $nativeJobBody.Contains('compatibility.json')) -Message 'Native jobs report runner-version mismatches against compatibility.json without substituting a runtime.'
    Assert-WorkflowCondition -Condition ($nativeJobBody -notmatch '(?im)^\s*(?:sudo\s+)?(?:apt(?:-get)?|brew|dnf|pacman|snap)\s+(?:install|upgrade|remove|uninstall)\b') -Message 'Native workflow steps do not call live package-manager commands.'
}
Assert-WorkflowCondition -Condition ($requiredCliGateMatch.Success -and $requiredCliGateMatch.Groups['body'].Value -match '(?m)^    name: Required shared CLI compatibility$' -and $requiredCliGateMatch.Groups['body'].Value -match '(?ms)^    needs:\r?\n      - windows-build-compatibility\r?\n      - native-cli-linux\r?\n      - native-cli-macos' -and $requiredCliGateMatch.Groups['body'].Value.Contains('LINUX_RESULT') -and $requiredCliGateMatch.Groups['body'].Value.Contains('MACOS_RESULT') -and $requiredCliGateMatch.Groups['body'].Value.Contains('Native Linux compatibility unavailable') -and $requiredCliGateMatch.Groups['body'].Value.Contains('Native macOS compatibility unavailable')) -Message 'The named required compatibility gate depends on Windows, Linux, and macOS results and rejects unsupported native PowerShell versions.'
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
Assert-WorkflowCondition -Condition ($actionReferences.Count -eq 4) -Message 'Only pinned checkout and opt-in artifact upload actions should be used across Windows, Linux, and macOS jobs.'
foreach ($actionReference in $actionReferences) {
    $value = $actionReference.Groups[1].Value
    Assert-WorkflowCondition -Condition ($value -match '^actions/(checkout|upload-artifact)@[0-9a-f]{40}$') -Message ('Every action must use an immutable full SHA from an official actions repository: {0}' -f $value)
}
Assert-WorkflowCondition -Condition ($workflowText.Contains('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1')) -Message 'Checkout must use the reviewed immutable release commit.'
Assert-WorkflowCondition -Condition ($workflowText.Contains('actions/upload-artifact@c2acdedd35a8824a1552c7137f8c18288c3ea469')) -Message 'Artifact upload must use the reviewed immutable release commit.'

Assert-WorkflowCondition -Condition ($bootstrapTestText.Contains('-GetReleaseMetadata $releaseProvider') -and $bootstrapTestText.Contains('-DownloadFile $downloadProvider') -and $bootstrapTestText.Contains('-InstallPackage $packageInstaller')) -Message 'The included WinGet bootstrap test must inject fake release, download, and package-install boundaries.'
foreach ($engine in @('Desktop-5.1', 'Core-7.6.9')) {
    Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-winget-bootstrap.ps1' -Engine $engine -ExpectedStatus 'included'
    Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-instruction-html-security.ps1' -Engine $engine -ExpectedStatus 'included'
    Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-compatibility-runtime-current-host.ps1' -Engine $engine -ExpectedStatus 'unavailable'
    Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-startup-entrypoints-offline.ps1' -Engine $engine -ExpectedStatus 'unavailable'
}
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-executable-build.ps1' -Engine 'Desktop-5.1' -ExpectedStatus 'skipped'
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-executable-payload.ps1' -Engine 'Desktop-5.1' -ExpectedStatus 'skipped'
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-installer-release-assets.ps1' -Engine 'Desktop-5.1' -ExpectedStatus 'skipped'
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-executable-build.ps1' -Engine 'Core-7.6.9' -ExpectedStatus 'included'
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-executable-payload.ps1' -Engine 'Core-7.6.9' -ExpectedStatus 'included'
Assert-WorkflowInventoryDisposition -InventoryTests $inventoryTests -FileName 'test-installer-release-assets.ps1' -Engine 'Core-7.6.9' -ExpectedStatus 'included'

$regressionStepMatch = [regex]::Match($workflowText, '(?ms)^      - name: Run syntax and offline regression checks(?<body>.*?)(?=^      - name:|\z)')
$artifactStepIndex = $workflowText.IndexOf('      - name: Publish versioned unsigned artifact and provenance', [System.StringComparison]::Ordinal)
$regressionStepIndex = $workflowText.IndexOf('      - name: Run syntax and offline regression checks', [System.StringComparison]::Ordinal)
Assert-WorkflowCondition -Condition ($regressionStepMatch.Success -and $regressionStepMatch.Groups['body'].Value.Contains('APP_INSTALLER_CI_ENGINE: ${{ matrix.engine }}') -and $regressionStepMatch.Groups['body'].Value.Contains('Invoke-CIRegressionSuite.ps1') -and $regressionStepMatch.Groups['body'].Value.Contains('-Engine $env:APP_INSTALLER_CI_ENGINE') -and $regressionStepMatch.Groups['body'].Value.Contains('exit $LASTEXITCODE')) -Message 'The GitHub Actions step must pass the selected matrix engine and return the regression suite exit code.'
Assert-WorkflowCondition -Condition ($regressionStepIndex -ge 0 -and $artifactStepIndex -gt $regressionStepIndex -and $workflowText -match '(?m)^      - name: Publish versioned unsigned artifact and provenance\r?\n        if: \$\{\{ matrix\.engine == ''Core-7\.6\.9'' && github\.event_name == ''workflow_dispatch'' && inputs\.publish_artifact \}\}') -Message 'Artifact publication must remain after the regression step and gated by its explicit manual opt-in.'
Assert-WorkflowCondition -Condition (@($buildConfiguration.host.windowsBuilds | ForEach-Object { [int]$_ }) -contains 26100) -Message 'The pinned build-host contract must include Windows Server 2025 build 26100.'
Assert-WorkflowCondition -Condition (@($buildConfiguration.host.windowsBuilds | ForEach-Object { [int]$_ }) -contains 26300) -Message 'The pinned build-host contract must retain Windows 11 build 26300.'
$serverContract = @($compatibility.windowsClient.unsupportedFamilies | Where-Object { [string]$_.name -eq 'Windows Server' })
Assert-WorkflowCondition -Condition ($serverContract.Count -eq 1) -Message 'Allowing Windows Server as a build host must not add it to the App Installer runtime support matrix.'

Assert-WorkflowCondition -Condition ($workflowText -match '(?ms)^  workflow_call:\r?\n    inputs:\r?\n      validate_release_tag:\r?\n        description:.*?\r?\n        required: false\r?\n        default: false\r?\n        type: boolean') -Message 'The compatibility workflow must expose an opt-in release-tag validation input for reuse.'
Assert-WorkflowCondition -Condition ($workflowText -match 'matrix\.engine == ''Core-7\.6\.9'' && inputs\.validate_release_tag') -Message 'The reusable workflow must validate release tags before its pinned executable build.'
Assert-WorkflowCondition -Condition ($workflowText -match 'tools[\\/]Test-InstallerReleaseTag\.ps1') -Message 'The reusable workflow must use the shared release tag validator.'
Assert-WorkflowCondition -Condition ($workflowText -match '(?m)^      - name: Publish versioned unsigned artifact and provenance\r?\n        if: \$\{\{ matrix\.engine == ''Core-7\.6\.9'' && github\.event_name == ''workflow_dispatch'' && inputs\.publish_artifact \}\}') -Message 'Release workflow reuse must not enable the manual Actions artifact upload path.'

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
$releaseJobsSectionMatch = [regex]::Match($releaseWorkflowText, '(?ms)^jobs:\r?\n(?<body>.*)\z')
$releaseJobMatches = [regex]::Matches([string]$releaseJobsSectionMatch.Groups['body'].Value, '(?ms)^  (?<name>[a-z][a-z0-9_-]*):\r?\n(?<body>.*?)(?=^  [a-z][a-z0-9_-]*:\r?\n|\z)')
$releaseJobBodies = @{}
foreach ($releaseJob in $releaseJobMatches) {
    $releaseJobBodies[$releaseJob.Groups['name'].Value] = $releaseJob.Groups['body'].Value
}
Assert-WorkflowCondition -Condition ($releaseJobsSectionMatch.Success -and $releaseJobMatches.Count -eq 5 -and $releaseJobBodies.ContainsKey('validate_release_tag') -and $releaseJobBodies.ContainsKey('compatibility') -and $releaseJobBodies.ContainsKey('supported_client_gui_evidence') -and $releaseJobBodies.ContainsKey('release_protection_readiness') -and $releaseJobBodies.ContainsKey('publish_release')) -Message 'The release dependency contract covers exactly the five declared release jobs.'
$tagValidationJobBody = [string]$releaseJobBodies['validate_release_tag']
$compatibilityJobBody = [string]$releaseJobBodies['compatibility']
$clientEvidenceJobBody = [string]$releaseJobBodies['supported_client_gui_evidence']
$protectionReadinessJobBody = [string]$releaseJobBodies['release_protection_readiness']
$releasePublisherJobBody = [string]$releaseJobBodies['publish_release']
$validationNeedsCount = [regex]::Matches($tagValidationJobBody, '(?m)^    needs:').Count
$compatibilityNeedsCount = [regex]::Matches($compatibilityJobBody, '(?m)^    needs:').Count
$clientEvidenceNeedsCount = [regex]::Matches($clientEvidenceJobBody, '(?m)^    needs:').Count
$protectionReadinessNeedsCount = [regex]::Matches($protectionReadinessJobBody, '(?m)^    needs:').Count
$publisherNeedsCount = [regex]::Matches($releasePublisherJobBody, '(?m)^    needs:').Count
Assert-WorkflowCondition -Condition ($validationNeedsCount -eq 0 -and $compatibilityNeedsCount -eq 1 -and $compatibilityJobBody -match '(?m)^    needs: validate_release_tag$' -and $clientEvidenceNeedsCount -eq 1 -and $clientEvidenceJobBody -match '(?m)^    needs: validate_release_tag$' -and $protectionReadinessNeedsCount -eq 1 -and $protectionReadinessJobBody -match '(?m)^    needs: validate_release_tag$' -and $publisherNeedsCount -eq 1 -and $releasePublisherJobBody -match '(?ms)^    needs:\r?\n      - validate_release_tag\r?\n      - compatibility\r?\n      - supported_client_gui_evidence\r?\n      - release_protection_readiness$' -and $releasePublisherJobBody -match 'needs\.supported_client_gui_evidence\.result == ''success''' -and $releasePublisherJobBody -match 'needs\.release_protection_readiness\.result == ''success''') -Message 'Release publication depends on tag validation, compatibility, supported client GUI evidence, and remote protection readiness.'
Assert-WorkflowCondition -Condition ($clientEvidenceJobBody -match '(?m)^    runs-on: windows-2025$' -and $clientEvidenceJobBody.Contains('github.event.repository.default_branch') -and $clientEvidenceJobBody.Contains('github.sha') -and $clientEvidenceJobBody.Contains('WINDOWS_CLIENT_GUI_RELEASE_EVIDENCE.json') -and $clientEvidenceJobBody.Contains('Test-InstallerClientGuiReleaseEvidence') -and $clientEvidenceJobBody.Contains('did not run client GUI checks')) -Message 'The release gate validates the default-branch record against the tagged SHA and labels its Server runner as metadata-only.'
Assert-WorkflowCondition -Condition ($protectionReadinessJobBody -match '(?m)^    runs-on: windows-2025$' -and $protectionReadinessJobBody.Contains('github.event.repository.default_branch') -and $protectionReadinessJobBody.Contains('release-protection') -and $protectionReadinessJobBody.Contains('RELEASE_PROTECTION_VERIFICATION.json') -and $protectionReadinessJobBody.Contains('Test-InstallerReleaseProtectionReadiness') -and $protectionReadinessJobBody.Contains('if (-not $result.IsReady)') -and $protectionReadinessJobBody.Contains('exit 1')) -Message 'The release gate checks the default-branch remote record and fails before publication when it is not ready.'
$protectedTagStepMatch = [regex]::Match($tagValidationJobBody, '(?ms)^      - name: Require a protected semantic-version tag\r?\n(?<body>.*?)(?=^      - name:|\z)')
$protectedTagStepBody = [string]$protectedTagStepMatch.Groups['body'].Value
Assert-WorkflowCondition -Condition ($protectedTagStepMatch.Success -and $protectedTagStepBody.Contains('RELEASE_REF_PROTECTED: ${{ github.ref_protected }}') -and $protectedTagStepBody.Contains("if (`$env:RELEASE_REF_PROTECTED -cne 'true') {") -and $protectedTagStepBody.Contains("throw 'The release tag must be protected by a GitHub ruleset or tag protection rule.'")) -Message 'Tag validation maps github.ref_protected and fails closed unless its value is exactly true.'
Assert-WorkflowCondition -Condition ($tagValidationJobBody -match '(?ms)tools[\\/]Test-CompatibilityReview\.ps1\s+-RequireFresh') -Message 'Release tag validation requires a fresh manual compatibility source review before matrix release work.'
Assert-WorkflowCondition -Condition ($releasePublisherJobBody.Contains('RELEASE_REF_PROTECTED: ${{ github.ref_protected }}')) -Message 'The publishing job independently passes github.ref_protected to the release publisher.'
Assert-WorkflowCondition -Condition ($releaseProtectionVerificationText.Contains('**Remote settings status:** NOT VERIFIED') -and $releaseProtectionVerificationText.Contains('**Local access check timestamp:**') -and $releaseProtectionVerificationText.Contains('**Remote observation timestamp:** NOT VERIFIED') -and $releaseProtectionVerificationText.Contains('30 days')) -Message 'The release readiness record keeps remote status separate from the local check and documents the evidence freshness window.'
Assert-WorkflowCondition -Condition ($releaseProtectionVerificationRecord.status -ceq 'NOT VERIFIED' -and $releaseProtectionVerificationRecord.repository -ceq 'mytech-today-now/app_installer' -and $null -eq $releaseProtectionVerificationRecord.observedAtUtc -and $null -eq $releaseProtectionVerificationRecord.evidence.location -and $releaseProtectionReadinessModuleText.Contains('Test-InstallerReleaseProtectionReadiness') -and $releaseProtectionReadinessTestText.Contains('stale') -and $releaseProtectionReadinessTestText.Contains('incomplete')) -Message 'The machine-readable remote record remains NOT VERIFIED and the validator tests incomplete and stale evidence fixtures.'
Assert-WorkflowCondition -Condition ($releaseProtectionVerificationText.Contains('| Ruleset name/ID, source, and enforcement status | NOT VERIFIED |') -and $releaseProtectionVerificationText.Contains('| Target tag pattern and exclusions | NOT VERIFIED |') -and $releaseProtectionVerificationText.Contains('| Tag creation, update, and deletion restrictions | NOT VERIFIED |') -and $releaseProtectionVerificationText.Contains('| Required reviewers or approval control | NOT VERIFIED |') -and $releaseProtectionVerificationText.Contains('| Bypass actors and modes | NOT VERIFIED |') -and $releaseProtectionVerificationText.Contains('| Effective repository/organization workflow permission scope | NOT VERIFIED |')) -Message 'Each unobserved remote release control is explicitly recorded as NOT VERIFIED.'
foreach ($verificationField in @('Ruleset identity and enforcement', 'Tag pattern', 'Required reviewers and approval control', 'Bypass actors', 'Workflow permission scope')) {
    Assert-WorkflowCondition -Condition ($releaseProtectionVerificationText.Contains($verificationField)) -Message ('The release readiness checklist records the remote setting to verify: {0}.' -f $verificationField)
}
Assert-WorkflowCondition -Condition ($releaseWorkflowText -notmatch '(?i)actions/(upload-artifact|download-artifact)|workflow_run') -Message 'The release path must not use artifact storage or rely on a separate workflow run.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -notmatch '(?i)\$\{\{\s*secrets\.') -Message 'The release workflow must not require a repository-defined secret.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText.Contains('${{ github.token }}')) -Message 'Release publication must use the automatically provided workflow token.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -notmatch '(?i)git\s+tag|git\s+push|signtool|Set-AuthenticodeSignature|codesign') -Message 'The workflow must not create or push tags or sign the executable.'
$releaseActionReferences = [regex]::Matches($releaseWorkflowText, '(?m)^\s*uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40})')
Assert-WorkflowCondition -Condition ($releaseActionReferences.Count -eq 6) -Message 'The release workflow must use only its six pinned checkout actions.'
foreach ($actionReference in $releaseActionReferences) {
    Assert-WorkflowCondition -Condition ($actionReference.Groups[1].Value -ceq 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1') -Message 'Every third-party release action must use the verified immutable checkout commit.'
}
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match '(?m)^  compatibility:\r?\n    needs: validate_release_tag\r?\n    if:.*?\r?\n    uses: \.\/\.github\/workflows\/windows-build-compatibility\.yml') -Message 'The release matrix job must use the local reusable workflow after tag validation.'
Assert-WorkflowCondition -Condition ($releaseWorkflowText -match 'Build-InstallerExe\.ps1' -and $releaseWorkflowText -match 'New-InstallerReleaseAssets\.ps1' -and $releaseWorkflowText -match 'Publish-InstallerRelease\.ps1') -Message 'The release must reuse the pinned builder and the shared asset and publication tooling.'
Assert-WorkflowCondition -Condition ($releaseModuleText -match 'outputNamePattern' -and $releaseModuleText -match 'artifact\.identity' -and $releaseModuleText -match '\.sha256' -and $releaseModuleText -match "authenticodeStatus = 'NotSigned'") -Message 'Release tooling must enforce the current artifact identity, versioned x64 name, digest, and unsigned status.'
Assert-WorkflowCondition -Condition ($buildScriptText -match '(?m)^\s*schemaVersion = 2$' -and $buildScriptText.Contains('digestLimit = ''SHA-256 detects byte changes only when the expected digest is obtained through a trusted release channel. It does not authenticate the publisher or replace a digital signature.''')) -Message 'Builder provenance must version and carry the SHA-256 publisher-authentication limitation.'
Assert-WorkflowCondition -Condition ($releaseModuleText.Contains('SHA-256 detects byte changes only when the expected digest is obtained through a trusted release channel. It does not authenticate the publisher or replace a digital signature.') -and $releaseModuleText.Contains('This release is not signed.') -and $releaseModuleText.Contains("signerSubject = ''")) -Message 'Release metadata and notes must retain the unsigned disclosure, empty signer identity, and checksum limitation.'
Assert-WorkflowCondition -Condition ($releaseModuleText -match "'/releases/tags/'" -and $releasePublisherText -match 'RELEASE_REF_PROTECTED') -Message 'The publisher must check for duplicate releases and protected tags.'
Assert-WorkflowCondition -Condition ($buildTestText -match 'test-installer-release-assets\.ps1') -Message 'The clean executable fixture test must run the focused release asset simulation.'
Assert-WorkflowCondition -Condition ($releaseAssetTestText -match 'DryRun' -and $releaseAssetTestText -match 'failed upload must block publication' -and $releaseAssetTestText -match 'existing release must be rejected') -Message 'The focused release test must cover dry-run, duplicate release, and failed upload gates.'
$releaseSigningReferences = ($releaseWorkflowText + $releaseModuleText + $releasePublisherText) -match '(?i)\b(?:signtool(?:\.exe)?|Set-AuthenticodeSignature|codesign|osslsigncode)\b'
Assert-WorkflowCondition -Condition (-not $releaseSigningReferences) -Message 'No release workflow or publisher step may invoke a signing tool.'

Write-Output ('[OK] GitHub Actions workflow contract passed: assertions={0}; releaseActions={1}; engines=2; releaseGates=protected-tag+client-gui-evidence+remote-protection+tests.' -f $script:assertionCount, $releaseActionReferences.Count)
