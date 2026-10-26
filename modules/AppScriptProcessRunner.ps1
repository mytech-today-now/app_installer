[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetScriptPath,

    [Parameter(Mandatory = $true)]
    [string]$ResultPath,

    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [AllowEmptyCollection()]
    [string[]]$TargetArguments = @()
)

$noResultSentinel = [int]::MinValue
$global:LASTEXITCODE = $noResultSentinel
$global:AppInstallerScriptOutcome = $null

& $TargetScriptPath @TargetArguments

if ($null -ne $global:AppInstallerScriptOutcome) {
    $allowedOutcomes = @('Installed', 'Failure', 'Unknown', 'ManualActionRequired')
    $outcomeStatus = if ($global:AppInstallerScriptOutcome.PSObject.Properties['Status']) {
        [string]$global:AppInstallerScriptOutcome.Status
    }
    else {
        'Unknown'
    }
    $outcomeMessage = if ($global:AppInstallerScriptOutcome.PSObject.Properties['Message']) {
        [string]$global:AppInstallerScriptOutcome.Message
    }
    else {
        ''
    }

    if ($outcomeStatus -notin $allowedOutcomes) {
        $outcomeStatus = 'Unknown'
        $outcomeMessage = 'The app script declared an unsupported outcome.'
    }

    $resultPayload = [PSCustomObject]@{
        Protocol = 'AppInstallerScriptOutcomeV1'
        Status = $outcomeStatus
        Message = $outcomeMessage
    }
    $resultJson = ConvertTo-Json -InputObject $resultPayload -Compress
    [System.IO.File]::WriteAllText($ResultPath, $resultJson, (New-Object System.Text.UTF8Encoding($false)))

    $outcomeExitCode = if ($outcomeStatus -eq 'Failure') { 1 } else { 0 }
    exit $outcomeExitCode
}

if ($global:LASTEXITCODE -eq $noResultSentinel) {
    [System.IO.File]::WriteAllText($ResultPath, 'unknown', [System.Text.Encoding]::ASCII)
    exit 0
}

[System.IO.File]::WriteAllText($ResultPath, 'declared', [System.Text.Encoding]::ASCII)
exit $global:LASTEXITCODE
