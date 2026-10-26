#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$productionModulePath = Join-Path $repositoryRoot 'modules\BelarcInstallerTrust.psm1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('app-installer-belarc-tests-' + [Guid]::NewGuid().ToString('N'))
$encoding = New-Object System.Text.UTF8Encoding($false)
$assertionCount = 0
$state = [PSCustomObject]@{
    DownloadCalls  = 0
    SignatureCalls = 0
    ProcessCalls   = 0
    SeenUri        = $null
    SeenPath       = $null
    SeenArguments  = @()
    SeenBytes      = $null
}
$testBytes = $encoding.GetBytes('synthetic installer payload for offline trust tests')
$testDigest = $null
$testSigner = 'A' * 40
# URI, digest, signer, and bytes below are synthetic fixtures. All execution paths
# use injected fake boundaries and never contact Belarc or launch an executable.
$testUri = 'https://downloads.belarc.com/advisor/releases/test-only-fixture-1.0.0/advisorinstaller.exe'

function Assert-Condition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Get-TestSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha256.ComputeHash($Bytes)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function New-FakeDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $payload = $Bytes
    $downloadState = $script:state
    return {
        param($RequestedUri)
        $downloadState.DownloadCalls++
        $downloadState.SeenUri = $RequestedUri
        return ,$payload
    }.GetNewClosure()
}

function New-FakeSignatureVerifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Valid
    )

    $signatureState = $script:state
    $expectedSigner = $script:testSigner
    return {
        param($LiteralPath, $ExpectedThumbprint)
        $signatureState.SignatureCalls++
        $signatureState.SeenPath = $LiteralPath
        return ($Valid -and $ExpectedThumbprint -ceq $expectedSigner -and (Test-Path -LiteralPath $LiteralPath -PathType Leaf))
    }.GetNewClosure()
}

try {
    [void][System.IO.Directory]::CreateDirectory($testRoot)
    $testDigest = Get-TestSha256 -Bytes $testBytes

    Import-Module -Name $productionModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null
    $productionRelease = Get-BelarcInstallerPinnedRelease
    Assert-Condition -Condition ($null -eq $productionRelease.Version -and $null -eq $productionRelease.Uri -and $null -eq $productionRelease.Sha256 -and $null -eq $productionRelease.SignerThumbprint) -Message 'Production version, source, digest, and signer pins remain unset.'

    $moduleSource = [System.IO.File]::ReadAllText($productionModulePath)
    Assert-Condition -Condition ($moduleSource.Contains('$directorySecurity.SetAccessRuleProtection($true, $false)') -and $moduleSource.Contains('S-1-5-18') -and $moduleSource.Contains('S-1-5-32-544') -and $moduleSource.Contains('Set-Acl -LiteralPath $LiteralPath')) -Message 'Production staging ACL is protected and grants access only to the current user, SYSTEM, and Administrators.'
    Assert-Condition -Condition ($moduleSource.Contains('Get-AuthenticodeSignature -FilePath $LiteralPath') -and $moduleSource.Contains('[System.Management.Automation.SignatureStatus]::Valid') -and $moduleSource.Contains('$ExpectedThumbprint')) -Message 'Production signature verification requires a valid Authenticode status and the pinned signer thumbprint.'
    Assert-Condition -Condition ($moduleSource.Contains('$request.AllowAutoRedirect = $false') -and $moduleSource.Contains('source-changed-during-download')) -Message 'Production download handling rejects redirects and response-source changes.'

    $module = Get-Module -Name BelarcInstallerTrust
    Remove-Module -ModuleInfo $module -Force -ErrorAction Stop

    # The host sandbox blocks temp-directory DACL updates. Stub only that call in
    # a test copy while retaining the production transfer, verification, and cleanup code.
    $aclCall = 'Set-BelarcPrivateDirectoryAcl -LiteralPath $directoryPath'
    if ($moduleSource.Split(@($aclCall), [System.StringSplitOptions]::None).Length -ne 2) {
        throw 'Expected exactly one staging ACL call in the production module.'
    }
    $testModulePath = Join-Path $testRoot 'BelarcInstallerTrust.psm1'
    $testModuleSource = $moduleSource.Replace($aclCall, '# Test harness stub: ACL writes are blocked by this host sandbox.')
    [System.IO.File]::WriteAllText($testModulePath, $testModuleSource, $encoding)
    Import-Module -Name $testModulePath -Force -DisableNameChecking -ErrorAction Stop | Out-Null

    $state.DownloadCalls = 0
    $state.ProcessCalls = 0
    $processState = $state
    $neverExecute = {
        param($LiteralPath, $Arguments)
        $processState.ProcessCalls++
        return [PSCustomObject]@{ ExitCode = 0 }
    }.GetNewClosure()
    $missingPins = Invoke-VerifiedBelarcInstaller `
        -Uri $productionRelease.Uri `
        -ExpectedSha256 $productionRelease.Sha256 `
        -ExpectedSignerThumbprint $productionRelease.SignerThumbprint `
        -TempRoot $testRoot `
        -DownloadScript (New-FakeDownload -Bytes $testBytes) `
        -ExecutorScript $neverExecute
    Assert-Condition -Condition ($missingPins.FailureReason -eq 'release-not-configured' -and $missingPins.VerificationStatus -eq 'not-verified' -and $missingPins.Message -match 'No download or installation was attempted') -Message 'Missing production pins return a clear not-verified result.'
    Assert-Condition -Condition ($missingPins.DownloadStatus -eq 'not-attempted' -and $state.DownloadCalls -eq 0 -and $state.ProcessCalls -eq 0) -Message 'Missing pins fail before network or process boundaries.'

    $missingSigner = Invoke-VerifiedBelarcInstaller `
        -Uri $testUri `
        -ExpectedSha256 $testDigest `
        -ExpectedSignerThumbprint $null `
        -TempRoot $testRoot `
        -DownloadScript (New-FakeDownload -Bytes $testBytes)
    Assert-Condition -Condition ($missingSigner.FailureReason -eq 'release-not-configured' -and $missingSigner.DownloadStatus -eq 'not-attempted') -Message 'A missing signer pin fails before download.'
    Assert-Condition -Condition ($state.DownloadCalls -eq 0) -Message 'Missing signer pin does not call the fake downloader.'

    $mutableUris = @(
        'https://downloads.belarc.com/advisor/advisorinstaller.exe',
        'https://downloads.belarc.com/advisor/releases/latest/advisorinstaller.exe',
        'https://downloads.belarc.com/advisor/releases/test-only-fixture-1.0.0/advisorinstaller.exe?download=1',
        'http://downloads.belarc.com/advisor/releases/test-only-fixture-1.0.0/advisorinstaller.exe',
        'https://downloads.example.invalid/advisor/releases/test-only-fixture-1.0.0/advisorinstaller.exe'
    )
    foreach ($mutableUri in $mutableUris) {
        $sourceRejected = Invoke-VerifiedBelarcInstaller `
            -Uri $mutableUri `
            -ExpectedSha256 $testDigest `
            -ExpectedSignerThumbprint $testSigner `
            -TempRoot $testRoot `
            -DownloadScript (New-FakeDownload -Bytes $testBytes)
        Assert-Condition -Condition ($sourceRejected.FailureReason -eq 'source-not-immutable' -and $sourceRejected.DownloadStatus -eq 'not-attempted') -Message "Mutable or unapproved source is rejected before download: $mutableUri"
    }
    Assert-Condition -Condition ($state.DownloadCalls -eq 0 -and $state.ProcessCalls -eq 0) -Message 'Rejected sources reach neither downloader nor executor.'

    $executorState = $state
    $fakeExecutor = {
        param($LiteralPath, $Arguments)
        $executorState.ProcessCalls++
        $executorState.SeenPath = $LiteralPath
        $executorState.SeenArguments = @($Arguments)
        $executorState.SeenBytes = [System.IO.File]::ReadAllBytes($LiteralPath)
        return [PSCustomObject]@{ ExitCode = 0 }
    }.GetNewClosure()
    $approved = Invoke-VerifiedBelarcInstaller `
        -Uri $testUri `
        -ExpectedSha256 $testDigest `
        -ExpectedSignerThumbprint $testSigner `
        -TempRoot $testRoot `
        -DownloadScript (New-FakeDownload -Bytes $testBytes) `
        -SignatureVerifier (New-FakeSignatureVerifier -Valid $true) `
        -ExecutorScript $fakeExecutor
    Assert-Condition -Condition ($approved.Success -and $approved.VerificationStatus -eq 'verified' -and $approved.InstallationStatus -eq 'succeeded' -and $approved.ExitCode -eq 0) -Message 'Digest and signer verified fake execution succeeds.'
    Assert-Condition -Condition ($state.SeenUri -ceq $testUri -and $state.SeenPath -ceq $approved.StagedFilePath) -Message 'The exact immutable test URI and verified staged file reach the fake boundaries.'
    Assert-Condition -Condition ((Get-TestSha256 -Bytes $state.SeenBytes) -ceq $testDigest) -Message 'The executor sees the exact bytes whose digest was verified.'
    Assert-Condition -Condition ($state.SeenArguments.Count -eq 1 -and $state.SeenArguments[0] -ceq '/S') -Message 'The existing silent installer argument is preserved.'
    Assert-Condition -Condition ($approved.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $approved.StagedFilePath) -and -not (Test-Path -LiteralPath $approved.TempDirectory)) -Message 'Successful execution removes only its staged file and empty owned directory.'

    $changedBytes = $encoding.GetBytes('different synthetic installer bytes')
    $processCallsBeforeDigestMismatch = $state.ProcessCalls
    $digestMismatch = Invoke-VerifiedBelarcInstaller `
        -Uri $testUri `
        -ExpectedSha256 $testDigest `
        -ExpectedSignerThumbprint $testSigner `
        -TempRoot $testRoot `
        -DownloadScript (New-FakeDownload -Bytes $changedBytes) `
        -SignatureVerifier (New-FakeSignatureVerifier -Valid $true) `
        -ExecutorScript $fakeExecutor
    Assert-Condition -Condition ($digestMismatch.FailureReason -eq 'digest-mismatch' -and $digestMismatch.VerificationStatus -eq 'rejected' -and $digestMismatch.InstallationStatus -eq 'not-started') -Message 'Changed installer bytes fail digest verification.'
    Assert-Condition -Condition ($state.ProcessCalls -eq $processCallsBeforeDigestMismatch) -Message 'Digest mismatch never reaches the executor.'
    Assert-Condition -Condition ($digestMismatch.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $digestMismatch.StagedFilePath) -and -not (Test-Path -LiteralPath $digestMismatch.TempDirectory)) -Message 'Digest mismatch cleans the owned staged file and directory.'

    $processCallsBeforeSignerMismatch = $state.ProcessCalls
    $signerMismatch = Invoke-VerifiedBelarcInstaller `
        -Uri $testUri `
        -ExpectedSha256 $testDigest `
        -ExpectedSignerThumbprint $testSigner `
        -TempRoot $testRoot `
        -DownloadScript (New-FakeDownload -Bytes $testBytes) `
        -SignatureVerifier (New-FakeSignatureVerifier -Valid $false) `
        -ExecutorScript $fakeExecutor
    Assert-Condition -Condition ($signerMismatch.FailureReason -eq 'signer-mismatch' -and $signerMismatch.VerificationStatus -eq 'rejected' -and $signerMismatch.InstallationStatus -eq 'not-started') -Message 'A signer mismatch rejects digest-matching bytes.'
    Assert-Condition -Condition ($state.ProcessCalls -eq $processCallsBeforeSignerMismatch) -Message 'Signer mismatch never reaches the executor.'
    Assert-Condition -Condition ($signerMismatch.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $signerMismatch.StagedFilePath)) -Message 'Signer mismatch removes its staged installer.'

    $nonzeroState = $state
    $nonzeroExecutor = {
        param($LiteralPath, $Arguments)
        $nonzeroState.ProcessCalls++
        return [PSCustomObject]@{ ExitCode = 37 }
    }.GetNewClosure()
    $childFailure = Invoke-VerifiedBelarcInstaller `
        -Uri $testUri `
        -ExpectedSha256 $testDigest `
        -ExpectedSignerThumbprint $testSigner `
        -TempRoot $testRoot `
        -DownloadScript (New-FakeDownload -Bytes $testBytes) `
        -SignatureVerifier (New-FakeSignatureVerifier -Valid $true) `
        -ExecutorScript $nonzeroExecutor
    Assert-Condition -Condition (-not $childFailure.Success -and $childFailure.InstallationStatus -eq 'failed' -and $childFailure.ExitCode -eq 37) -Message 'A nonzero child exit code is preserved exactly as failure.'
    Assert-Condition -Condition ($childFailure.CleanupStatus -eq 'cleaned' -and -not (Test-Path -LiteralPath $childFailure.StagedFilePath)) -Message 'A child failure still cleans its staged installer.'

    $preservedFileName = 'executor-created-unowned-file.txt'
    $preservedName = $preservedFileName
    $preservingExecutor = {
        param($LiteralPath, $Arguments)
        $extraPath = Join-Path (Split-Path -Parent $LiteralPath) $preservedName
        [System.IO.File]::WriteAllText($extraPath, 'preserve this unrelated staged-directory file')
        return [PSCustomObject]@{ ExitCode = 0 }
    }.GetNewClosure()
    $cleanupBoundary = Invoke-VerifiedBelarcInstaller `
        -Uri $testUri `
        -ExpectedSha256 $testDigest `
        -ExpectedSignerThumbprint $testSigner `
        -TempRoot $testRoot `
        -DownloadScript (New-FakeDownload -Bytes $testBytes) `
        -SignatureVerifier (New-FakeSignatureVerifier -Valid $true) `
        -ExecutorScript $preservingExecutor
    $preservedPath = Join-Path $cleanupBoundary.TempDirectory $preservedFileName
    Assert-Condition -Condition ($cleanupBoundary.CleanupStatus -eq 'failed' -and -not $cleanupBoundary.Success) -Message 'Cleanup does not claim success when the owned directory contains an extra file.'
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $cleanupBoundary.StagedFilePath) -and (Test-Path -LiteralPath $preservedPath -PathType Leaf)) -Message 'Cleanup removes only the owned staged installer and preserves other directory contents.'

    $appScriptPath = Join-Path $repositoryRoot 'apps\belarc.ps1'
    $appSource = [System.IO.File]::ReadAllText($appScriptPath)
    Assert-Condition -Condition ($appSource.Contains('BelarcInstallerTrust.psm1') -and $appSource.Contains('$global:LASTEXITCODE') -and -not $appSource.Contains('Invoke-WebRequest') -and -not $appSource.Contains('Start-Process')) -Message 'The app script delegates to the trust helper and no longer directly downloads or launches installer bytes.'

    $payloadManifestPath = Join-Path $repositoryRoot 'payload-manifest.json'
    $payloadManifest = [System.IO.File]::ReadAllText($payloadManifestPath) | ConvertFrom-Json
    foreach ($featureName in @('cli', 'gui')) {
        Assert-Condition -Condition (@($payloadManifest.features.$featureName) -contains 'modules/BelarcInstallerTrust.psm1') -Message "The verified Belarc module is required by the $featureName payload contract."
    }

    Write-Host "[PASS] $script:assertionCount Belarc installer trust assertions passed." -ForegroundColor Green
}
finally {
    Remove-Module -Name BelarcInstallerTrust -Force -ErrorAction SilentlyContinue
    if ([System.IO.Directory]::Exists($testRoot)) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
