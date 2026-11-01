#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$inventoryPath = Join-Path $PSScriptRoot 'ci-regression-inventory.json'
$runnerPath = Join-Path $PSScriptRoot 'Invoke-CIRegressionSuite.ps1'
$workflowContractPath = Join-Path $PSScriptRoot 'test-github-actions-workflow.ps1'
$fixturePath = Join-Path $PSScriptRoot 'fixtures\ci-intentional-failure.ps1'
$readmePath = Join-Path $repositoryRoot 'README.md'
$script:assertionCount = 0

function Assert-InventoryCondition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) {
        throw "CI regression inventory assertion failed: $Message"
    }
}

function Get-TestInventoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InventoryTests,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $matches = @($InventoryTests | Where-Object { [System.IO.Path]::GetFileName([string]$_.path) -ceq $FileName })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one inventory entry for $FileName; found $($matches.Count)."
    }
    return $matches[0]
}

function Assert-EngineDisposition {
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

    $entry = Get-TestInventoryEntry -InventoryTests $InventoryTests -FileName $FileName
    $engineProperty = $entry.engines.PSObject.Properties[$Engine]
    Assert-InventoryCondition -Condition ($null -ne $engineProperty -and [string]$engineProperty.Value.status -ceq $ExpectedStatus) -Message "$FileName has $ExpectedStatus status for $Engine."
}

if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    throw 'The documented CI regression inventory is missing.'
}
$inventory = Get-Content -LiteralPath $inventoryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$inventoryTests = @($inventory.tests)
$engineNames = @('Desktop-5.1', 'Core-7.6.9')
$validStatuses = @('included', 'skipped', 'unavailable')
$discoveredPaths = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter 'test-*.ps1' | ForEach-Object { 'tests/' + $_.Name } | Sort-Object)
$listedPaths = @($inventoryTests | ForEach-Object { [string]$_.path } | Sort-Object)

Assert-InventoryCondition -Condition ([int]$inventory.schemaVersion -eq 1) -Message 'The inventory schema version is supported.'
Assert-InventoryCondition -Condition ($inventoryTests.Count -eq $discoveredPaths.Count) -Message 'Every standalone test script has exactly one inventory entry.'
Assert-InventoryCondition -Condition ((@($listedPaths | Select-Object -Unique).Count) -eq $listedPaths.Count) -Message 'The inventory contains no duplicate test paths.'
Assert-InventoryCondition -Condition (@($discoveredPaths | Where-Object { $_ -notin $listedPaths }).Count -eq 0) -Message 'No discovered test script is missing from the allowlist.'
Assert-InventoryCondition -Condition (@($listedPaths | Where-Object { $_ -notin $discoveredPaths }).Count -eq 0) -Message 'The allowlist contains no test path that is absent from the tests directory.'
Assert-InventoryCondition -Condition ([int]$inventory.documentedCounts.totalScripts -eq $discoveredPaths.Count) -Message 'The documented total equals the actual standalone script count.'

foreach ($entry in $inventoryTests) {
    $relativePath = [string]$entry.path
    Assert-InventoryCondition -Condition ($relativePath -match '^tests/test-[^/\\]+\.ps1$') -Message "The inventory path is a repository-relative test script path: $relativePath"
    Assert-InventoryCondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$entry.prerequisites)) -Message "$relativePath documents its platform and runtime prerequisites."
    Assert-InventoryCondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$entry.boundary)) -Message "$relativePath documents its fake or live state boundary."

    foreach ($engine in $engineNames) {
        $engineProperty = $entry.engines.PSObject.Properties[$engine]
        Assert-InventoryCondition -Condition ($null -ne $engineProperty) -Message "$relativePath has an explicit $engine disposition."
        if ($null -eq $engineProperty) {
            continue
        }

        $disposition = $engineProperty.Value
        $status = [string]$disposition.status
        Assert-InventoryCondition -Condition ($status -in $validStatuses) -Message "$relativePath has a valid $engine status."
        if ($status -in @('skipped', 'unavailable')) {
            Assert-InventoryCondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$disposition.reason)) -Message "$relativePath explains why it is $status for $engine."
        }
    }
}

foreach ($engine in $engineNames) {
    $engineCountProperty = $inventory.documentedCounts.PSObject.Properties[$engine]
    Assert-InventoryCondition -Condition ($null -ne $engineCountProperty) -Message "Documented test counts exist for $engine."
    if ($null -eq $engineCountProperty) {
        continue
    }

    $actualCounts = @{}
    foreach ($status in $validStatuses) {
        $actualCounts[$status] = @($inventoryTests | Where-Object { [string]$_.engines.PSObject.Properties[$engine].Value.status -ceq $status }).Count
        Assert-InventoryCondition -Condition ([int]$engineCountProperty.Value.$status -eq $actualCounts[$status]) -Message "The $engine $status count matches the inventory entries."
    }
    Assert-InventoryCondition -Condition (($actualCounts.Values | Measure-Object -Sum).Sum -eq $discoveredPaths.Count) -Message "Every $engine disposition is represented in its documented counts."
}

$criticalIncludedTests = @(
    'test-ci-regression-inventory.ps1',
    'test-github-actions-workflow.ps1',
    'test-compatibility-review-freshness.ps1',
    'test-belarc-installer-trust.ps1',
    'test-cli-runtime-handoff.ps1',
    'test-custom-app-script-results.ps1',
    'test-executable-install-lifecycle.ps1',
    'test-gui-queue-state.ps1',
    'test-gui-startup-capability.ps1',
    'test-instruction-html-security.ps1',
    'test-package-dependency-outcomes.ps1',
    'test-remote-helper-trust.ps1',
    'test-update-scan-status.ps1',
    'test-winget-bootstrap.ps1'
)
foreach ($fileName in $criticalIncludedTests) {
    foreach ($engine in $engineNames) {
        Assert-EngineDisposition -InventoryTests $inventoryTests -FileName $fileName -Engine $engine -ExpectedStatus 'included'
    }
}
Assert-EngineDisposition -InventoryTests $inventoryTests -FileName 'test-installer-release-assets.ps1' -Engine 'Desktop-5.1' -ExpectedStatus 'skipped'
Assert-EngineDisposition -InventoryTests $inventoryTests -FileName 'test-installer-release-assets.ps1' -Engine 'Core-7.6.9' -ExpectedStatus 'included'
foreach ($engine in $engineNames) {
    Assert-EngineDisposition -InventoryTests $inventoryTests -FileName 'test-native-cli-boundaries.ps1' -Engine $engine -ExpectedStatus 'skipped'
}
$clientRuntimeEntry = Get-TestInventoryEntry -InventoryTests $inventoryTests -FileName 'test-compatibility-runtime-current-host.ps1'
$clientStartupEntry = Get-TestInventoryEntry -InventoryTests $inventoryTests -FileName 'test-startup-entrypoints-offline.ps1'
foreach ($engine in $engineNames) {
    Assert-EngineDisposition -InventoryTests $inventoryTests -FileName 'test-executable-build.ps1' -Engine $engine -ExpectedStatus $(if ($engine -eq 'Core-7.6.9') { 'included' } else { 'skipped' })
    Assert-EngineDisposition -InventoryTests $inventoryTests -FileName 'test-executable-payload.ps1' -Engine $engine -ExpectedStatus $(if ($engine -eq 'Core-7.6.9') { 'included' } else { 'skipped' })
    Assert-EngineDisposition -InventoryTests $inventoryTests -FileName 'test-compatibility-runtime-current-host.ps1' -Engine $engine -ExpectedStatus 'unavailable'
    Assert-EngineDisposition -InventoryTests $inventoryTests -FileName 'test-startup-entrypoints-offline.ps1' -Engine $engine -ExpectedStatus 'unavailable'
    $runtimeUnavailableReason = [string]$clientRuntimeEntry.engines.PSObject.Properties[$engine].Value.reason
    $startupUnavailableReason = [string]$clientStartupEntry.engines.PSObject.Properties[$engine].Value.reason
    Assert-InventoryCondition -Condition ($runtimeUnavailableReason.Contains('Windows Server 2025') -and $runtimeUnavailableReason.Contains('outside the Windows 11 client runtime contract')) -Message "$engine current-host runtime evidence explains why Server cannot validate the client matrix."
    Assert-InventoryCondition -Condition ($startupUnavailableReason.Contains('Server 2025') -and $startupUnavailableReason.Contains('supported interactive Windows client')) -Message "$engine GUI startup evidence is explicitly unavailable on Server."
}

$runnerText = Get-Content -LiteralPath $runnerPath -Raw -ErrorAction Stop
$workflowContractText = Get-Content -LiteralPath $workflowContractPath -Raw -ErrorAction Stop
$fixtureText = Get-Content -LiteralPath $fixturePath -Raw -ErrorAction Stop
$readmeText = Get-Content -LiteralPath $readmePath -Raw -ErrorAction Stop
$failurePropagationEntry = Get-TestInventoryEntry -InventoryTests $inventoryTests -FileName 'test-ci-regression-suite-failure.ps1'
$failureScriptText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-ci-regression-suite-failure.ps1') -Raw -ErrorAction Stop

Assert-InventoryCondition -Condition ($runnerText.Contains('ci-regression-inventory.json') -and $runnerText.Contains('$entry.engines.PSObject.Properties[$Engine]')) -Message 'The runner consumes per-engine dispositions from the explicit inventory.'
Assert-InventoryCondition -Condition ($runnerText.Contains("'^tests/test-[^/\\]+\.ps1$'") -and $runnerText.Contains('duplicate test path')) -Message 'The runner rejects inventory paths outside the standalone test-script allowlist and rejects duplicate paths.'
Assert-InventoryCondition -Condition ($runnerText.Contains('APP_INSTALLER_ARTIFACT_PATH') -and $runnerText.Contains('-RepositoryRoot') -and $runnerText.Contains('-ExecutablePath')) -Message 'The Core runner passes its validated build artifact to the release asset test.'
Assert-InventoryCondition -Condition ($failurePropagationEntry.engines.PSObject.Properties['Desktop-5.1'].Value.status -ceq 'included' -and $failurePropagationEntry.engines.PSObject.Properties['Core-7.6.9'].Value.status -ceq 'included') -Message 'The failure-propagation regression runs in both engine legs.'
Assert-InventoryCondition -Condition ($failureScriptText.Contains('-InjectFailureForTest') -and $failureScriptText.Contains('$probeExitCode -ne 31') -and $failureScriptText.Contains('exited with code 31')) -Message 'The failure-propagation regression verifies the injected exit code and failure report.'
Assert-InventoryCondition -Condition ($fixtureText -match '(?m)^exit 31\s*$' -and $runnerText.Contains('exit $testExitCode')) -Message 'The injected child failure is nonzero and the runner preserves its exact exit code.'
Assert-InventoryCondition -Condition ($workflowContractText.Contains('test-ci-regression-inventory.ps1')) -Message 'The workflow contract test is itself included in the inventory.'
Assert-InventoryCondition -Condition ($readmeText.Contains('36 standalone `test-*.ps1` scripts') -and $readmeText.Contains('Desktop-5.1: 30 included, 4 skipped, 2 unavailable') -and $readmeText.Contains('Core-7.6.9: 33 included, 1 skipped, 2 unavailable')) -Message 'README inventory counts match the tested dispositions.'

$previouslyOmittedTests = @(
    'test-belarc-installer-trust.ps1',
    'test-cli-runtime-handoff.ps1',
    'test-compatibility-runtime-current-host.ps1',
    'test-custom-app-script-results.ps1',
    'test-executable-install-lifecycle.ps1',
    'test-gui-queue-state.ps1',
    'test-gui-startup-capability.ps1',
    'test-install-bat-elevation.ps1',
    'test-installer-release-assets.ps1',
    'test-package-dependency-outcomes.ps1',
    'test-remote-helper-trust.ps1',
    'test-winget-bootstrap.ps1'
)
$readmeLines = @($readmeText -split '\r?\n')
foreach ($fileName in $previouslyOmittedTests) {
    $rowPrefix = '| `' + $fileName + '` |'
    $rows = @($readmeLines | Where-Object { $_.StartsWith($rowPrefix, [System.StringComparison]::Ordinal) })
    Assert-InventoryCondition -Condition ($rows.Count -eq 1) -Message "$fileName has exactly one row in the omitted-test platform and boundary table."
    if ($rows.Count -ne 1) {
        continue
    }

    $cells = @($rows[0].Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    Assert-InventoryCondition -Condition ($cells.Count -eq 5 -and -not [string]::IsNullOrWhiteSpace($cells[1]) -and -not [string]::IsNullOrWhiteSpace($cells[2])) -Message "$fileName table row documents platform prerequisites and its execution boundary."
    if ($cells.Count -ne 5) {
        continue
    }

    $entry = Get-TestInventoryEntry -InventoryTests $inventoryTests -FileName $fileName
    foreach ($engine in $engineNames) {
        $status = [string]$entry.engines.PSObject.Properties[$engine].Value.status
        $expectedLabel = switch ($status) {
            'included' { 'Included' }
            'skipped' { 'Skipped' }
            'unavailable' { 'Unavailable' }
            default { '' }
        }
        $cellIndex = if ($engine -eq 'Desktop-5.1') { 3 } else { 4 }
        Assert-InventoryCondition -Condition ($cells[$cellIndex].StartsWith($expectedLabel, [System.StringComparison]::OrdinalIgnoreCase)) -Message "$fileName table disposition matches $engine inventory status."
    }
}

Write-Output ('[OK] CI regression inventory contract passed: scripts={0}; Desktop-5.1 included={1} skipped={2} unavailable={3}; Core-7.6.9 included={4} skipped={5} unavailable={6}; assertions={7}.' -f $discoveredPaths.Count, [int]$inventory.documentedCounts.'Desktop-5.1'.included, [int]$inventory.documentedCounts.'Desktop-5.1'.skipped, [int]$inventory.documentedCounts.'Desktop-5.1'.unavailable, [int]$inventory.documentedCounts.'Core-7.6.9'.included, [int]$inventory.documentedCounts.'Core-7.6.9'.skipped, [int]$inventory.documentedCounts.'Core-7.6.9'.unavailable, $script:assertionCount)
