$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\InstructionHtmlTrust.psm1'
Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null

$script:checkCount = 0
$script:openedTargets = @()

function Assert-InstructionCondition {
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

$benignResult = ConvertTo-SanitizedInstructionDocument -Content @'
<!DOCTYPE html><html><head><title>Untrusted title</title></head><body><h1>Guide</h1><p>Read the <a href="https://example.test/guide" target="_blank">guide</a>.</p><p><a href="mailto:help@example.test">Email support</a></p></body></html>
'@
Assert-InstructionCondition -Condition ($benignResult.Status -eq 'Sanitized') -Message 'Benign well-formed HTML is accepted.'
Assert-InstructionCondition -Condition ($benignResult.DocumentText.Contains('<h1>Guide</h1>') -and $benignResult.DocumentText.Contains('href="https://example.test/guide"')) -Message 'Allowed structure and HTTPS links are retained.'
Assert-InstructionCondition -Condition ($benignResult.DocumentText.Contains('href="mailto:help@example.test"') -and -not $benignResult.DocumentText.Contains('target=')) -Message 'Mailto links are retained and window-target attributes are removed.'
$unapprovedLinkResult = ConvertTo-SanitizedInstructionDocument -Content '<html><head></head><body><a href="javascript:alert(1)">unsafe script link</a><a href="http://example.test/">plain HTTP link</a></body></html>'
Assert-InstructionCondition -Condition ($unapprovedLinkResult.DocumentText.Contains('unsafe script link') -and $unapprovedLinkResult.DocumentText.Contains('plain HTTP link')) -Message 'Labels for rejected links remain readable.'
Assert-InstructionCondition -Condition ($unapprovedLinkResult.DocumentText -notmatch '(?i)href="(?:javascript:|http:)') -Message 'JavaScript and non-HTTPS href values are removed during sanitization.'

$scriptResult = ConvertTo-SanitizedInstructionDocument -Content '<html><head></head><body><script>alert("untrusted-script")</script><p>Visible guide text</p></body></html>'
Assert-InstructionCondition -Condition ($scriptResult.Status -eq 'Sanitized' -and $scriptResult.DocumentText.Contains('Visible guide text')) -Message 'Safe text remains when script elements are removed.'
Assert-InstructionCondition -Condition ($scriptResult.DocumentText -notmatch '(?i)<\s*script\b|untrusted-script') -Message 'Script elements and their contents never reach the rendered document.'

$activeAttributeResult = ConvertTo-SanitizedInstructionDocument -Content '<html><head></head><body><p onclick="alert(1)" style="background:url(https://example.test/pixel)">Safe paragraph</p><img src="https://example.test/pixel" onerror="alert(2)"/><iframe src="https://example.test/frame">frame text</iframe><object data="https://example.test/object">object text</object><embed src="https://example.test/embed"/></body></html>'
Assert-InstructionCondition -Condition ($activeAttributeResult.Status -eq 'Sanitized' -and $activeAttributeResult.DocumentText.Contains('Safe paragraph')) -Message 'Allowed text survives input containing active attributes and resource tags.'
Assert-InstructionCondition -Condition ($activeAttributeResult.DocumentText -notmatch '(?i)\son[a-z0-9_-]+\s*=|\s(?:src|srcdoc|data|style|action|formaction)\s*=|<\s*(?:img|iframe|object|embed)\b') -Message 'Event attributes and unapproved resource references are removed.'
Assert-InstructionCondition -Condition (-not $activeAttributeResult.DocumentText.Contains('frame text') -and -not $activeAttributeResult.DocumentText.Contains('object text')) -Message 'Embedded object contents are discarded with their blocked elements.'

$malformedResult = ConvertTo-SanitizedInstructionDocument -Content '<html><head></head><body><div><p>malformed attacker content'
Assert-InstructionCondition -Condition ($malformedResult.Status -eq 'Fallback') -Message 'Malformed HTML uses the fixed static fallback.'
Assert-InstructionCondition -Condition ($malformedResult.DocumentText.Contains('Instructions unavailable') -and -not $malformedResult.DocumentText.Contains('malformed attacker content')) -Message 'Malformed source content is not reflected into the fallback.'

$instructionsPath = Join-Path $repositoryRoot 'instructions.html'
$localResult = Get-TrustedInstructionDocument -Path $instructionsPath
Assert-InstructionCondition -Condition ($localResult.Status -eq 'Loaded' -and $localResult.Reason -eq 'verified-local-payload') -Message 'The bundled instructions file matches its reviewed digest.'
Assert-InstructionCondition -Condition ($localResult.DocumentText.Contains('App Installer - User Guide')) -Message 'The verified local guide is available to the GUI.'
Assert-InstructionCondition -Condition ($localResult.DocumentText -notmatch '(?i)<\s*(?:script|iframe|object|embed)\b|\son[a-z0-9_-]+\s*=|\s(?:src|srcdoc|data|style|action|formaction)\s*=|javascript:') -Message 'The bundled guide reaches DocumentText only after active markup and attributes are removed.'

$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
$temporaryRoot = [System.IO.Path]::GetFullPath((Join-Path $temporaryBase ('app-installer-instruction-' + [guid]::NewGuid().ToString('N'))))
if (-not $temporaryRoot.StartsWith(($temporaryBase + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The instruction test temporary path is outside the system temporary directory.'
}
try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $guideContent = [System.IO.File]::ReadAllText($instructionsPath)
    $normalizedGuide = $guideContent -replace "`r`n?", "`n"
    $alternateLineEndings = $normalizedGuide.Replace("`n", "`r`n")
    $lineEndingVariantPath = Join-Path $temporaryRoot 'instructions-line-endings.html'
    [System.IO.File]::WriteAllText($lineEndingVariantPath, $alternateLineEndings, (New-Object System.Text.UTF8Encoding($false)))
    $lineEndingVariant = Get-TrustedInstructionDocument -Path $lineEndingVariantPath
    Assert-InstructionCondition -Condition ($lineEndingVariant.Status -eq 'Loaded') -Message 'The reviewed source digest is stable across Windows and Unix line endings.'

    $mismatchedSourcePath = Join-Path $temporaryRoot 'instructions.html'
    [System.IO.File]::WriteAllText($mismatchedSourcePath, '<html><head></head><body><script>unverified-source</script></body></html>', (New-Object System.Text.UTF8Encoding($false)))
    $mismatchedResult = Get-TrustedInstructionDocument -Path $mismatchedSourcePath
    Assert-InstructionCondition -Condition ($mismatchedResult.Status -eq 'Fallback' -and $mismatchedResult.Reason -eq 'source-digest-mismatch') -Message 'A changed or mismatched local source fails closed before rendering.'
    Assert-InstructionCondition -Condition (-not $mismatchedResult.DocumentText.Contains('unverified-source')) -Message 'Mismatched source content is not copied into the fallback document.'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

$navigationAction = {
    param($approvedUrl)
    $script:openedTargets += $approvedUrl
}
$httpsOpened = Invoke-AllowedExternalNavigation -Url 'https://example.test/support?q=help' -OpenAction $navigationAction
Assert-InstructionCondition -Condition ($httpsOpened -and $script:openedTargets.Count -eq 1 -and $script:openedTargets[0] -eq 'https://example.test/support?q=help') -Message 'HTTPS navigation is handed to the injected external opener.'
$mailtoOpened = Invoke-AllowedExternalNavigation -Url 'mailto:help@example.test' -OpenAction $navigationAction
Assert-InstructionCondition -Condition ($mailtoOpened -and $script:openedTargets.Count -eq 2 -and $script:openedTargets[1] -eq 'mailto:help@example.test') -Message 'Mailto navigation is handed to the injected external opener.'

foreach ($blockedUrl in @('http://example.test/', 'tel:+15551234567', 'javascript:alert(1)', 'data:text/html,unsafe', 'file:///C:/Windows/win.ini', '//example.test/path', 'https://user@example.test/')) {
    $wasOpened = Invoke-AllowedExternalNavigation -Url $blockedUrl -OpenAction $navigationAction
    Assert-InstructionCondition -Condition (-not $wasOpened -and $script:openedTargets.Count -eq 2) -Message ("Navigation is blocked for {0}." -f $blockedUrl)
}

$manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'payload-manifest.json') -Raw | ConvertFrom-Json -ErrorAction Stop
Assert-InstructionCondition -Condition (@($manifest.features.gui) -contains 'instructions.html') -Message 'The reviewed instructions file is part of the GUI payload.'
Assert-InstructionCondition -Condition (@($manifest.features.gui) -contains 'modules/InstructionHtmlTrust.psm1') -Message 'The instruction verifier and sanitizer are part of the GUI payload.'

$appSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'app-installer.ps1') -Raw
Assert-InstructionCondition -Condition ($appSource -notmatch 'raw\.githubusercontent\.com/mytech-today-now/app_installer/.+instructions\.html') -Message 'The GUI instruction path contains no mutable GitHub fetch.'
$switchStart = $appSource.IndexOf('function Switch-ToInstructionsView', [System.StringComparison]::Ordinal)
$switchEnd = $appSource.IndexOf('function ', $switchStart + 1, [System.StringComparison]::Ordinal)
if ($switchStart -lt 0 -or $switchEnd -le $switchStart) {
    throw 'Could not locate the instruction view function for its offline source contract.'
}
$switchSource = $appSource.Substring($switchStart, $switchEnd - $switchStart)
Assert-InstructionCondition -Condition ($switchSource.Contains('Get-TrustedInstructionDocument') -and $switchSource.Contains('DocumentText = $script:InstructionsHtmlContent')) -Message 'DocumentText receives only the verified sanitizer result.'
Assert-InstructionCondition -Condition ($switchSource -notmatch 'Invoke-WebRequest|\$response\.Content') -Message 'The instructions view performs no HTTP response assignment or remote fetch.'

$browserSetupStart = $appSource.IndexOf('$script:WebBrowser.Add_NewWindow', [System.StringComparison]::Ordinal)
$browserSetupEnd = $appSource.IndexOf('# Calculate responsive HTML font sizes', $browserSetupStart, [System.StringComparison]::Ordinal)
if ($browserSetupStart -lt 0 -or $browserSetupEnd -le $browserSetupStart) {
    throw 'Could not locate the WebBrowser navigation handlers for their offline contract.'
}
$browserSetup = $appSource.Substring($browserSetupStart, $browserSetupEnd - $browserSetupStart)
Assert-InstructionCondition -Condition ([regex]::Matches($browserSetup, 'Invoke-AllowedExternalNavigation').Count -eq 2) -Message 'Normal and new-window navigation both use the shared URI allowlist.'
Assert-InstructionCondition -Condition ($browserSetup.Contains('$e.Cancel = $true') -and $browserSetup -notmatch 'Start-Process\s+\$url') -Message 'Navigation is canceled in the embedded browser before any external handoff.'

Write-Host ("[OK] Instruction HTML security checks passed: {0} assertions." -f $script:checkCount) -ForegroundColor Green
exit 0
