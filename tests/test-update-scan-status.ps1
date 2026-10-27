# Offline contract coverage for GUI and CLI update discovery.
# The command boundary is stubbed; this harness never invokes winget or a package source.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'modules\AppInstallerCore.psm1') -Force -ErrorAction Stop
$script:assertionCount = 0
$script:logs = @()
$script:visibleMessages = @()
$script:notices = @()
$script:dialogUpdateCount = 0
$script:packageMutationCount = 0
$script:commandResult = $null
$script:commandArguments = @()
$script:runnerAction = 'Return'
$script:consumerResult = $null

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:assertionCount++
    [Console]::WriteLine("[PASS] $Message")
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $script:logs += [PSCustomObject]@{ Message = $Message; Level = $Level }
}

function Write-Output {
    param([object]$Message, [object]$Color)
    $script:visibleMessages += [string]$Message
}

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)][AllowNull()][object[]]$Object,
        [switch]$NoNewline,
        [object]$ForegroundColor
    )
    $script:visibleMessages += ($Object -join ' ')
}

function Invoke-PackageManagerProcess {
    param([string]$Executable, [string[]]$Arguments)
    $script:commandArguments = [string[]]$Arguments
    if ($script:runnerAction -eq 'Cancel') {
        throw [System.OperationCanceledException]::new()
    }
    if ($script:runnerAction -eq 'Unknown') {
        throw [System.InvalidOperationException]::new('Injected private command detail.')
    }
    return $script:commandResult
}

function Show-UpdateScanNotice {
    param([string]$Message, [string]$Title, [bool]$Warning)
    $script:notices += [PSCustomObject]@{ Message = $Message; Title = $Title; Warning = $Warning }
}

function Show-UpdatesDialog {
    param([object[]]$Updates)
    $script:dialogUpdateCount = $Updates.Count
    return $null
}

function Read-Host {
    param([string]$Prompt)
    return 'Q'
}

function Update-Applications {
    param([object[]]$Updates)
    $script:packageMutationCount++
}

function Reset-TestState {
    $script:logs = @()
    $script:visibleMessages = @()
    $script:notices = @()
    $script:dialogUpdateCount = 0
    $script:packageMutationCount = 0
    $script:commandResult = $null
    $script:commandArguments = @()
    $script:runnerAction = 'Return'
    $script:consumerResult = $null
}

function Import-InstallerFunctions {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $source = [System.IO.File]::ReadAllText($Path)

    foreach ($name in $Names) {
        $marker = "function $name {"
        $start = $source.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($start -lt 0) {
            throw "Function $name was not found in $Path."
        }

        $bodyStart = $start + $marker.Length
        $nextFunction = [regex]::Match($source.Substring($bodyStart), '(?m)^function\s+[A-Za-z][A-Za-z0-9_-]*\s*\{')
        $end = if ($nextFunction.Success) { $bodyStart + $nextFunction.Index } else { $source.Length }
        $functionText = $source.Substring($start, $end - $start)
        $tokens = $null
        $parseErrors = $null
        $functionAst = [System.Management.Automation.Language.Parser]::ParseInput($functionText, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) {
            throw "Could not parse function $name in ${Path}: $($parseErrors[0].Message)"
        }

        $definition = $functionAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true) | Select-Object -First 1
        if (-not $definition) {
            throw "Function $name could not be isolated in $Path."
        }

        $body = $definition.Body.Extent.Text
        $body = $body.Substring(1, $body.Length - 2)
        Set-Item -Path ("Function:\script:{0}" -f $name) -Value ([scriptblock]::Create($body)) -Force
    }
}

function Set-ConsumerResultStub {
    $stub = { return $script:consumerResult }
    Set-Item -Path 'Function:\script:Get-AvailableUpdates' -Value $stub -Force
}

function New-CommandResult {
    param(
        [string]$Status = 'Succeeded',
        [AllowNull()][object]$Output = @(),
        [AllowNull()][Nullable[int]]$ExitCode = 0
    )
    return [PSCustomObject]@{
        Status = $Status
        Output = [object[]]@($Output)
        ExitCode = $ExitCode
    }
}

$tableWithUpdate = @(
    'Name  Id  Version  Available  Source',
    '--------------------------------------------------------',
    'Google Chrome  Google.Chrome  1.0  1.1  winget',
    '1 upgrade available'
) -join [Environment]::NewLine
$tableWithoutUpdates = @(
    'Name  Id  Version  Available  Source',
    '--------------------------------------------------------',
    '0 upgrades available'
) -join [Environment]::NewLine
$verificationFailedMessage = 'Update availability could not be verified. No packages were changed. Retry the check or use winget upgrade manually.'

$scanCases = @(
    @{ Name = 'valid populated table'; Result = (New-CommandResult -Output $tableWithUpdate); ExpectedStatus = 'CompletedWithUpdates'; ExpectedExitCode = 0; ExpectedReason = 'table-validated' },
    @{ Name = 'valid empty table'; Result = (New-CommandResult -Output $tableWithoutUpdates); ExpectedStatus = 'CompletedNoUpdates'; ExpectedExitCode = 0; ExpectedReason = 'table-validated' },
    @{ Name = 'WinGet no-updates marker'; Result = (New-CommandResult -Output 'No applicable upgrade found.'); ExpectedStatus = 'CompletedNoUpdates'; ExpectedExitCode = 0; ExpectedReason = 'no-updates-marker' },
    @{ Name = 'nonzero command exit'; Result = (New-CommandResult -Status Failed -Output 'Private failure detail: token=do-not-log' -ExitCode 42); ExpectedStatus = 'Failed'; ExpectedExitCode = 42; ExpectedReason = 'command-failed' },
    @{ Name = 'missing executable'; Result = (New-CommandResult -Status Unavailable -Output @() -ExitCode $null); ExpectedStatus = 'Failed'; ExpectedExitCode = $null; ExpectedReason = 'command-unavailable' },
    @{ Name = 'empty output'; Result = (New-CommandResult -Output @()); ExpectedStatus = 'Unknown'; ExpectedExitCode = 0; ExpectedReason = 'empty-output' },
    @{ Name = 'missing header'; Result = (New-CommandResult -Output 'WinGet returned an unexpected response.'); ExpectedStatus = 'Unknown'; ExpectedExitCode = 0; ExpectedReason = 'missing-header' },
    @{ Name = 'error message output'; Result = (New-CommandResult -Output 'Failed when searching source: private detail token=do-not-log'); ExpectedStatus = 'Unknown'; ExpectedExitCode = 0; ExpectedReason = 'missing-header' },
    @{ Name = 'missing separator'; Result = (New-CommandResult -Output (@('Name  Id  Version  Available  Source', 'Example Application  Example.App  1.0  1.1  winget', '1 upgrade available') -join [Environment]::NewLine)); ExpectedStatus = 'Unknown'; ExpectedExitCode = 0; ExpectedReason = 'missing-separator' },
    @{ Name = 'malformed row'; Result = (New-CommandResult -Output (@('Name  Id  Version  Available  Source', '--------------------------------------------------------', 'Example Application  Example.App  1.0', '1 upgrade available') -join [Environment]::NewLine)); ExpectedStatus = 'Unknown'; ExpectedExitCode = 0; ExpectedReason = 'malformed-row' },
    @{ Name = 'truncated table'; Result = (New-CommandResult -Output (@('Name  Id  Version  Available  Source', '--------------------------------------------------------', 'Google Chrome  Google.Chrome  1.0  1.1  winget') -join [Environment]::NewLine)); ExpectedStatus = 'Unknown'; ExpectedExitCode = 0; ExpectedReason = 'missing-summary' },
    @{ Name = 'localized table'; Result = (New-CommandResult -Output (@('Nombre  Identificador  Versión  Disponible  Origen', '--------------------------------------------------------', 'Aplicación de ejemplo  Example.App  1.0  1.1  winget', '1 actualización disponible') -join [Environment]::NewLine)); ExpectedStatus = 'Unknown'; ExpectedExitCode = 0; ExpectedReason = 'missing-header' }
)

$entrypoints = @(
    @{ Name = 'GUI'; Path = (Join-Path $repositoryRoot 'app-installer.ps1') },
    @{ Name = 'CLI'; Path = (Join-Path $repositoryRoot 'app-installer-cli.ps1') }
)
$scanFunctionNames = @('New-UpdateScanResult', 'ConvertFrom-WingetUpgradeTable', 'Get-AvailableUpdates', 'Invoke-WingetDependencyCommand')
$consumerFunctionNames = @('Check-ForUpdates')

foreach ($entrypoint in $entrypoints) {
    Import-InstallerFunctions -Path $entrypoint.Path -Names ($scanFunctionNames + $consumerFunctionNames)

    foreach ($case in $scanCases) {
        Reset-TestState
        $script:commandResult = $case.Result
        $result = Get-AvailableUpdates
        Assert-Condition -Condition ($result.Status -ceq $case.ExpectedStatus) -Message "$($entrypoint.Name): $($case.Name) status is $($case.ExpectedStatus)"
        Assert-Condition -Condition ((($result.Status -ceq 'CompletedNoUpdates') -eq ($case.ExpectedStatus -ceq 'CompletedNoUpdates')) -and ($result.Status -ne 'CompletedNoUpdates' -or $result.Updates.Count -eq 0)) -Message "$($entrypoint.Name): $($case.Name) reports empty success only for recognized no-update output"
        Assert-Condition -Condition ($result.ExitCode -ceq $case.ExpectedExitCode) -Message "$($entrypoint.Name): $($case.Name) preserves the exit code"
        Assert-Condition -Condition ($result.Reason -ceq $case.ExpectedReason) -Message "$($entrypoint.Name): $($case.Name) records reason $($case.ExpectedReason)"
        Assert-Condition -Condition ($script:commandArguments.Count -eq 1 -and $script:commandArguments[0] -ceq 'upgrade') -Message "$($entrypoint.Name): $($case.Name) uses the read-only upgrade query"
        Assert-Condition -Condition ($script:packageMutationCount -eq 0) -Message "$($entrypoint.Name): $($case.Name) performs no package mutation"
        if ($case.Name -eq 'valid populated table') {
            Assert-Condition -Condition ($result.Updates.Count -eq 1 -and $result.Updates[0].Id -ceq 'Google.Chrome' -and $result.Updates[0].Source -ceq 'winget') -Message "$($entrypoint.Name): validated table returns the catalog-backed update and source"
        }
        if ($case.Name -eq 'nonzero command exit') {
            $loggedText = ($script:logs | ForEach-Object Message) -join ' '
            Assert-Condition -Condition ($loggedText -notmatch 'token=do-not-log' -and $loggedText -match 'reason=command-failed') -Message "$($entrypoint.Name): command failure logs a sanitized reason"
        }
    }

    Reset-TestState
    $script:runnerAction = 'Cancel'
    $cancelled = Get-AvailableUpdates
    Assert-Condition -Condition ($cancelled.Status -ceq 'Cancelled' -and $null -eq $cancelled.ExitCode) -Message "$($entrypoint.Name): interrupted scan is Cancelled with no exit code"
    Assert-Condition -Condition (($script:logs | ForEach-Object Message) -join ' ' -match 'reason=command-cancelled') -Message "$($entrypoint.Name): cancellation reason is logged"

    Reset-TestState
    $script:runnerAction = 'Unknown'
    $unknownCommand = Get-AvailableUpdates
    Assert-Condition -Condition ($unknownCommand.Status -ceq 'Unknown' -and $unknownCommand.Reason -ceq 'command-outcome-unknown') -Message "$($entrypoint.Name): unconfirmed command outcome is Unknown"
    Assert-Condition -Condition ((($script:logs | ForEach-Object Message) -join ' ') -notmatch 'Injected private command detail') -Message "$($entrypoint.Name): thrown command details are not logged"

    $integrationFailures = @(
        @{ Name = 'fake WinGet nonzero exit'; Result = (New-CommandResult -Status Failed -Output 'Failed when searching source: private detail token=do-not-log' -ExitCode 42) },
        @{ Name = 'fake WinGet arbitrary output'; Result = (New-CommandResult -Output 'Failed when searching source: private detail token=do-not-log' -ExitCode 0) }
    )
    foreach ($failure in $integrationFailures) {
        Reset-TestState
        $script:commandResult = $failure.Result
        $null = Check-ForUpdates
        $visibleText = $script:visibleMessages -join ' '
        if ($entrypoint.Name -eq 'GUI') {
            $noticeText = ($script:notices | ForEach-Object Message) -join ' '
            Assert-Condition -Condition ($noticeText -ceq $verificationFailedMessage -and $script:notices[0].Warning) -Message "GUI displays the recovery message for $($failure.Name)"
            Assert-Condition -Condition ($noticeText -notmatch 'All applications are up to date') -Message "GUI does not claim all applications are current for $($failure.Name)"
        }
        else {
            Assert-Condition -Condition ($visibleText -match [regex]::Escape($verificationFailedMessage)) -Message "CLI displays the recovery message for $($failure.Name)"
            Assert-Condition -Condition ($visibleText -notmatch 'All applications are up to date') -Message "CLI does not claim all applications are current for $($failure.Name)"
        }
        Assert-Condition -Condition ($script:packageMutationCount -eq 0 -and $script:dialogUpdateCount -eq 0) -Message "$($entrypoint.Name): $($failure.Name) does not open update selection or mutate packages"
        Assert-Condition -Condition ((($script:logs | ForEach-Object Message) -join ' ') -notmatch 'token=do-not-log') -Message "$($entrypoint.Name): $($failure.Name) does not log raw command output"
    }

    Set-ConsumerResultStub
    foreach ($status in @('Failed', 'Unknown', 'Cancelled')) {
        Reset-TestState
        $script:consumerResult = [PSCustomObject]@{ Status = $status; Updates = @(); ExitCode = $null; Reason = 'injected-safe-reason' }
        $null = Check-ForUpdates
        $visibleText = $script:visibleMessages -join ' '
        if ($entrypoint.Name -eq 'GUI') {
            $noticeText = ($script:notices | ForEach-Object Message) -join ' '
            Assert-Condition -Condition ($noticeText -ceq $verificationFailedMessage -and $script:notices[0].Warning) -Message ('GUI shows the incomplete-check warning for ' + $status)
            Assert-Condition -Condition ($noticeText -notmatch 'All applications are up to date') -Message ('GUI does not claim all applications are current for ' + $status)
        }
        else {
            Assert-Condition -Condition ($visibleText -match [regex]::Escape($verificationFailedMessage)) -Message ('CLI shows the incomplete-check warning for ' + $status)
            Assert-Condition -Condition ($visibleText -notmatch 'All applications are up to date') -Message ('CLI does not claim all applications are current for ' + $status)
        }
        Assert-Condition -Condition ($script:packageMutationCount -eq 0 -and $script:dialogUpdateCount -eq 0) -Message "$($entrypoint.Name): $status does not open update selection or mutate packages"
    }

    Reset-TestState
    $script:consumerResult = [PSCustomObject]@{ Status = 'CompletedNoUpdates'; Updates = @(); ExitCode = 0; Reason = 'table-validated' }
    $null = Check-ForUpdates
    if ($entrypoint.Name -eq 'GUI') {
        Assert-Condition -Condition (($script:notices | ForEach-Object Message) -join ' ' -match 'All applications are up to date!') -Message 'GUI shows all-current only for a validated empty scan'
    }
    else {
        Assert-Condition -Condition (($script:visibleMessages -join ' ') -match 'All applications are up to date!') -Message 'CLI shows all-current only for a validated empty scan'
    }

    Reset-TestState
    $script:consumerResult = [PSCustomObject]@{
        Status = 'CompletedWithUpdates'
        Updates = @([PSCustomObject]@{ Name = 'Example Application'; Id = 'Example.App'; CurrentVersion = '1.0'; AvailableVersion = '1.1'; Source = 'winget' })
        ExitCode = 0
        Reason = 'table-validated'
    }
    $null = Check-ForUpdates
    if ($entrypoint.Name -eq 'GUI') {
        Assert-Condition -Condition ($script:dialogUpdateCount -eq 1) -Message 'GUI preserves the update selection dialog for validated update results'
    }
    else {
        Assert-Condition -Condition (($script:visibleMessages -join ' ') -match 'Example Application' -and ($script:visibleMessages -join ' ') -notmatch 'All applications are up to date') -Message 'CLI displays validated update results without an all-current claim'
    }
    Assert-Condition -Condition ($script:packageMutationCount -eq 0) -Message "$($entrypoint.Name): cancelling selection does not mutate packages"

    Reset-TestState
    $script:consumerResult = [PSCustomObject]@{
        Status = 'CompletedNoUpdates'
        Updates = @([PSCustomObject]@{ Name = 'Contradictory update'; Id = 'Example.Bad'; CurrentVersion = '1.0'; AvailableVersion = '2.0'; Source = 'winget' })
        ExitCode = 0
        Reason = 'injected-inconsistent-result'
    }
    $null = Check-ForUpdates
    if ($entrypoint.Name -eq 'GUI') {
        Assert-Condition -Condition (($script:notices | ForEach-Object Message) -join ' ' -match [regex]::Escape($verificationFailedMessage)) -Message 'GUI treats a status and update-count mismatch as incomplete'
    }
    else {
        Assert-Condition -Condition (($script:visibleMessages -join ' ') -match [regex]::Escape($verificationFailedMessage)) -Message 'CLI treats a status and update-count mismatch as incomplete'
    }
}

[Console]::WriteLine("[OK] Update discovery status checks passed ($script:assertionCount assertions).")
