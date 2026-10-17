#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$trustModulePath = Join-Path $repositoryRoot 'modules\StartupHelperTrust.psm1'
$responsiveHelperPath = Join-Path $repositoryRoot 'modules\ResponsiveGuiHelper.psm1'
$guiEntryPath = Join-Path $repositoryRoot 'app-installer.ps1'
$cliEntryPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('app-installer-startup-trust-' + [guid]::NewGuid().ToString('N'))
$checkCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:checkCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Get-StartupRegion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$StartMarker,

        [Parameter(Mandatory = $true)]
        [string]$EndMarker
    )

    $start = $Content.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Startup region marker was not found: $StartMarker"
    }

    $end = $Content.IndexOf($EndMarker, $start, [System.StringComparison]::Ordinal)
    if ($end -lt 0) {
        throw "Startup region end marker was not found: $EndMarker"
    }

    return $Content.Substring($start, $end - $start)
}

function Get-PowerShellParseErrors {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
    return ,$parseErrors
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Import-Module -Name $trustModulePath -Force -DisableNameChecking

    $guiContent = [System.IO.File]::ReadAllText($guiEntryPath)
    $cliContent = [System.IO.File]::ReadAllText($cliEntryPath)
    $helperContent = [System.IO.File]::ReadAllText($responsiveHelperPath)
    $guiStartup = Get-StartupRegion -Content $guiContent -StartMarker '#region Load Responsive GUI Helper' -EndMarker '#endregion'
    $cliStartup = Get-StartupRegion -Content $cliContent -StartMarker '#region Load Generic Logging Module' -EndMarker '#endregion'

    Assert-Condition -Condition (-not $guiStartup.Contains('Invoke-WebRequest')) -Message 'GUI helper startup makes no HTTP request'
    Assert-Condition -Condition (-not $guiStartup.Contains('Invoke-Expression')) -Message 'GUI helper startup does not evaluate response text'
    Assert-Condition -Condition (-not $guiStartup.Contains('raw.githubusercontent.com')) -Message 'GUI helper startup contains no mutable remote source URL'
    Assert-Condition -Condition (-not $cliStartup.Contains('Invoke-WebRequest')) -Message 'CLI helper startup makes no HTTP request'
    Assert-Condition -Condition (-not $cliStartup.Contains('Invoke-Expression')) -Message 'CLI helper startup does not evaluate response text'
    Assert-Condition -Condition (-not $cliStartup.Contains('raw.githubusercontent.com')) -Message 'CLI helper startup contains no mutable remote source URL'
    Assert-Condition -Condition ($guiStartup.Contains('Test-StartupHelperFile') -and $guiStartup.Contains('Import-Module')) -Message 'GUI loads the bundled helper only after the digest verifier succeeds'
    Assert-Condition -Condition ($guiStartup.Contains('ResponsiveHelperSha256')) -Message 'GUI startup has a separately reviewed SHA-256 pin'
    Assert-Condition -Condition ($guiContent.Contains('function New-BuiltInResponsiveForm')) -Message 'GUI has built-in responsive form behavior when the helper is absent'
    Assert-Condition -Condition ($guiContent.Contains('ResponsiveHelperLoadAttempted')) -Message 'GUI prevents duplicate helper initialization in one script scope'
    Assert-Condition -Condition ($guiContent.Contains('A required optional helper could not be verified. Installation remains available with built-in behavior.')) -Message 'GUI contains the required fallback status'
    Assert-Condition -Condition ($cliContent.Contains('A required optional helper could not be verified. Installation remains available with built-in behavior.')) -Message 'CLI contains the required fallback status'
    Assert-Condition -Condition ($cliContent.Contains('function Initialize-Logging') -and $cliContent.Contains('function Write-Log')) -Message 'CLI retains built-in logging'
    Assert-Condition -Condition ($guiContent.Contains('function Initialize-Logging') -and $guiContent.Contains('function Write-Log')) -Message 'GUI retains built-in logging'
    Assert-Condition -Condition ($helperContent.Contains('function New-ResponsiveForm')) -Message 'Bundled responsive helper preserves the GUI form contract'

    $pinMatch = [regex]::Match($guiContent, "ResponsiveHelperSha256\s*=\s*'([0-9A-Fa-f]{64})'")
    Assert-Condition -Condition $pinMatch.Success -Message 'GUI helper trust anchor is a 64-character SHA-256 value'

    $actualHelperHash = Get-StartupHelperSha256 -LiteralPath $responsiveHelperPath
    Assert-Condition -Condition ([string]::Equals($actualHelperHash, $pinMatch.Groups[1].Value, [System.StringComparison]::OrdinalIgnoreCase)) -Message 'Bundled GUI helper matches the reviewed SHA-256 pin'

    $verifiedHelper = Test-StartupHelperFile -LiteralPath $responsiveHelperPath -ExpectedSha256 $pinMatch.Groups[1].Value
    Assert-Condition -Condition ($verifiedHelper.Verified -and $verifiedHelper.Reason -eq 'verified') -Message 'Known digest is accepted before the bundled helper is loaded'

    $alreadyLoaded = Get-Module -Name ResponsiveGuiHelper |
        Where-Object { $_.Path -eq $verifiedHelper.Path } |
        Select-Object -First 1
    if (-not $alreadyLoaded) {
        Import-Module -Name $verifiedHelper.Path -ErrorAction Stop
    }

    $moduleInstances = @(Get-Module -Name ResponsiveGuiHelper | Where-Object { $_.Path -eq $verifiedHelper.Path })
    Assert-Condition -Condition ($moduleInstances.Count -eq 1) -Message 'Known digest loads the helper once'

    $maliciousPath = Join-Path $tempRoot 'ChangedHelper.psm1'
    $safeContent = "function Get-TestHelperValue { 'safe' }`nExport-ModuleMember -Function Get-TestHelperValue`n"
    [System.IO.File]::WriteAllText($maliciousPath, $safeContent, [System.Text.Encoding]::UTF8)
    $knownSafeHash = Get-StartupHelperSha256 -LiteralPath $maliciousPath
    $markerPath = Join-Path $tempRoot 'rejected-helper-marker.txt'
    $markerLiteralPath = $markerPath.Replace("'", "''")
    $maliciousContent = '$global:RejectedStartupHelperSentinel = $true' + "`nSet-Content -LiteralPath '$markerLiteralPath' -Value 'executed'`n"
    [System.IO.File]::WriteAllText($maliciousPath, $maliciousContent, [System.Text.Encoding]::UTF8)
    Remove-Variable -Name RejectedStartupHelperSentinel -Scope Global -ErrorAction SilentlyContinue

    $changedHelper = Test-StartupHelperFile -LiteralPath $maliciousPath -ExpectedSha256 $knownSafeHash
    Assert-Condition -Condition (-not $changedHelper.Verified -and $changedHelper.Reason -eq 'mismatch') -Message 'Changed digest is rejected'
    if ($changedHelper.Verified) {
        Import-Module -Name $changedHelper.Path -Force -ErrorAction Stop
    }
    Assert-Condition -Condition ($null -eq (Get-Variable -Name RejectedStartupHelperSentinel -Scope Global -ErrorAction SilentlyContinue)) -Message 'Changed content does not execute a sentinel statement'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) -Message 'Changed content does not create a marker file'

    $invalidPin = Test-StartupHelperFile -LiteralPath $responsiveHelperPath -ExpectedSha256 'not-a-digest'
    Assert-Condition -Condition (-not $invalidPin.Verified -and $invalidPin.Reason -eq 'invalid-pin') -Message 'Malformed digest pin is rejected'

    $missingHelper = Test-StartupHelperFile -LiteralPath (Join-Path $tempRoot 'missing.psm1') -ExpectedSha256 $pinMatch.Groups[1].Value
    Assert-Condition -Condition (-not $missingHelper.Verified -and $missingHelper.Reason -eq 'missing') -Message 'Missing helper selects the built-in fallback path'

    $malformedPath = Join-Path $tempRoot 'MalformedHelper.psm1'
    $malformedContent = '$global:MalformedStartupHelperSentinel = $true' + "`nfunction Broken {`n"
    [System.IO.File]::WriteAllText($malformedPath, $malformedContent, [System.Text.Encoding]::UTF8)
    $malformedHash = Get-StartupHelperSha256 -LiteralPath $malformedPath
    $malformedCheck = Test-StartupHelperFile -LiteralPath $malformedPath -ExpectedSha256 $malformedHash
    Assert-Condition -Condition $malformedCheck.Verified -Message 'Malformed helper bytes can pass only the byte-integrity phase'
    Remove-Variable -Name MalformedStartupHelperSentinel -Scope Global -ErrorAction SilentlyContinue
    try {
        Import-Module -Name $malformedPath -Force -ErrorAction Stop | Out-Null
        throw 'Malformed helper unexpectedly parsed.'
    }
    catch {
        if ($_.Exception.Message -eq 'Malformed helper unexpectedly parsed.') {
            throw
        }
    }
    Assert-Condition -Condition ($null -eq (Get-Variable -Name MalformedStartupHelperSentinel -Scope Global -ErrorAction SilentlyContinue)) -Message 'Malformed helper source does not run a sentinel before parsing succeeds'

    Assert-Condition -Condition (-not $guiStartup.Contains('Invoke-WebRequest') -and -not $cliStartup.Contains('Invoke-WebRequest')) -Message 'Timeout and non-success HTTP cases cannot execute response content because startup makes no request'
    Assert-Condition -Condition (-not $guiStartup.Contains('winget') -and -not $cliStartup.Contains('winget')) -Message 'Helper fallback path does not invoke a package manager'

    foreach ($path in @($guiEntryPath, $cliEntryPath, $trustModulePath, $responsiveHelperPath)) {
        $parseErrors = Get-PowerShellParseErrors -Path $path
        Assert-Condition -Condition ($parseErrors.Count -eq 0) -Message "PowerShell syntax is valid: $(Split-Path $path -Leaf)"
    }

    Write-Host "Startup helper trust checks passed ($checkCount assertions)." -ForegroundColor Cyan
}
finally {
    Remove-Module -Name ResponsiveGuiHelper -ErrorAction SilentlyContinue
    Remove-Module -Name StartupTrustPositive -ErrorAction SilentlyContinue
    Remove-Module -Name ChangedHelper -ErrorAction SilentlyContinue
    Remove-Module -Name MalformedHelper -ErrorAction SilentlyContinue
    Remove-Variable -Name RejectedStartupHelperSentinel, MalformedStartupHelperSentinel -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
