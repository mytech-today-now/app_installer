function Get-InstallerCompatibilityReviewFreshness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LastReviewed,

        [Parameter(Mandatory = $true)]
        [datetime]$AsOfDate,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 3660)]
        [int]$MaximumAgeDays
    )

    if ($LastReviewed -cnotmatch '^\d{4}-\d{2}-\d{2}$') {
        throw 'compatibility.json lastReviewed must use the exact yyyy-MM-dd date format.'
    }

    try {
        $reviewDate = [datetime]::ParseExact(
            $LastReviewed,
            'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None
        ).Date
    }
    catch {
        throw 'compatibility.json lastReviewed must be a real calendar date in yyyy-MM-dd format.'
    }

    $comparisonDate = $AsOfDate.Date
    if ($reviewDate -gt $comparisonDate) {
        throw 'compatibility.json lastReviewed cannot be later than the review check date.'
    }

    $ageDays = ($comparisonDate - $reviewDate).Days
    $isFresh = $ageDays -le $MaximumAgeDays
    $warningMessage = ''
    if (-not $isFresh) {
        $warningMessage = 'Compatibility source review is overdue: lastReviewed {0} is {1} days old (maximum {2}). Manually review the official Windows client lifecycle and PowerShell support sources, then update compatibility.json lastReviewed.' -f $LastReviewed, $ageDays, $MaximumAgeDays
    }

    [PSCustomObject][ordered]@{
        LastReviewed = $LastReviewed
        AsOfDate = $comparisonDate
        AgeDays = $ageDays
        MaximumAgeDays = $MaximumAgeDays
        NextReviewDueDate = $reviewDate.AddDays($MaximumAgeDays)
        IsFresh = $isFresh
        WarningMessage = $warningMessage
    }
}

Export-ModuleMember -Function Get-InstallerCompatibilityReviewFreshness
