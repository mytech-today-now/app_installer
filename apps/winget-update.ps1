<#
.SYNOPSIS
    Monthly Windows Package Manager (winget) Update Script 

.DESCRIPTION
    Without -PackageIds, manual execution updates all applications installed via winget.
    Scheduled execution supplies the confirmed package IDs and updates only that scope.
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

    if ($ExpectedPackageId -and $noUpdatesAvailable -and $packageStates.Count -eq 0 -and $ExitCode -eq 0) {
        $packageStates[$ExpectedPackageId] = 'Succeeded'
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

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return New-FailedUpdateResult -Reason 'winget is unavailable for the selected monthly package scope. No updates were started.'
    }

    $packageResults = @()
    $commandExitCode = 0
    $commandFailed = $false
    Write-Log ("Starting scoped monthly updates for {0} package(s)." -f $packageIdList.Count) -Level INFO
    foreach ($packageId in $packageIdList) {
        Write-Host "Updating selected package: $packageId" -ForegroundColor Cyan
        Write-Log "Running scoped update for package ID: $packageId" -Level INFO
        try {
            $script:UpdateCommandStarted = $true
            $packageOutput = @(winget update --id $packageId --exact --accept-source-agreements --accept-package-agreements 2>&1)
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
    $attemptedCount = $packageResults.Count
    if ($attemptedCount -eq 0) {
        $attemptedCount = $packageIdList.Count
    }
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

# Display friendly explanation to user
function Show-UserExplanation {
    Clear-Host
    
    Write-Host ""
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host "|              myTech.Today Monthly Application Updates             |" -ForegroundColor Cyan
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Hello! This is your monthly application update from myTech.Today," -ForegroundColor White
    Write-Host "  your IT solutions provider." -ForegroundColor White
    Write-Host ""
    Write-Host "  WHAT'S HAPPENING:" -ForegroundColor Yellow
    Write-Host "  We're updating all of your applications to keep your computer" -ForegroundColor Gray
    Write-Host "  secure, stable, and running smoothly. This happens automatically" -ForegroundColor Gray
    Write-Host "  on the 15th of each month at 1:00 PM." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  WHY YOU'RE SEEING THIS:" -ForegroundColor Yellow
    Write-Host "  Microsoft requires administrator permission to update applications." -ForegroundColor Gray
    Write-Host "  Unfortunately, Microsoft makes this process very obvious and" -ForegroundColor Gray
    Write-Host "  sometimes alarming with security prompts. We can't make it silent" -ForegroundColor Gray
    Write-Host "  or invisible - that's a Microsoft security requirement." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  WHAT YOU NEED TO DO:" -ForegroundColor Yellow
    Write-Host "  When Microsoft asks if it's OK to make changes to your device," -ForegroundColor Green
    Write-Host "  please click:" -ForegroundColor Green
    Write-Host ""
    Write-Host "    [OK]  or  [YES]  or  [ALLOW]  or  [CONTINUE]" -ForegroundColor Cyan -BackgroundColor DarkBlue
    Write-Host ""
    Write-Host "  This is normal and expected. We're just updating your apps!" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  At myTech.Today, we explain what's happening because it makes" -ForegroundColor White
    Write-Host "  life easier. No surprises, no confusion - just clear communication." -ForegroundColor White
    Write-Host ""
    Write-Host "+===================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Starting updates in 10 seconds..." -ForegroundColor Yellow
    Write-Host "  (Press Ctrl+C to cancel if needed)" -ForegroundColor Gray
    Write-Host ""
    
    # Give user time to read
    Start-Sleep -Seconds 10
}

# Main execution
$updateResult = $null
try {
    Write-Log '=== Starting Monthly winget Update ===' -Level INFO
    Write-Log "Script Version: $script:ScriptVersion" -Level INFO

    Show-UserExplanation

    Write-Log 'Checking for winget availability...' -Level INFO
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        $updateResult = New-FailedUpdateResult -Reason 'Windows Package Manager (winget) is unavailable. No updates were started.'
        Write-Log 'winget is unavailable; no update command was started.' -Level ERROR
    }
    else {
        Write-Log 'winget is available.' -Level INFO
        Write-Host ''
        Write-Host '+===================================================================+' -ForegroundColor Cyan
        Write-Host '|                    Updating All Applications                      |' -ForegroundColor Cyan
        Write-Host '+===================================================================+' -ForegroundColor Cyan
        Write-Host ''

        Write-Log 'Running: winget update --all' -Level INFO
        Write-Host 'Running: winget update --all' -ForegroundColor Cyan
        Write-Host ''

        $script:UpdateCommandStarted = $true
        $commandOutput = @(winget update --all --accept-source-agreements --accept-package-agreements 2>&1)
        $script:WingetExitCode = $LASTEXITCODE
        $updateResult = New-WingetUpdateResult -CommandOutput $commandOutput -ExitCode $script:WingetExitCode
    }
}
catch {
    $exceptionType = $_.Exception.GetType().Name
    Write-Log ("Monthly update raised an unexpected {0} exception." -f $exceptionType) -Level ERROR
    if ($script:UpdateCommandStarted) {
        $exitCode = if ($script:WingetExitCode -ne $null -and $script:WingetExitCode -ne 0) { $script:WingetExitCode } else { 1 }
        $updateResult = New-UnknownUpdateResult -Reason ("An unexpected {0} exception left the update result unconfirmed." -f $exceptionType) -ExitCode $exitCode
    }
    else {
        $updateResult = New-FailedUpdateResult -Reason ("An unexpected {0} exception prevented the update from starting." -f $exceptionType)
    }
}

if ($null -eq $updateResult) {
    $updateResult = New-UnknownUpdateResult -Reason 'The updater did not produce a result.'
}

Write-Host ''
Write-Host '+===================================================================+' -ForegroundColor Cyan
Write-Host '|                         Update Result                             |' -ForegroundColor Cyan
Write-Host '+===================================================================+' -ForegroundColor Cyan
$processExitCode = Complete-UpdateResult -Result $updateResult

if ($updateResult.Status -eq 'Completed') {
    Write-Host ''
    Write-Host '  Thank you for using myTech.Today services!' -ForegroundColor Cyan
    Write-Host '  Questions? Contact us at sales@mytech.today or (847) 767-4914' -ForegroundColor White
    Write-Host ''
    if (-not [Console]::IsInputRedirected) {
        Write-Host '  This window will close in 30 seconds...' -ForegroundColor Yellow
        Write-Host '  (Press any key to close now)' -ForegroundColor Gray
        Write-Host ''
        $timeout = 30
        $startTime = Get-Date
        while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                break
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

exit $processExitCode

