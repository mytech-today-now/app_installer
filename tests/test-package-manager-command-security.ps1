#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$platformDetectPath = Join-Path $repoRoot 'platform-detect.ps1'
$manifestPath = Join-Path $repoRoot 'apps-manifest.json'
$assertionCount = 0
$script:QuietAssertions = $false

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }

    $script:assertionCount++
    if (-not $script:QuietAssertions) {
        Write-Host "[PASS] $Message" -ForegroundColor Green
    }
}

function Assert-ArgumentList {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Actual,

        [Parameter(Mandatory = $true)]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    Assert-Condition -Condition ($Actual.Count -eq $Expected.Count) -Message "$Context argument count is exact"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-Condition -Condition ($Actual[$index] -ceq $Expected[$index]) -Message "$Context argument $index is exact"
    }
}

function Invoke-TestInstall {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Packages
    )

    $records = @(& {
            Install-CrossPlatformApp -AppName 'Test package' `
                -WingetId $Packages.winget `
                -BrewCask $Packages.brewCask `
                -BrewFormula $Packages.brewFormula `
                -AptPackage $Packages.apt `
                -DnfPackage $Packages.dnf `
                -PacmanPackage $Packages.pacman `
                -SnapPackage $Packages.snap
        } 6>&1)

    $resultCode = $records | Where-Object { $_ -is [int] } | Select-Object -Last 1
    $displayText = ($records | ForEach-Object {
            if ($_ -is [System.Management.Automation.InformationRecord]) {
                [string]$_.MessageData
            }
            else {
                [string]$_
            }
        }) -join "`n"

    return [pscustomobject]@{
        ResultCode = $resultCode
        DisplayText = $displayText
    }
}

function Set-TestManifest {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('app installer command tests ' + [guid]::NewGuid().ToString('N'))
$fakeManagerRoot = Join-Path $testRoot 'fake manager path with spaces'
$captureScriptPath = Join-Path $fakeManagerRoot 'capture-arguments.ps1'
$testManifestPath = Join-Path $testRoot 'apps-manifest-test-copy.json'
$capturePath = Join-Path $testRoot 'captured-arguments.json'
$markerPath = Join-Path $testRoot 'injection marker.txt'
$oldPath = $env:PATH
$oldPathExt = $env:PATHEXT
$oldCapturePath = $env:PACKAGE_MANAGER_CAPTURE_PATH
$oldCaptureCode = $env:PACKAGE_MANAGER_CAPTURE_EXIT_CODE
$oldTestPwsh = $env:PACKAGE_MANAGER_TEST_PWSH
$oldCaptureScript = $env:PACKAGE_MANAGER_TEST_CAPTURE_SCRIPT
$oldPlatform = $null
$oldPackageManager = $null

try {
    New-Item -Path $fakeManagerRoot -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination $testManifestPath

    $script:PackageManager = $null
    . $platformDetectPath
    $oldPlatform = $script:Platform
    $oldPackageManager = $script:PackageManager

    $pwshPath = (Get-Process -Id $PID).Path
    $env:PACKAGE_MANAGER_TEST_PWSH = $pwshPath
    $env:PACKAGE_MANAGER_TEST_CAPTURE_SCRIPT = $captureScriptPath

    Set-Content -LiteralPath $captureScriptPath -Encoding UTF8 -Value @'
$capturedArguments = @($args)
$json = ConvertTo-Json -InputObject $capturedArguments -Compress
[System.IO.File]::WriteAllText($env:PACKAGE_MANAGER_CAPTURE_PATH, $json, [System.Text.UTF8Encoding]::new($false))
Write-Output 'fake manager output'
exit [int]$env:PACKAGE_MANAGER_CAPTURE_EXIT_CODE
'@

    if ($IsWindows -or $env:OS -match 'Windows') {
        $fakeManagerExtension = '.cmd'
        $env:PATHEXT = '.CMD;' + $oldPathExt
        $fakeManagerContents = @'
@echo off
"%PACKAGE_MANAGER_TEST_PWSH%" -NoLogo -NoProfile -File "%PACKAGE_MANAGER_TEST_CAPTURE_SCRIPT%" %*
exit /b %ERRORLEVEL%
'@
    }
    else {
        $fakeManagerExtension = ''
        $fakeManagerContents = @'
#!/bin/sh
exec "$PACKAGE_MANAGER_TEST_PWSH" -NoLogo -NoProfile -File "$PACKAGE_MANAGER_TEST_CAPTURE_SCRIPT" "$@"
'@
    }

    foreach ($name in @('winget', 'brew', 'sudo')) {
        $fakeManagerPath = Join-Path $fakeManagerRoot ($name + $fakeManagerExtension)
        Set-Content -LiteralPath $fakeManagerPath -Value $fakeManagerContents -Encoding ASCII
        if (-not $fakeManagerExtension) {
            & chmod +x $fakeManagerPath
            if ($LASTEXITCODE -ne 0) {
                throw 'Could not mark the fake package manager executable for the test.'
            }
        }
    }

    $pathSeparator = [string][IO.Path]::PathSeparator
    $env:PATH = $fakeManagerRoot + $pathSeparator + $oldPath
    $env:PACKAGE_MANAGER_CAPTURE_EXIT_CODE = '23'

    $originalManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $testManifest = Get-Content -LiteralPath $testManifestPath -Raw | ConvertFrom-Json
    $appRows = @(
        [pscustomobject]@{ Platform = 'Windows'; Manager = 'winget'; AppName = '7zip'; Field = 'WingetId'; ManifestField = 'winget'; Expected = @('install', '--id', '7zip.7zip', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--force') },
        [pscustomobject]@{ Platform = 'macOS'; Manager = 'brew'; AppName = '7zip'; Field = 'BrewCask'; ManifestField = 'brewCask'; Expected = @('install', '--cask', 'the-unarchiver') },
        [pscustomobject]@{ Platform = 'macOS'; Manager = 'brew'; AppName = 'php'; Field = 'BrewFormula'; ManifestField = 'brewFormula'; Expected = @('install', 'php') },
        [pscustomobject]@{ Platform = 'Linux'; Manager = 'apt'; AppName = '7zip'; Field = 'AptPackage'; ManifestField = 'apt'; Expected = @('apt', 'install', '-y', 'p7zip-full') },
        [pscustomobject]@{ Platform = 'Linux'; Manager = 'dnf'; AppName = '7zip'; Field = 'DnfPackage'; ManifestField = 'dnf'; Expected = @('dnf', 'install', '-y', 'p7zip') },
        [pscustomobject]@{ Platform = 'Linux'; Manager = 'pacman'; AppName = '7zip'; Field = 'PacmanPackage'; ManifestField = 'pacman'; Expected = @('pacman', '-S', '--noconfirm', 'p7zip') },
        [pscustomobject]@{ Platform = 'Linux'; Manager = 'snap'; AppName = '7zip'; Field = 'SnapPackage'; ManifestField = 'snap'; Expected = @('snap', 'install', 'p7zip-desktop') }
    )

    # Confirm every current manifest package value satisfies the selected manager grammar.
    $script:PackageManager = 'unsupported-test-manager'
    $script:QuietAssertions = $true
    foreach ($app in $originalManifest.apps) {
        $mapping = $app.packages
        $check = Get-PackageManagerCommand `
            -WingetId $mapping.winget `
            -BrewCask $mapping.brewCask `
            -BrewFormula $mapping.brewFormula `
            -AptPackage $mapping.apt `
            -DnfPackage $mapping.dnf `
            -PacmanPackage $mapping.pacman `
            -SnapPackage $mapping.snap
        Assert-Condition -Condition ($check.IsValid -and $check.Status -eq 'Unavailable') -Message "Manifest package IDs are valid for $($app.name)"
    }
    $script:QuietAssertions = $false
    Write-Host "[PASS] Package IDs are valid across all $($originalManifest.apps.Count) manifest entries" -ForegroundColor Green

    # Exercise each adapter through a fake executable found earlier on PATH.
    $script:QuietAssertions = $true
    foreach ($testCase in $appRows) {
        $script:Platform = $testCase.Platform
        $script:PackageManager = $testCase.Manager
        $app = $testManifest.apps | Where-Object { $_.name -eq $testCase.AppName } | Select-Object -First 1

        Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
        $env:PACKAGE_MANAGER_CAPTURE_PATH = $capturePath
        $run = Invoke-TestInstall -Packages $app.packages

        Assert-Condition -Condition ($run.ResultCode -eq 23) -Message "$($testCase.Manager) adapter preserves the fake process exit code"
        Assert-Condition -Condition (Test-Path -LiteralPath $capturePath) -Message "$($testCase.Manager) adapter invokes only the fake executable"
        $actualArguments = @(Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json)
        Assert-ArgumentList -Actual $actualArguments -Expected $testCase.Expected -Context $testCase.Manager
        Assert-Condition -Condition ($run.DisplayText.Contains('fake manager output')) -Message "$($testCase.Manager) native output remains available for diagnostics"
    }
    $script:QuietAssertions = $false
    Write-Host '[PASS] All manager adapters captured exact argv, native output, and exit status' -ForegroundColor Green

    # The process helper exposes a structured status, exit code, and native output.
    $script:Platform = 'Windows'
    $script:PackageManager = 'winget'
    $env:PACKAGE_MANAGER_CAPTURE_PATH = $capturePath
    $processResult = Invoke-PackageManagerProcess -Executable 'winget' -Arguments @('install', '--id', '7zip.7zip')
    Assert-Condition -Condition ($processResult.Status -eq 'Failed') -Message 'Nonzero fake process status is structured as failed'
    Assert-Condition -Condition ($processResult.ExitCode -eq 23) -Message 'Structured process result preserves the nonzero exit code'
    Assert-Condition -Condition (@($processResult.Output | Where-Object { [string]$_ -match 'fake manager output' }).Count -gt 0) -Message 'Structured process result retains native output'
    $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    if ($nativePreference) {
        $oldNativePreference = $nativePreference.Value
        $global:PSNativeCommandUseErrorActionPreference = $true
        try {
            $processResult = Invoke-PackageManagerProcess -Executable 'winget' -Arguments @('install', '--id', '7zip.7zip')
        }
        finally {
            $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference
        }
        Assert-Condition -Condition ($processResult.Status -eq 'Failed' -and $processResult.ExitCode -eq 23) -Message 'Native error preference does not hide a package manager exit code'
    }

    # A copy of the manifest is mutated for hostile values; production data is never changed.
    $dangerousValues = @(
        'bad package',
        "bad'quote",
        'bad"quote',
        'bad&echo marker',
        "bad`nnewline",
        "bad'; Set-Content -LiteralPath '$markerPath' -Value 'created'; '",
        "bad; touch '$markerPath'"
    )

    $script:QuietAssertions = $true
    foreach ($testCase in $appRows) {
        foreach ($dangerousValue in $dangerousValues) {
            $fixture = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $app = $fixture.apps | Where-Object { $_.name -eq $testCase.AppName } | Select-Object -First 1
            $app.packages | Add-Member -MemberType NoteProperty -Name $testCase.ManifestField -Value $dangerousValue -Force
            Set-TestManifest -Manifest $fixture -Path $testManifestPath
            $fixtureCopy = Get-Content -LiteralPath $testManifestPath -Raw | ConvertFrom-Json
            $mutatedApp = $fixtureCopy.apps | Where-Object { $_.name -eq $testCase.AppName } | Select-Object -First 1

            $script:Platform = $testCase.Platform
            $script:PackageManager = $testCase.Manager
            Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
            $env:PACKAGE_MANAGER_CAPTURE_PATH = $capturePath
            $run = Invoke-TestInstall -Packages $mutatedApp.packages

            Assert-Condition -Condition ($run.ResultCode -eq 1) -Message "$($testCase.Field) rejects unsafe mapping data"
            Assert-Condition -Condition ($run.DisplayText.Contains('This package entry is invalid. No package command was run.')) -Message "$($testCase.Field) shows the required invalid-entry message"
            Assert-Condition -Condition (-not (Test-Path -LiteralPath $capturePath)) -Message "$($testCase.Field) starts no package manager for an invalid value"
            Assert-Condition -Condition (-not (Test-Path -LiteralPath $markerPath)) -Message "$($testCase.Field) creates no injection marker"
        }
    }
    $script:QuietAssertions = $false
    Write-Host "[PASS] Unsafe token matrix rejected across $($appRows.Count) mappings and $($dangerousValues.Count) payloads" -ForegroundColor Green

    # Unsupported and missing mappings return a structured unavailable result without an empty invocation.
    $script:PackageManager = 'winget'
    $unavailable = Get-PackageManagerCommand -WingetId $null
    Assert-Condition -Condition ($unavailable.Status -eq 'Unavailable' -and -not $unavailable.Available) -Message 'Missing package mapping returns structured unavailable status'
    Assert-Condition -Condition ($unavailable.Arguments.Count -eq 0 -and -not $unavailable.Executable) -Message 'Unavailable mapping has no executable or arguments'
    $script:PackageManager = 'unsupported-test-manager'
    $unsupported = Get-PackageManagerCommand -WingetId '7zip.7zip'
    Assert-Condition -Condition ($unsupported.Status -eq 'Unavailable' -and $unsupported.Arguments.Count -eq 0) -Message 'Unsupported manager returns unavailable without an empty command'

    # The helper validates non-string mapping types before they can be coerced into package tokens.
    $script:PackageManager = 'winget'
    $nonString = Get-PackageManagerCommand -WingetId @('7zip.7zip', 'another-token')
    Assert-Condition -Condition ($nonString.Status -eq 'InvalidMapping') -Message 'Non-string package mapping is rejected'

    $missingExecutable = Invoke-PackageManagerProcess -Executable ('missing-manager-' + [guid]::NewGuid().ToString('N')) -Arguments @('install', '7zip.7zip')
    Assert-Condition -Condition ($missingExecutable.Status -eq 'Unavailable' -and $null -eq $missingExecutable.ExitCode) -Message 'Missing package manager executable returns unavailable without execution'
    Assert-Condition -Condition ($missingExecutable.Diagnostic -eq 'The package manager executable is unavailable.') -Message 'Missing executable diagnostic is sanitized'

    $rowWithoutManager = $originalManifest.apps | Where-Object { $_.name -eq '7zip' } | Select-Object -First 1
    $invalidWithoutManager = [pscustomobject]@{
        winget = 'bad package'
        brewCask = $rowWithoutManager.packages.brewCask
        brewFormula = $rowWithoutManager.packages.brewFormula
        apt = $rowWithoutManager.packages.apt
        dnf = $rowWithoutManager.packages.dnf
        pacman = $rowWithoutManager.packages.pacman
        snap = $rowWithoutManager.packages.snap
    }
    $script:Platform = 'Windows'
    $script:PackageManager = $null
    Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
    $env:PACKAGE_MANAGER_CAPTURE_PATH = $capturePath
    $invalidRun = Invoke-TestInstall -Packages $invalidWithoutManager
    Assert-Condition -Condition ($invalidRun.ResultCode -eq 1) -Message 'Invalid package data fails even when no manager is detected'
    Assert-Condition -Condition ($invalidRun.DisplayText.Contains('This package entry is invalid. No package command was run.')) -Message 'No-manager invalid mapping shows the required fallback'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $capturePath)) -Message 'No-manager invalid mapping launches no executable'

    $source = Get-Content -LiteralPath $platformDetectPath -Raw
    Assert-Condition -Condition (-not $source.Contains('Invoke-Expression')) -Message 'Platform helper contains no Invoke-Expression execution path'
    Assert-Condition -Condition ($source -notmatch '(?im)\bbash\s+-c\b') -Message 'Platform helper contains no bash -c execution path'

    Write-Host "`nPackage command security checks passed: $assertionCount assertions" -ForegroundColor Green
}
finally {
    $env:PATH = $oldPath
    if ($null -eq $oldPathExt) {
        Remove-Item Env:PATHEXT -ErrorAction SilentlyContinue
    }
    else {
        $env:PATHEXT = $oldPathExt
    }

    foreach ($envName in @('PACKAGE_MANAGER_CAPTURE_PATH', 'PACKAGE_MANAGER_CAPTURE_EXIT_CODE', 'PACKAGE_MANAGER_TEST_PWSH', 'PACKAGE_MANAGER_TEST_CAPTURE_SCRIPT')) {
        $originalValue = switch ($envName) {
            'PACKAGE_MANAGER_CAPTURE_PATH' { $oldCapturePath }
            'PACKAGE_MANAGER_CAPTURE_EXIT_CODE' { $oldCaptureCode }
            'PACKAGE_MANAGER_TEST_PWSH' { $oldTestPwsh }
            'PACKAGE_MANAGER_TEST_CAPTURE_SCRIPT' { $oldCaptureScript }
        }
        if ($null -eq $originalValue) {
            Remove-Item -LiteralPath "Env:$envName" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -LiteralPath "Env:$envName" -Value $originalValue
        }
    }

    if ($null -ne $oldPlatform) {
        $script:Platform = $oldPlatform
    }
    if ($null -ne $oldPackageManager) {
        $script:PackageManager = $oldPackageManager
    }

    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
