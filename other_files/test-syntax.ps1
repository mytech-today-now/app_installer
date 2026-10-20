# Focused syntax smoke check for the current App Installer entry points and helpers.
$scriptPaths = @(
    (Join-Path $PSScriptRoot '..\app-installer.ps1'),
    (Join-Path $PSScriptRoot '..\app-installer-cli.ps1'),
    (Join-Path $PSScriptRoot '..\platform-detect.ps1'),
    (Join-Path $PSScriptRoot '..\modules\StartupHelperTrust.psm1'),
    (Join-Path $PSScriptRoot '..\modules\OOShutUp10Trust.psm1'),
    (Join-Path $PSScriptRoot '..\modules\RemotePowerShellTrust.psm1'),
    (Join-Path $PSScriptRoot '..\modules\ResponsiveGuiHelper.psm1'),
    (Join-Path $PSScriptRoot '..\modules\WingetBootstrap.psm1'),
    (Join-Path $PSScriptRoot '..\modules\InstallerCompatibility.psm1'),
    (Join-Path $PSScriptRoot '..\modules\InstallerRuntimeDiscovery.psm1'),
    (Join-Path $PSScriptRoot '..\modules\InstallerPrerequisitePlan.psm1'),
    (Join-Path $PSScriptRoot '..\tools\Install-CompatiblePowerShell.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Start-Installer.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Test-InstallerCompatibility.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Set-InstallerExeMetadata.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Build-InstallerExe.ps1'),
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
    (Join-Path $PSScriptRoot '..\tests\test-compatibility-contract.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-compatibility-runtime-current-host.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-gui-startup-capability.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-runtime-engine-discovery-offline.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-executable-metadata.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-executable-resource-update.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-cli-whatif.ps1'),
    (Join-Path $PSScriptRoot '..\invoke-elevated-install.ps1'),
    (Join-Path $PSScriptRoot '..\tests\test-install-bat-elevation.ps1')
)

$repositoryRoot = Split-Path -Parent $PSScriptRoot
foreach ($sourceDirectoryName in @('apps', 'modules', 'tools', 'tests')) {
    $sourceDirectory = Join-Path $repositoryRoot $sourceDirectoryName
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        continue
    }

    $sourceFiles = Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') } |
        Select-Object -ExpandProperty FullName
    $scriptPaths += @($sourceFiles)
}

$scriptPaths = @($scriptPaths | ForEach-Object { [System.IO.Path]::GetFullPath($_) } | Sort-Object -Unique)

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

Write-Host ("[OK] All {0} discovered App Installer PowerShell files parse cleanly under {1} {2}." -f $scriptPaths.Count, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion) -ForegroundColor Green
exit 0
