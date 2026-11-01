#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Linux', 'macOS')]
    [string]$ExpectedPlatform,

    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$script:assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:assertionCount++
    Write-Host "[PASS] $Message"
}

function Invoke-InstallWhatIfBoundaryCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CliPath
    )

    $parseErrors = $null
    $cliAst = [System.Management.Automation.Language.Parser]::ParseFile($CliPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) {
        throw 'The CLI source has parse errors, so its WhatIf boundary cannot be evaluated.'
    }

    foreach ($functionName in @('New-InstallerActionResult', 'Test-InstallerShouldProcess', 'Install-Application')) {
        $functionAst = $cliAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq $functionName
            }, $true)
        if ($null -eq $functionAst) {
            throw "The CLI function required for the WhatIf boundary was not found: $functionName"
        }

        Invoke-Expression -Command $functionAst.Extent.Text
    }

    $app = [PSCustomObject]@{
        Name = 'Native WhatIf Preview'
        AptPackage = 'native-preview-package'
        BrewCask = 'native-preview-cask'
    }
    $preview = Install-Application -App $app -WhatIf

    Assert-Condition -Condition ($preview.Status -ceq 'Preview' -and -not $preview.Success) -Message 'The CLI install function returns Preview under WhatIf.'
    Assert-Condition -Condition ($preview.Message -match 'No package, network, or local installer action was performed') -Message 'The WhatIf result makes no installation claim.'

    return $preview
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$actualPlatform = if ($IsMacOS) {
    'macOS'
}
elseif ($IsLinux) {
    'Linux'
}
else {
    $null
}

if ($WhatIfOnly) {
    $null = Invoke-InstallWhatIfBoundaryCheck -CliPath $cliPath
    Write-Output ('[OK] Isolated CLI WhatIf boundary passed; assertions={0}.' -f $script:assertionCount)
    return
}

if ($null -eq $actualPlatform) {
    Write-Host '[SKIP] Native CLI boundary checks require a Linux or macOS PowerShell Core host.'
    exit 77
}
if ($actualPlatform -cne $ExpectedPlatform) {
    throw ('Expected native {0}, but PowerShell reports {1}.' -f $ExpectedPlatform, $actualPlatform)
}

$manifestPath = Join-Path $repositoryRoot 'compatibility.json'
$compatibility = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$supportedVersion = [string]$compatibility.engines.powerShellCore.version
$actualVersion = $PSVersionTable.PSVersion.ToString()
$versionMatch = $actualVersion -ceq $supportedVersion
Write-Output ('[HOST] platform={0}; PowerShell Core={1}; supported={2}; exactVersionMatch={3}' -f $actualPlatform, $actualVersion, $supportedVersion, $versionMatch.ToString().ToLowerInvariant())

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app installer native boundary ' + [guid]::NewGuid().ToString('N'))))
$fakeManagerRoot = Join-Path $testRoot 'fake package managers'
$captureScriptPath = Join-Path $testRoot 'capture-arguments.ps1'
$capturePath = Join-Path $testRoot 'captured-arguments.json'
$originalEnvironment = @{}
$environmentNames = @(
    'PATH',
    'APP_INSTALLER_NATIVE_PWSH',
    'APP_INSTALLER_NATIVE_CAPTURE_SCRIPT',
    'APP_INSTALLER_NATIVE_CAPTURE_PATH',
    'APP_INSTALLER_NATIVE_CAPTURE_EXIT_CODE'
)

foreach ($name in $environmentNames) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$tempPrefix = $tempBase.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) + [System.IO.Path]::DirectorySeparatorChar
if (-not $testRoot.StartsWith($tempPrefix, [System.StringComparison]::Ordinal)) {
    throw 'Temporary test files must stay inside the system temporary directory.'
}

try {
    New-Item -ItemType Directory -Path $fakeManagerRoot -Force | Out-Null
    $captureScript = @'
$capturedArguments = @($args)
$json = ConvertTo-Json -InputObject $capturedArguments -Compress
[System.IO.File]::WriteAllText($env:APP_INSTALLER_NATIVE_CAPTURE_PATH, $json, [System.Text.UTF8Encoding]::new($false))
Write-Output 'fake package manager output'
exit [int]$env:APP_INSTALLER_NATIVE_CAPTURE_EXIT_CODE
'@
    [System.IO.File]::WriteAllText($captureScriptPath, $captureScript, [System.Text.UTF8Encoding]::new($false))

    $fakeManagerContents = @'
#!/bin/sh
exec "$APP_INSTALLER_NATIVE_PWSH" -NoLogo -NoProfile -File "$APP_INSTALLER_NATIVE_CAPTURE_SCRIPT" "$@"
'@
    foreach ($managerName in @('apt', 'apt-get', 'brew', 'dnf', 'pacman', 'snap', 'sudo', 'winget', 'pwsh')) {
        $fakeManagerPath = Join-Path $fakeManagerRoot $managerName
        [System.IO.File]::WriteAllText($fakeManagerPath, $fakeManagerContents, [System.Text.UTF8Encoding]::new($false))
        & chmod +x $fakeManagerPath
        if ($LASTEXITCODE -ne 0) {
            throw ('Could not mark the temporary fake command executable: {0}' -f $managerName)
        }
    }

    $env:APP_INSTALLER_NATIVE_PWSH = (Get-Process -Id $PID -ErrorAction Stop).Path
    $env:APP_INSTALLER_NATIVE_CAPTURE_SCRIPT = $captureScriptPath
    $env:APP_INSTALLER_NATIVE_CAPTURE_PATH = $capturePath
    $env:APP_INSTALLER_NATIVE_CAPTURE_EXIT_CODE = '23'
    $env:PATH = $fakeManagerRoot + [System.IO.Path]::PathSeparator + $originalEnvironment.PATH

    $platformDetectPath = Join-Path $repositoryRoot 'platform-detect.ps1'
    . $platformDetectPath

    $expectedCoreModulePath = Join-Path (Join-Path $repositoryRoot 'modules') 'AppInstallerCore.psm1'
    Assert-Condition -Condition ([System.IO.Path]::GetFullPath($script:AppInstallerCorePath) -ceq [System.IO.Path]::GetFullPath($expectedCoreModulePath) -and (Test-Path -LiteralPath $script:AppInstallerCorePath -PathType Leaf)) -Message 'platform-detect resolves its shared module through native path semantics.'
    Assert-Condition -Condition ($script:Platform -ceq $ExpectedPlatform) -Message ('platform-detect.ps1 selects the native {0} host.' -f $ExpectedPlatform)
    $expectedManager = if ($ExpectedPlatform -ceq 'macOS') { 'brew' } else { 'apt' }
    Assert-Condition -Condition ($script:PackageManager -ceq $expectedManager) -Message ('The native host selects its expected fake package manager: {0}.' -f $expectedManager)

    if ($ExpectedPlatform -ceq 'macOS') {
        $packageCommand = Get-PackageManagerCommand -BrewCask 'native-test-cask'
        $expectedArguments = @('install', '--cask', 'native-test-cask')
    }
    else {
        $packageCommand = Get-PackageManagerCommand -AptPackage 'native-test-package'
        $expectedArguments = @('apt', 'install', '-y', 'native-test-package')
    }

    Assert-Condition -Condition ($packageCommand.IsValid -and $packageCommand.Status -ceq 'Ready') -Message 'The native package mapping produces a ready argument list.'
    $processResult = Invoke-PackageManagerProcess -Executable $packageCommand.Executable -Arguments $packageCommand.Arguments
    Assert-Condition -Condition ($processResult.ExitCode -eq 23 -and $processResult.ExecutablePath.StartsWith($fakeManagerRoot, [System.StringComparison]::Ordinal)) -Message 'The native process adapter resolves only the temporary fake executable and preserves its exit code.'
    Assert-Condition -Condition (($processResult.Output -join ' ') -match 'fake package manager output') -Message 'The native process adapter returns output from the fake executable.'

    $capturedArguments = @(Get-Content -LiteralPath $capturePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    if ($capturedArguments.Count -eq 1 -and $capturedArguments[0] -is [System.Array]) {
        $capturedArguments = @($capturedArguments[0])
    }
    $actualArgumentsJson = ConvertTo-Json -InputObject @($capturedArguments) -Compress
    $expectedArgumentsJson = ConvertTo-Json -InputObject @($expectedArguments) -Compress
    Assert-Condition -Condition ($actualArgumentsJson -ceq $expectedArgumentsJson) -Message ('Native argv is captured exactly: {0}' -f $actualArgumentsJson)

    $fakePwshCommand = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $fakePwshPath = if ($fakePwshCommand.Path) { $fakePwshCommand.Path } else { $fakePwshCommand.Source }
    Assert-Condition -Condition ($fakePwshPath.StartsWith($fakeManagerRoot, [System.StringComparison]::Ordinal)) -Message 'install.sh resolves only the temporary fake pwsh command.'

    $launcherRoot = Join-Path $testRoot 'source path with spaces'
    New-Item -ItemType Directory -Path $launcherRoot -Force | Out-Null
    $launcherPath = Join-Path $launcherRoot 'install.sh'
    $launcherCliPath = Join-Path $launcherRoot 'app-installer-cli.ps1'
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'install.sh') -Destination $launcherPath -ErrorAction Stop
    [System.IO.File]::WriteAllText($launcherCliPath, '# fake CLI target', [System.Text.UTF8Encoding]::new($false))

    Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
    $launcherArguments = @('--native-flag', 'argument with spaces')
    $launcherOutput = @(& bash $launcherPath @launcherArguments 2>&1)
    $launcherExitCode = $LASTEXITCODE
    Assert-Condition -Condition ($launcherExitCode -eq 23 -and ($launcherOutput -join "`n") -match 'Installer exited with code: 23' -and ($launcherOutput -join "`n") -notmatch 'Setup complete') -Message 'install.sh preserves the fake child exit code and does not claim completion.'

    $launcherCapturedArguments = @(Get-Content -LiteralPath $capturePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    if ($launcherCapturedArguments.Count -eq 1 -and $launcherCapturedArguments[0] -is [System.Array]) {
        $launcherCapturedArguments = @($launcherCapturedArguments[0])
    }
    $expectedLauncherArguments = @('-NoProfile', '-File', [System.IO.Path]::GetFullPath($launcherCliPath)) + $launcherArguments
    $launcherArgumentsJson = ConvertTo-Json -InputObject @($launcherCapturedArguments) -Compress
    $expectedLauncherArgumentsJson = ConvertTo-Json -InputObject @($expectedLauncherArguments) -Compress
    Assert-Condition -Condition ($launcherArgumentsJson -ceq $expectedLauncherArgumentsJson) -Message ('install.sh forwards native argv and the spaced target path exactly: {0}' -f $launcherArgumentsJson)

    Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
    $null = Invoke-InstallWhatIfBoundaryCheck -CliPath $cliPath
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) -Message 'CLI WhatIf does not invoke any package-manager fake.'

    Write-Output ('[OK] Native CLI boundary checks passed: platform={0}; version={1}; assertions={2}.' -f $ExpectedPlatform, $actualVersion, $script:assertionCount)
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedRoot.StartsWith($tempPrefix, [System.StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
