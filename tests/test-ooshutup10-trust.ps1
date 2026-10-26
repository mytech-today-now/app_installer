#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$productionModulePath = Join-Path $repositoryRoot 'modules\OOShutUp10Trust.psm1'
$guiPath = Join-Path $repositoryRoot 'app-installer.ps1'
$cliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$fallbackScriptPath = Join-Path $repositoryRoot 'apps\shutup10.ps1'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-ooshutup10-tests-' + [Guid]::NewGuid().ToString('N'))))
$checkCount = 0

if (-not $testRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Test directory is outside the system temporary directory.'
}

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

function Get-TestSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha256.ComputeHash($Bytes)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function New-FakeDownloadScript {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $capturedBytes = $Bytes
    return { param($RequestedUri) return ,$capturedBytes }.GetNewClosure()
}

function New-RunScriptExecutor {
    return {
        param($LiteralPath, $ScriptArguments)
        & $LiteralPath @ScriptArguments
        return [PSCustomObject]@{ ExitCode = 0 }
    }.GetNewClosure()
}

function Get-FunctionDefinitionText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
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

try {
    New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
    Import-Module -Name $productionModulePath -Force -DisableNameChecking -ErrorAction Stop

    $release = Get-OOShutUp10PinnedRelease
    Assert-Condition -Condition (-not $release.Uri -and -not $release.Sha256) -Message 'No unreviewed O&O release is enabled in production.'
    $productionChildRunnerText = Get-FunctionDefinitionText -Path $productionModulePath -Name 'Start-OOVerifiedChildProcess'
    Assert-Condition -Condition ($productionChildRunnerText.Contains('-NoProfile -NonInteractive -File') -and $productionChildRunnerText.Contains('-RedirectStandardError $standardErrorPath') -and $productionChildRunnerText.Contains('PolicyBlocked = [bool]$policyBlocked') -and $productionChildRunnerText -notmatch '(?i)-ExecutionPolicy\b') -Message 'Verified O&O children respect policy, detect blocked launch stderr, and retain no bypass option.'

    $fixedSharedPath = Join-Path $testRoot 'Install-OOShutUp10.ps1'
    $markerPath = Join-Path $testRoot 'approved-script-executed.txt'
    $markerLiteral = $markerPath.Replace("'", "''")
    $harmlessScript = "`$marker = '$markerLiteral'`r`nAdd-Content -LiteralPath `$marker -Value 'ran'`r`n"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $approvedBytes = $encoding.GetBytes($harmlessScript)
    $approvedHash = Get-TestSha256 -Bytes $approvedBytes
    Write-Host ("Test-only harmless payload SHA-256: {0}" -f $approvedHash) -ForegroundColor Gray
    $immutableUri = 'https://raw.githubusercontent.com/mytech-today-now/OO/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Install-OOShutUp10.ps1'
    $tempRoot = Join-Path $testRoot 'private-temp'
    New-Item -ItemType Directory -Path $tempRoot -ErrorAction Stop | Out-Null
    $fakeDownload = New-FakeDownloadScript -Bytes $approvedBytes
    $runExecutor = New-RunScriptExecutor

    $productionAclProbe = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload `
        -ExecutorScript { param($LiteralPath, $ScriptArguments) return [PSCustomObject]@{ ExitCode = 0 } }
    if ($productionAclProbe.FailureReason -eq 'temporary-workspace-unavailable') {
        Assert-Condition -Condition ($productionAclProbe.DownloadStatus -eq 'not-attempted' -and -not $productionAclProbe.Success) -Message 'Production fails closed when this sandbox blocks private ACL setup.'
        Write-Host '[SKIP] Runtime ACL hardening is blocked by the current host sandbox; the production path failed closed.' -ForegroundColor Yellow
    }
    elseif ($productionAclProbe.Success) {
        Assert-Condition -Condition ($productionAclProbe.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $productionAclProbe.TempDirectory)) -Message 'Production ACL hardening succeeds and cleans the verified test path when permitted.'
    }
    else {
        throw "Unexpected production ACL probe outcome: $($productionAclProbe.FailureReason)"
    }

    $productionModule = Get-Module -Name OOShutUp10Trust
    Remove-Module -ModuleInfo $productionModule -Force -ErrorAction Stop
    $productionModuleContent = [System.IO.File]::ReadAllText($productionModulePath)
    Assert-Condition -Condition ($productionModuleContent.Contains('$directorySecurity.SetAccessRuleProtection($true, $false)') -and $productionModuleContent.Contains('S-1-5-18') -and $productionModuleContent.Contains('S-1-5-32-544') -and $productionModuleContent.Contains('Set-Acl -LiteralPath $LiteralPath')) -Message 'Production temp ACL is protected and grants access only to the current user, SYSTEM, and Administrators.'

    # The current Codex sandbox blocks DACL updates on temp directories. Test a copy
    # with only the ACL setter call stubbed so the transfer, hash, child, and cleanup
    # paths remain executable without weakening the production module.
    $moduleSource = [System.IO.File]::ReadAllText($productionModulePath)
    $aclCall = 'Set-OOPrivateDirectoryAcl -LiteralPath $directoryPath'
    if ($moduleSource.Split(@($aclCall), [System.StringSplitOptions]::None).Length -ne 2) {
        throw 'Expected exactly one temp ACL call in the production module.'
    }
    $testModulePath = Join-Path $testRoot 'OOShutUp10Trust.TestHarness.psm1'
    $testModuleSource = $moduleSource.Replace($aclCall, '# Test harness stub: ACL writes are blocked by this host sandbox.')
    [System.IO.File]::WriteAllText($testModulePath, $testModuleSource, $encoding)
    $modulePath = $testModulePath
    Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop

    $approvedResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload

    Assert-Condition -Condition $approvedResult.Success -Message 'An approved SHA-256 executes the harmless test script successfully.'
    Assert-Condition -Condition ($approvedResult.DownloadStatus -eq 'downloaded' -and $approvedResult.VerificationStatus -eq 'verified' -and $approvedResult.InstallationStatus -eq 'succeeded') -Message 'Download, verification, and installation statuses are independent and truthful.'
    Assert-Condition -Condition ((Get-Content -LiteralPath $markerPath).Count -eq 1) -Message 'Verified script bytes execute exactly once.'
    Assert-Condition -Condition ($approvedResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $approvedResult.TempDirectory)) -Message 'The private temp directory is removed after success.'

    $staleScript = '$global:OOScriptFromStalePathExecuted = $true'
    [System.IO.File]::WriteAllText($fixedSharedPath, $staleScript, $encoding)
    $staleResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload

    Assert-Condition -Condition $staleResult.Success -Message 'A stale file at the former shared temp filename does not block a verified run.'
    Assert-Condition -Condition ($approvedResult.TempDirectory -ne $staleResult.TempDirectory) -Message 'Separate invocations receive different randomized temp directories.'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($fixedSharedPath) -eq $staleScript) -Message 'The stale shared temp file is not reused, overwritten, or executed.'
    Assert-Condition -Condition ($null -eq (Get-Variable -Name OOScriptFromStalePathExecuted -Scope Global -ErrorAction SilentlyContinue)) -Message 'The stale script content is never executed.'
    Assert-Condition -Condition ((Get-Content -LiteralPath $markerPath).Count -eq 2) -Message 'The second verified invocation executes its own bytes once.'

    $changedBytes = $encoding.GetBytes("`$global:OOChangedBytesExecuted = `$true`r`n")
    $changedResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript (New-FakeDownloadScript -Bytes $changedBytes) `
        -ExecutorScript $runExecutor

    Assert-Condition -Condition (-not $changedResult.Success -and $changedResult.FailureReason -eq 'digest-mismatch' -and $changedResult.InstallationStatus -eq 'not-started') -Message 'Changed response bytes are rejected before child execution.'
    Assert-Condition -Condition ($changedResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $changedResult.TempDirectory)) -Message 'Changed bytes are cleaned from the private temp directory.'
    Assert-Condition -Condition ($null -eq (Get-Variable -Name OOChangedBytesExecuted -Scope Global -ErrorAction SilentlyContinue)) -Message 'Changed response code never executes.'

    $httpFailure = { param($RequestedUri) throw [System.Net.WebException]::new('fake HTTP failure') }.GetNewClosure()
    $httpFailureResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $httpFailure `
        -ExecutorScript $runExecutor

    Assert-Condition -Condition (-not $httpFailureResult.Success -and $httpFailureResult.DownloadStatus -eq 'failed' -and $httpFailureResult.InstallationStatus -eq 'not-started') -Message 'Failed HTTP stops before execution and reports download failure.'
    Assert-Condition -Condition ($httpFailureResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $httpFailureResult.TempDirectory)) -Message 'Failed HTTP cleans its private temp directory.'

    $signatureFailure = { param($LiteralPath, $Thumbprint) return $false }.GetNewClosure()
    $signatureFailureResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -ExpectedSignerThumbprint ('A' * 40) `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload `
        -SignatureVerifier $signatureFailure `
        -ExecutorScript $runExecutor

    Assert-Condition -Condition (-not $signatureFailureResult.Success -and $signatureFailureResult.FailureReason -eq 'signature-invalid' -and $signatureFailureResult.InstallationStatus -eq 'not-started') -Message 'An invalid Authenticode signer is rejected before execution.'
    Assert-Condition -Condition ($signatureFailureResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $signatureFailureResult.TempDirectory)) -Message 'Invalid signatures are cleaned from the private temp directory.'
    Assert-Condition -Condition ((Get-Content -LiteralPath $markerPath).Count -eq 2) -Message 'Digest-valid content with an invalid signer is not executed.'

    $invalidOutput = { param($RequestedUri) return ,([byte[]]@()) }.GetNewClosure()
    $invalidOutputResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $invalidOutput `
        -ExecutorScript $runExecutor
    Assert-Condition -Condition (-not $invalidOutputResult.Success -and $invalidOutputResult.DownloadStatus -eq 'invalid-output' -and $invalidOutputResult.InstallationStatus -eq 'not-started') -Message 'Empty or invalid download output cannot execute.'

    $cancelledDownload = { param($RequestedUri) throw [System.OperationCanceledException]::new() }.GetNewClosure()
    $cancelledResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $cancelledDownload `
        -ExecutorScript $runExecutor
    Assert-Condition -Condition (-not $cancelledResult.Success -and $cancelledResult.FailureReason -eq 'cancelled' -and $cancelledResult.InstallationStatus -eq 'not-started') -Message 'Cancellation stops before execution and does not record success.'
    Assert-Condition -Condition ($cancelledResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $cancelledResult.TempDirectory)) -Message 'Cancellation cleans its private temp directory.'

    $throwingExecutor = { param($LiteralPath, $ScriptArguments) throw 'fake child launch failure' }.GetNewClosure()
    $executionExceptionResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload `
        -ExecutorScript $throwingExecutor
    Assert-Condition -Condition (-not $executionExceptionResult.Success -and $executionExceptionResult.InstallationStatus -eq 'unknown' -and $executionExceptionResult.FailureReason -eq 'child-execution-failed') -Message 'Unexpected child failures never leave a success status.'
    Assert-Condition -Condition ($executionExceptionResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $executionExceptionResult.TempDirectory)) -Message 'A child exception still cleans the private temp directory.'
    Assert-Condition -Condition (-not $executionExceptionResult.FailureReason.Contains('fake child launch failure')) -Message 'Unexpected exception details are not exposed in the result.'

    $cancelledExecutor = { param($LiteralPath, $ScriptArguments) throw [System.OperationCanceledException]::new() }.GetNewClosure()
    $cancelledExecutionResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload `
        -ExecutorScript $cancelledExecutor
    Assert-Condition -Condition (-not $cancelledExecutionResult.Success -and $cancelledExecutionResult.InstallationStatus -eq 'unknown' -and $cancelledExecutionResult.FailureReason -eq 'child-execution-cancelled') -Message 'Cancellation after child start records an unknown result, not a no-change claim.'
    Assert-Condition -Condition ($cancelledExecutionResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $cancelledExecutionResult.TempDirectory)) -Message 'Child cancellation still removes the verified temp script.'

    $nonzeroExecutor = { param($LiteralPath, $ScriptArguments) return [PSCustomObject]@{ ExitCode = 7 } }.GetNewClosure()
    $nonzeroResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload `
        -ExecutorScript $nonzeroExecutor
    Assert-Condition -Condition (-not $nonzeroResult.Success -and $nonzeroResult.ExitCode -eq 7 -and $nonzeroResult.InstallationStatus -eq 'failed') -Message 'Nonzero child status is captured and never reported as success.'
    Assert-Condition -Condition ($nonzeroResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $nonzeroResult.TempDirectory)) -Message 'A nonzero child result still removes the temp script.'

    $policyBefore = (Get-ExecutionPolicy -List | ForEach-Object { '{0}={1}' -f $_.Scope, $_.ExecutionPolicy }) -join ';'
    $policyMessage = 'PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator.'
    $policyBlockedExecutor = { param($LiteralPath, $ScriptArguments) return [PSCustomObject]@{ ExitCode = 1; PolicyBlocked = $true } }.GetNewClosure()
    $policyBlockedResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload `
        -ExecutorScript $policyBlockedExecutor
    $policyAfter = (Get-ExecutionPolicy -List | ForEach-Object { '{0}={1}' -f $_.Scope, $_.ExecutionPolicy }) -join ';'
    Assert-Condition -Condition (-not $policyBlockedResult.Success -and $policyBlockedResult.ExitCode -eq 1 -and $policyBlockedResult.InstallationStatus -eq 'failed' -and $policyBlockedResult.FailureReason -eq 'execution-policy-blocked') -Message 'A policy-blocked fake child returns nonzero and cannot be reported complete.'
    Assert-Condition -Condition ($policyBlockedResult.RecoveryMessage -ceq $policyMessage) -Message 'A policy block carries the sanitized recovery message for visible reporting.'
    Assert-Condition -Condition ($policyAfter -ceq $policyBefore) -Message 'The policy-blocked child harness leaves every execution-policy scope unchanged.'
    Assert-Condition -Condition ($policyBlockedResult.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $policyBlockedResult.TempDirectory)) -Message 'A policy-blocked child still cleans its verified temp script.'

    $invalidPowerShell = $encoding.GetBytes("function Broken {`r`n")
    $invalidPowerShellHash = Get-TestSha256 -Bytes $invalidPowerShell
    $invalidPowerShellResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $immutableUri `
        -ExpectedSha256 $invalidPowerShellHash `
        -TempRoot $tempRoot `
        -DownloadScript (New-FakeDownloadScript -Bytes $invalidPowerShell) `
        -ExecutorScript $runExecutor
    Assert-Condition -Condition (-not $invalidPowerShellResult.Success -and $invalidPowerShellResult.FailureReason -eq 'invalid-powershell-output' -and $invalidPowerShellResult.InstallationStatus -eq 'not-started') -Message 'Digest-matching but invalid PowerShell output is rejected before launch.'

    $mutableUriResult = Invoke-VerifiedOOShutUp10Script `
        -Uri 'https://raw.githubusercontent.com/mytech-today-now/OO/main/Install-OOShutUp10.ps1' `
        -ExpectedSha256 $approvedHash `
        -TempRoot $tempRoot `
        -DownloadScript $fakeDownload `
        -ExecutorScript $runExecutor
    Assert-Condition -Condition (-not $mutableUriResult.Success -and $mutableUriResult.FailureReason -eq 'source-not-immutable' -and $mutableUriResult.DownloadStatus -eq 'not-attempted') -Message 'Mutable branch URLs are rejected before network access.'

    $unconfiguredNetworkAttempts = New-Object 'System.Collections.Generic.List[int]'
    $unconfiguredNetworkProbe = { param($RequestedUri) $unconfiguredNetworkAttempts.Add(1); return ,([byte[]]@()) }.GetNewClosure()
    $unconfiguredResult = Invoke-VerifiedOOShutUp10Script `
        -Uri $release.Uri `
        -ExpectedSha256 $release.Sha256 `
        -TempRoot $tempRoot `
        -DownloadScript $unconfiguredNetworkProbe
    Assert-Condition -Condition (-not $unconfiguredResult.Success -and $unconfiguredResult.FailureReason -eq 'release-not-configured' -and $unconfiguredResult.DownloadStatus -eq 'not-attempted' -and $unconfiguredNetworkAttempts.Count -eq 0) -Message 'Production fails closed without a release pin and makes no network call.'

    # Run two isolated operations in parallel using fake bytes and a no-op executor.
    $encodedPayload = [Convert]::ToBase64String($approvedBytes)
    $parallelJob = {
        param($TrustModulePath, $SourceUri, $Digest, $Payload, $PrivateTempRoot)
        Import-Module -Name $TrustModulePath -Force -DisableNameChecking -ErrorAction Stop
        $bytes = [Convert]::FromBase64String($Payload)
        $download = { param($RequestedUri) return ,$bytes }.GetNewClosure()
        $executor = { param($LiteralPath, $ScriptArguments) return [PSCustomObject]@{ ExitCode = 0 } }.GetNewClosure()
        Invoke-VerifiedOOShutUp10Script -Uri $SourceUri -ExpectedSha256 $Digest -TempRoot $PrivateTempRoot -DownloadScript $download -ExecutorScript $executor
    }
    $jobA = Start-Job -ScriptBlock $parallelJob -ArgumentList $modulePath, $immutableUri, $approvedHash, $encodedPayload, $tempRoot
    $jobB = Start-Job -ScriptBlock $parallelJob -ArgumentList $modulePath, $immutableUri, $approvedHash, $encodedPayload, $tempRoot
    try {
        $null = Wait-Job -Job @($jobA, $jobB) -Timeout 60
        $parallelResults = @(Receive-Job -Job @($jobA, $jobB) -ErrorAction Stop)
    }
    finally {
        Remove-Job -Job @($jobA, $jobB) -Force -ErrorAction SilentlyContinue
    }
    Assert-Condition -Condition ($parallelResults.Count -eq 2 -and @($parallelResults | Where-Object { $_.Success }).Count -eq 2) -Message 'Two concurrent fake invocations complete without sharing script paths.'
    Assert-Condition -Condition ($parallelResults[0].TempDirectory -ne $parallelResults[1].TempDirectory) -Message 'Concurrent invocations get exclusive randomized directories.'
    Assert-Condition -Condition (@($parallelResults | Where-Object { $_.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $_.TempDirectory) }).Count -eq 2) -Message 'Concurrent invocations both clean up after success.'

    # Exercise the real CLI O&O branch with the local fallback present and fail-closed release configuration.
    $fallbackRoot = Join-Path $testRoot 'fallback'
    New-Item -ItemType Directory -Path $fallbackRoot -ErrorAction Stop | Out-Null
    $localMarkerPath = Join-Path $testRoot 'local-fallback-executed.txt'
    $localMarkerLiteral = $localMarkerPath.Replace("'", "''")
    [System.IO.File]::WriteAllText((Join-Path $fallbackRoot 'shutup10.ps1'), "Set-Content -LiteralPath '$localMarkerLiteral' -Value 'executed'`r`n", $encoding)
    $script:OOShutUp10TrustModulePath = [System.IO.Path]::GetFullPath($productionModulePath)
    $script:AppsPath = $fallbackRoot
    $script:InstalledApps = @{}
    $fixtureDirectory = Join-Path $testRoot 'fixture'
    New-Item -ItemType Directory -Path $fixtureDirectory -ErrorAction Stop | Out-Null
    $fixtureExecutablePath = Join-Path $fixtureDirectory 'OOSU10.exe'
    [System.IO.File]::WriteAllBytes($fixtureExecutablePath, [byte[]]@(77, 90, 0, 0, 0, 0))
    $script:OOFixtureExecutablePath = $fixtureExecutablePath
    function Write-Log { param($Message, $Level) }
    function Safe-TestPath {
        param($Path, [string]$PathType = 'Any')
        if ($Path -eq 'C:\Program Files\OOShutUp10\OOSU10.exe') {
            if (-not $script:OOFixtureExecutablePath) { return $false }
            if ($PathType -eq 'Leaf') {
                return (Test-Path -LiteralPath $script:OOFixtureExecutablePath -PathType Leaf)
            }
            return (Test-Path -LiteralPath $script:OOFixtureExecutablePath)
        }
        return $false
    }

    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'New-InstallerActionResult')
    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'Get-InstallerActionStatus')
    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'Test-InstallerShouldProcess')
    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'Install-OOShutUp10FromRemote')
    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'Install-Application')

    # Installed-app discovery is observational and must not re-run O&O settings.
    $cliRemoteHelperText = Get-FunctionDefinitionText -Path $cliPath -Name 'Install-OOShutUp10FromRemote'
    $script:Applications = @([PSCustomObject]@{ Name = 'O&O ShutUp10'; WingetId = $null })
    $script:OOSettingsApplyCount = 0
    $settingsMarkerPath = Join-Path $testRoot 'ooshutup-settings-applied.txt'
    function Test-WingetAvailable { return $false }
    function Get-ItemProperty { param([string[]]$Path, $ErrorAction) return @() }
    function Safe-TestPath {
        param($Path, [string]$PathType = 'Any')
        if ($Path -eq 'C:\Program Files\OOShutUp10\OOSU10.exe') {
            if (-not $script:OOFixtureExecutablePath) { return $false }
            if ($PathType -eq 'Leaf') {
                return (Test-Path -LiteralPath $script:OOFixtureExecutablePath -PathType Leaf)
            }
            return (Test-Path -LiteralPath $script:OOFixtureExecutablePath)
        }
        return $false
    }
    function Get-Item {
        param([string]$Path, $ErrorAction)
        return [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ FileVersion = 'test-installed-version' } }
    }
    function Install-OOShutUp10FromRemote {
        $script:OOSettingsApplyCount++
        Set-Content -LiteralPath $settingsMarkerPath -Value 'settings applied'
    }
    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'Get-InstalledApplications')
    $detectedInstalledApps = Get-InstalledApplications
    Assert-Condition -Condition ($detectedInstalledApps.ContainsKey('O&O ShutUp10') -and $detectedInstalledApps['O&O ShutUp10'] -eq 'test-installed-version') -Message 'An existing O&O executable is detected without invoking installation.'
    Assert-Condition -Condition ($script:OOSettingsApplyCount -eq 0 -and -not (Test-Path -LiteralPath $settingsMarkerPath)) -Message 'Installed-app discovery does not reapply O&O privacy settings.'

    # Restore the real helper for subsequent fail-closed integration checks.
    Invoke-Expression $cliRemoteHelperText

    $script:OOFixtureExecutablePath = $null
    $queue = @(
        @{ Name = 'O&O ShutUp10'; ScriptName = 'shutup10.ps1'; WingetId = $null },
        @{ Name = 'Other App A'; ScriptName = 'other-a.ps1'; WingetId = 'Example.A' },
        @{ Name = 'Other App B'; ScriptName = 'other-b.ps1'; WingetId = 'Example.B' }
    )
    $originalQueueOrder = @($queue | ForEach-Object { $_.Name })
    $installOutcome = Install-Application -App $queue[0]
    $currentQueueOrder = @($queue | ForEach-Object { $_.Name })

    Assert-Condition -Condition ($installOutcome.Status -eq 'Failed' -and -not $installOutcome.Success -and -not $script:InstalledApps.ContainsKey('O&O ShutUp10')) -Message 'Remote release failure leaves O&O not installed in CLI state.'
    Assert-Condition -Condition ($installOutcome.InstallerExecutionStatus -eq 'not-started' -and $installOutcome.ExecutableStatus -eq 'missing' -and $installOutcome.PrivacySettingsStatus -eq 'not-applied' -and $installOutcome.DownloadStatus -eq 'not-attempted') -Message 'CLI reports execution, executable, and privacy-setting status separately when the release is unconfigured.'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $localMarkerPath)) -Message 'An unverified local fallback is not invoked after remote failure.'
    Assert-Condition -Condition ([string]::Join('|', $currentQueueOrder) -eq [string]::Join('|', $originalQueueOrder)) -Message 'A failed O&O item leaves the selected queue in its original resumable order.'

    # Inject child outcomes and map only the expected product path to a private fixture file.
    function Install-OOShutUp10FromRemote { return $script:InjectedOOInstallerResult }
    $script:InstalledApps = @{ 'O&O ShutUp10' = 'stale' }
    $script:OOFixtureExecutablePath = $null
    $script:InjectedOOInstallerResult = [PSCustomObject]@{
        Success = $true; InstallationStatus = 'succeeded'; FailureReason = $null
        DownloadStatus = 'verified'; VerificationStatus = 'verified'; ExitCode = 0; RecoveryMessage = $null
    }
    $missingExecutableResult = Install-Application -App $queue[0]
    Assert-Condition -Condition (-not $missingExecutableResult.Success -and $missingExecutableResult.Status -eq 'Failed' -and (Get-InstallerActionStatus -Result $missingExecutableResult) -eq 'Failed' -and -not $script:InstalledApps.ContainsKey('O&O ShutUp10')) -Message 'A successful child with no executable is not counted as installed or completed in CLI state.'
    Assert-Condition -Condition ($missingExecutableResult.InstallerExecutionStatus -eq 'succeeded' -and $missingExecutableResult.ExecutableStatus -eq 'missing' -and $missingExecutableResult.PrivacySettingsStatus -eq 'not-applied') -Message 'CLI keeps child success, missing executable, and unapplied settings distinct.'
    Assert-Condition -Condition ($missingExecutableResult.RecoveryMessage -match 'result could not be confirmed.*before retrying') -Message 'CLI tells the user to check O&O before retrying when the executable is absent.'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $localMarkerPath) -and -not (Test-Path -LiteralPath $settingsMarkerPath)) -Message 'The missing-executable case runs neither the local fallback nor privacy-setting changes.'

    $script:OOFixtureExecutablePath = $fixtureExecutablePath
    $script:InstalledApps = @{}
    $presentExecutableResult = Install-Application -App $queue[0]
    Assert-Condition -Condition ($presentExecutableResult.Success -and $presentExecutableResult.Status -eq 'Completed' -and (Get-InstallerActionStatus -Result $presentExecutableResult) -eq 'Completed' -and $script:InstalledApps.ContainsKey('O&O ShutUp10')) -Message 'A successful child and present executable fixture are required for CLI install success.'
    Assert-Condition -Condition ($presentExecutableResult.InstallerExecutionStatus -eq 'succeeded' -and $presentExecutableResult.ExecutableStatus -eq 'present' -and $presentExecutableResult.PrivacySettingsStatus -eq 'not-applied' -and $presentExecutableResult.Message -match 'Privacy settings were not applied') -Message 'CLI reports executable presence separately and does not claim privacy settings were applied.'

    $script:OOFixtureExecutablePath = $null
    $script:InstalledApps = @{}
    $script:InjectedOOInstallerResult = [PSCustomObject]@{
        Success = $false; InstallationStatus = 'failed'; FailureReason = 'child-nonzero-exit'
        DownloadStatus = 'downloaded'; VerificationStatus = 'verified'; ExitCode = 7; RecoveryMessage = $null
    }
    $nonzeroExecutableResult = Install-Application -App $queue[0]
    Assert-Condition -Condition (-not $nonzeroExecutableResult.Success -and $nonzeroExecutableResult.InstallerExecutionStatus -eq 'failed' -and $nonzeroExecutableResult.ExecutableStatus -eq 'missing' -and -not $script:InstalledApps.ContainsKey('O&O ShutUp10')) -Message 'A nonzero child exit with no executable remains failed and unregistered.'

    $script:InjectedOOInstallerResult = [PSCustomObject]@{
        Success = $false; InstallationStatus = 'unknown'; FailureReason = 'child-result-unavailable'
        DownloadStatus = 'downloaded'; VerificationStatus = 'verified'; ExitCode = $null; RecoveryMessage = $null
    }
    $unknownExecutableResult = Install-Application -App $queue[0]
    Assert-Condition -Condition (-not $unknownExecutableResult.Success -and $unknownExecutableResult.InstallerExecutionStatus -eq 'unknown' -and $unknownExecutableResult.ExecutableStatus -eq 'missing' -and $unknownExecutableResult.RecoveryMessage -match 'result could not be confirmed') -Message 'An unknown child result stays unconfirmed and recommends checking O&O before retrying.'

    $script:InjectedOOInstallerResult = [PSCustomObject]@{
        Success = $false; InstallationStatus = 'not-started'; FailureReason = 'cancelled'
        DownloadStatus = 'cancelled'; VerificationStatus = 'not-verified'; ExitCode = $null; RecoveryMessage = $null
    }
    $cancelledInstallerResult = Install-Application -App $queue[0]
    Assert-Condition -Condition (-not $cancelledInstallerResult.Success -and $cancelledInstallerResult.InstallerExecutionStatus -eq 'not-started' -and $cancelledInstallerResult.Message -match 'cancelled.*No O&O changes were made') -Message 'Pre-execution cancellation is reported as cancelled without claiming an installation.'

    # Restore the production helper before exercising the selected-app queue.
    Invoke-Expression $cliRemoteHelperText

    # Exercise queue continuation and explicit user cancellation without running a package manager.
    $script:SelectedAppAttempts = @()
    $script:SelectedOOResult = $null
    function Get-InstalledApplications { return @{} }
    function Read-Host { param([string]$Prompt) return 'Y' }
    function Install-Application {
        param([hashtable]$App)
        $script:SelectedAppAttempts += $App.Name
        if ($App.Name -eq 'O&O ShutUp10') {
            $script:SelectedOOResult = Install-OOShutUp10FromRemote
            if ($script:SelectedOOResult.Success) {
                Set-Content -LiteralPath $settingsMarkerPath -Value 'settings applied'
            }
            return [bool]$script:SelectedOOResult.Success
        }
        return $true
    }
    Invoke-Expression (Get-FunctionDefinitionText -Path $cliPath -Name 'Install-SelectedApplications')
    $stateQueue = @(
        @{ Name = 'Other App A'; ScriptName = 'other-a.ps1'; WingetId = 'Example.A' },
        @{ Name = 'O&O ShutUp10'; ScriptName = 'shutup10.ps1'; WingetId = $null },
        @{ Name = 'Other App B'; ScriptName = 'other-b.ps1'; WingetId = 'Example.B' }
    )
    $stateQueueOrder = @($stateQueue | ForEach-Object { $_.Name })
    Install-SelectedApplications -Apps $stateQueue
    $unrelatedAttemptOrder = @($script:SelectedAppAttempts | Where-Object { $_ -ne 'O&O ShutUp10' })
    Assert-Condition -Condition (-not $script:SelectedOOResult.Success -and $script:SelectedOOResult.InstallationStatus -eq 'not-started') -Message 'Selecting O&O with no approved release fails before installation starts.'
    Assert-Condition -Condition ([string]::Join('|', $unrelatedAttemptOrder) -eq 'Other App A|Other App B') -Message 'Other selected applications continue in their original relative order after O&O failure.'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $settingsMarkerPath) -and -not (Test-Path -LiteralPath $localMarkerPath)) -Message 'Remote verification failure writes no settings marker and runs no local fallback.'
    Assert-Condition -Condition ([string]::Join('|', @($stateQueue | ForEach-Object { $_.Name })) -eq [string]::Join('|', $stateQueueOrder)) -Message 'The selected queue remains intact and resumable after O&O failure.'

    $script:SelectedAppAttempts = @()
    function Read-Host { param([string]$Prompt) return 'N' }
    Install-SelectedApplications -Apps $stateQueue
    Assert-Condition -Condition ($script:SelectedAppAttempts.Count -eq 0) -Message 'User cancellation stops before any selected installer is invoked.'
    Assert-Condition -Condition (@(Get-ChildItem -LiteralPath $tempRoot -Force).Count -eq 0 -and -not (Test-Path -LiteralPath $settingsMarkerPath)) -Message 'User cancellation creates no O&O temp script or settings marker.'

    # Exercise the GUI branch with stand-in controls; no real installer or settings run.
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Remove-Item -LiteralPath Function:\Install-Application, Function:\Install-OOShutUp10FromRemote -ErrorAction SilentlyContinue
    $script:OutputMessages = @()
    function Write-Output {
        param(
            [Parameter(Position = 0)][string]$Message,
            [System.Drawing.Color]$Color
        )
        $script:OutputMessages += $Message
    }
    Invoke-Expression (Get-FunctionDefinitionText -Path $guiPath -Name 'Install-OOShutUp10FromRemote')
    Invoke-Expression (Get-FunctionDefinitionText -Path $guiPath -Name 'Install-Application')

    $script:InstalledApps = @{}
    $script:OOFixtureExecutablePath = $null
    $script:StatusLabel = [PSCustomObject]@{ Text = ''; ForeColor = [System.Drawing.Color]::Empty }
    $script:AppProgressBar = [PSCustomObject]@{ Visible = $false }
    $guiQueue = @(
        [PSCustomObject]@{ Name = 'O&O ShutUp10'; ScriptName = 'shutup10.ps1'; WingetId = $null },
        [PSCustomObject]@{ Name = 'Other App A'; ScriptName = 'other-a.ps1'; WingetId = 'Example.A' },
        [PSCustomObject]@{ Name = 'Other App B'; ScriptName = 'other-b.ps1'; WingetId = 'Example.B' }
    )
    $originalGuiQueueOrder = @($guiQueue | ForEach-Object { $_.Name })
    $guiOutcome = Install-Application -App $guiQueue[0]
    $currentGuiQueueOrder = @($guiQueue | ForEach-Object { $_.Name })
    Assert-Condition -Condition (-not $guiOutcome -and -not $script:InstalledApps.ContainsKey('O&O ShutUp10')) -Message 'Remote release failure leaves O&O not installed in GUI state.'
    Assert-Condition -Condition ($script:StatusLabel.Text -match 'Installer execution: not-started; executable: missing; privacy settings: not-applied.*The O&O installer could not be verified') -Message 'The GUI visibly reports the unverified O&O result and separate state fields.'
    Assert-Condition -Condition (-not $script:AppProgressBar.Visible -and -not (Test-Path -LiteralPath $localMarkerPath)) -Message 'GUI failure hides progress and does not invoke the local fallback.'
    Assert-Condition -Condition ([string]::Join('|', $currentGuiQueueOrder) -eq [string]::Join('|', $originalGuiQueueOrder)) -Message 'A failed GUI O&O item preserves the selected queue order.'
    Assert-Condition -Condition ($script:OutputMessages -contains $script:StatusLabel.Text) -Message 'The GUI announces the fallback text through its visible output channel.'

    function Install-OOShutUp10FromRemote { return $script:InjectedOOInstallerResult }
    $script:InjectedOOInstallerResult = [PSCustomObject]@{
        Success = $true; InstallationStatus = 'succeeded'; FailureReason = $null
        DownloadStatus = 'verified'; VerificationStatus = 'verified'; ExitCode = 0; RecoveryMessage = $null
    }
    $script:OOFixtureExecutablePath = $null
    $script:InstalledApps = @{ 'O&O ShutUp10' = 'stale' }
    $missingGuiExecutableOutcome = Install-Application -App $guiQueue[0]
    Assert-Condition -Condition (-not $missingGuiExecutableOutcome -and -not $script:InstalledApps.ContainsKey('O&O ShutUp10') -and $script:LastOOShutUp10Result.ExecutableStatus -eq 'missing') -Message 'A successful GUI helper with no executable does not leave O&O marked installed.'
    Assert-Condition -Condition ($script:StatusLabel.Text -match 'Installer execution: succeeded; executable: missing; privacy settings: not-applied.*result could not be confirmed.*before retrying' -and $script:StatusLabel.Text -match [regex]::Escape($script:LastOOShutUp10Result.RecoveryMessage)) -Message 'The GUI gives the O&O recovery message when executable presence cannot be confirmed.'

    $script:OOFixtureExecutablePath = $fixtureExecutablePath
    $script:InstalledApps = @{}
    $script:OutputMessages = @()
    $presentGuiExecutableOutcome = Install-Application -App $guiQueue[0]
    Assert-Condition -Condition ($presentGuiExecutableOutcome -and $script:InstalledApps.ContainsKey('O&O ShutUp10') -and $script:LastOOShutUp10Result.ExecutableStatus -eq 'present') -Message 'The GUI records install success only with a present executable fixture.'
    Assert-Condition -Condition ($script:LastOOShutUp10Result.PrivacySettingsStatus -eq 'not-applied' -and $script:StatusLabel.Text -match 'Privacy settings were not applied') -Message 'The GUI separates installed executable state from privacy-settings application.'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $settingsMarkerPath) -and -not (Test-Path -LiteralPath $localMarkerPath)) -Message 'Injected GUI outcomes do not run privacy-setting code or the local fallback.'

    $guiContent = [System.IO.File]::ReadAllText($guiPath)
    $cliContent = [System.IO.File]::ReadAllText($cliPath)
    $guiRemoteHelperText = Get-FunctionDefinitionText -Path $guiPath -Name 'Install-OOShutUp10FromRemote'
    $cliRemoteHelperText = Get-FunctionDefinitionText -Path $cliPath -Name 'Install-OOShutUp10FromRemote'
    Assert-Condition -Condition ($guiRemoteHelperText.Contains("elseif (`$result.FailureReason -eq 'execution-policy-blocked')") -and $guiRemoteHelperText.Contains('Write-Output $result.RecoveryMessage')) -Message 'The GUI visibly reports the sanitized child policy-block message.'
    Assert-Condition -Condition ($cliRemoteHelperText.Contains("elseif (`$result.FailureReason -eq 'execution-policy-blocked')") -and $cliRemoteHelperText.Contains('Write-Host $result.RecoveryMessage')) -Message 'The CLI visibly reports the sanitized child policy-block message.'
    $guiInstallFunctionText = Get-FunctionDefinitionText -Path $guiPath -Name 'Install-Application'
    Assert-Condition -Condition ($guiInstallFunctionText.Contains('New-OOShutUp10ProductResult') -and $guiInstallFunctionText.Contains('$productResult.Message') -and $guiInstallFunctionText.Contains('return $false')) -Message 'The GUI reports product verification failures through its truthful status message and returns failure.'
    foreach ($entryPath in @($guiPath, $cliPath)) {
        $installText = Get-FunctionDefinitionText -Path $entryPath -Name 'Install-Application'
        $parseErrors = $null
        $functionAst = [System.Management.Automation.Language.Parser]::ParseInput($installText, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "Could not inspect Install-Application in $(Split-Path $entryPath -Leaf)." }
        $ooBranch = $functionAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
            $node.Clauses.Count -gt 0 -and
            $node.Clauses[0].Item1.Extent.Text -match '\$App\.Name\s+-eq\s+["'']O&O ShutUp10["'']'
        }, $true)
        if (-not $ooBranch) { throw "O&O handling branch was not found in $(Split-Path $entryPath -Leaf)." }
        $ooBranchText = $ooBranch.Clauses[0].Item2.Extent.Text
        Assert-Condition -Condition ($ooBranchText.Contains('New-OOShutUp10ProductResult') -and $ooBranchText.Contains('PathType Leaf') -and -not $ooBranchText.Contains('$scriptPath')) -Message "$(Split-Path $entryPath -Leaf) checks the executable and fails the O&O item before the generic local-script path."
    }
    $expectedMessage = 'The O&O installer could not be verified. No O&O changes were made. Review the local installer or retry after the release source is verified.'
    Assert-Condition -Condition ($guiContent.Contains($expectedMessage) -and $cliContent.Contains($expectedMessage)) -Message 'Both entry points show the exact accessible unverified-release message.'
    Assert-Condition -Condition (-not $guiContent.Contains('raw.githubusercontent.com/mytech-today-now/OO/main/Install-OOShutUp10.ps1') -and -not $cliContent.Contains('raw.githubusercontent.com/mytech-today-now/OO/main/Install-OOShutUp10.ps1')) -Message 'Neither entry point keeps the mutable O&O main URL.'
    $fallbackContent = [System.IO.File]::ReadAllText($fallbackScriptPath)
    Assert-Condition -Condition ($fallbackContent.Contains('Invoke-WebRequest -Uri $shutupUrl -OutFile $exePath') -and $fallbackContent.Contains('$shortcut.TargetPath = $exePath') -and $fallbackContent -notmatch '(?im)^\s*(?:Start-Process|&\s*\$exePath)') -Message 'The local script downloads the executable and creates a shortcut without applying privacy settings.'

    Write-Host "O&O trust checks passed ($checkCount assertions)." -ForegroundColor Cyan
}
finally {
    Remove-Module -Name OOShutUp10Trust, 'OOShutUp10Trust.TestHarness' -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
