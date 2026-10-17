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

& $TargetScriptPath @TargetArguments

if ($global:LASTEXITCODE -eq $noResultSentinel) {
    [System.IO.File]::WriteAllText($ResultPath, 'unknown', [System.Text.Encoding]::ASCII)
    exit 0
}

[System.IO.File]::WriteAllText($ResultPath, 'declared', [System.Text.Encoding]::ASCII)
exit $global:LASTEXITCODE
