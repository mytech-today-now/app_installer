# Runtime compatibility checks for APIs whose behavior differs by PowerShell edition.
# These checks use local temporary files only and do not launch package managers.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot 'compatibility.json'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-engine-compat-' + [guid]::NewGuid().ToString('N'))))
$script:assertionCount = 0
$utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)

if (-not $testRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary test directory is outside the system temporary directory.'
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Import-Module -Name (Join-Path $repositoryRoot 'modules\InstallerCompatibility.psm1') -Force -DisableNameChecking -ErrorAction Stop
    Import-Module -Name (Join-Path $repositoryRoot 'modules\AppInstallerCore.psm1') -Force -DisableNameChecking -ErrorAction Stop

    $manifest = Get-InstallerCompatibilityManifest -Path $manifestPath
    $currentEngine = [PSCustomObject]@{
        PSEdition = [string]$PSVersionTable.PSEdition
        PSVersion = [version]$PSVersionTable.PSVersion
    }
    $currentDecision = Test-InstallerPowerShellEngine -EngineInfo $currentEngine -Manifest $manifest
    Assert-Condition -Condition $currentDecision.IsSupported -Message ("Current engine is in compatibility.json: {0} {1}" -f $currentEngine.PSEdition, $currentEngine.PSVersion)

    $unsupportedCore = [PSCustomObject]@{ PSEdition = 'Core'; PSVersion = [version]'7.6.6' }
    $unsupportedDecision = Test-InstallerPowerShellEngine -EngineInfo $unsupportedCore -Manifest $manifest
    Assert-Condition -Condition (-not $unsupportedDecision.IsSupported) -Message 'PowerShell Core 7.6.6 is rejected by the actual compatibility contract.'

    $argumentListProperty = [System.Diagnostics.ProcessStartInfo].GetProperty('ArgumentList')
    if ($currentEngine.PSEdition -eq 'Desktop') {
        Assert-Condition -Condition ($null -eq $argumentListProperty) -Message 'Windows PowerShell uses the .NET Framework process-argument quoting fallback.'
    }
    else {
        Assert-Condition -Condition ($null -ne $argumentListProperty) -Message 'PowerShell Core exposes ProcessStartInfo.ArgumentList on the supported .NET runtime.'
    }

    $jsonArrayValues = @(ConvertFrom-Json -InputObject '["first","second"]')
    if ($currentEngine.PSEdition -eq 'Desktop') {
        Assert-Condition -Condition ($jsonArrayValues.Count -eq 1 -and $jsonArrayValues[0] -is [System.Array]) -Message 'Windows PowerShell returns a JSON array as one nested pipeline object.'
        $jsonArrayValues = @($jsonArrayValues[0])
    }
    else {
        Assert-Condition -Condition ($jsonArrayValues.Count -eq 2 -and $jsonArrayValues[0] -is [string]) -Message 'PowerShell Core enumerates JSON array values through the pipeline.'
    }
    Assert-Condition -Condition ($jsonArrayValues.Count -eq 2 -and $jsonArrayValues[0] -ceq 'first' -and $jsonArrayValues[1] -ceq 'second') -Message 'Normalizing the JSON array produces the same ordered values in both engines.'

    $profilePath = Join-Path $testRoot 'profile.json'
    $accent = [char]233
    $expectedApplications = @(('Caf' + $accent + ' Viewer'), 'O&O Assistant')
    Export-InstallationProfile -Applications $expectedApplications -ProfilePath $profilePath -ProfileName 'Compatibility profile'
    Assert-Condition -Condition (Test-Path -LiteralPath $profilePath -PathType Leaf) -Message 'Profile export creates its local JSON file.'

    $profileBytes = [System.IO.File]::ReadAllBytes($profilePath)
    $hasBom = $profileBytes.Length -ge 3 -and
        $profileBytes[0] -eq $utf8Bom[0] -and
        $profileBytes[1] -eq $utf8Bom[1] -and
        $profileBytes[2] -eq $utf8Bom[2]
    if ($currentEngine.PSEdition -eq 'Desktop') {
        Assert-Condition -Condition $hasBom -Message 'Windows PowerShell UTF8 profile output includes its documented BOM.'
    }
    else {
        Assert-Condition -Condition (-not $hasBom) -Message 'PowerShell Core UTF8 profile output is UTF-8 without a BOM.'
    }

    $importedApplications = @(Import-InstallationProfile -ProfilePath $profilePath)
    Assert-Condition -Condition ($importedApplications.Count -eq $expectedApplications.Count) -Message 'Profile import preserves the exported application count.'
    for ($index = 0; $index -lt $expectedApplications.Count; $index++) {
        Assert-Condition -Condition ($importedApplications[$index] -ceq $expectedApplications[$index]) -Message ("Profile round-trip preserves application value {0}." -f $index)
    }

    $linuxHost = [PSCustomObject]@{
        Platform = 'Linux'
        DisplayVersion = ''
        BuildNumber = 0
        ProductType = ''
        InstallationType = ''
        EditionId = ''
        Architecture = 'X64'
        DotNetFrameworkRelease = 0
    }
    $linuxGuiDecision = Test-InstallerCompatibility -Component WindowsGui -HostInfo $linuxHost -EngineInfo $currentEngine -WindowsFormsAvailable $true
    Assert-Condition -Condition (-not $linuxGuiDecision.IsSupported -and $linuxGuiDecision.Reason.Contains('requires Windows')) -Message 'A Windows Forms capability cannot bypass the Windows host guard.'

    Write-Host "[PASS] $script:assertionCount engine compatibility runtime assertions passed." -ForegroundColor Green
}
finally {
    Remove-Module -Name AppInstallerCore -Force -ErrorAction SilentlyContinue
    Remove-Module -Name InstallerCompatibility -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolvedTempTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedTempTestRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTempTestRoot -Recurse -Force
        }
    }
}
