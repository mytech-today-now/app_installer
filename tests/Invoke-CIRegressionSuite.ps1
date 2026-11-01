#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Desktop-5.1', 'Core-7.6.9')]
    [string]$Engine,

    [switch]$InjectFailureForTest
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$inventoryPath = Join-Path $PSScriptRoot 'ci-regression-inventory.json'

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
        throw '[UNAVAILABLE] PowerShell Core 7.6.9 is required but pwsh.exe is not available.'
    }
    $enginePath = $pwsh.Source
    $expectedEngine = 'Core 7.6.9'
    $engineDetails = @(& $enginePath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')
    $engineExitCode = $LASTEXITCODE
    $actualVersion = [string]::Join('', $engineDetails).Trim()
    $actualEngine = 'Core {0}' -f $actualVersion
    $engineMatches = $actualVersion -ceq '7.6.9'
}

if ($engineExitCode -ne 0 -or -not $engineMatches) {
    throw ('[UNAVAILABLE] Expected {0}; found {1}.' -f $expectedEngine, $actualEngine)
}

$passedTestCount = 0
$passedCheckCount = 0
$skippedTestCount = 0
$skippedCheckCount = 0
$unavailableTestCount = 0
$inventoryScriptCount = 0

if ($InjectFailureForTest) {
    $tests = @([PSCustomObject]@{ Path = 'tests/fixtures/ci-intentional-failure.ps1'; Arguments = @() })
    Write-Output '[TEST MODE] Running the fixed failing fixture to verify nonzero propagation.'
}
else {
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw ('The CI regression inventory is missing: {0}' -f $inventoryPath)
    }

    $inventory = Get-Content -LiteralPath $inventoryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([int]$inventory.schemaVersion -ne 1) {
        throw ('Unsupported CI regression inventory schema version: {0}' -f $inventory.schemaVersion)
    }

    $inventoryScriptCount = @($inventory.tests).Count
    $tests = @([PSCustomObject]@{ Path = 'other_files/test-syntax.ps1'; Arguments = @(); Kind = 'check' })
    $seenTestPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($inventory.tests)) {
        $relativePath = [string]$entry.path
        if ($relativePath -notmatch '^tests/test-[^/\\]+\.ps1$') {
            throw ('The CI regression inventory contains an unsafe test path: {0}' -f $relativePath)
        }
        if (-not $seenTestPaths.Add($relativePath)) {
            throw ('The CI regression inventory contains a duplicate test path: {0}' -f $relativePath)
        }

        $testPath = Join-Path $repositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
            throw ('A regression script in the explicit inventory is missing: {0}' -f $relativePath)
        }

        $engineDispositionProperty = $entry.engines.PSObject.Properties[$Engine]
        if ($null -eq $engineDispositionProperty) {
            throw ('The CI regression inventory has no {0} disposition for {1}.' -f $Engine, $relativePath)
        }

        $engineDisposition = $engineDispositionProperty.Value
        $status = [string]$engineDisposition.status
        switch ($status) {
            'included' {
                $tests += [PSCustomObject]@{ Path = $relativePath; Arguments = @(); Kind = 'test' }
            }
            'skipped' {
                if ([string]::IsNullOrWhiteSpace([string]$engineDisposition.reason)) {
                    throw ('The skipped inventory entry has no reason: {0} ({1}).' -f $relativePath, $Engine)
                }
                $skippedTestCount++
                Write-Output ('[SKIP] {0}: {1}' -f $relativePath, [string]$engineDisposition.reason)
            }
            'unavailable' {
                if ([string]::IsNullOrWhiteSpace([string]$engineDisposition.reason)) {
                    throw ('The unavailable inventory entry has no reason: {0} ({1}).' -f $relativePath, $Engine)
                }
                $unavailableTestCount++
                Write-Output ('[UNAVAILABLE] {0}: {1}' -f $relativePath, [string]$engineDisposition.reason)
            }
            default {
                throw ('The CI regression inventory has an invalid disposition for {0} ({1}): {2}.' -f $relativePath, $Engine, $status)
            }
        }
    }
}

Write-Output ('[ENGINE] {0} at {1}' -f $actualEngine, $enginePath)
Write-Output ('[INVENTORY] standalone scripts={0}; engine={1}' -f $inventoryScriptCount, $Engine)
foreach ($test in $tests) {
    $relativePath = [string]$test.Path
    $testPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw ('A required CI regression script is missing: {0}' -f $relativePath)
    }

    $testArguments = @($test.Arguments)
    if ($relativePath -ceq 'tests/test-installer-release-assets.ps1') {
        $artifactPath = [string]$env:APP_INSTALLER_ARTIFACT_PATH
        if ([string]::IsNullOrWhiteSpace($artifactPath)) {
            if ([string]$env:GITHUB_ACTIONS -ceq 'true') {
                throw '[FAIL] The Core CI leg must pass APP_INSTALLER_ARTIFACT_PATH from its validated build step.'
            }
            $unavailableTestCount++
            Write-Output '[UNAVAILABLE] tests/test-installer-release-assets.ps1: no locally built executable was provided in APP_INSTALLER_ARTIFACT_PATH.'
            continue
        }

        if (-not [System.IO.Path]::IsPathRooted($artifactPath)) {
            $artifactPath = Join-Path $repositoryRoot $artifactPath
        }
        $artifactPath = [System.IO.Path]::GetFullPath($artifactPath)
        $repositoryPrefix = [System.IO.Path]::GetFullPath($repositoryRoot).TrimEnd([char[]]@([char]92, [char]47)) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $artifactPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('The release asset test input must be inside the repository: {0}' -f $artifactPath)
        }
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            if ([string]$env:GITHUB_ACTIONS -ceq 'true') {
                throw ('[FAIL] The validated CI build artifact is missing: {0}' -f $artifactPath)
            }
            $unavailableTestCount++
            Write-Output ('[UNAVAILABLE] tests/test-installer-release-assets.ps1: the local build artifact is missing: {0}' -f $artifactPath)
            continue
        }
        $testArguments = @('-RepositoryRoot', $repositoryRoot, '-ExecutablePath', $artifactPath)
    }

    Write-Output ('[RUN] {0} under {1}' -f $relativePath, $actualEngine)
    $testOutput = @(& $enginePath -NoProfile -File $testPath @testArguments 2>&1)
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
    if ([string]$test.Kind -ceq 'check') {
        $passedCheckCount++
        Write-Output ('[PASS] {0} under {1}' -f $relativePath, $actualEngine)
    }
    else {
        $passedTestCount++
        Write-Output ('[PASS] {0} under {1}' -f $relativePath, $actualEngine)
    }
}

Write-Output ('[SUMMARY] passed tests={0}; passed checks={1}; skipped tests={2}; skipped checks={3}; unavailable tests={4}' -f $passedTestCount, $passedCheckCount, $skippedTestCount, $skippedCheckCount, $unavailableTestCount)
