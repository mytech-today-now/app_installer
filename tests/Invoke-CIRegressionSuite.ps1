#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Desktop-5.1', 'Core-7.6.7')]
    [string]$Engine
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

$tests = @(
    'other_files/test-syntax.ps1',
    'tests/test-github-actions-workflow.ps1',
    'tests/test-compatibility-contract.ps1',
    'tests/test-engine-compatibility-runtime.ps1',
    'tests/test-executable-metadata.ps1',
    'tests/test-executable-resource-update.ps1',
    'tests/test-execution-policy-launchers.ps1',
    'tests/test-runtime-engine-discovery-offline.ps1',
    'tests/test-runtime-prerequisite-plan-offline.ps1',
    'tests/test-startup-entrypoints-offline.ps1',
    'tests/test-cli-whatif.ps1'
)

if ($Engine -eq 'Core-7.6.7') {
    $tests += @(
        'tests/test-executable-build.ps1',
        'tests/test-executable-payload.ps1'
    )
}

Write-Output ('[ENGINE] {0} at {1}' -f $actualEngine, $enginePath)
foreach ($relativePath in $tests) {
    $testPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw ('A required CI regression script is missing: {0}' -f $relativePath)
    }

    Write-Output ('[RUN] {0} under {1}' -f $relativePath, $actualEngine)
    & $enginePath -NoProfile -File $testPath
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) {
        throw ('[FAIL] {0} under {1} exited with code {2}.' -f $relativePath, $actualEngine, $testExitCode)
    }
    Write-Output ('[PASS] {0} under {1}' -f $relativePath, $actualEngine)
}

Write-Output '[NOT RUN] tests/test-compatibility-runtime-current-host.ps1 requires a supported Windows client. The standard windows-2025 runner is Windows Server 2025 and remains outside the App Installer runtime support matrix.'
