#Requires -Version 5.1

$ErrorActionPreference = 'Stop'


function ConvertTo-WindowsCommandLineArgument {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            if ($backslashCount -gt 0) {
                [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            }
            else {
                [void]$builder.Append('\')
            }
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-NativeErrorCode {
    param([System.Exception]$Exception)

    $currentException = $Exception
    while ($null -ne $currentException) {
        if ($currentException -is [System.ComponentModel.Win32Exception]) {
            return $currentException.NativeErrorCode
        }
        $currentException = $currentException.InnerException
    }

    return 0
}

function Invoke-ElevatedInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments
    )

    if ($Arguments.Count -lt 1 -or [string]::IsNullOrWhiteSpace($Arguments[0])) {
        [Console]::Error.WriteLine('[ERROR] The batch installer path was not supplied; elevation could not be started.')
        return 2
    }

    $batchPath = $Arguments[0]
    $installerArguments = @()
    if ($Arguments.Count -gt 1) {
        $installerArguments = @($Arguments | Select-Object -Skip 1)
    }

    $argumentLine = ($installerArguments | ForEach-Object {
        ConvertTo-WindowsCommandLineArgument -Argument $_
    }) -join ' '

    $startParameters = @{
        FilePath     = $batchPath
        Verb         = 'RunAs'
        PassThru     = $true
        ErrorAction  = 'Stop'
    }
    if ($argumentLine.Length -gt 0) {
        $startParameters.ArgumentList = $argumentLine
    }

    try {
        $elevatedProcess = Start-Process @startParameters
    }
    catch {
        $nativeErrorCode = Get-NativeErrorCode -Exception $_.Exception
        if ($nativeErrorCode -eq 1223 -or $_.Exception.ToString() -match '(?i)canceled by the user|cancelled by the user') {
            [Console]::Error.WriteLine('[ERROR] Administrator elevation was declined or canceled. The installer was not confirmed as started.')
            return 1223
        }

        [Console]::Error.WriteLine(('[ERROR] Could not start the elevated App Installer: {0}' -f $_.Exception.Message))
        return 2
    }

    if ($null -eq $elevatedProcess) {
        [Console]::Error.WriteLine('[ERROR] Windows did not return an elevated process handle. The installer result is unknown.')
        return 125
    }

    $timeoutMilliseconds = 14400000
    try {
        $completed = $elevatedProcess.WaitForExit($timeoutMilliseconds)
    }
    catch {
        [Console]::Error.WriteLine(('[ERROR] Could not confirm elevated installer completion: {0}' -f $_.Exception.Message))
        return 125
    }

    if (-not $completed) {
        [Console]::Error.WriteLine('[ERROR] The elevated installer exceeded the four-hour wait limit. Its result could not be confirmed, and it may still be running.')
        return 124
    }

    try {
        $elevatedProcess.Refresh()
        $elevatedExitCode = $elevatedProcess.ExitCode
    }
    catch {
        [Console]::Error.WriteLine(('[ERROR] The elevated process ended, but its exit code could not be confirmed: {0}' -f $_.Exception.Message))
        return 125
    }

    if ($null -eq $elevatedExitCode) {
        [Console]::Error.WriteLine('[ERROR] The elevated process ended without a confirmed exit code.')
        return 125
    }

    return [int]$elevatedExitCode
}

if ($MyInvocation.InvocationName -ne '.') {
    $compatibilityModulePath = Join-Path $PSScriptRoot 'modules\InstallerCompatibility.psm1'
    if (-not (Test-Path -LiteralPath $compatibilityModulePath -PathType Leaf)) {
        [Console]::Error.WriteLine('[ERROR] The compatibility contract module is missing. Elevation was not started.')
        exit 1
    }

    try {
        Import-Module -Name $compatibilityModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
        $hostInfo = Get-InstallerHostInfo
        $hostDecision = Test-InstallerCompatibility -Component WindowsHost -HostInfo $hostInfo
        if (-not $hostDecision.IsSupported) {
            [Console]::Error.WriteLine($hostDecision.Message)
            exit 1
        }
    }
    catch {
        [Console]::Error.WriteLine("[ERROR] Windows support could not be verified. Elevation was not started. $($_.Exception.Message)")
        exit 1
    }

    $helperExitCode = Invoke-ElevatedInstall -Arguments @($args)
    exit $helperExitCode
}
