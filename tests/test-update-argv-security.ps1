# Offline argument-boundary coverage for GUI and CLI WinGet update paths.
# The package process is captured in-process; this test never starts WinGet or a shell.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'modules\AppInstallerCore.psm1') -Force -ErrorAction Stop
$script:assertionCount = 0
$script:processCalls = @()
$script:processResponses = @()
$script:shellStartCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    $script:assertionCount++
    [Console]::WriteLine("[PASS] $Message")
}

function Assert-ArgumentList {
    param(
        [Parameter(Mandatory = $true)][string[]]$Actual,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-Condition -Condition ($Actual.Count -eq $Expected.Count) -Message "$Context has $($Expected.Count) separate arguments"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-Condition -Condition ($Actual[$index] -ceq $Expected[$index]) -Message "$Context argument $index is exact"
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
}

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)][AllowNull()][object[]]$Object,
        [switch]$NoNewline,
        [object]$ForegroundColor
    )
}

function Write-Output {
    param([AllowNull()][object]$Message, [object]$Color)
}

function Start-Sleep {
    param([int]$Seconds, [int]$Milliseconds)
}

function Test-InstallerShouldProcess {
    param([string]$Target, [string]$Action)
    return $true
}

function Get-PackageDependencies {
    param([string]$PackageId, [string]$Source)
    return [pscustomobject]@{ Status = 'unknown'; Dependencies = [string[]]@() }
}

function Write-PackageDependencyFallbackNotice {
    param([string]$PackageName, [object]$DiscoveryResult, [object]$InstallResult)
}

function Get-WingetErrorMessage {
    param([AllowNull()][object]$ExitCode)
    return 'Injected fake WinGet failure.'
}

function Invoke-PackageManagerProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
    )

    $script:processCalls += [pscustomobject]@{
        Executable = $Executable
        Arguments = [string[]]@($Arguments)
    }

    $response = if ($script:processResponses.Count -gt 0) {
        $next = $script:processResponses[0]
        $script:processResponses = @($script:processResponses | Select-Object -Skip 1)
        $next
    }
    else {
        [pscustomobject]@{ ExitCode = 0; Output = [object[]]@() }
    }

    return [pscustomobject]@{
        Status = if ($response.ExitCode -eq 0) { 'Succeeded' } else { 'Failed' }
        ExitCode = $response.ExitCode
        Output = [object[]]@($response.Output)
    }
}

function cmd {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
    $script:shellStartCount++
    throw 'A shell command was attempted by the update path.'
}

Set-Item -LiteralPath 'Function:\script:cmd.exe' -Value {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
    $script:shellStartCount++
    throw 'A shell command was attempted by the update path.'
} -Force

function Reset-TestState {
    param([AllowEmptyCollection()][object[]]$Responses = @())
    $script:processCalls = @()
    $script:processResponses = @($Responses)
    $script:shellStartCount = 0
}

function New-FakeResponse {
    param(
        [int]$ExitCode = 0,
        [AllowNull()][object[]]$Output = @()
    )
    return [pscustomobject]@{ ExitCode = $ExitCode; Output = [object[]]@($Output) }
}

function New-UpgradeTable {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PackageId,
        [AllowNull()][string]$Source,
        [switch]$OmitSourceColumn
    )

    if ($OmitSourceColumn) {
        return @(
            'Name  Id  Version  Available',
            '--------------------------------------------------------',
            ("Example App  {0}  1.0  2.0" -f $PackageId),
            '1 upgrade available'
        ) -join [Environment]::NewLine
    }

    return @(
        'Name  Id  Version  Available  Source',
        '--------------------------------------------------------',
        ("Example App  {0}  1.0  2.0  {1}" -f $PackageId, $Source),
        '1 upgrade available'
    ) -join [Environment]::NewLine
}

function Import-InstallerFunctions {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $source = [System.IO.File]::ReadAllText($Path)
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Could not parse $Path`: $($parseErrors[0].Message)"
    }

    foreach ($name in $Names) {
        $definition = $scriptAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true) | Select-Object -First 1
        if (-not $definition) {
            throw "Function $name was not found in $Path."
        }

        $body = $definition.Body.Extent.Text
        $body = $body.Substring(1, $body.Length - 2)
        Set-Item -Path ("Function:\script:{0}" -f $name) -Value ([scriptblock]::Create($body)) -Force
    }
}

function Assert-NoShellCommandInUpdatePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Could not parse $Path`: $($parseErrors[0].Message)"
    }

    foreach ($functionName in @('Update-Applications', 'Invoke-WingetDependencyCommand')) {
        $definition = $scriptAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
            }, $true) | Select-Object -First 1
        if (-not $definition) {
            throw "Function $functionName was not found in $Path."
        }

        $shellCalls = @($definition.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    [string]$node.GetCommandName() -match '^(?i:cmd|cmd\.exe)$'
                }, $true))
        Assert-Condition -Condition ($shellCalls.Count -eq 0) -Message "$functionName contains no cmd.exe command"
    }
}

$processHelperSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'platform-detect.ps1'))
Assert-Condition -Condition ($processHelperSource -match '(?s)Get-Command\s+-Name\s+\$Executable\s+-CommandType\s+Application') -Message 'The shared process helper resolves an executable application explicitly'
Assert-Condition -Condition ($processHelperSource -match '(?s)&\s+\$executablePath\s+@Arguments') -Message 'The shared process helper invokes the resolved executable with a splatted argument array'
Assert-Condition -Condition ($processHelperSource -notmatch '(?is)cmd(?:\.exe)?\s+/c') -Message 'The shared process helper contains no cmd.exe /c dispatch'

$entrypoints = @(
    [pscustomobject]@{ Name = 'GUI'; Path = (Join-Path $repositoryRoot 'app-installer.ps1') },
    [pscustomobject]@{ Name = 'CLI'; Path = (Join-Path $repositoryRoot 'app-installer-cli.ps1') }
)
$functionNames = @('New-UpdateScanResult', 'ConvertFrom-WingetUpgradeTable', 'Get-AvailableUpdates', 'Invoke-WingetDependencyCommand', 'Update-Applications')
$invalidIds = @('Bad Package', 'Bad"Quote', "Bad'Quote", 'Bad&echo', 'Bad%PATH%', 'Ünicode.Package', '', 'Bad;echo', '--all')
$invalidSources = @('bad source', 'bad"source', "bad'source", 'winget&source', '%PATH%', 'μsource', '')

foreach ($entrypoint in $entrypoints) {
    Import-InstallerFunctions -Path $entrypoint.Path -Names $functionNames
    Assert-NoShellCommandInUpdatePath -Path $entrypoint.Path

    foreach ($invalidId in $invalidIds) {
        $text = New-UpgradeTable -PackageId $invalidId -Source 'winget'
        $parsed = ConvertFrom-WingetUpgradeTable -Text $text
        Assert-Condition -Condition ($parsed.Status -ceq 'Unknown' -and $parsed.Updates.Count -eq 0) -Message "$($entrypoint.Name) rejects ID payload '$invalidId' during discovery"

        Reset-TestState
        $null = Update-Applications -Updates @([pscustomobject]@{
                Name = 'Untrusted candidate'
                Id = $invalidId
                CurrentVersion = '1.0'
                AvailableVersion = '2.0'
                Source = 'winget'
            })
        Assert-Condition -Condition ($script:processCalls.Count -eq 0) -Message "$($entrypoint.Name) starts no package process for invalid ID '$invalidId'"
        Assert-Condition -Condition ($script:shellStartCount -eq 0) -Message "$($entrypoint.Name) starts no shell for invalid ID '$invalidId'"
    }

    foreach ($invalidSource in $invalidSources) {
        $text = New-UpgradeTable -PackageId 'Google.Chrome' -Source $invalidSource
        $parsed = ConvertFrom-WingetUpgradeTable -Text $text
        Assert-Condition -Condition ($parsed.Status -ceq 'Unknown' -and $parsed.Updates.Count -eq 0) -Message "$($entrypoint.Name) rejects source '$invalidSource' during discovery"

        Reset-TestState
        $null = Update-Applications -Updates @([pscustomobject]@{
                Name = 'Untrusted source'
                Id = 'Google.Chrome'
                CurrentVersion = '1.0'
                AvailableVersion = '2.0'
                Source = $invalidSource
            })
        Assert-Condition -Condition ($script:processCalls.Count -eq 0) -Message "$($entrypoint.Name) starts no package process for invalid source '$invalidSource'"
        Assert-Condition -Condition ($script:shellStartCount -eq 0) -Message "$($entrypoint.Name) starts no shell for invalid source '$invalidSource'"
    }

    foreach ($untrustedCandidate in @(
            [pscustomobject]@{ Name = 'Unmapped package'; Id = 'Unmapped.Package'; Source = 'winget' },
            [pscustomobject]@{ Name = 'Mismatched source'; Id = 'Google.Chrome'; Source = 'msstore' }
        )) {
        $text = New-UpgradeTable -PackageId $untrustedCandidate.Id -Source $untrustedCandidate.Source
        $parsed = ConvertFrom-WingetUpgradeTable -Text $text
        Assert-Condition -Condition ($parsed.Status -ceq 'Unknown' -and $parsed.Updates.Count -eq 0) -Message "$($entrypoint.Name) rejects unmapped or mismatched catalog source during discovery"

        Reset-TestState
        $null = Update-Applications -Updates @([pscustomobject]@{
                Name = $untrustedCandidate.Name
                Id = $untrustedCandidate.Id
                CurrentVersion = '1.0'
                AvailableVersion = '2.0'
                Source = $untrustedCandidate.Source
            })
        Assert-Condition -Condition ($script:processCalls.Count -eq 0) -Message "$($entrypoint.Name) starts no package process for unmapped or mismatched source"
    }

    Reset-TestState
    $scanOutput = New-UpgradeTable -PackageId 'XPFD23M0L795KD' -Source $null -OmitSourceColumn
    $script:processResponses = @(New-FakeResponse -Output @($scanOutput))
    $scan = Get-AvailableUpdates
    Assert-Condition -Condition ($scan.Status -ceq 'CompletedWithUpdates' -and $scan.Updates.Count -eq 1 -and $scan.Updates[0].Source -ceq 'msstore') -Message "$($entrypoint.Name) resolves an omitted source from the catalog"
    Assert-Condition -Condition ($script:processCalls.Count -eq 1 -and $script:processCalls[0].Executable -ceq 'winget') -Message "$($entrypoint.Name) captures the discovery executable separately"
    Assert-ArgumentList -Actual $script:processCalls[0].Arguments -Expected @('upgrade') -Context "$($entrypoint.Name) discovery argv"
    Assert-Condition -Condition ($script:shellStartCount -eq 0) -Message "$($entrypoint.Name) discovery starts no shell"

    Reset-TestState
    $null = Update-Applications -Updates @([pscustomobject]@{
            Name = 'Google Chrome'
            Id = 'Google.Chrome'
            CurrentVersion = '1.0'
            AvailableVersion = '2.0'
            Source = 'winget'
        })
    Assert-Condition -Condition ($script:processCalls.Count -eq 1 -and $script:processCalls[0].Executable -ceq 'winget') -Message "$($entrypoint.Name) captures the update executable separately"
    Assert-ArgumentList -Actual $script:processCalls[0].Arguments -Expected @('upgrade', '--id', 'Google.Chrome', '--exact', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements') -Context "$($entrypoint.Name) community update argv"
    Assert-Condition -Condition ($script:shellStartCount -eq 0) -Message "$($entrypoint.Name) community update starts no shell"

    Reset-TestState
    $null = Update-Applications -Updates @([pscustomobject]@{
            Name = 'Microsoft Store application'
            Id = 'XPFD23M0L795KD'
            CurrentVersion = '1.0'
            AvailableVersion = '2.0'
            Source = 'msstore'
        })
    Assert-Condition -Condition ($script:processCalls.Count -eq 1) -Message "$($entrypoint.Name) launches one Store update"
    Assert-ArgumentList -Actual $script:processCalls[0].Arguments -Expected @('upgrade', '--id', 'XPFD23M0L795KD', '--source', 'msstore', '--silent', '--accept-source-agreements', '--accept-package-agreements') -Context "$($entrypoint.Name) Store update argv"

    Reset-TestState -Responses @(
        (New-FakeResponse -ExitCode -1978335212),
        (New-FakeResponse -ExitCode 0)
    )
    $null = Update-Applications -Updates @([pscustomobject]@{
            Name = 'Google Chrome'
            Id = 'Google.Chrome'
            CurrentVersion = '1.0'
            AvailableVersion = '2.0'
            Source = 'winget'
        })
    Assert-Condition -Condition ($script:processCalls.Count -eq 2) -Message "$($entrypoint.Name) architecture retry makes two captured attempts"
    Assert-ArgumentList -Actual $script:processCalls[0].Arguments -Expected @('upgrade', '--id', 'Google.Chrome', '--exact', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements') -Context "$($entrypoint.Name) first retry argv"
    Assert-ArgumentList -Actual $script:processCalls[1].Arguments -Expected @('upgrade', '--id', 'Google.Chrome', '--exact', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--force') -Context "$($entrypoint.Name) force retry argv"

    Reset-TestState -Responses @(
        (New-FakeResponse -ExitCode -1978335226),
        (New-FakeResponse -ExitCode 0)
    )
    $null = Update-Applications -Updates @([pscustomobject]@{
            Name = 'Google Chrome'
            Id = 'Google.Chrome'
            CurrentVersion = '1.0'
            AvailableVersion = '2.0'
            Source = 'winget'
        })
    Assert-Condition -Condition ($script:processCalls.Count -eq 2) -Message "$($entrypoint.Name) source retry makes two captured attempts"
    Assert-ArgumentList -Actual $script:processCalls[1].Arguments -Expected @('upgrade', '--id', 'Google.Chrome', '--exact', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements') -Context "$($entrypoint.Name) catalog-source retry argv"
    Assert-Condition -Condition ($script:shellStartCount -eq 0) -Message "$($entrypoint.Name) retry paths start no shell"
}

[Console]::WriteLine("[OK] Update argv security checks passed ($script:assertionCount assertions).")
