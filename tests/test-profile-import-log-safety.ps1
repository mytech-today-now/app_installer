#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-profile-log-' + [guid]::NewGuid().ToString('N'))))
$script:assertionCount = 0
$script:InstallInvocationCount = 0
$unicodeText = 'München 漢字 🙂'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $testRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary profile log test directory is outside the system temporary directory.'
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Get-FunctionDefinitionText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $parseErrors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) {
        throw "Cannot inspect $Name because $(Split-Path $Path -Leaf) has a parse error."
    }

    $functionAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)
    if (-not $functionAst) {
        throw "Function $Name was not found in $(Split-Path $Path -Leaf)."
    }

    return $functionAst.Extent.Text
}

function Safe-TestPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Test-Path -LiteralPath $Path)
}

function Write-Host {
    param(
        [object]$Object,
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor,
        [switch]$NoNewline
    )

    if ($NoNewline) {
        [Console]::Write([string]$Object)
    }
    else {
        [Console]::WriteLine([string]$Object)
    }
}

function Write-Warning {
    param([object]$Message)
}

function Install-SelectedApplications {
    $script:InstallInvocationCount++
}

function Get-MarkdownLogLines {
    if (-not (Test-Path -LiteralPath $script:LogPath -PathType Leaf)) {
        return @()
    }

    return [System.IO.File]::ReadAllLines($script:LogPath, [System.Text.Encoding]::UTF8)
}

function Get-MarkdownLogRows {
    $lines = @(Get-MarkdownLogLines)
    return @($lines | Where-Object { $_ -match '^\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| ' })
}

function Test-LogRowsContainPattern {
    param(
        [Parameter(Mandatory = $true)][string[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    return (@($Rows | Where-Object { $_ -match $Pattern }).Count -gt 0)
}

function Assert-FixedBoundedRows {
    param([Parameter(Mandatory = $true)][string[]]$Rows)

    foreach ($row in $Rows) {
        Assert-Condition -Condition ([regex]::Matches($row, '\|').Count -eq 4) -Message 'Log row has exactly three Markdown cells.'
        Assert-Condition -Condition ($row.Length -le 1150) -Message 'Log row stays within the fixed output bound.'
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $sourcePath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
    foreach ($functionName in @('ConvertTo-MarkdownLogMessage', 'Write-Log', 'ConvertTo-BoundedProfileText', 'Import-InstallationProfile')) {
        Remove-Item -LiteralPath ("Function:\$functionName") -ErrorAction SilentlyContinue
        Invoke-Expression (Get-FunctionDefinitionText -Path $sourcePath -Name $functionName)
    }

    $fixtureApp = [PSCustomObject]@{ Name = 'Fixture App' }
    $script:Applications = @($fixtureApp)
    $script:LogPath = Join-Path $testRoot 'profile-import.md'
    $logHeader = "| Timestamp | Level | Message |`r`n|-----------|-------|---------|`r`n"
    [System.IO.File]::WriteAllText($script:LogPath, $logHeader, $utf8NoBom)

    $beforeRows = @(Get-MarkdownLogRows)
    $beforeLineCount = @(Get-MarkdownLogLines).Count
    $message = "unicode $unicodeText | first`rsecond`nthird | end"
    Write-Log -Message $message -Level INFO
    $rowsAfterSingleCall = @(Get-MarkdownLogRows)
    $linesAfterSingleCall = @(Get-MarkdownLogLines)
    Assert-Condition -Condition ($rowsAfterSingleCall.Count -eq ($beforeRows.Count + 1)) -Message 'One Write-Log call creates exactly one physical Markdown row.'
    Assert-Condition -Condition ($linesAfterSingleCall.Count -eq ($beforeLineCount + 1)) -Message 'Embedded CR and LF characters do not create a forged physical log line.'
    Assert-FixedBoundedRows -Rows @($rowsAfterSingleCall[-1])
    Assert-Condition -Condition ($rowsAfterSingleCall[-1].Contains('unicode ' + $unicodeText) -and $rowsAfterSingleCall[-1].Contains('/ first second third / end')) -Message 'Unicode remains readable while line breaks and pipes are normalized.'

    $beforeRows = @(Get-MarkdownLogRows)
    $beforeLineCount = @(Get-MarkdownLogLines).Count
    Write-Log -Message ('x' * 5000) -Level WARNING
    $oversizedRows = @(Get-MarkdownLogRows)
    $oversizedLines = @(Get-MarkdownLogLines)
    Assert-Condition -Condition ($oversizedRows.Count -eq ($beforeRows.Count + 1)) -Message 'An oversized message still creates exactly one row.'
    Assert-Condition -Condition ($oversizedLines.Count -eq ($beforeLineCount + 1)) -Message 'An oversized message creates no extra physical lines.'
    Assert-FixedBoundedRows -Rows @($oversizedRows[-1])
    Assert-Condition -Condition ($oversizedRows[-1].EndsWith('... |')) -Message 'An oversized message is visibly truncated at the logging boundary.'

    $beforeRows = @(Get-MarkdownLogRows)
    $beforeLineCount = @(Get-MarkdownLogLines).Count
    Write-Log -Message ([PSCustomObject]@{ Value = "untrusted|`nvalue" }) -Level INFO
    $wrongTypeRows = @(Get-MarkdownLogRows)
    $wrongTypeLines = @(Get-MarkdownLogLines)
    Assert-Condition -Condition ($wrongTypeRows.Count -eq ($beforeRows.Count + 1) -and $wrongTypeRows[-1].Contains('[non-text message]')) -Message 'A non-string log value is represented by a bounded safe marker.'
    Assert-Condition -Condition ($wrongTypeLines.Count -eq ($beforeLineCount + 1)) -Message 'A non-string log value creates no extra physical lines.'
    Assert-FixedBoundedRows -Rows @($wrongTypeRows[-1])

    $profilePath = Join-Path $testRoot 'hostile-profile.json'
    $hostileProfile = [ordered]@{
        Version = [PSCustomObject]@{ Value = "bad|version`r`nforged row" }
        Timestamp = "2026-11-07 $unicodeText|line one`rline two`nforged row"
        ComputerName = [PSCustomObject]@{ Value = 'DEVICE-IDENTITY-SHOULD-NOT-LOG' }
        UserName = 74001
        InstallerVersion = ('installer ' + $unicodeText + '|' + ('i' * 1800))
        Applications = @(
            'Fixture App',
            "Missing|App`rline two`nforged row $unicodeText",
            (('A' * 300) + '|oversized'),
            [PSCustomObject]@{ Name = 'Fixture App' }
        )
    }
    $hostileProfileText = ConvertTo-Json -InputObject $hostileProfile -Depth 8
    [System.IO.File]::WriteAllText($profilePath, $hostileProfileText, $utf8NoBom)
    $hostileProfileBytesBefore = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($profilePath))
    $beforeRows = @(Get-MarkdownLogRows)
    $beforeLineCount = @(Get-MarkdownLogLines).Count

    $hostileResult = Import-InstallationProfile -FilePath $profilePath
    $hostileRows = @(Get-MarkdownLogRows)
    $hostileLines = @(Get-MarkdownLogLines)
    $hostileImportRows = @($hostileRows | Select-Object -Skip $beforeRows.Count)
    Assert-Condition -Condition ($hostileResult.Success -and $hostileImportRows.Count -eq 10) -Message 'Malformed metadata imports one selected legacy-compatible application and writes one row per log call.'
    Assert-Condition -Condition ($hostileLines.Count -eq ($beforeLineCount + $hostileImportRows.Count)) -Message 'Malformed metadata and application names create no forged physical log lines.'
    Assert-Condition -Condition ($hostileResult.Applications.Count -eq 1 -and [object]::ReferenceEquals($hostileResult.Applications[0], $fixtureApp)) -Message 'Imported selected applications are unchanged for the valid application name.'
    Assert-Condition -Condition (Test-LogRowsContainPattern -Rows $hostileRows -Pattern 'Profile version: \[invalid Version type\]') -Message 'Wrong-type metadata is validated before it reaches a log message.'
    Assert-Condition -Condition (Test-LogRowsContainPattern -Rows $hostileRows -Pattern ('Profile created: 2026-11-07 ' + [regex]::Escape($unicodeText) + '/line one line two forged row')) -Message 'Imported Unicode metadata is preserved and embedded line breaks and pipes are normalized.'
    Assert-Condition -Condition (($hostileRows -join "`n") -match 'Profile installer version: installer .*\.\.\. \[truncated\]') -Message 'Oversized metadata is truncated before log formatting.'
    Assert-Condition -Condition (($hostileRows -join "`n") -match ('Application not found in current installer: Missing/App line two forged row ' + [regex]::Escape($unicodeText))) -Message 'Missing application names stay useful after Markdown delimiter normalization.'
    Assert-Condition -Condition (Test-LogRowsContainPattern -Rows $hostileRows -Pattern 'Application name ignored because it exceeds 256 characters: .*\.\.\. \[truncated\]') -Message 'Oversized application names are bounded before logging.'
    Assert-Condition -Condition (Test-LogRowsContainPattern -Rows $hostileRows -Pattern 'Application entry ignored because its name is not a string') -Message 'Wrong-type application entries are rejected before matching or formatting.'
    Assert-Condition -Condition (-not (($hostileRows -join "`n").Contains('DEVICE-IDENTITY-SHOULD-NOT-LOG'))) -Message 'Legacy computer identity remains excluded from import diagnostics.'
    Assert-Condition -Condition ($null -eq $hostileResult.ProfileInfo.PSObject.Properties['ComputerName'] -and $null -eq $hostileResult.ProfileInfo.PSObject.Properties['UserName']) -Message 'Legacy computer and user identity remain excluded from returned profile information.'
    Assert-Condition -Condition ($hostileResult.MissingApps.Count -eq 3) -Message 'Missing and invalid application entries remain accounted for.'
    Assert-Condition -Condition ($hostileProfileBytesBefore -ceq [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($profilePath))) -Message 'Import leaves the source profile bytes unchanged.'
    Assert-FixedBoundedRows -Rows $hostileImportRows

    $legacyPath = Join-Path $testRoot 'legacy-profile.json'
    $legacyProfile = [ordered]@{
        Version = '1.0'
        Timestamp = '2025-11-10T18:40:47'
        ComputerName = 'LEGACY-DEVICE-SHOULD-NOT-LOG'
        UserName = 'legacy-user'
        InstallerVersion = 'legacy-version'
        Applications = @('Fixture App')
    }
    [System.IO.File]::WriteAllText($legacyPath, (ConvertTo-Json -InputObject $legacyProfile -Depth 8), $utf8NoBom)
    $legacyBytesBefore = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($legacyPath))
    $beforeRows = @(Get-MarkdownLogRows)
    $beforeLineCount = @(Get-MarkdownLogLines).Count
    $legacyResult = Import-InstallationProfile -FilePath $legacyPath
    $legacyRows = @(Get-MarkdownLogRows)
    $legacyLines = @(Get-MarkdownLogLines)
    $legacyImportRows = @($legacyRows | Select-Object -Skip $beforeRows.Count)
    Assert-Condition -Condition ($legacyResult.Success -and $legacyResult.Applications.Count -eq 1 -and [object]::ReferenceEquals($legacyResult.Applications[0], $fixtureApp)) -Message 'A valid legacy profile still imports its selected application.'
    Assert-Condition -Condition ($legacyImportRows.Count -eq 6) -Message 'A valid legacy import writes one row for each log call.'
    Assert-Condition -Condition ($legacyLines.Count -eq ($beforeLineCount + $legacyImportRows.Count)) -Message 'Valid legacy import produces no additional physical log lines.'
    Assert-Condition -Condition (($legacyRows -join "`n").Contains('Profile version: 1.0') -and ($legacyRows -join "`n").Contains('Profile created: 2025-11-10T18:40:47') -and ($legacyRows -join "`n").Contains('Profile installer version: legacy-version')) -Message 'Valid legacy metadata remains readable in the Markdown log.'
    Assert-Condition -Condition (-not (($legacyRows -join "`n").Contains('LEGACY-DEVICE-SHOULD-NOT-LOG'))) -Message 'Valid legacy identity metadata remains excluded from the Markdown log.'
    Assert-Condition -Condition ($legacyBytesBefore -ceq [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($legacyPath))) -Message 'Valid legacy import does not rewrite its source file.'
    Assert-FixedBoundedRows -Rows $legacyImportRows

    $unavailableDirectory = Join-Path $testRoot 'unavailable-log-directory'
    $script:LogPath = Join-Path $unavailableDirectory 'profile-import.md'
    $script:InstallInvocationCount = 0
    $bytesBeforeUnavailableLogImport = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($legacyPath))
    $unavailableLogResult = Import-InstallationProfile -FilePath $legacyPath
    Assert-Condition -Condition ($unavailableLogResult.Success -and $unavailableLogResult.Applications.Count -eq 1 -and [object]::ReferenceEquals($unavailableLogResult.Applications[0], $fixtureApp)) -Message 'Import outcome remains successful when the log path is unavailable.'
    Assert-Condition -Condition ($script:InstallInvocationCount -eq 0) -Message 'Import and logging failure do not start any installation action.'
    Assert-Condition -Condition ($bytesBeforeUnavailableLogImport -ceq [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($legacyPath))) -Message 'An unavailable log path does not alter the source profile.'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $unavailableDirectory)) -Message 'Unavailable logging does not create an unexpected log directory.'

    Write-Host "[OK] Profile import/log safety checks passed: $($script:assertionCount) assertions." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
