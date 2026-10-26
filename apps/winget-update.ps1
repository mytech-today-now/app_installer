<#
.SYNOPSIS
    Monthly Windows Package Manager (winget) Update Script 

.DESCRIPTION
    Requires an explicit catalog-backed package ID scope and updates only that scope.
    Windows-only: Winget-AutoUpdate is not available on macOS or Linux.
    Installed and managed by myTech.Today to keep your system up-to-date and secure.

.NOTES
    File Name      : winget-update.ps1
    Author         : Kyle C. Rode / myTech.Today
    Version        : 1.0.0
    DateCreated    : 2025-10-31
    LastModified   : 2025-10-31
    Copyright      : (c) 2025 myTech.Today. All rights reserved.
    Requires       : PowerShell 5.1 or later, winget

.LINK
    https://mytech.today
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PackageIds
)

$script:PackageIdsWereProvided = $PSBoundParameters.ContainsKey('PackageIds')
$script:IncompleteUpdateMessage = 'Update status is incomplete. Some applications may remain out of date. Review the log and run a manual update check.'
$script:LogWriteFailed = $false
$script:UpdateCommandStarted = $false
$script:WingetExitCode = $null

# Platform check - this application is Windows-only
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
    Write-Host $script:IncompleteUpdateMessage -ForegroundColor Yellow
    exit 1
}

$script:CatalogLoadError = $null
try {
    $coreModulePath = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules') 'AppInstallerCore.psm1'
    if (-not (Test-Path -LiteralPath $coreModulePath -PathType Leaf)) {
        throw 'The shared package catalog module is missing.'
    }
    Import-Module -Name $coreModulePath -Force -ErrorAction Stop
}
catch {
    $script:CatalogLoadError = 'The shared package catalog could not be loaded.'
}

# Script configuration
$script:ScriptName = 'winget-update.ps1'
$script:ScriptVersion = '1.0.0'
$script:LogPath = "C:\mytech.today\logs"

# Ensure log directory exists
if (-not (Test-Path $script:LogPath)) {
    New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
}

# Log file
$script:LogFile = Join-Path $script:LogPath "winget-update-$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',
        [switch]$FileOnly
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # A missing log entry means the result cannot be reported reliably.
    try {
        Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop
    }
    catch {
        $script:LogWriteFailed = $true
    }
    
    # Write to console with color
    $color = switch ($Level) {
        'INFO'    { 'White' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
    }
    if (-not $FileOnly) {
        Write-Host $logMessage -ForegroundColor $color
    }
}

function New-UpdateResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Completed', 'PartiallyCompleted', 'Failed', 'Unknown')]
        [string]$Status,
        [int]$Attempted = 0,
        [int]$Succeeded = 0,
        [int]$Failed = 0,
        [int]$Unknown = 0,
        [int]$CommandExitCode = 0,
        [string]$Reason = '',
        [object[]]$Packages = @()
    )

    [PSCustomObject]@{
        Status = $Status
        Attempted = $Attempted
        Succeeded = $Succeeded
        Failed = $Failed
        Unknown = $Unknown
        CommandExitCode = $CommandExitCode
        ProcessExitCode = 0
        Reason = $Reason
        Packages = @($Packages)
    }
}

function New-WingetUpdateResult {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$CommandOutput = @(),
        [AllowNull()]
        [Nullable[int]]$ExitCode,
        [string]$ExpectedPackageId = ''
    )

    $packageStates = [ordered]@{}
    $currentPackageId = $null
    $successWithoutPackageId = 0
    $failureWithoutPackageId = 0
    $noUpdatesAvailable = $false
    $recognizedFailure = $false
    $installStarted = $false
    $hasOutput = $false

    foreach ($outputItem in @($CommandOutput)) {
        if ($null -eq $outputItem) {
            continue
        }
        $escape = [string][char]27
        $line = [regex]::Replace([string]$outputItem, ($escape + '\[[0-?]*[ -/]*[@-~]'), '')
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $hasOutput = $true

        if ($line -match '(?i)\b(?:no applicable (?:upgrade|update) found|no upgrades available|0 upgrades available)\b') {
            $noUpdatesAvailable = $true
        }

        if ($line -match '(?i)\bStarting package (?:install|upgrade)') {
            $installStarted = $true
        }

        if ($line -match '(?i)\bFound\s+.*?\[(?<id>[A-Za-z0-9][A-Za-z0-9._+-]{0,127})\]\s+Version\b') {
            $currentPackageId = $matches['id']
            if (-not $packageStates.Contains($currentPackageId)) {
                $packageStates[$currentPackageId] = 'Unknown'
            }
            continue
        }

        if ($line -match '(?i)\bSuccessfully installed\b') {
            if ($currentPackageId) {
                $packageStates[$currentPackageId] = 'Succeeded'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($ExpectedPackageId)) {
                if (-not $packageStates.Contains($ExpectedPackageId)) {
                    $packageStates[$ExpectedPackageId] = 'Succeeded'
                }
                else {
                    $packageStates[$ExpectedPackageId] = 'Succeeded'
                }
            }
            else {
                $successWithoutPackageId++
            }
            $currentPackageId = $null
            continue
        }

        if ($line -match '(?i)\bInstaller failed with exit code\b|\bFailed to install\b|\bpackage update failed\b') {
            $recognizedFailure = $true
            if ($currentPackageId) {
                $packageStates[$currentPackageId] = 'Failed'
            }
            else {
                $failureWithoutPackageId++
            }
            $currentPackageId = $null
            continue
        }

        if ($line -match '(?i)\bFailed to open one or more sources\b|\bFailed when opening source\(s\)\b|\bNo package found matching\b|\bNo installed package found matching\b') {
            $recognizedFailure = $true
        }
    }

    if ($successWithoutPackageId -gt 0) {
        for ($index = 1; $index -le $successWithoutPackageId; $index++) {
            $packageStates["Unidentified package $index"] = 'Succeeded'
        }
    }
    if ($failureWithoutPackageId -gt 0) {
        for ($index = 1; $index -le $failureWithoutPackageId; $index++) {
            $packageStates["Unidentified failed package $index"] = 'Failed'
        }
    }

    if ($ExitCode -eq $null) {
        $states = @($packageStates.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{ PackageId = [string]$_.Key; Status = [string]$_.Value }
        })
        if ($states.Count -eq 0) {
            $states = @([PSCustomObject]@{ PackageId = 'winget command'; Status = 'Unknown' })
        }
        return New-UpdateResult -Status Unknown -Attempted $states.Count -Unknown $states.Count -CommandExitCode 1 -Reason 'winget did not provide a process exit code.' -Packages $states
    }

    $succeededCount = @($packageStates.Values | Where-Object { $_ -eq 'Succeeded' }).Count
    $failedCount = @($packageStates.Values | Where-Object { $_ -eq 'Failed' }).Count
    $unknownCount = @($packageStates.Values | Where-Object { $_ -eq 'Unknown' }).Count

    if ($ExitCode -ne 0 -and $recognizedFailure -and -not $installStarted -and $succeededCount -eq 0) {
        foreach ($packageId in @($packageStates.Keys)) {
            if ($packageStates[$packageId] -eq 'Unknown') {
                $packageStates[$packageId] = 'Failed'
            }
        }
        $failedCount = @($packageStates.Values | Where-Object { $_ -eq 'Failed' }).Count
        $unknownCount = @($packageStates.Values | Where-Object { $_ -eq 'Unknown' }).Count
    }

    if ($packageStates.Count -eq 0 -and $ExitCode -ne 0 -and $recognizedFailure -and -not $installStarted) {
        $packageStates['winget command'] = 'Failed'
        $failedCount = 1
    }

    if ($packageStates.Count -eq 0 -and $ExitCode -eq 0 -and $noUpdatesAvailable) {
        return New-UpdateResult -Status Completed -Reason 'No applicable application updates were available.' -Packages @()
    }

    if ($packageStates.Count -eq 0 -and -not $noUpdatesAvailable) {
        $packageStates['winget command'] = 'Unknown'
        $unknownCount = 1
    }

    $states = @($packageStates.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{ PackageId = [string]$_.Key; Status = [string]$_.Value }
    })
    $attemptedCount = $states.Count
    $succeededCount = @($states | Where-Object { $_.Status -eq 'Succeeded' }).Count
    $failedCount = @($states | Where-Object { $_.Status -eq 'Failed' }).Count
    $unknownCount = @($states | Where-Object { $_.Status -eq 'Unknown' }).Count

    if ($ExitCode -eq 0 -and $failedCount -eq 0 -and $unknownCount -eq 0 -and $succeededCount -gt 0) {
        return New-UpdateResult -Status Completed -Attempted $attemptedCount -Succeeded $succeededCount -CommandExitCode 0 -Reason 'winget completed and reported successful package results.' -Packages $states
    }

    if ($ExitCode -ne 0 -and $succeededCount -gt 0) {
        if ($failedCount -eq 0 -and $unknownCount -eq 0) {
            $unknownCount = 1
            $attemptedCount++
            $states += [PSCustomObject]@{ PackageId = 'winget command result'; Status = 'Unknown' }
        }
        return New-UpdateResult -Status PartiallyCompleted -Attempted $attemptedCount -Succeeded $succeededCount -Failed $failedCount -Unknown $unknownCount -CommandExitCode $ExitCode -Reason 'winget reported successful package work and a nonzero command result.' -Packages $states
    }

    if ($ExitCode -ne 0 -and $failedCount -gt 0 -and $unknownCount -eq 0) {
        return New-UpdateResult -Status Failed -Attempted $attemptedCount -Failed $failedCount -CommandExitCode $ExitCode -Reason 'winget reported a failed update operation.' -Packages $states
    }

    if ($ExitCode -eq 0 -and $failedCount -eq 0 -and $unknownCount -eq 0 -and $noUpdatesAvailable) {
        return New-UpdateResult -Status Completed -Reason 'No applicable application updates were available.' -Packages @()
    }

    if ($ExitCode -ne 0 -and $failedCount -gt 0 -and $unknownCount -eq 0 -and $recognizedFailure -and -not $installStarted) {
        return New-UpdateResult -Status Failed -Attempted $attemptedCount -Failed $failedCount -CommandExitCode $ExitCode -Reason 'winget failed before package installation began.' -Packages $states
    }

    if ($ExitCode -ne 0 -and $failedCount -gt 0 -and $succeededCount -eq 0 -and $unknownCount -eq 0) {
        return New-UpdateResult -Status Failed -Attempted $attemptedCount -Failed $failedCount -CommandExitCode $ExitCode -Reason 'winget reported failed package results.' -Packages $states
    }

    if ($attemptedCount -eq 0) {
        $attemptedCount = 1
    }
    if ($unknownCount -eq 0) {
        $unknownCount = 1
    }
    if ($attemptedCount -lt ($succeededCount + $failedCount + $unknownCount)) {
        $attemptedCount = $succeededCount + $failedCount + $unknownCount
    }
    $processCode = if ($ExitCode -ne 0) { $ExitCode } else { 1 }
    $reason = if (-not $hasOutput) { 'winget returned no parseable result.' } else { 'winget returned output that did not establish a complete package result.' }
    return New-UpdateResult -Status Unknown -Attempted $attemptedCount -Succeeded $succeededCount -Failed $failedCount -Unknown $unknownCount -CommandExitCode $processCode -Reason $reason -Packages $states
}

function Set-UpdateResultUnknown {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Reason
    )
    $Result.Status = 'Unknown'
    $Result.Reason = $Reason
    if ($Result.Unknown -eq 0) {
        $Result.Unknown = 1
    }
    if ($Result.Attempted -lt ($Result.Succeeded + $Result.Failed + $Result.Unknown)) {
        $Result.Attempted = $Result.Succeeded + $Result.Failed + $Result.Unknown
    }
    if ($Result.CommandExitCode -eq 0) {
        $Result.CommandExitCode = 1
    }
}

function New-FailedUpdateResult {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [int]$ExitCode = 1
    )
    New-UpdateResult -Status Failed -Attempted 1 -Failed 1 -CommandExitCode $ExitCode -Reason $Reason
}

function New-UnknownUpdateResult {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [int]$ExitCode = 1
    )
    New-UpdateResult -Status Unknown -Attempted 1 -Unknown 1 -CommandExitCode $ExitCode -Reason $Reason
}

function Complete-UpdateResult {
    param(
        [Parameter(Mandatory = $true)]$Result
    )

    if ($script:LogWriteFailed) {
        Set-UpdateResultUnknown -Result $Result -Reason 'The update log could not be written, so the result cannot be recorded reliably.'
    }

    $level = switch ($Result.Status) {
        'Completed' { 'SUCCESS' }
        'PartiallyCompleted' { 'WARNING' }
        'Failed' { 'ERROR' }
        default { 'ERROR' }
    }
    foreach ($package in @($Result.Packages)) {
        $packageLevel = switch ($package.Status) {
            'Succeeded' { 'SUCCESS' }
            'Failed' { 'ERROR' }
            default { 'WARNING' }
        }
        Write-Log ("Package result: {0} = {1}." -f $package.PackageId, $package.Status) -Level $packageLevel -FileOnly
    }

    $summary = "Update result: {0}; attempted={1}; succeeded={2}; failed={3}; unknown={4}; winget-exit-code={5}." -f $Result.Status, $Result.Attempted, $Result.Succeeded, $Result.Failed, $Result.Unknown, $Result.CommandExitCode
    if (-not [string]::IsNullOrWhiteSpace($Result.Reason)) {
        $summary += " $($Result.Reason)"
    }
    Write-Log $summary -Level $level -FileOnly

    if ($script:LogWriteFailed -and $Result.Status -ne 'Unknown') {
        Set-UpdateResultUnknown -Result $Result -Reason 'The update log could not be written, so the result cannot be recorded reliably.'
        $level = 'ERROR'
        $summary = "Update result: {0}; attempted={1}; succeeded={2}; failed={3}; unknown={4}; winget-exit-code={5}. {6}" -f $Result.Status, $Result.Attempted, $Result.Succeeded, $Result.Failed, $Result.Unknown, $Result.CommandExitCode, $Result.Reason
        Write-Log $summary -Level $level -FileOnly
    }

    if ($Result.Status -eq 'Completed') {
        $Result.ProcessExitCode = 0
    }
    elseif ($Result.CommandExitCode -ne 0) {
        $Result.ProcessExitCode = $Result.CommandExitCode
    }
    else {
        $Result.ProcessExitCode = 1
    }

    $displayStatus = switch ($Result.Status) {
        'Completed' { 'COMPLETED' }
        'PartiallyCompleted' { 'PARTIALLY COMPLETED' }
        'Failed' { 'FAILED' }
        default { 'UNKNOWN' }
    }
    Write-Host ''
    Write-Host ("[{0}] Update outcome: attempted={1}, succeeded={2}, failed={3}, unknown={4}, winget-exit-code={5}." -f $displayStatus, $Result.Attempted, $Result.Succeeded, $Result.Failed, $Result.Unknown, $Result.CommandExitCode) -ForegroundColor $(switch ($Result.Status) {
        'Completed' { 'Green' }
        'PartiallyCompleted' { 'Yellow' }
        default { 'Red' }
    })
    foreach ($package in @($Result.Packages)) {
        Write-Host ("  {0}: {1}" -f $package.PackageId, $package.Status) -ForegroundColor $(switch ($package.Status) {
            'Succeeded' { 'Green' }
            'Failed' { 'Red' }
            default { 'Yellow' }
        })
    }

    if ($Result.Status -eq 'Completed') {
        if ($Result.Succeeded -gt 0) {
            Write-Host '  Your applications have been updated.' -ForegroundColor Green
        }
        else {
            Write-Host '  No application updates were available.' -ForegroundColor Green
        }
        Write-Host '  Next update: 15th of next month at 1:00 PM' -ForegroundColor Gray
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($Result.Reason)) {
            Write-Host ("  Detail: {0}" -f $Result.Reason) -ForegroundColor Gray
        }
        Write-Host $script:IncompleteUpdateMessage -ForegroundColor Yellow
    }

    Write-Host "  Log file: $script:LogFile" -ForegroundColor Gray
    Write-Host ''
    return [int]$Result.ProcessExitCode
}

function Invoke-ScopedWingetUpdates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectedPackageIds
    )

    $packageIdList = @($SelectedPackageIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($packageIdList.Count -eq 0 -or @($packageIdList | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._ +()\-]*$' }).Count -gt 0) {
        return New-FailedUpdateResult -Reason 'The saved monthly package scope is empty or invalid. No updates were started.' -ExitCode 2
    }

    if ($script:CatalogLoadError) {
        return New-FailedUpdateResult -Reason "$script:CatalogLoadError No updates were started." -ExitCode 2
    }

    $packageDefinitions = @()
    try {
        foreach ($packageId in $packageIdList) {
            $packageSource = Get-WingetPackageSource -PackageId $packageId
            $upgradeArguments = New-WingetArgumentList `
                -Operation upgrade `
                -PackageId $packageId `
                -Source $packageSource `
                -AdditionalArguments @('--accept-source-agreements', '--accept-package-agreements')
            $packageDefinitions += [PSCustomObject]@{
                PackageId = $packageId
                Source = $packageSource
                Arguments = [string[]]$upgradeArguments
            }
        }
    }
    catch {
        return New-FailedUpdateResult -Reason 'The saved monthly package scope has missing, invalid, or conflicting catalog source metadata. No updates were started.' -ExitCode 2
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return New-FailedUpdateResult -Reason 'winget is unavailable for the selected monthly package scope. No updates were started.'
    }

    $packageResults = @()
    $commandExitCode = 0
    $commandFailed = $false
    Write-Log ("Starting scoped monthly updates for {0} package(s)." -f $packageDefinitions.Count) -Level INFO
    foreach ($packageDefinition in $packageDefinitions) {
        $packageId = [string]$packageDefinition.PackageId
        Write-Host "Updating selected package: $packageId" -ForegroundColor Cyan
        Write-Log "Running scoped update for package ID: $packageId" -Level INFO
        try {
            $upgradeArguments = [string[]]$packageDefinition.Arguments
            Write-Log ("Executing: winget {0}" -f ($upgradeArguments -join ' ')) -Level INFO
            $script:UpdateCommandStarted = $true
            $packageOutput = @(& winget @upgradeArguments 2>&1)
            $script:WingetExitCode = $LASTEXITCODE
            $packageResult = New-WingetUpdateResult -CommandOutput $packageOutput -ExitCode $script:WingetExitCode -ExpectedPackageId $packageId
        }
        catch {
            $packageResult = New-UnknownUpdateResult -Reason ("The package update raised an unexpected {0} exception." -f $_.Exception.GetType().Name)
        }

        foreach ($packageOutcome in @($packageResult.Packages)) {
            $packageResults += [PSCustomObject]@{
                PackageId = if (-not [string]::IsNullOrWhiteSpace([string]$packageOutcome.PackageId)) { [string]$packageOutcome.PackageId } else { [string]$packageId }
                Status = [string]$packageOutcome.Status
            }
        }
        if ($packageResult.Packages.Count -eq 0) {
            if ($packageResult.Status -eq 'Completed') {
                continue
            }
            $packageStatus = switch ($packageResult.Status) {
                'Completed' { 'Succeeded' }
                'Failed' { 'Failed' }
                default { 'Unknown' }
            }
            $packageResults += [PSCustomObject]@{ PackageId = [string]$packageId; Status = $packageStatus }
        }

        if ($packageResult.Status -eq 'Completed') {
            continue
        }
        else {
            $commandFailed = $true
            if ($packageResult.CommandExitCode -ne 0 -and $commandExitCode -eq 0) {
                $commandExitCode = $packageResult.CommandExitCode
            }
        }
    }

    $succeededCount = @($packageResults | Where-Object { $_.Status -eq 'Succeeded' }).Count
    $failedCount = @($packageResults | Where-Object { $_.Status -eq 'Failed' }).Count
    $unknownCount = @($packageResults | Where-Object { $_.Status -eq 'Unknown' }).Count
    $attemptedCount = $packageDefinitions.Count
    if (-not $commandFailed) {
        return New-UpdateResult -Status Completed -Attempted $attemptedCount -Succeeded $succeededCount -CommandExitCode 0 -Reason 'All selected package update checks completed.' -Packages $packageResults
    }

    if ($succeededCount -gt 0) {
        return New-UpdateResult -Status PartiallyCompleted -Attempted $attemptedCount -Succeeded $succeededCount -Failed $failedCount -Unknown $unknownCount -CommandExitCode $commandExitCode -Reason 'One or more selected package updates did not complete.' -Packages $packageResults
    }
    if ($failedCount -gt 0 -and $unknownCount -eq 0) {
        return New-UpdateResult -Status Failed -Attempted $attemptedCount -Failed $failedCount -CommandExitCode $commandExitCode -Reason 'All attempted selected package updates failed.' -Packages $packageResults
    }
    return New-UpdateResult -Status Unknown -Attempted $attemptedCount -Failed $failedCount -Unknown $unknownCount -CommandExitCode $commandExitCode -Reason 'One or more selected package update outcomes are unknown.' -Packages $packageResults
}

if ($script:PackageIdsWereProvided) {
    try {
        $scopedResult = Invoke-ScopedWingetUpdates -SelectedPackageIds $PackageIds
    }
    catch {
        $scopedResult = New-UnknownUpdateResult -Reason ("Scoped monthly update raised an unexpected {0} exception." -f $_.Exception.GetType().Name)
    }
    $scopedExitCode = Complete-UpdateResult -Result $scopedResult
    exit $scopedExitCode
}

$unscopedResult = New-FailedUpdateResult `
    -Reason 'An explicit catalog-backed package scope is required. No package updates were started.' `
    -ExitCode 2
$unscopedExitCode = Complete-UpdateResult -Result $unscopedResult
exit $unscopedExitCode
