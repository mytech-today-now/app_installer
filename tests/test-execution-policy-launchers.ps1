#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$policyFallback = 'PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator.'
$signingGuide = 'https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5'
$assertionCount = 0

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
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Get-PolicySnapshot {
    return (Get-ExecutionPolicy -List | ForEach-Object {
        '{0}={1}' -f $_.Scope, $_.ExecutionPolicy
    }) -join ';'
}

function Invoke-BatchLauncher {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchPath,
        [Parameter(Mandatory = $true)]
        [string]$TestRoot,
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [string]$ProcessPolicy
    )

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $runnerPath = Join-Path $TestRoot ('invoke-' + $Mode + '.bat')
    Set-Content -LiteralPath $runnerPath -Value @'
@echo off
call "%~dp0install.bat" --test-flag "two words"
exit /b %ERRORLEVEL%
'@ -Encoding ASCII

    $processInfo.FileName = $env:ComSpec
    $processInfo.Arguments = '/d /c ""' + $runnerPath + '""'
    $processInfo.WorkingDirectory = $TestRoot
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $realPwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $processInfo.EnvironmentVariables['PATH'] = (Split-Path -Parent $realPwsh) + ';' + $env:PATH
    $processInfo.EnvironmentVariables['FAKE_PWSH_MODE'] = $Mode
    $processInfo.EnvironmentVariables['FAKE_PWSH_LOG'] = Join-Path $TestRoot 'fake-pwsh-arguments.txt'

    if ($ProcessPolicy) {
        $processInfo.EnvironmentVariables['PSExecutionPolicyPreference'] = $ProcessPolicy
    }
    else {
        [void]$processInfo.EnvironmentVariables.Remove('PSExecutionPolicyPreference')
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw 'Could not start the isolated cmd.exe wrapper test.'
    }

    $process.StandardInput.WriteLine()
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(90000)) {
        $process.Kill()
        throw 'The isolated batch wrapper test did not exit within 20 seconds.'
    }

    $exitCode = $process.ExitCode
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.Dispose()

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $standardOutput + $standardError
    }
}

try {
    $readme = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'README.md')
    $instructions = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'instructions.html')
    $help = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'app-installer.ps1')
    $batch = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'install.bat')
    $shell = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'install.sh')
    $scheduledUpdater = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'app-installer-cli.ps1')
    $ooshutupHelper = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'modules\OOShutUp10Trust.psm1')
    $hostsHelper = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'apps\hosts.ps1')
    $restorePointsHelper = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'apps\managerestorepoints.ps1')
    $remoteHelperTrust = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'modules\RemotePowerShellTrust.psm1')
    $applicationSources = $help + (Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'app-installer-cli.ps1'))

    Assert-Condition -Condition (($readme + $help) -notmatch '(?im)Set-ExecutionPolicy\s+-Scope\s+CurrentUser\s+-ExecutionPolicy\s+Unrestricted') -Message 'README and PowerShell help do not recommend persistent CurrentUser Unrestricted.'
    Assert-Condition -Condition ($readme -match '(?i)Do not use\s+`?Unblock-File`?\s+or a policy change as a substitute' -and $readme -notmatch '(?i)Unblock the EXE|Run anyway') -Message 'README rejects unblocking or policy changes as substitutes for verification.'
    Assert-Condition -Condition ($batch -notmatch '(?i)-ExecutionPolicy\s+Bypass') -Message 'The Windows launcher does not override execution policy.'
    Assert-Condition -Condition ($shell -notmatch '(?i)-ExecutionPolicy\s+Bypass') -Message 'The POSIX launcher does not override execution policy.'
    Assert-Condition -Condition (($scheduledUpdater + $ooshutupHelper) -notmatch '(?i)-ExecutionPolicy\s+Bypass') -Message 'Scheduled and verified child launches do not override execution policy.'
    Assert-Condition -Condition (($hostsHelper + $restorePointsHelper + $remoteHelperTrust) -notmatch '(?i)-ExecutionPolicy\s+Bypass') -Message 'Hosts and restore-point helper launches do not override execution policy.'
    Assert-Condition -Condition (($hostsHelper + $restorePointsHelper + $remoteHelperTrust) -notmatch '(?i)-ExecutionPolicy\b') -Message 'Hosts and restore-point production sources contain no process-level policy option.'
    Assert-Condition -Condition (($hostsHelper + $restorePointsHelper + $remoteHelperTrust) -notmatch 'Invoke-Expression') -Message 'Hosts and restore-point helpers do not evaluate downloaded PowerShell text.'
    Assert-Condition -Condition ($applicationSources -notmatch '(?i)\bUnblock-File\b' -and $applicationSources -notmatch '(?i)-ExecutionPolicy\s+Bypass') -Message 'Application entrypoints preserve file blocking marks and never bypass execution policy.'
    Assert-Condition -Condition ($hostsHelper.Contains('-NoProfile -File') -and $hostsHelper.Contains('Hosts File Manager.lnk')) -Message 'The hosts shortcut uses a direct file launch and keeps its existing name.'
    Assert-Condition -Condition ($restorePointsHelper.Contains('-NoProfile -File') -and $restorePointsHelper.Contains('-Action List') -and $restorePointsHelper.Contains('Manage Restore Points.lnk')) -Message 'The restore-point shortcut uses a direct file launch and keeps List behavior.'
    Assert-Condition -Condition (($batch + $shell + $help) -notmatch '(?im)Set-ExecutionPolicy\b') -Message 'The documented launch path does not write PowerShell policy settings.'
    Assert-Condition -Condition (($instructions -notmatch '(?im)Set-ExecutionPolicy\b') -and (($readme + $instructions) -notmatch '(?im)(?:powershell|pwsh)(?:\.exe)?\s+[^\r\n]*\s+-ExecutionPolicy\b')) -Message 'User documentation does not recommend writing policy settings or passing a process policy override.'
    Assert-Condition -Condition ($batch -match '(?s)-NoProfile\s+-File[^\r\n]*%\*') -Message 'The Windows launcher still invokes the script directly and forwards arguments.'
    Assert-Condition -Condition ($shell -match '(?s)-NoProfile\s+-File[^\r\n]*"\$@"') -Message 'The POSIX launcher still invokes the script directly and forwards arguments.'
    Assert-Condition -Condition ($batch -match '(?i)if not exist "%~dp0app-installer\.ps1"' -and $shell -match '(?i)\[\[ ! -f "\$SCRIPT_DIR/app-installer-cli\.ps1" \]\]') -Message 'Both wrappers fail clearly when their target script is missing.'
    Assert-Condition -Condition ($readme.Contains('Get-AuthenticodeSignature') -and $readme.Contains($signingGuide)) -Message 'README documents Authenticode verification and links to Microsoft signing guidance.'
    Assert-Condition -Condition (($batch.Contains($policyFallback)) -and ($shell.Contains($policyFallback)) -and ($readme.Contains($policyFallback))) -Message 'Both launchers and the README provide the required policy-block fallback.'

    if ($env:OS -eq 'Windows_NT' -and (Get-Command cmd.exe -ErrorAction SilentlyContinue) -and (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
        $policyBefore = Get-PolicySnapshot
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('app-installer-policy-test-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null

        try {
            Copy-Item -LiteralPath (Join-Path $repoRoot 'install.bat') -Destination (Join-Path $testRoot 'install.bat')
            Copy-Item -LiteralPath (Join-Path $repoRoot 'compatibility.json') -Destination (Join-Path $testRoot 'compatibility.json')
            New-Item -ItemType Directory -Path (Join-Path $testRoot 'modules') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $testRoot 'tools') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $repoRoot 'modules\InstallerCompatibility.psm1') -Destination (Join-Path $testRoot 'modules')
            Copy-Item -LiteralPath (Join-Path $repoRoot 'modules\InstallerRuntimeDiscovery.psm1') -Destination (Join-Path $testRoot 'modules')
            Copy-Item -LiteralPath (Join-Path $repoRoot 'modules\InstallerPrerequisitePlan.psm1') -Destination (Join-Path $testRoot 'modules')
            Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\Start-Installer.ps1') -Destination (Join-Path $testRoot 'tools')
            Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\Test-InstallerCompatibility.ps1') -Destination (Join-Path $testRoot 'tools')
            $targetScript = @'
[System.IO.File]::WriteAllText($env:FAKE_PWSH_LOG, ($args -join '|'))
if ($env:FAKE_PWSH_MODE -eq 'gpo-simulated') {
    [Console]::Error.WriteLine('File is blocked because it is not digitally signed under simulated Group Policy.')
    exit 1
}
if ($env:FAKE_PWSH_MODE -eq 'nonzero') {
    exit 23
}
Write-Output 'isolated installer test target ran'
exit 0
'@
            $targetPath = Join-Path $testRoot 'app-installer.ps1'
            Set-Content -LiteralPath $targetPath -Value $targetScript -Encoding UTF8
            $batchPath = Join-Path $testRoot 'install.bat'

            Remove-Item -LiteralPath $targetPath -Force
            $missingRun = Invoke-BatchLauncher -BatchPath $batchPath -TestRoot $testRoot -Mode 'missing'
            Assert-Condition -Condition ($missingRun.ExitCode -eq 2 -and $missingRun.Output.Contains('App Installer script was not found') -and -not $missingRun.Output.Contains('Setup complete.')) -Message 'The Windows launcher reports a missing script and returns failure.'
            Set-Content -LiteralPath $targetPath -Value $targetScript -Encoding UTF8

            $failedRun = Invoke-BatchLauncher -BatchPath $batchPath -TestRoot $testRoot -Mode 'nonzero'
            $argumentLogPath = Join-Path $testRoot 'fake-pwsh-arguments.txt'
            $argumentLog = if (Test-Path -LiteralPath $argumentLogPath -PathType Leaf) { Get-Content -Raw -LiteralPath $argumentLogPath } else { '' }
            Assert-Condition -Condition ($failedRun.ExitCode -eq 23 -and $failedRun.Output.Contains('Installer exited with code: 23') -and -not $failedRun.Output.Contains('Setup complete.')) -Message ("A failed child launch returns its nonzero status and does not claim success (exit {0}; output: {1})." -f $failedRun.ExitCode, $failedRun.Output.Trim())
            Assert-Condition -Condition ($argumentLog -eq '--test-flag|two words') -Message 'The Windows launcher forwards arguments to the PowerShell script unchanged.'

            $gpoRun = Invoke-BatchLauncher -BatchPath $batchPath -TestRoot $testRoot -Mode 'gpo-simulated'
            Assert-Condition -Condition ($gpoRun.ExitCode -ne 0 -and $gpoRun.Output.Contains($policyFallback) -and $gpoRun.Output.Contains($signingGuide) -and -not $gpoRun.Output.Contains('Setup complete.')) -Message ("A simulated Group Policy denial displays the fallback and returns failure (exit {0}; output: {1})." -f $gpoRun.ExitCode, $gpoRun.Output.Trim())

            $restrictedRun = Invoke-BatchLauncher -BatchPath $batchPath -TestRoot $testRoot -Mode 'restrictive-process' -ProcessPolicy 'AllSigned'
            Assert-Condition -Condition ($restrictedRun.ExitCode -ne 0 -and $restrictedRun.Output.Contains($policyFallback) -and -not $restrictedRun.Output.Contains('Setup complete.')) -Message ("A restrictive process-scoped policy blocks an unsigned script without a bypass (exit {0}; output: {1})." -f $restrictedRun.ExitCode, $restrictedRun.Output.Trim())
            Assert-Condition -Condition ($restrictedRun.Output -notmatch '(?i)winget|brew install|apt-get install|dnf install|pacman -S') -Message 'Wrapper integration checks did not run a package manager.'

        }
        finally {
            $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
            if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Assert-Condition -Condition ((Get-PolicySnapshot) -eq $policyBefore) -Message 'Get-ExecutionPolicy -List is unchanged after default, restrictive, and simulated Group Policy launch checks.'
    }
    else {
        Write-Host '[SKIP] Windows batch integration requires cmd.exe and pwsh.exe.' -ForegroundColor Yellow
    }

    Write-Host "[OK] $assertionCount execution-policy launcher assertions passed." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
