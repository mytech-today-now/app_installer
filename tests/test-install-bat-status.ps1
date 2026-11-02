#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourceBatchPath = Join-Path $repositoryRoot 'install.bat'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('app-installer-bat-status-' + [Guid]::NewGuid().ToString('N'))
$assertionCount = 0
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$failureMessage = 'PowerShell returned a failure status. Review the stage output; no full-success result is reported.'

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }

    $script:assertionCount++
}

function Write-TestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, $script:utf8NoBom)
}

function Invoke-BatchScenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('cmd', 'parent')][string]$Invocation,
        [Parameter(Mandatory = $true)][ValidateRange(0, 255)][int]$ChildExitCode,
        [switch]$WhatIf,
        [switch]$KeepConsoleOpen,
        [switch]$VerifyPauseOptIn
    )

    $batchPath = Join-Path $script:testRoot 'install.bat'
    $childStartedPath = Join-Path $script:testRoot ($Name + '-child-started.txt')
    $childFinishedPath = Join-Path $script:testRoot ($Name + '-child-finished.txt')
    $parentStatusPath = Join-Path $script:testRoot ($Name + '-parent-status.txt')
    $arguments = '-ForceCLI'
    if ($WhatIf) {
        $arguments += ' -WhatIf'
    }
    if ($KeepConsoleOpen) {
        $arguments += ' -KeepConsoleOpen'
    }

    if ($Invocation -eq 'parent') {
        $parentBatchPath = Join-Path $script:testRoot ($Name + '-parent.bat')
        $parentContent = @"
@echo off
call "$batchPath" $arguments
set "PARENT_RC=%ERRORLEVEL%"
>"$parentStatusPath" echo %PARENT_RC%
exit /b %PARENT_RC%
"@
        $parentContent = $parentContent -replace "`r?`n", "`r`n"
        Write-TestFile -Path $parentBatchPath -Content $parentContent
        $commandLine = '/d /c ""' + $parentBatchPath + '""'
    }
    else {
        $commandLine = '/d /c ""' + $batchPath + '" ' + $arguments + '"'
    }

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $env:ComSpec
    $processInfo.Arguments = $commandLine
    $processInfo.WorkingDirectory = $script:testRoot
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.EnvironmentVariables['TEMP'] = $script:testRoot
    $processInfo.EnvironmentVariables['TMP'] = $script:testRoot
    $processInfo.EnvironmentVariables['ProgramW6432'] = $script:runtimeRoot
    $processInfo.EnvironmentVariables['ProgramFiles'] = $script:runtimeRoot
    $processInfo.EnvironmentVariables['ProgramFiles(x86)'] = $script:testRoot
    $processInfo.EnvironmentVariables['LOCALAPPDATA'] = $script:testRoot
    $processInfo.EnvironmentVariables['FAKE_CHILD_EXIT_CODE'] = [string]$ChildExitCode
    $processInfo.EnvironmentVariables['FAKE_CHILD_STARTED_FILE'] = $childStartedPath
    $processInfo.EnvironmentVariables['FAKE_CHILD_FINISHED_FILE'] = $childFinishedPath

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    try {
        if (-not $process.Start()) {
            throw "Could not start isolated cmd.exe scenario '$Name'."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($VerifyPauseOptIn) {
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $childFinishedPath -PathType Leaf) -and -not $process.HasExited) {
                Start-Sleep -Milliseconds 50
            }

            if (-not (Test-Path -LiteralPath $childFinishedPath -PathType Leaf)) {
                throw "The fake PowerShell stage did not finish in the opt-in pause scenario '$Name'."
            }

            if ($process.WaitForExit(750)) {
                throw "The -KeepConsoleOpen scenario '$Name' returned before receiving a keypress."
            }

            $process.StandardInput.WriteLine()
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(10000)) {
                $process.Kill()
                [void]$process.WaitForExit(5000)
                throw "The -KeepConsoleOpen scenario '$Name' did not return after a keypress."
            }
        }
        else {
            if (-not $process.WaitForExit(15000)) {
                $process.Kill()
                [void]$process.WaitForExit(5000)
                $process.StandardInput.Close()
                throw "Unattended batch scenario '$Name' blocked instead of returning."
            }

            $process.StandardInput.Close()
        }

        $process.WaitForExit()
        $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
        $parentStatus = ''
        if (Test-Path -LiteralPath $parentStatusPath -PathType Leaf) {
            $parentStatus = [System.IO.File]::ReadAllText($parentStatusPath).Trim()
        }

        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Output = $output
            ParentStatus = $parentStatus
            ChildStarted = Test-Path -LiteralPath $childStartedPath -PathType Leaf
            ChildFinished = Test-Path -LiteralPath $childFinishedPath -PathType Leaf
        }
    }
    finally {
        if (-not $process.HasExited) {
            try { $process.Kill() } catch { }
        }
        $process.Dispose()
    }
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This command-processor regression requires Windows.'
    }

    $osVersion = [Environment]::OSVersion.Version
    if ($osVersion.Major -ne 10 -or $osVersion.Build -notin @(26200, 26300) -or -not [Environment]::Is64BitOperatingSystem) {
        throw ("This baseline requires a supported Windows 11 x64 client build (26200 or 26300); found {0} on {1}-bit Windows." -f $osVersion, $(if ([Environment]::Is64BitOperatingSystem) { 64 } else { 32 }))
    }

    $pwsh = Get-Command -Name 'pwsh.exe' -CommandType Application -ErrorAction Stop
    $pwshPath = [System.IO.Path]::GetFullPath($pwsh.Source)
    $requiredSuffix = '\PowerShell\7\pwsh.exe'
    if (-not $pwshPath.EndsWith($requiredSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "This baseline requires the supported fixed PowerShell Core location ending in '$requiredSuffix'."
    }

    $script:runtimeRoot = $pwshPath.Substring(0, $pwshPath.Length - $requiredSuffix.Length)
    if (-not (Test-Path -LiteralPath (Join-Path $script:runtimeRoot 'PowerShell\7\pwsh.exe') -PathType Leaf)) {
        throw 'The fixed PowerShell Core executable is unavailable for the isolated wrapper scenarios.'
    }
    if (-not (Test-Path -LiteralPath $sourceBatchPath -PathType Leaf)) {
        throw 'The repository install.bat file is missing.'
    }
    $startInstallerPath = Join-Path $repositoryRoot 'tools\Start-Installer.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $startInstallerAst = [System.Management.Automation.Language.Parser]::ParseFile($startInstallerPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw 'The shared PowerShell launcher has a parse error.'
    }
    $launcherParameterNames = @($startInstallerAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $keepConsoleParameterIndex = [Array]::IndexOf($launcherParameterNames, 'KeepConsoleOpen')
    $remainingArgumentsParameterIndex = [Array]::IndexOf($launcherParameterNames, 'InstallerArguments')
    Assert-Condition -Condition ($keepConsoleParameterIndex -ge 0 -and $keepConsoleParameterIndex -lt $remainingArgumentsParameterIndex) -Message 'The shared launcher consumes -KeepConsoleOpen before its remaining application arguments.'

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Copy-Item -LiteralPath $sourceBatchPath -Destination (Join-Path $testRoot 'install.bat')
    Write-TestFile -Path (Join-Path $testRoot 'app-installer.ps1') -Content '# Isolated entry-point placeholder.'
    Write-TestFile -Path (Join-Path $testRoot 'app-installer-cli.ps1') -Content '# Isolated entry-point placeholder.'

    $fakeStarter = @'
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$ForceCLI,
    [Parameter()]
    [switch]$KeepConsoleOpen,
    [Parameter(ValueFromRemainingArguments = $true)]
    [AllowEmptyCollection()]
    [string[]]$InstallerArguments = @()
)

$startedPath = [string]$env:FAKE_CHILD_STARTED_FILE
$finishedPath = [string]$env:FAKE_CHILD_FINISHED_FILE
$bootstrapMarker = [string]$env:APP_INSTALLER_BOOTSTRAP_STARTED_FILE
if (-not [string]::IsNullOrWhiteSpace($bootstrapMarker)) {
    [System.IO.File]::WriteAllText($bootstrapMarker, 'STARTED')
}
if (-not [string]::IsNullOrWhiteSpace($startedPath)) {
    [System.IO.File]::WriteAllText($startedPath, 'STARTED')
}
[Console]::Out.WriteLine('FAKE POWERSHELL STAGE')
$exitCode = [int]$env:FAKE_CHILD_EXIT_CODE
if (-not [string]::IsNullOrWhiteSpace($finishedPath)) {
    [System.IO.File]::WriteAllText($finishedPath, 'FINISHED')
}
exit $exitCode
'@
    $fakeStarter = $fakeStarter -replace "`r?`n", "`r`n"
    Write-TestFile -Path (Join-Path $testRoot 'tools\Start-Installer.ps1') -Content $fakeStarter

    foreach ($invocation in @('cmd', 'parent')) {
        foreach ($childExitCode in @(0, 1, 23)) {
            $name = '{0}-{1}' -f $invocation, $childExitCode
            $result = Invoke-BatchScenario -Name $name -Invocation $invocation -ChildExitCode $childExitCode
            Assert-Condition -Condition ($result.ChildStarted -and $result.ChildFinished) -Message "The fake PowerShell stage ran in the $name scenario."
            Assert-Condition -Condition ($result.ExitCode -eq $childExitCode) -Message "The $invocation invocation returned the exact child exit code $childExitCode (received $($result.ExitCode))."
            if ($invocation -eq 'parent') {
                Assert-Condition -Condition ($result.ParentStatus -eq [string]$childExitCode) -Message "The parent batch captured the exact child exit code $childExitCode (received '$($result.ParentStatus)')."
            }

            Assert-Condition -Condition (-not $result.Output.Contains('Press any key to continue')) -Message "The unattended $name scenario did not print or wait at a pause prompt."
            Assert-Condition -Condition (-not $result.Output.Contains($testRoot) -and $result.Output -notmatch 'app-installer-bootstrap-[^\s]+\.(status|err)') -Message "The $name status output does not disclose temporary paths."
            if ($childExitCode -eq 0) {
                Assert-Condition -Condition ($result.Output.Contains('[INFO] Setup complete.') -and -not $result.Output.Contains($failureMessage)) -Message "The $name scenario reports full success only for exit code 0."
            }
            else {
                Assert-Condition -Condition ($result.Output.Contains($failureMessage) -and $result.Output.Contains("[ERROR] Exit code: $childExitCode") -and -not $result.Output.Contains('Setup complete.')) -Message "The $name failure reports its code without a full-success message."
            }
        }
    }

    $whatIfSuccess = Invoke-BatchScenario -Name 'whatif-success' -Invocation cmd -ChildExitCode 0 -WhatIf
    Assert-Condition -Condition ($whatIfSuccess.ExitCode -eq 0 -and $whatIfSuccess.Output.Contains('WhatIf completed without creating bootstrap status files') -and -not $whatIfSuccess.Output.Contains('Setup complete.')) -Message 'The WhatIf path reports preflight completion only after a successful child status.'
    $whatIfFailure = Invoke-BatchScenario -Name 'whatif-failure' -Invocation cmd -ChildExitCode 23 -WhatIf
    Assert-Condition -Condition ($whatIfFailure.ExitCode -eq 23 -and $whatIfFailure.Output.Contains($failureMessage) -and $whatIfFailure.Output.Contains('[ERROR] Exit code: 23') -and -not $whatIfFailure.Output.Contains('WhatIf completed') -and -not $whatIfFailure.Output.Contains('Setup complete.')) -Message 'The WhatIf path preserves a nonzero child status without reporting completion.'

    $pauseResult = Invoke-BatchScenario -Name 'opt-in-pause' -Invocation cmd -ChildExitCode 0 -KeepConsoleOpen -VerifyPauseOptIn
    Assert-Condition -Condition ($pauseResult.ExitCode -eq 0 -and $pauseResult.Output.Contains('[INFO] Setup complete.')) -Message 'The explicit -KeepConsoleOpen switch waits for input, then returns successful status.'
    $pauseFailure = Invoke-BatchScenario -Name 'opt-in-pause-failure' -Invocation cmd -ChildExitCode 23 -KeepConsoleOpen -VerifyPauseOptIn
    Assert-Condition -Condition ($pauseFailure.ExitCode -eq 23 -and $pauseFailure.Output.Contains($failureMessage) -and $pauseFailure.Output.Contains('[ERROR] Exit code: 23') -and -not $pauseFailure.Output.Contains('Setup complete.')) -Message 'The explicit pause keeps failure output visible and still returns the exact nonzero status.'

    Write-Host "[OK] $assertionCount install.bat status and pause assertions passed on Windows build $($osVersion.Build)." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and $resolvedTestRoot -like '*app-installer-bat-status-*') {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
