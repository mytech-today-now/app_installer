# Offline checks for manual compatibility-source review cadence and release gating.
# Uses injected dates and local files only. It does not fetch sources or rewrite compatibility.json.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot 'compatibility.json'
$modulePath = Join-Path $repositoryRoot 'modules\InstallerCompatibilityReview.psm1'
$checkerPath = Join-Path $repositoryRoot 'tools\Test-CompatibilityReview.ps1'
$readmePath = Join-Path $repositoryRoot 'README.md'
$releaseChecklistPath = Join-Path $repositoryRoot 'WINDOWS_CLIENT_GUI_RELEASE_CHECKLIST.md'
$manifestTextBefore = [System.IO.File]::ReadAllText($manifestPath)
$manifestHashBefore = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
$assertionCount = 0

Import-Module -Name $modulePath -Force -DisableNameChecking
$manifest = $manifestTextBefore | ConvertFrom-Json -ErrorAction Stop

function Assert-ReviewCondition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

$maximumAgeDays = [int]$manifest.reviewPolicy.maximumAgeDays
Assert-ReviewCondition -Condition ($maximumAgeDays -eq 180 -and [bool]$manifest.reviewPolicy.requiredBeforeRelease) -Message 'The contract requires source review every 180 days and before release.'

$lifecycleSource = [string]$manifest.windowsClient.verification.lifecycleSource
$powerShellLifecycleSource = [string]$manifest.windowsClient.verification.powerShellSource
$powerShellReleaseSource = [string]$manifest.windowsClient.verification.powerShellReleaseSource
Assert-ReviewCondition -Condition ($lifecycleSource -ceq 'https://learn.microsoft.com/en-us/windows/release-health/supported-versions-windows-client' -and $powerShellLifecycleSource -ceq 'https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6' -and $powerShellReleaseSource -ceq 'https://github.com/PowerShell/PowerShell/releases/tag/v7.6.9') -Message 'The reviewed official Windows and PowerShell lifecycle and release URLs are recorded in the contract.'

$readmeText = [System.IO.File]::ReadAllText($readmePath)
$releaseChecklistText = [System.IO.File]::ReadAllText($releaseChecklistPath)
Assert-ReviewCondition -Condition ($readmeText.Contains('at least every 180 days and before a versioned release') -and $readmeText.Contains('The checker makes no network requests and never writes to the contract')) -Message 'README documents the review cadence, release trigger, and read-only offline boundary.'
Assert-ReviewCondition -Condition ($releaseChecklistText.Contains('Before a versioned release') -and $releaseChecklistText.Contains('Update `lastReviewed` by hand after the review') -and $releaseChecklistText.Contains($lifecycleSource) -and $releaseChecklistText.Contains($powerShellLifecycleSource) -and $releaseChecklistText.Contains($powerShellReleaseSource)) -Message 'The Windows client release checklist requires the human review and names its official sources.'

$reviewDate = [datetime]::ParseExact([string]$manifest.lastReviewed, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$freshReview = Get-InstallerCompatibilityReviewFreshness -LastReviewed ([string]$manifest.lastReviewed) -AsOfDate $reviewDate -MaximumAgeDays $maximumAgeDays
Assert-ReviewCondition -Condition ($freshReview.IsFresh -and $freshReview.AgeDays -eq 0 -and [string]::IsNullOrEmpty($freshReview.WarningMessage)) -Message 'An injected date matching lastReviewed passes without a stale warning.'

$freshBoundary = Get-InstallerCompatibilityReviewFreshness -LastReviewed '2026-01-01' -AsOfDate ([datetime]::ParseExact('2026-06-30', 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)) -MaximumAgeDays $maximumAgeDays
Assert-ReviewCondition -Condition ($freshBoundary.IsFresh -and $freshBoundary.AgeDays -eq 180) -Message 'A review exactly 180 days old remains within the configured cadence.'

$staleDate = ([datetime]::ParseExact('2026-01-01', 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).AddDays($maximumAgeDays + 1)
$staleReview = Get-InstallerCompatibilityReviewFreshness -LastReviewed '2026-01-01' -AsOfDate $staleDate -MaximumAgeDays $maximumAgeDays
Assert-ReviewCondition -Condition (-not $staleReview.IsFresh -and $staleReview.AgeDays -eq 181 -and $staleReview.WarningMessage -match 'review is overdue') -Message 'A review older than 180 days returns an actionable stale warning.'

$invalidDateRejected = $false
try {
    Get-InstallerCompatibilityReviewFreshness -LastReviewed '2026-1-01' -AsOfDate $reviewDate -MaximumAgeDays $maximumAgeDays | Out-Null
}
catch {
    $invalidDateRejected = $true
}
Assert-ReviewCondition -Condition $invalidDateRejected -Message 'A noncanonical lastReviewed date is rejected.'

$futureDateRejected = $false
try {
    Get-InstallerCompatibilityReviewFreshness -LastReviewed ($reviewDate.AddDays(1).ToString('yyyy-MM-dd')) -AsOfDate $reviewDate -MaximumAgeDays $maximumAgeDays | Out-Null
}
catch {
    $futureDateRejected = $true
}
Assert-ReviewCondition -Condition $futureDateRejected -Message 'A lastReviewed date later than the injected check date is rejected.'

$checkerText = [System.IO.File]::ReadAllText($checkerPath)
$moduleText = [System.IO.File]::ReadAllText($modulePath)
Assert-ReviewCondition -Condition (($checkerText + $moduleText) -notmatch '(?i)Invoke-WebRequest|Invoke-RestMethod|WebClient|HttpClient|DownloadFile|Set-Content|WriteAllText|WriteAllBytes') -Message 'The freshness checker has no network-fetch or contract-write implementation.'

$currentWarnings = @()
$currentCheck = & $checkerPath -CompatibilityPath $manifestPath -AsOfDate $reviewDate -WarningVariable currentWarnings
Assert-ReviewCondition -Condition ($currentCheck.IsFresh -and @($currentWarnings).Count -eq 0) -Message 'The offline checker reports a current review for the injected review date.'

$staleManifestPath = Join-Path ([System.IO.Path]::GetTempPath()) ('compatibility-review-' + [guid]::NewGuid().ToString('N') + '.json')
$staleManifest = $manifestTextBefore | ConvertFrom-Json -ErrorAction Stop
$staleManifest.lastReviewed = '2026-01-01'
$staleManifestJson = ConvertTo-Json -InputObject $staleManifest -Depth 64
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($staleManifestPath, $staleManifestJson, $utf8NoBom)

$originalActionsValue = $env:GITHUB_ACTIONS
try {
    Remove-Item Env:\GITHUB_ACTIONS -ErrorAction SilentlyContinue
    $staleWarnings = @()
    $staleCheck = & $checkerPath -CompatibilityPath $staleManifestPath -AsOfDate $staleDate -WarningVariable staleWarnings
    Assert-ReviewCondition -Condition (-not $staleCheck.IsFresh -and @($staleWarnings).Count -eq 1 -and $staleWarnings[0].Message -match 'review is overdue') -Message 'The offline checker emits a warning when the injected review date exceeds the cadence.'

    $releaseGateFailed = $false
    try {
        & $checkerPath -CompatibilityPath $staleManifestPath -AsOfDate $staleDate -RequireFresh | Out-Null
    }
    catch {
        $releaseGateFailed = $_.Exception.Message -match 'review is overdue'
    }
    Assert-ReviewCondition -Condition $releaseGateFailed -Message 'The pre-release mode rejects a stale review.'
}
finally {
    Remove-Item -LiteralPath $staleManifestPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $originalActionsValue) {
        Remove-Item Env:\GITHUB_ACTIONS -ErrorAction SilentlyContinue
    }
    else {
        $env:GITHUB_ACTIONS = $originalActionsValue
    }
}

$actualWarnings = @()
$actualCheck = & $checkerPath -CompatibilityPath $manifestPath -WarningVariable actualWarnings
$actualWarningStateMatches = if ($actualCheck.IsFresh) {
    @($actualWarnings).Count -eq 0
}
else {
    @($actualWarnings).Count -eq 1 -and $actualWarnings[0].Message -match 'review is overdue'
}
Assert-ReviewCondition -Condition $actualWarningStateMatches -Message 'The repository review check reports its real age and warns only when overdue.'

$manifestHashAfter = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
Assert-ReviewCondition -Condition ($manifestHashAfter -ceq $manifestHashBefore) -Message 'Freshness checks do not mutate compatibility.json.'

[Console]::WriteLine("[OK] Compatibility review freshness checks passed ($script:assertionCount assertions).")
