# Offline regression coverage for WinGet dependency discovery and installation.
# All package commands are injected fakes; this test never invokes live WinGet.

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path (Join-Path $repositoryRoot 'modules') 'AppInstallerCore.psm1') -Force -ErrorAction Stop
$script:AppsPath = Join-Path $repositoryRoot 'apps'
$script:StatusLabel = $null
$script:AppProgressBar = $null
$script:ListView = $null
$script:TotalCount = 0
$script:assertionCount = 0
$script:logs = @()
$script:messages = @()
$script:dependencyCommands = @()
$script:mainWingetCalls = @()
$script:installedDependencyIds = @()
$script:throwCheckIds = @()
$script:throwInstallIds = @()
$script:installExitCodes = @{}
$script:mainExitCodes = @{}
$script:dependenciesByPackage = @{}
$script:defaultDependencyIds = @()
$script:showExitCode = 0
$script:throwShow = $false
$script:scriptPaths = @{}
$ConfirmPreference = 'None'
$WhatIfPreference = $false
$global:LASTEXITCODE = 0

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

    $script:assertionCount++
    Microsoft.PowerShell.Utility\Write-Output "[PASS] $Message"
}

function Reset-MockState {
    $script:logs = @()
    $script:messages = @()
    $script:dependencyCommands = @()
    $script:mainWingetCalls = @()
    $script:installedDependencyIds = @()
    $script:throwCheckIds = @()
    $script:throwInstallIds = @()
    $script:installExitCodes = @{}
    $script:mainExitCodes = @{}
    $script:dependenciesByPackage = @{}
    $script:defaultDependencyIds = @()
    $script:showExitCode = 0
    $script:throwShow = $false
    $global:LASTEXITCODE = 0
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $script:logs += [PSCustomObject]@{
        Level = $Level
        Message = $Message
    }
}

function Write-Output {
    param(
        [Parameter(Position = 0)]
        [string]$Message,

        [object]$Color
    )

    $script:messages += $Message
}

function Test-WingetAvailable {
    return $true
}

function Resolve-WingetPackageSource {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [AllowNull()][string]$DeclaredSource,
        [string]$ManifestPath
    )

    if (-not [string]::IsNullOrWhiteSpace($DeclaredSource) -and $DeclaredSource -cne 'winget') {
        throw 'Injected catalog source conflict.'
    }
    return 'winget'
}

function Test-InstallerShouldProcess {
    return $true
}

function Get-WingetErrorMessage {
    param([int]$ExitCode)
    return "Injected WinGet failure ($ExitCode)."
}

function Get-InstalledApplications {
    return @{}
}

function Get-InstallerActionStatus {
    param([AllowNull()]$Result)

    if ($null -ne $Result -and $Result.PSObject.Properties['Status']) {
        return [string]$Result.Status
    }
    if ($Result) {
        return 'Completed'
    }
    return 'Failed'
}

function Start-Sleep {
    param([int]$Seconds, [int]$Milliseconds)
}

function Safe-TestPath {
    param([string]$Path)
    return $false
}

function Invoke-WingetDependencyCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $script:dependencyCommands += ,([string[]]$Arguments)
    $operation = $Arguments[0]
    $packageId = if ($Arguments -contains '--id') { $Arguments[[array]::IndexOf($Arguments, '--id') + 1] } else { '' }

    if ($operation -eq 'show') {
        if ($script:throwShow) {
            throw 'Injected show exception.'
        }
        if ($script:showExitCode -ne 0) {
            return [PSCustomObject]@{
                Status = 'Failed'
                ExitCode = $script:showExitCode
                Output = [object[]]@()
            }
        }

        $dependencyIds = if ($script:dependenciesByPackage.ContainsKey($packageId)) {
            @($script:dependenciesByPackage[$packageId])
        }
        else {
            @($script:defaultDependencyIds)
        }

        if ($dependencyIds.Count -eq 0) {
            $outputText = 'Package: Test.Package'
        }
        else {
            $outputLines = @('Dependencies:', '  Package Dependencies:')
            foreach ($dependencyId in $dependencyIds) {
                $outputLines += "    $dependencyId"
            }
            $outputLines += ''
            $outputText = $outputLines -join [Environment]::NewLine
        }

        return [PSCustomObject]@{
            Status = 'Succeeded'
            ExitCode = 0
            Output = [object[]]@($outputText)
        }
    }

    if ($operation -eq 'list') {
        if ($script:throwCheckIds -contains $packageId) {
            throw 'Injected dependency check exception.'
        }

        $output = if ($script:installedDependencyIds -contains $packageId) { @($packageId) } else { @() }
        return [PSCustomObject]@{
            Status = 'Succeeded'
            ExitCode = 0
            Output = [object[]]$output
        }
    }

    if ($operation -eq 'install') {
        if ($script:throwInstallIds -contains $packageId) {
            throw 'Injected dependency install exception.'
        }

        if ($script:mainExitCodes.ContainsKey($packageId)) {
            $script:mainWingetCalls += ,([string[]]$Arguments)
            $exitCode = [int]$script:mainExitCodes[$packageId]
        }
        else {
            $exitCode = if ($script:installExitCodes.ContainsKey($packageId)) {
                [int]$script:installExitCodes[$packageId]
            }
            else {
                0
            }
        }
        return [PSCustomObject]@{
            Status = if ($exitCode -eq 0) { 'Succeeded' } else { 'Failed' }
            ExitCode = $exitCode
            Output = [object[]]@()
        }
    }

    throw "Unexpected injected WinGet operation: $operation"
}

function winget {
    $arguments = [string[]]$args
    $script:mainWingetCalls += ,$arguments
    $packageId = if ($arguments -contains '--id') { $arguments[[array]::IndexOf($arguments, '--id') + 1] } else { '' }
    $exitCode = if ($script:mainExitCodes.ContainsKey($packageId)) {
        [int]$script:mainExitCodes[$packageId]
    }
    else {
        0
    }
    $global:LASTEXITCODE = $exitCode
    if ($exitCode -eq 0) {
        return 'Successfully installed by injected WinGet.'
    }
    return 'Injected main package failure.'
}

function Import-InstallerFunctions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    $source = [System.IO.File]::ReadAllText($Path)

    foreach ($name in $Names) {
        $marker = "function $name {"
        $start = $source.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($start -lt 0) {
            throw "Function $name was not found in $Path."
        }

        $searchStart = $start + $marker.Length
        $nextFunction = [regex]::Match($source.Substring($searchStart), '(?m)^function\s+[A-Za-z][A-Za-z0-9_-]*\s*\{')
        $end = if ($nextFunction.Success) { $searchStart + $nextFunction.Index } else { $source.Length }
        $functionText = $source.Substring($start, $end - $start)
        $tokens = $null
        $parseErrors = $null
        $functionAst = [System.Management.Automation.Language.Parser]::ParseInput($functionText, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) {
            $message = $parseErrors[0].Message
            throw "Could not parse function $name from $($Path): $message"
        }

        $definition = $functionAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true) | Select-Object -First 1
        if (-not $definition) {
            throw "Function $name could not be isolated in $Path."
        }

        $bodyText = $definition.Body.Extent.Text
        $bodyText = $bodyText.Substring(1, $bodyText.Length - 2)
        $functionBody = [scriptblock]::Create($bodyText)
        Set-Item -Path ("Function:\script:" + $name) -Value $functionBody -Force
    }
}

function Assert-ResultState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedStatus,

        [Parameter(Mandatory = $true)]
        [bool]$ExpectedSuccess,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    Assert-Condition -Condition ($Result.Status -ceq $ExpectedStatus) -Message "$Context aggregate state is $ExpectedStatus (observed $($Result.Status), success $($Result.Success))"
    Assert-Condition -Condition ($Result.Success -eq $ExpectedSuccess) -Message "$Context aggregate success is $ExpectedSuccess"
}

function Invoke-DependencyHelperCases {
    param([string]$EntryPoint)

    Reset-MockState
    $noDependencies = Get-PackageDependencies -PackageId 'Test.Parent'
    Assert-ResultState -Result $noDependencies -ExpectedStatus 'succeeded' -ExpectedSuccess $true -Context "$EntryPoint no-dependency discovery"
    Assert-Condition -Condition ($noDependencies.Dependencies.Count -eq 0) -Message "$EntryPoint preserves no-dependency discovery"
    $emptyResult = Install-PackageDependencies -Dependencies @() -PackageName 'Test Parent'
    Assert-ResultState -Result $emptyResult -ExpectedStatus 'succeeded' -ExpectedSuccess $true -Context "$EntryPoint empty dependency install"
    Assert-Condition -Condition ($emptyResult.Outcomes.Count -eq 0) -Message "$EntryPoint preserves the empty dependency path"

    Reset-MockState
    $script:defaultDependencyIds = @('Test.Success')
    $discovery = Get-PackageDependencies -PackageId 'Test.Parent'
    Assert-ResultState -Result $discovery -ExpectedStatus 'succeeded' -ExpectedSuccess $true -Context "$EntryPoint dependency discovery"
    Assert-Condition -Condition ($discovery.Dependencies.Count -eq 1 -and $discovery.Dependencies[0] -ceq 'Test.Success') -Message "$EntryPoint extracts the exact dependency ID"
    $success = Install-PackageDependencies -Dependencies @('Test.Success') -PackageName 'Test Parent'
    Assert-ResultState -Result $success -ExpectedStatus 'succeeded' -ExpectedSuccess $true -Context "$EntryPoint successful dependency"
    Assert-Condition -Condition ($success.Outcomes.Count -eq 1 -and $success.Outcomes[0].Status -ceq 'succeeded') -Message "$EntryPoint marks successful dependency succeeded"
    Assert-Condition -Condition ($script:dependencyCommands.Count -eq 3) -Message "$EntryPoint checks and installs a dependency once"
    Assert-Condition -Condition (($script:dependencyCommands[0] -join '|') -ceq 'show|--id|Test.Parent|--exact|--source|winget') -Message "$EntryPoint queries parent dependencies with exact ID and explicit source"
    Assert-Condition -Condition (($script:dependencyCommands[1] -join '|') -ceq 'list|--id|Test.Success|--exact|--source|winget') -Message "$EntryPoint checks each dependency with its catalog source"
    Assert-Condition -Condition (($script:dependencyCommands[2] -join '|') -ceq 'install|--id|Test.Success|--exact|--source|winget|--silent|--accept-source-agreements|--accept-package-agreements') -Message "$EntryPoint installs each dependency with exact ID and explicit source"

    Reset-MockState
    $script:installedDependencyIds = @('Test.Installed')
    $alreadyInstalled = Install-PackageDependencies -Dependencies @('Test.Installed') -PackageName 'Test Parent'
    Assert-ResultState -Result $alreadyInstalled -ExpectedStatus 'succeeded' -ExpectedSuccess $true -Context "$EntryPoint already-installed dependency"
    Assert-Condition -Condition ($alreadyInstalled.Outcomes[0].Status -ceq 'skipped') -Message "$EntryPoint marks an already-installed dependency skipped"
    Assert-Condition -Condition ($script:dependencyCommands.Count -eq 1) -Message "$EntryPoint does not reinstall an already-installed dependency"

    Reset-MockState
    $script:installExitCodes['Test.Failed'] = 23
    $failed = Install-PackageDependencies -Dependencies @('Test.Failed') -PackageName 'Test Parent'
    Assert-ResultState -Result $failed -ExpectedStatus 'failed' -ExpectedSuccess $false -Context "$EntryPoint nonzero dependency install"
    Assert-Condition -Condition ($failed.Outcomes[0].Status -ceq 'failed' -and $failed.Outcomes[0].InstallExitCode -eq 23) -Message "$EntryPoint records dependency failure and exit code"
    Assert-Condition -Condition ($script:dependencyCommands.Count -eq 2) -Message "$EntryPoint does not retry a failed dependency install"

    Reset-MockState
    $script:throwCheckIds = @('Test.CheckException')
    $checkException = Install-PackageDependencies -Dependencies @('Test.CheckException') -PackageName 'Test Parent'
    Assert-ResultState -Result $checkException -ExpectedStatus 'unknown' -ExpectedSuccess $false -Context "$EntryPoint dependency check exception"
    Assert-Condition -Condition ($checkException.Outcomes[0].Status -ceq 'unknown') -Message "$EntryPoint identifies check exception as unknown"
    Assert-Condition -Condition ($script:dependencyCommands.Count -eq 1) -Message "$EntryPoint does not install after an unknown dependency check"

    Reset-MockState
    $script:throwInstallIds = @('Test.InstallException')
    $installException = Install-PackageDependencies -Dependencies @('Test.InstallException') -PackageName 'Test Parent'
    Assert-ResultState -Result $installException -ExpectedStatus 'unknown' -ExpectedSuccess $false -Context "$EntryPoint dependency install exception"
    Assert-Condition -Condition ($installException.Outcomes[0].Status -ceq 'unknown' -and $installException.Outcomes[0].InstallExitCode -eq $null) -Message "$EntryPoint does not mark a thrown install as installed"
    Assert-Condition -Condition ($script:dependencyCommands.Count -eq 2) -Message "$EntryPoint does not retry after an install exception"

    Reset-MockState
    $script:installExitCodes['Test.MultiFailed'] = 23
    $multiple = Install-PackageDependencies -Dependencies @('Test.MultiFailed', 'Test.MultiSuccess') -PackageName 'Test Parent'
    Assert-ResultState -Result $multiple -ExpectedStatus 'failed' -ExpectedSuccess $false -Context "$EntryPoint multiple dependencies"
    Assert-Condition -Condition ($multiple.Outcomes.Count -eq 2) -Message "$EntryPoint returns one outcome for every dependency"
    Assert-Condition -Condition ($multiple.Outcomes[0].Status -ceq 'failed' -and $multiple.Outcomes[1].Status -ceq 'succeeded') -Message "$EntryPoint preserves per-dependency outcome order"
    Assert-Condition -Condition ($script:dependencyCommands.Count -eq 4) -Message "$EntryPoint continues evaluating later dependencies without retrying"

    Reset-MockState
    $script:showExitCode = 17
    $showFailure = Get-PackageDependencies -PackageId 'Test.Unknown'
    Assert-ResultState -Result $showFailure -ExpectedStatus 'unknown' -ExpectedSuccess $false -Context "$EntryPoint failed dependency discovery"
    Assert-Condition -Condition ($showFailure.Dependencies.Count -eq 0) -Message "$EntryPoint does not invent a no-dependency result after a query failure"

    Reset-MockState
    $script:throwShow = $true
    $showException = Get-PackageDependencies -PackageId 'Test.Unknown'
    Assert-ResultState -Result $showException -ExpectedStatus 'unknown' -ExpectedSuccess $false -Context "$EntryPoint dependency discovery exception"
}

function Invoke-ApplicationParentCases {
    param([string]$EntryPoint)

    Reset-MockState
    $script:dependenciesByPackage['Parent.App'] = @('Parent.Dependency')
    $script:installExitCodes['Parent.Dependency'] = 23
    $script:mainExitCodes['Parent.App'] = 23
    $app = [PSCustomObject]@{
        Name = 'Parent App'
        WingetId = 'Parent.App'
        ScriptName = ''
    }
    $failedInstall = Install-Application -App $app
    Assert-Condition -Condition (-not $failedInstall) -Message "$EntryPoint parent install does not claim success when WinGet fails after dependency failure"
    Assert-Condition -Condition ($script:mainWingetCalls.Count -eq 1) -Message "$EntryPoint invokes the documented main-manager dependency fallback once"
    Assert-Condition -Condition ($script:mainWingetCalls[0] -notcontains '--skip-dependencies') -Message "$EntryPoint leaves WinGet's documented dependency processing enabled"
    Assert-Condition -Condition (@($script:logs | Where-Object { $_.Message -match 'Dependency outcome: Parent.Dependency is failed' }).Count -eq 1) -Message "$EntryPoint parent retains the failed prerequisite outcome"
    Assert-Condition -Condition (@($script:messages | Where-Object { $_ -match 'winget install --id Parent.Dependency --exact --source winget' }).Count -gt 0) -Message "$EntryPoint shows a safe dependency recovery step"
    Assert-Condition -Condition (@($script:messages | Where-Object { $_ -match 'Parent App installed successfully' }).Count -eq 0) -Message "$EntryPoint does not show a success marker after main-manager failure"

    Reset-MockState
    $script:dependenciesByPackage['Parent.App'] = @('Parent.Dependency')
    $script:installExitCodes['Parent.Dependency'] = 23
    $script:mainExitCodes['Parent.App'] = 0
    $managerResolvedInstall = Install-Application -App $app
    Assert-Condition -Condition ([bool]$managerResolvedInstall) -Message "$EntryPoint accepts success reported by WinGet after dependency fallback"
    Assert-Condition -Condition (@($script:logs | Where-Object { $_.Message -match 'Dependency outcome: Parent.Dependency is failed' }).Count -eq 1) -Message "$EntryPoint keeps the failed manual preflight visible after manager success"
    Assert-Condition -Condition (@($script:messages | Where-Object { $_ -match 'processes manifest dependencies by default' }).Count -gt 0) -Message "$EntryPoint explains why the main-manager fallback may proceed"

    Reset-MockState
    $script:showExitCode = 17
    $script:mainExitCodes['Parent.App'] = 23
    $unknownDiscoveryInstall = Install-Application -App $app
    Assert-Condition -Condition (-not $unknownDiscoveryInstall) -Message "$EntryPoint does not claim install success after unknown dependency discovery and main-manager failure"
    Assert-Condition -Condition ($script:mainWingetCalls.Count -eq 1) -Message "$EntryPoint still gives WinGet one opportunity to resolve declared dependencies"
    Assert-Condition -Condition (@($script:messages | Where-Object { $_ -match 'Could not verify dependencies for Parent App' }).Count -gt 0) -Message "$EntryPoint communicates unknown dependency discovery"
}

function Assert-GuiQueueContinuesAfterFailure {
    param([string]$Path)

    $source = [System.IO.File]::ReadAllText($Path)
    $functionStart = $source.IndexOf('function Install-SelectedApplications {', [System.StringComparison]::Ordinal)
    if ($functionStart -lt 0) {
        throw 'GUI Install-SelectedApplications function was not found.'
    }
    $loopStart = $source.IndexOf('# Process queue', $functionStart, [System.StringComparison]::Ordinal)
    $loopEnd = $source.IndexOf('# Clear queue state (installation completed successfully)', $loopStart, [System.StringComparison]::Ordinal)
    if ($loopStart -lt 0 -or $loopEnd -lt 0) {
        throw 'GUI installation queue loop was not found.'
    }

    $loopText = $source.Substring($loopStart, $loopEnd - $loopStart)
    $installPosition = $loopText.IndexOf('Install-Application -App $app', [System.StringComparison]::Ordinal)
    $advancePosition = $loopText.IndexOf('$script:CurrentQueueIndex++', $installPosition, [System.StringComparison]::Ordinal)
    Assert-Condition -Condition ($installPosition -ge 0 -and $advancePosition -gt $installPosition) -Message 'GUI queue advances after an application install returns failure'
    Assert-Condition -Condition ($loopText -notmatch '\b(break|return)\b') -Message 'GUI queue does not abort remaining applications after one failed install'
}

$cliPath = Join-Path $repositoryRoot 'app-installer-cli.ps1'
$guiPath = Join-Path $repositoryRoot 'app-installer.ps1'
$cliNames = @(
    'Write-PackageDependencyMessage',
    'Get-PackageDependencies',
    'Install-PackageDependencies',
    'Write-PackageDependencyFallbackNotice',
    'Install-Application',
    'Install-SelectedApplications'
)
$guiNames = @(
    'Write-PackageDependencyMessage',
    'Get-PackageDependencies',
    'Install-PackageDependencies',
    'Write-PackageDependencyFallbackNotice',
    'Install-Application'
)

try {
    Import-InstallerFunctions -Path $cliPath -Names $cliNames
    Invoke-DependencyHelperCases -EntryPoint 'CLI'
    Invoke-ApplicationParentCases -EntryPoint 'CLI'

    Reset-MockState
    $script:dependenciesByPackage['Queue.Broken'] = @('Queue.Dependency.Broken')
    $script:dependenciesByPackage['Queue.Healthy'] = @('Queue.Dependency.Healthy')
    $script:installExitCodes['Queue.Dependency.Broken'] = 23
    $script:mainExitCodes['Queue.Broken'] = 23
    $script:mainExitCodes['Queue.Healthy'] = 0
    $queueApps = @(
        [PSCustomObject]@{ Name = 'Broken App'; WingetId = 'Queue.Broken'; ScriptName = '' },
        [PSCustomObject]@{ Name = 'Healthy App'; WingetId = 'Queue.Healthy'; ScriptName = '' }
    )
    Install-SelectedApplications -Apps $queueApps
    Assert-Condition -Condition ($script:mainWingetCalls.Count -eq 2) -Message 'CLI continues to the next selected app after dependency and main-package failure'
    Assert-Condition -Condition ($script:mainWingetCalls[0][2] -ceq 'Queue.Broken' -and $script:mainWingetCalls[1][2] -ceq 'Queue.Healthy') -Message 'CLI preserves selected application order after a failed item'

    Import-InstallerFunctions -Path $guiPath -Names $guiNames
    Invoke-DependencyHelperCases -EntryPoint 'GUI'
    Invoke-ApplicationParentCases -EntryPoint 'GUI'
    Assert-GuiQueueContinuesAfterFailure -Path $guiPath

    Microsoft.PowerShell.Utility\Write-Output "[OK] $script:assertionCount dependency regression assertions passed."
}
catch {
    Microsoft.PowerShell.Utility\Write-Output "[FAIL] $($_.Exception.Message)"
    exit 1
}
