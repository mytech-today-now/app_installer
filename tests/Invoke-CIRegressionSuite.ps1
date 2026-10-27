#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Desktop-5.1', 'Core-7.6.7')]
    [string]$Engine,

    [switch]$InjectFailureForTest
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot

if ($Engine -eq 'Desktop-5.1') {
    $enginePath = Join-Path $PSHOME 'powershell.exe'
    $expectedEngine = 'Desktop 5.1'
    $actualEngine = '{0} {1}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion
    $engineExitCode = 0
    $engineMatches = $PSVersionTable.PSEdition -eq 'Desktop' -and $PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1
}
else {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        throw '[UNAVAILABLE] PowerShell Core 7.6.7 is required but pwsh.exe is not available.'
    }
    $enginePath = $pwsh.Source
    $expectedEngine = 'Core 7.6.7'
    $engineDetails = @(& $enginePath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')
    $engineExitCode = $LASTEXITCODE
    $actualVersion = [string]::Join('', $engineDetails).Trim()
    $actualEngine = 'Core {0}' -f $actualVersion
    $engineMatches = $actualVersion -ceq '7.6.7'
}

if ($engineExitCode -ne 0 -or -not $engineMatches) {
    throw ('[UNAVAILABLE] Expected {0}; found {1}.' -f $expectedEngine, $actualEngine)
}

$passedTestCount = 0
$skippedTestCount = 0
$skippedCheckCount = 0
$unavailableTestCount = 0

if ($InjectFailureForTest) {
    $tests = @('tests/fixtures/ci-intentional-failure.ps1')
    Write-Output '[TEST MODE] Running the fixed failing fixture to verify nonzero propagation.'
}
else {
    $tests = @(
        'other_files/test-syntax.ps1',
        'tests/test-github-actions-workflow.ps1',
        'tests/test-ci-regression-suite-failure.ps1',
        'tests/test-compatibility-contract.ps1',
        'tests/test-engine-compatibility-runtime.ps1',
        'tests/test-executable-metadata.ps1',
        'tests/test-executable-resource-update.ps1',
        'tests/test-execution-policy-launchers.ps1',
        'tests/test-runtime-engine-discovery-offline.ps1',
        'tests/test-runtime-prerequisite-plan-offline.ps1',
        'tests/test-startup-entrypoints-offline.ps1',
        'tests/test-startup-helper-trust.ps1',
        'tests/test-ooshutup10-trust.ps1',
        'tests/test-package-manager-command-security.ps1',
        'tests/test-update-scan-status.ps1',
        'tests/test-update-argv-security.ps1',
        'tests/test-monthly-update-scheduling.ps1',
        'tests/test-monthly-update-results.ps1',
        'tests/test-cli-whatif.ps1'
    )

    if ($Engine -eq 'Core-7.6.7') {
        $tests += @(
            'tests/test-executable-build.ps1',
            'tests/test-executable-payload.ps1'
        )
    }
}

Write-Output ('[ENGINE] {0} at {1}' -f $actualEngine, $enginePath)
foreach ($relativePath in $tests) {
    $testPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw ('A required CI regression script is missing: {0}' -f $relativePath)
    }

    Write-Output ('[RUN] {0} under {1}' -f $relativePath, $actualEngine)
    $testOutput = @(& $enginePath -NoProfile -File $testPath 2>&1)
    $testExitCode = $LASTEXITCODE

    foreach ($outputLine in $testOutput) {
        Write-Output $outputLine
    }

    $skipLines = @($testOutput | Where-Object { [string]$_ -match '^\[SKIP\]\s*\S' })
    if ($testExitCode -eq 77) {
        if ($skipLines.Count -eq 0) {
            Write-Output ('[FAIL] {0} exited with skip code 77 without an explicit [SKIP] reason.' -f $relativePath)
            exit 1
        }

        $skippedTestCount++
        Write-Output ('[SKIP] {0}: {1}' -f $relativePath, ([string]$skipLines[0]).Substring(7).Trim())
        continue
    }

    if ($testExitCode -ne 0) {
        Write-Output ('[FAIL] {0} under {1} exited with code {2}.' -f $relativePath, $actualEngine, $testExitCode)
        exit $testExitCode
    }

    $skippedCheckCount += $skipLines.Count
    $passedTestCount++
    Write-Output ('[PASS] {0} under {1}' -f $relativePath, $actualEngine)
}

$unavailableTestCount++
Write-Output '[UNAVAILABLE] tests/test-compatibility-runtime-current-host.ps1 requires a supported Windows client. The standard windows-2025 runner is Windows Server 2025 and remains outside the App Installer runtime support matrix.'
Write-Output ('[SUMMARY] passed tests={0}; skipped tests={1}; skipped checks={2}; unavailable tests={3}' -f $passedTestCount, $skippedTestCount, $skippedCheckCount, $unavailableTestCount)
