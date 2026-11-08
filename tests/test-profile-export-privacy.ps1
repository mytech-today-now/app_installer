#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-profile-privacy-' + [guid]::NewGuid().ToString('N'))))
$script:assertionCount = 0
$script:capturedHostLines = @()
$script:readHostResponses = New-Object System.Collections.Queue
$script:readHostCallCount = 0
$script:logMessages = @()
$knownComputerName = 'APPINSTALLER-TEST-HOST'
$knownUserName = 'APPINSTALLER-TEST-USER'
$originalIdentityEnvironment = @{
    COMPUTERNAME = [Environment]::GetEnvironmentVariable('COMPUTERNAME', 'Process')
    USERNAME = [Environment]::GetEnvironmentVariable('USERNAME', 'Process')
}

if (-not $testRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary profile test directory is outside the system temporary directory.'
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
    return Test-Path -LiteralPath $Path
}

function Write-Log {
    param([string]$Message, [string]$Level)
    $script:logMessages += [string]$Message
}

function Write-Host {
    param(
        [object]$Object,
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor,
        [switch]$NoNewline
    )

    $line = [string]$Object
    $script:capturedHostLines += $line
    if ($NoNewline) {
        [Console]::Write($line)
    }
    else {
        [Console]::WriteLine($line)
    }
}

function Read-Host {
    param([string]$Prompt)

    $script:readHostCallCount++
    $disclosure = $script:capturedHostLines -join [Environment]::NewLine
    if ($disclosure -notmatch '\[DISCLOSURE\].*computer name and user name' -or
        $disclosure -notmatch 'may learn the device and account identifiers') {
        throw 'Identity confirmation was requested before the disclosure was shown.'
    }
    if (-not [string]::IsNullOrWhiteSpace($script:consentTargetPath) -and (Test-Path -LiteralPath $script:consentTargetPath)) {
        throw 'The profile was written before identity confirmation.'
    }
    if ($script:readHostResponses.Count -eq 0) {
        throw 'No test response was queued for the identity confirmation prompt.'
    }

    return [string]$script:readHostResponses.Dequeue()
}

function Test-IdentityPropertiesAbsent {
    param([Parameter(Mandatory = $true)][object]$Profile)
    return ($null -eq $Profile.PSObject.Properties['ComputerName'] -and $null -eq $Profile.PSObject.Properties['UserName'])
}

function Test-ApplicationList {
    param([Parameter(Mandatory = $true)][object]$Profile)
    $names = @($Profile.Applications | ForEach-Object { [string]$_ })
    return ($names.Count -eq 1 -and $names[0] -ceq 'Fixture App')
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    [Environment]::SetEnvironmentVariable('COMPUTERNAME', $knownComputerName, 'Process')
    [Environment]::SetEnvironmentVariable('USERNAME', $knownUserName, 'Process')

    $script:ScriptVersion = 'test-version'
    $script:Applications = @([PSCustomObject]@{ Name = 'Fixture App' })
    $cliSourceText = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'app-installer-cli.ps1'))
    $guiSourceText = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'app-installer.ps1'))
    Assert-Condition -Condition ($cliSourceText.Contains('Export-InstallationProfile -SelectedApps $selectedApps -FilePath $filePath -IncludeIdentity')) -Message 'CLI menu routes the disclosed identity prompt through the explicit diagnostic option.'
    Assert-Condition -Condition ($cliSourceText.Contains('$defaultFileName = "profile-$timestamp.json"') -and $guiSourceText.Contains('$saveDialog.FileName = "profile-$timestamp.json"')) -Message 'CLI and GUI menu defaults omit the computer name from suggested filenames.'

    $sourceCases = @(
        [PSCustomObject]@{
            Name = 'cli'
            Path = Join-Path $repositoryRoot 'app-installer-cli.ps1'
            SelectedApps = @([PSCustomObject]@{ Name = 'Fixture App' })
            IsCli = $true
        },
        [PSCustomObject]@{
            Name = 'gui'
            Path = Join-Path $repositoryRoot 'app-installer.ps1'
            SelectedApps = @('Fixture App')
            IsCli = $false
        }
    )

    foreach ($sourceCase in $sourceCases) {
        Remove-Item -LiteralPath 'Function:\Export-InstallationProfile' -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'Function:\Import-InstallationProfile' -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'Function:\ConvertTo-BoundedProfileText' -ErrorAction SilentlyContinue
        Invoke-Expression (Get-FunctionDefinitionText -Path $sourceCase.Path -Name 'Export-InstallationProfile')
        if ($sourceCase.IsCli) {
            Invoke-Expression (Get-FunctionDefinitionText -Path $sourceCase.Path -Name 'ConvertTo-BoundedProfileText')
        }
        Invoke-Expression (Get-FunctionDefinitionText -Path $sourceCase.Path -Name 'Import-InstallationProfile')

        $script:ProfilesPath = Join-Path $testRoot $sourceCase.Name
        $script:logMessages = @()
        $script:capturedHostLines = @()
        $script:readHostCallCount = 0

        $defaultPath = Export-InstallationProfile -SelectedApps $sourceCase.SelectedApps
        Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$defaultPath) -and (Test-Path -LiteralPath $defaultPath -PathType Leaf)) -Message "$($sourceCase.Name) default export creates a temporary profile."
        $defaultName = [System.IO.Path]::GetFileName([string]$defaultPath)
        Assert-Condition -Condition ($defaultName -match '^profile-\d{4}-\d{2}-\d{2}-\d{6}\.json$' -and $defaultName -notmatch [regex]::Escape($knownComputerName) -and $defaultName -notmatch [regex]::Escape($knownUserName)) -Message "$($sourceCase.Name) default filename contains no computer or user identifier."
        $defaultText = [System.IO.File]::ReadAllText([string]$defaultPath)
        $defaultProfile = $defaultText | ConvertFrom-Json
        Assert-Condition -Condition (Test-IdentityPropertiesAbsent -Profile $defaultProfile) -Message "$($sourceCase.Name) default JSON omits ComputerName and UserName properties."
        Assert-Condition -Condition (-not $defaultText.Contains($knownComputerName) -and -not $defaultText.Contains($knownUserName)) -Message "$($sourceCase.Name) default JSON omits the injected identity values."
        Assert-Condition -Condition ([string]$defaultProfile.Version -ceq '1.0' -and [string]$defaultProfile.InstallerVersion -ceq 'test-version' -and (Test-ApplicationList -Profile $defaultProfile)) -Message "$($sourceCase.Name) default JSON preserves version, installer version, and selected applications."
        Assert-Condition -Condition ($script:readHostCallCount -eq 0) -Message "$($sourceCase.Name) default export does not request identity consent."

        if ($sourceCase.IsCli) {
            $diagnosticPath = Join-Path $testRoot 'cli-diagnostic-opt-in.json'
            $script:consentTargetPath = $diagnosticPath
            $script:capturedHostLines = @()
            $script:readHostResponses.Enqueue('YES')
            $diagnosticResult = Export-InstallationProfile -SelectedApps $sourceCase.SelectedApps -FilePath $diagnosticPath -IncludeIdentity
            Assert-Condition -Condition ([string]$diagnosticResult -ceq $diagnosticPath -and (Test-Path -LiteralPath $diagnosticPath -PathType Leaf)) -Message 'CLI diagnostic export proceeds after the disclosed affirmative response.'
            $diagnosticProfile = Get-Content -LiteralPath $diagnosticPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-Condition -Condition ([string]$diagnosticProfile.ComputerName -ceq $knownComputerName -and [string]$diagnosticProfile.UserName -ceq $knownUserName) -Message 'CLI identity fields appear only after the explicit YES response.'

            $declinedPath = Join-Path $testRoot 'cli-diagnostic-declined.json'
            $script:consentTargetPath = $declinedPath
            $script:capturedHostLines = @()
            $script:readHostResponses.Enqueue('NO')
            $declinedResult = Export-InstallationProfile -SelectedApps $sourceCase.SelectedApps -FilePath $declinedPath -IncludeIdentity
            Assert-Condition -Condition ([string]$declinedResult -ceq $declinedPath -and (Test-Path -LiteralPath $declinedPath -PathType Leaf)) -Message 'CLI export continues when diagnostic identity is declined.'
            $declinedText = [System.IO.File]::ReadAllText($declinedPath)
            $declinedProfile = $declinedText | ConvertFrom-Json
            Assert-Condition -Condition ((Test-IdentityPropertiesAbsent -Profile $declinedProfile) -and -not $declinedText.Contains($knownComputerName) -and -not $declinedText.Contains($knownUserName)) -Message 'CLI declined diagnostic export contains no identity fields or values.'
            Assert-Condition -Condition ($script:readHostCallCount -eq 2) -Message 'CLI diagnostic identity is gated by a confirmation each time the opt-in is requested.'
            $script:consentTargetPath = $null
        }

        $legacyPath = Join-Path $testRoot ($sourceCase.Name + '-legacy.json')
        $legacyProfile = [ordered]@{
            Version = '1.0'
            Timestamp = '2025-11-10T18:40:47'
            ComputerName = $knownComputerName
            UserName = $knownUserName
            InstallerVersion = 'legacy-version'
            Applications = @('Fixture App')
        }
        $legacyText = ConvertTo-Json -InputObject $legacyProfile -Depth 8
        [System.IO.File]::WriteAllText($legacyPath, $legacyText, (New-Object System.Text.UTF8Encoding($false)))
        $legacyBytesBefore = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($legacyPath))
        $script:logMessages = @()

        $importResult = Import-InstallationProfile -FilePath $legacyPath
        Assert-Condition -Condition ($importResult.Success -and $importResult.Applications.Count -eq 1) -Message "$($sourceCase.Name) imports a legacy profile with its selected application."
        if ($sourceCase.IsCli) {
            Assert-Condition -Condition ([string]$importResult.Applications[0].Name -ceq 'Fixture App') -Message 'CLI legacy import maps the application name to the current application object.'
        }
        else {
            Assert-Condition -Condition ([string]$importResult.Applications[0] -ceq 'Fixture App') -Message 'GUI legacy import preserves the selected application name.'
        }
        Assert-Condition -Condition (Test-IdentityPropertiesAbsent -Profile $importResult.ProfileInfo) -Message "$($sourceCase.Name) legacy import excludes identity fields from returned profile information."
        $loggedText = $script:logMessages -join [Environment]::NewLine
        Assert-Condition -Condition (-not $loggedText.Contains($knownComputerName) -and -not $loggedText.Contains($knownUserName)) -Message "$($sourceCase.Name) legacy import does not log identity field values."
        $legacyBytesAfter = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($legacyPath))
        Assert-Condition -Condition ($legacyBytesBefore -ceq $legacyBytesAfter) -Message "$($sourceCase.Name) import leaves the legacy source file byte-for-byte unchanged."
    }

    Write-Output ("[OK] Profile privacy checks passed: assertions={0}; sources=CLI+GUI; host/user values injected; temporary files only." -f $script:assertionCount)
}
finally {
    [Environment]::SetEnvironmentVariable('COMPUTERNAME', $originalIdentityEnvironment.COMPUTERNAME, 'Process')
    [Environment]::SetEnvironmentVariable('USERNAME', $originalIdentityEnvironment.USERNAME, 'Process')

    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedTestRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
    }
}
