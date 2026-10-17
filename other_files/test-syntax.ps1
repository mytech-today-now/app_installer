# Focused syntax smoke check for the current App Installer entry points and helpers.
$scriptPaths = @(
    (Join-Path $PSScriptRoot '..\app-installer.ps1'),
    (Join-Path $PSScriptRoot '..\app-installer-cli.ps1'),
    (Join-Path $PSScriptRoot '..\modules\StartupHelperTrust.psm1'),
    (Join-Path $PSScriptRoot '..\modules\OOShutUp10Trust.psm1'),
    (Join-Path $PSScriptRoot '..\modules\RemotePowerShellTrust.psm1'),
    (Join-Path $PSScriptRoot '..\modules\ResponsiveGuiHelper.psm1'),
    (Join-Path $PSScriptRoot '..\modules\WingetBootstrap.psm1'),
    (Join-Path $PSScriptRoot '..\apps\winget-update.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-startup-helper-trust.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-startup-entrypoints-offline.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-ooshutup10-trust.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-remote-helper-trust.ps1'),
    (Join-Path $PSScriptRoot '..\apps\hosts.ps1'),
    (Join-Path $PSScriptRoot '..\apps\managerestorepoints.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-monthly-update-scheduling.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-monthly-update-results.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-package-dependency-outcomes.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-winget-bootstrap.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-cli-whatif.ps1'),
    (Join-Path $PSScriptRoot '..\invoke-elevated-install.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-install-bat-elevation.ps1')
)

$hasErrors = $false
foreach ($scriptPath in $scriptPaths) {
    $resolvedPath = [System.IO.Path]::GetFullPath($scriptPath)
    Write-Host "Checking syntax of: $resolvedPath" -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        Write-Host "[ERROR] File not found: $resolvedPath" -ForegroundColor Red
        $hasErrors = $true
        continue
    }

    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $resolvedPath,
        [ref]$null,
        [ref]$parseErrors
    )

    if ($parseErrors) {
        foreach ($parseError in $parseErrors) {
            Write-Host "[ERROR] Line $($parseError.Extent.StartLineNumber): $($parseError.Message)" -ForegroundColor Red
        }
        $hasErrors = $true
    }
    else {
        Write-Host '[OK] No syntax errors found' -ForegroundColor Green
    }
}

if ($hasErrors) {
    exit 1
}

Write-Host '[OK] All listed App Installer PowerShell files parse cleanly' -ForegroundColor Green
exit 0
