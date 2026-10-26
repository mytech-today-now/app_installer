#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$suitePath = Join-Path $PSScriptRoot 'Invoke-CIRegressionSuite.ps1'

if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $enginePath = Join-Path $PSHOME 'powershell.exe'
    $engineName = 'Desktop-5.1'
}
else {
    $engineCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $engineCommand) {
        throw '[UNAVAILABLE] PowerShell Core executable could not be resolved for the failure-propagation check.'
    }
    $enginePath = $engineCommand.Source
    $engineName = 'Core-7.6.7'
}

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw ('[UNAVAILABLE] PowerShell engine executable is missing: {0}' -f $enginePath)
}

$probeOutput = @(& $enginePath -NoProfile -File $suitePath -Engine $engineName -InjectFailureForTest 2>&1)
$probeExitCode = $LASTEXITCODE
$probeText = [string]::Join([Environment]::NewLine, [string[]]@($probeOutput | ForEach-Object { [string]$_ }))

if ($probeExitCode -ne 31) {
    throw ('The runner did not preserve the injected failing child exit code 31; received {0}.' -f $probeExitCode)
}
if (-not $probeText.Contains('[INJECTED FAILURE]')) {
    throw 'The runner failure probe did not execute the controlled failing child fixture.'
}
if ($probeText -notmatch '\[FAIL\] tests/fixtures/ci-intentional-failure\.ps1.*exited with code 31') {
    throw 'The runner did not report the injected child as a failed test.'
}
if ($probeText.Contains('[RUN] other_files/test-syntax.ps1')) {
    throw 'The failure probe unexpectedly entered the normal regression suite.'
}

Write-Output ('[OK] Injected test failure propagated through the runner with exit code {0}.' -f $probeExitCode)
