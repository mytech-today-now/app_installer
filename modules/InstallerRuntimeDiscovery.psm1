function Get-InstallerRuntimeCurrentExecutablePath {
    [CmdletBinding()]
    param()

    try {
        $process = Get-Process -Id $PID -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$process.Path)) {
            return [System.IO.Path]::GetFullPath([string]$process.Path)
        }
    }
    catch {
    }

    $executableName = if ([string]$PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    return [System.IO.Path]::GetFullPath((Join-Path $PSHOME $executableName))
}

function ConvertTo-InstallerRuntimeWindowsArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }
        if ($character -eq '"') {
            if ($backslashCount -gt 0) {
                [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            }
            else {
                [void]$builder.Append('\')
            }
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-InstallerRuntimeArgumentArray {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary]$BoundParameters = @{},

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$RemainingArguments = @()
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in $BoundParameters.Keys) {
        $value = $BoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) {
                $arguments.Add(('-{0}' -f $key))
            }
            continue
        }
        if ($null -eq $value) {
            $arguments.Add(('-{0}' -f $key))
            continue
        }
        if ($value -is [bool]) {
            $arguments.Add(('-{0}:{1}' -f $key, ([string]$value).ToLowerInvariant()))
            continue
        }
        $arguments.Add(('-{0}' -f $key))
        if ($value -is [System.Array]) {
            foreach ($item in $value) {
                $arguments.Add([string]$item)
            }
        }
        else {
            $arguments.Add([string]$value)
        }
    }
    foreach ($argument in $RemainingArguments) {
        $arguments.Add([string]$argument)
    }
    return ,$arguments.ToArray()
}

function Test-InstallerRuntimeAllowedRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Core', 'Desktop')]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $roots = New-Object 'System.Collections.Generic.List[string]'
    if ($Engine -eq 'Core') {
        $rootSpecifications = @(
            [PSCustomObject]@{ Base = [string]$env:ProgramW6432; Suffix = 'PowerShell' },
            [PSCustomObject]@{ Base = [string]$env:ProgramFiles; Suffix = 'PowerShell' },
            [PSCustomObject]@{ Base = [string]${env:ProgramFiles(x86)}; Suffix = 'PowerShell' },
            [PSCustomObject]@{ Base = [string]$env:LOCALAPPDATA; Suffix = 'Programs\PowerShell' },
            [PSCustomObject]@{ Base = [string]$env:LOCALAPPDATA; Suffix = 'Microsoft\PowerShell' }
        )
        foreach ($specification in $rootSpecifications) {
            if (-not [string]::IsNullOrWhiteSpace([string]$specification.Base)) {
                $root = Join-Path ([string]$specification.Base) ([string]$specification.Suffix)
                $roots.Add([System.IO.Path]::GetFullPath($root).TrimEnd('\'))
            }
        }
        if ($Source -eq 'AppInstallerManaged' -and -not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) {
            $roots.Add([System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\myTech.Today\AppInstaller\PowerShell')).TrimEnd('\'))
        }
        if ($Source -eq 'StorePackage' -and -not [string]::IsNullOrWhiteSpace([string]$env:ProgramFiles)) {
            $roots.Add([System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\'))
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$env:SystemRoot)) {
        $roots.Add([System.IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\'))
    }

    foreach ($root in $roots) {
        $prefix = $root + '\'
        if ($Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-InstallerRuntimeCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Candidate,

        [Parameter()]
        [switch]$AllowTestCandidate
    )

    $path = [string]$Candidate.Path
    $engine = [string]$Candidate.Engine
    if ($engine -notin @('Core', 'Desktop')) {
        return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = 'The candidate has an unsupported engine label.' }
    }
    if ([string]::IsNullOrWhiteSpace($path) -or $path -match '[\x00-\x1F"]') {
        return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = 'The candidate path is empty or contains invalid quoting or control characters.' }
    }
    try {
        if (-not [System.IO.Path]::IsPathRooted($path)) {
            return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = 'The candidate path is not an absolute executable path.' }
        }
        $fullPath = [System.IO.Path]::GetFullPath($path)
    }
    catch {
        return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = 'The candidate path is malformed.' }
    }

    $expectedName = if ($engine -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    if ([System.IO.Path]::GetFileName($fullPath) -ine $expectedName) {
        return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = "The candidate must resolve to $expectedName." }
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = 'The candidate executable does not exist as a file.' }
    }

    if ($AllowTestCandidate -and [string]$Candidate.Source -eq 'TestFixture') {
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $fullPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = 'An injected test candidate must stay under the temporary directory.' }
        }
    }
    elseif (-not (Test-InstallerRuntimeAllowedRoot -Path $fullPath -Engine $engine -Source ([string]$Candidate.Source))) {
        return [PSCustomObject]@{ IsValid = $false; Path = ''; Reason = 'The candidate is outside the documented PowerShell installation roots.' }
    }

    return [PSCustomObject]@{ IsValid = $true; Path = $fullPath; Reason = '' }
}

function Add-InstallerRuntimeCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Candidates,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Core', 'Desktop')]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return
    }
    $record = [PSCustomObject]@{ Path = $fullPath; Engine = $Engine; Source = $Source }
    $validation = Test-InstallerRuntimeCandidatePath -Candidate $record
    if (-not $validation.IsValid) {
        return
    }
    if (@($Candidates | Where-Object { [string]$_.Path -ieq $validation.Path }).Count -gt 0) {
        return
    }
    $Candidates.Add([PSCustomObject]@{ Path = $validation.Path; Engine = $Engine; Source = $Source })
}

function Get-InstallerRegisteredPowerShellCorePaths {
    [CmdletBinding()]
    param()

    if ($env:OS -notmatch 'Windows') {
        return
    }

    foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryHive]::CurrentUser)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            $baseKey = $null
            try {
                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $installations = $baseKey.OpenSubKey('SOFTWARE\Microsoft\PowerShellCore\InstalledVersions')
                if ($null -ne $installations) {
                    foreach ($name in $installations.GetSubKeyNames()) {
                        $entry = $installations.OpenSubKey($name)
                        if ($null -ne $entry) {
                            $location = [string]$entry.GetValue('InstallLocation', '')
                            if (-not [string]::IsNullOrWhiteSpace($location)) {
                                [PSCustomObject]@{ Path = (Join-Path $location 'pwsh.exe'); Source = 'CoreRegistry' }
                            }
                            $entry.Dispose()
                        }
                    }
                    $installations.Dispose()
                }

                $appPath = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe')
                if ($null -ne $appPath) {
                    $registeredPath = [string]$appPath.GetValue('', '')
                    if (-not [string]::IsNullOrWhiteSpace($registeredPath)) {
                        [PSCustomObject]@{ Path = $registeredPath; Source = 'CoreAppPathRegistry' }
                    }
                    $appPath.Dispose()
                }
            }
            catch {
            }
            finally {
                if ($null -ne $baseKey) {
                    $baseKey.Dispose()
                }
            }
        }
    }
}

function Get-InstallerRuntimeCandidates {
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$Manifest = (Get-InstallerCompatibilityManifest)
    )

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    if ($env:OS -notmatch 'Windows') {
        return @()
    }

    $corePaths = @()
    foreach ($programFilesRoot in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace([string]$programFilesRoot)) {
            $corePaths += [PSCustomObject]@{ Path = (Join-Path $programFilesRoot 'PowerShell\7\pwsh.exe'); Source = 'CoreProgramFiles' }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) {
        $corePaths += [PSCustomObject]@{ Path = (Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe'); Source = 'CoreCurrentUser' }
        $corePaths += [PSCustomObject]@{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell\pwsh.exe'); Source = 'CoreCurrentUser' }
        $coreVersion = [string]$Manifest.engines.powerShellCore.version
        if (-not [string]::IsNullOrWhiteSpace($coreVersion)) {
            $corePaths += [PSCustomObject]@{ Path = (Join-Path $env:LOCALAPPDATA ('Programs\myTech.Today\AppInstaller\PowerShell\{0}\pwsh.exe' -f $coreVersion)); Source = 'AppInstallerManaged' }
        }
    }
    foreach ($path in $corePaths) {
        Add-InstallerRuntimeCandidate -Candidates $candidates -Path $path.Path -Engine Core -Source $path.Source
    }

    foreach ($registered in @(Get-InstallerRegisteredPowerShellCorePaths)) {
        Add-InstallerRuntimeCandidate -Candidates $candidates -Path ([string]$registered.Path) -Engine Core -Source ([string]$registered.Source)
    }

    if (Get-Command -Name Get-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            foreach ($package in @(Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction Stop)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$package.InstallLocation)) {
                    $packagePath = Join-Path ([string]$package.InstallLocation) 'pwsh.exe'
                    Add-InstallerRuntimeCandidate -Candidates $candidates -Path $packagePath -Engine Core -Source StorePackage
                }
            }
        }
        catch {
        }
    }

    $desktopPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($env:PROCESSOR_ARCHITEW6432) {
        $desktopPath = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    Add-InstallerRuntimeCandidate -Candidates $candidates -Path $desktopPath -Engine Desktop -Source WindowsPowerShell

    $engineOrder = @($Manifest.windowsExecutable.engineSelectionOrder)
    $ranked = foreach ($orderIndex in 0..([Math]::Max(0, $engineOrder.Count - 1))) {
        $engineLabel = [string]$engineOrder[$orderIndex]
        $engineKind = if ($engineLabel -match '^PowerShell Core\b') { 'Core' } else { 'Desktop' }
        foreach ($candidate in @($candidates | Where-Object { $_.Engine -eq $engineKind })) {
            [PSCustomObject]@{ Path = $candidate.Path; Engine = $candidate.Engine; Source = $candidate.Source; Order = $orderIndex }
        }
    }
    return @($ranked)
}

function Get-InstallerRuntimeProbeScript {
    return @'
$ErrorActionPreference = 'Stop'
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($env:APP_INSTALLER_PROBE_APPLICATION, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    [Console]::Error.WriteLine('Application parse preflight failed: ' + $parseErrors[0].Message)
    exit 21
}
$processArchitecture = ''
try {
    $processArchitecture = [string][System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
}
catch {
    if ([Environment]::Is64BitProcess) {
        $processArchitecture = [string]$env:PROCESSOR_ARCHITECTURE
        if ($processArchitecture -notmatch '(?i)ARM64|AARCH64|AMD64|X64') {
            $processArchitecture = 'X64'
        }
    }
    else {
        $processArchitecture = 'X86'
    }
}
switch -Regex ($processArchitecture.ToUpperInvariant()) {
    '^(AMD64|X64)$' { $processArchitecture = 'X64'; break }
    '^(ARM64|AARCH64)$' { $processArchitecture = 'Arm64'; break }
    '^(X86|I386)$' { $processArchitecture = 'X86'; break }
    default { $processArchitecture = $processArchitecture.ToUpperInvariant() }
}
$apartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState()
$guiCapability = $null
if ($env:APP_INSTALLER_PROBE_COMPONENT -eq 'WindowsGui') {
    try {
        Import-Module -Name $env:APP_INSTALLER_PROBE_COMPATIBILITY_MODULE -Force -DisableNameChecking -ErrorAction Stop | Out-Null
        $guiCapability = Test-InstallerGuiCapability -ProcessArchitecture $processArchitecture -ApartmentState $apartmentState
    }
    catch {
        $guiCapability = [PSCustomObject]@{ IsSupported = $false; ReasonCode = 'GUI_CAPABILITY_GATE_FAILED'; Reason = 'The shared GUI capability gate could not complete.' }
    }
}
$result = [ordered]@{
    Version = [string]$PSVersionTable.PSVersion
    Edition = [string]$PSVersionTable.PSEdition
    ProcessArchitecture = $processArchitecture
    Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
    ApartmentState = $apartmentState
    GuiCapabilityIsSupported = if ($null -ne $guiCapability) { [bool]$guiCapability.IsSupported } else { $false }
    GuiCapabilityReasonCode = if ($null -ne $guiCapability) { [string]$guiCapability.ReasonCode } else { '' }
    GuiCapabilityReason = if ($null -ne $guiCapability) { [string]$guiCapability.Reason } else { '' }
}
[Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
'@
}

function Invoke-InstallerRuntimeProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsCli', 'WindowsGui')]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$ApplicationPath,

        [Parameter()]
        [int]$TimeoutSeconds = 12
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ExecutablePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $argumentValues = @('-NoProfile', '-NonInteractive')
    if ($Component -eq 'WindowsGui') {
        $argumentValues += '-STA'
    }
    $argumentValues += @('-Command', (Get-InstallerRuntimeProbeScript))
    $startInfo.Arguments = (($argumentValues | ForEach-Object { ConvertTo-InstallerRuntimeWindowsArgument -Argument ([string]$_) }) -join ' ')
    $startInfo.EnvironmentVariables['APP_INSTALLER_PROBE_COMPONENT'] = $Component
    $startInfo.EnvironmentVariables['APP_INSTALLER_PROBE_APPLICATION'] = $ApplicationPath
    $startInfo.EnvironmentVariables['APP_INSTALLER_PROBE_COMPATIBILITY_MODULE'] = Join-Path (Split-Path -Parent $ApplicationPath) 'modules\InstallerCompatibility.psm1'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = $false; Reason = 'The candidate process did not start.'; Probe = $null }
        }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            try { [void]$process.WaitForExit(3000) } catch {}
            return [PSCustomObject]@{ Success = $false; TimedOut = $true; PolicyBlocked = $false; Reason = "The candidate preflight exceeded $TimeoutSeconds seconds."; Probe = $null }
        }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0) {
            $reason = if ($stderr) { $stderr } else { "The candidate preflight exited with code $($process.ExitCode)." }
            return [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = ($reason -match '(?i)execution policy|running scripts is disabled|not digitally signed'); Reason = $reason; Probe = $null }
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) {
            return [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = $false; Reason = 'The candidate returned no preflight data.'; Probe = $null }
        }
        try {
            $probe = $stdout | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            return [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = $false; Reason = 'The candidate returned malformed preflight data.'; Probe = $null }
        }
        return [PSCustomObject]@{ Success = $true; TimedOut = $false; PolicyBlocked = $false; Reason = ''; Probe = $probe }
    }
    catch {
        $exception = $_.Exception
        $policyBlocked = $exception.ToString() -match '(?i)execution policy|running scripts is disabled|not digitally signed'
        return [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = $policyBlocked; Reason = $exception.Message; Probe = $null }
    }
    finally {
        $process.Dispose()
    }
}

function Test-InstallerRuntimeProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Candidate,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Probe,

        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsCli', 'WindowsGui')]
        [string]$Component,

        [Parameter()]
        [PSCustomObject]$HostInfo = (Get-InstallerHostInfo),

        [Parameter()]
        [PSCustomObject]$Manifest = (Get-InstallerCompatibilityManifest)
    )

    try {
        $version = [version][string]$Probe.Version
    }
    catch {
        return [PSCustomObject]@{ IsCompatible = $false; Reason = 'The candidate returned a malformed PowerShell version.' }
    }
    if ([string]$Probe.ProcessArchitecture -ne [string]$Manifest.windowsClient.architecture -or -not [bool]$Probe.Is64BitOperatingSystem) {
        return [PSCustomObject]@{ IsCompatible = $false; Reason = "The candidate process architecture is $($Probe.ProcessArchitecture); x64 is required." }
    }
    $engineInfo = [PSCustomObject]@{ PSEdition = [string]$Probe.Edition; PSVersion = $version }
    $engineDecision = Test-InstallerPowerShellEngine -EngineInfo $engineInfo -Manifest $Manifest
    $identityMatches = ([string]$Candidate.Engine -eq 'Core' -and [string]$engineInfo.PSEdition -eq 'Core') -or ([string]$Candidate.Engine -eq 'Desktop' -and [string]$engineInfo.PSEdition -eq 'Desktop')
    if (($engineDecision.IsSupported -ne $true) -or -not $identityMatches) {
        $reason = if ($engineDecision.Reason) { $engineDecision.Reason } else { 'The executable identity does not match its PowerShell edition.' }
        return [PSCustomObject]@{ IsCompatible = $false; Reason = $reason }
    }

    if ($Component -eq 'WindowsGui' -and -not [bool]$Probe.GuiCapabilityIsSupported) {
        $reasonCode = if ($Probe.GuiCapabilityReasonCode) { [string]$Probe.GuiCapabilityReasonCode } else { 'GUI_CAPABILITY_GATE_FAILED' }
        $reason = if ($Probe.GuiCapabilityReason) { [string]$Probe.GuiCapabilityReason } else { 'The shared GUI capability gate rejected this PowerShell host.' }
        return [PSCustomObject]@{ IsCompatible = $false; Reason = ('[{0}] {1}' -f $reasonCode, $reason) }
    }

    return [PSCustomObject]@{ IsCompatible = $true; Reason = '' }
}

function Resolve-InstallerRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsCli', 'WindowsGui')]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$ApplicationPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CandidateRecords,

        [Parameter()]
        [scriptblock]$ProbeInvoker,

        [Parameter()]
        [switch]$AllowTestCandidates,

        [Parameter()]
        [int]$TimeoutSeconds = 12,

        [Parameter()]
        [PSCustomObject]$HostInfo = (Get-InstallerHostInfo),

        [Parameter()]
        [PSCustomObject]$Manifest = (Get-InstallerCompatibilityManifest)
    )

    if ($null -eq $CandidateRecords) {
        $CandidateRecords = @(Get-InstallerRuntimeCandidates -Manifest $Manifest)
    }
    $orderedCandidates = New-Object 'System.Collections.Generic.List[object]'
    $engineKindsInOrder = @($Manifest.windowsExecutable.engineSelectionOrder | ForEach-Object {
        if ([string]$_ -match '^PowerShell Core\b') { 'Core' } else { 'Desktop' }
    })
    foreach ($engineKind in $engineKindsInOrder) {
        foreach ($candidate in $CandidateRecords) {
            if ([string]$candidate.Engine -eq $engineKind) {
                $orderedCandidates.Add($candidate)
            }
        }
    }
    foreach ($candidate in $CandidateRecords) {
        if ($engineKindsInOrder -notcontains [string]$candidate.Engine) {
            $orderedCandidates.Add($candidate)
        }
    }
    $CandidateRecords = $orderedCandidates.ToArray()
    $attempts = New-Object 'System.Collections.Generic.List[object]'
    $selected = $null
    $hasPolicyBlock = $false
    foreach ($candidate in $CandidateRecords) {
        $validation = Test-InstallerRuntimeCandidatePath -Candidate $candidate -AllowTestCandidate:$AllowTestCandidates
        if (-not $validation.IsValid) {
            $attempts.Add([PSCustomObject]@{ Candidate = $candidate; IsCompatible = $false; Reason = $validation.Reason; PolicyBlocked = $false; Probe = $null })
            continue
        }

        try {
            if ($ProbeInvoker) {
                $probeResult = & $ProbeInvoker $candidate $Component $ApplicationPath $TimeoutSeconds
            }
            else {
                $probeResult = Invoke-InstallerRuntimeProbe -ExecutablePath $validation.Path -Component $Component -ApplicationPath $ApplicationPath -TimeoutSeconds $TimeoutSeconds
            }
        }
        catch {
            $probeResult = [PSCustomObject]@{ Success = $false; TimedOut = $false; PolicyBlocked = $false; Reason = $_.Exception.Message; Probe = $null }
        }

        if ($null -eq $probeResult -or -not [bool]$probeResult.Success) {
            $reason = if ($null -ne $probeResult -and $probeResult.Reason) { [string]$probeResult.Reason } elseif ($null -ne $probeResult -and $probeResult.TimedOut) { 'The candidate preflight timed out.' } else { 'The candidate preflight failed.' }
            $policyBlocked = ($null -ne $probeResult -and [bool]$probeResult.PolicyBlocked)
            $attempts.Add([PSCustomObject]@{ Candidate = $candidate; IsCompatible = $false; Reason = $reason; PolicyBlocked = $policyBlocked; Probe = $null })
            if ($policyBlocked) {
                $hasPolicyBlock = $true
                break
            }
            continue
        }

        $engineDecision = Test-InstallerRuntimeProbe -Candidate $candidate -Probe $probeResult.Probe -Component $Component -HostInfo $HostInfo -Manifest $Manifest
        $attempts.Add([PSCustomObject]@{ Candidate = $candidate; IsCompatible = [bool]$engineDecision.IsCompatible; Reason = [string]$engineDecision.Reason; PolicyBlocked = $false; Probe = $probeResult.Probe })
        if ($engineDecision.IsCompatible -and $null -eq $selected) {
            $selected = $candidate
        }
    }

    if ($null -ne $selected) {
        return [PSCustomObject]@{ IsSupported = $true; Component = $Component; Selected = $selected; Attempts = $attempts.ToArray(); PolicyBlocked = $false; Reason = '' }
    }

    $summary = if ($attempts.Count -eq 0) { 'No documented PowerShell executable candidates were found.' } else { (@($attempts | ForEach-Object { '{0}: {1}' -f $_.Candidate.Path, $_.Reason }) -join ' ') }
    if ($hasPolicyBlock) {
        $summary = 'PowerShell execution policy blocked the selected script engine. No alternate engine was attempted. ' + $summary
    }
    return [PSCustomObject]@{ IsSupported = $false; Component = $Component; Selected = $null; Attempts = $attempts.ToArray(); PolicyBlocked = $hasPolicyBlock; Reason = $summary }
}

function Test-InstallerRuntimeHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsCli', 'WindowsGui')]
        [string]$Component
    )

    $expectedPath = [string]$env:APP_INSTALLER_RUNTIME_HANDOFF_PATH
    $expectedComponent = [string]$env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT
    if ([string]::IsNullOrWhiteSpace($expectedPath) -or $expectedComponent -ne $Component) {
        return $false
    }
    try {
        $currentPath = Get-InstallerRuntimeCurrentExecutablePath
        $matches = [System.IO.Path]::GetFullPath($expectedPath).Equals($currentPath, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        $matches = $false
    }
    $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH = ''
    $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT = ''
    return $matches
}

function Invoke-InstallerRuntimeEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WindowsCli', 'WindowsGui')]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$ApplicationPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ScriptArguments = @(),

        [Parameter()]
        [switch]$AllowGuiCliFallback,

        [Parameter()]
        [switch]$AlwaysLaunchApplication,

        [Parameter()]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CandidateRecords,

        [Parameter()]
        [scriptblock]$ProbeInvoker,

        [Parameter()]
        [scriptblock]$LaunchInvoker,

        [Parameter()]
        [switch]$AllowTestCandidates,

        [Parameter()]
        [PSCustomObject]$HostInfo = (Get-InstallerHostInfo),

        [Parameter()]
        [PSCustomObject]$Manifest = (Get-InstallerCompatibilityManifest)
    )

    if (Test-InstallerRuntimeHandoff -Component $Component) {
        return [PSCustomObject]@{ Action = 'Continue'; Component = $Component; ExitCode = $null; Selected = $null; Reason = ''; Attempts = @() }
    }

    $decision = Resolve-InstallerRuntime -Component $Component -ApplicationPath $ApplicationPath -CandidateRecords $CandidateRecords -ProbeInvoker $ProbeInvoker -AllowTestCandidates:$AllowTestCandidates -HostInfo $HostInfo -Manifest $Manifest
    if (-not $decision.IsSupported -and $Component -eq 'WindowsGui' -and $AllowGuiCliFallback -and -not $decision.PolicyBlocked) {
        $cliAttempts = New-Object 'System.Collections.Generic.List[object]'
        $cliSelection = $null
        foreach ($attempt in $decision.Attempts) {
            if ($null -eq $attempt.Probe) {
                $cliAttempts.Add($attempt)
                continue
            }
            $cliCheck = Test-InstallerRuntimeProbe -Candidate $attempt.Candidate -Probe $attempt.Probe -Component WindowsCli -HostInfo $HostInfo -Manifest $Manifest
            $cliAttempt = [PSCustomObject]@{
                Candidate = $attempt.Candidate
                IsCompatible = [bool]$cliCheck.IsCompatible
                Reason = [string]$cliCheck.Reason
                PolicyBlocked = $false
                Probe = $attempt.Probe
            }
            $cliAttempts.Add($cliAttempt)
            if ($cliCheck.IsCompatible -and $null -eq $cliSelection) {
                $cliSelection = $attempt.Candidate
            }
        }
        if ($null -ne $cliSelection) {
            $decision = [PSCustomObject]@{ IsSupported = $true; Component = 'WindowsCli'; Selected = $cliSelection; Attempts = $cliAttempts.ToArray(); PolicyBlocked = $false; Reason = '' }
            $Component = 'WindowsCli'
            if (@($ScriptArguments | Where-Object { $_ -match '^(?i)-ForceCLI$' }).Count -eq 0) {
                $ScriptArguments += '-ForceCLI'
            }
        }
    }
    if (-not $decision.IsSupported) {
        return [PSCustomObject]@{ Action = 'Failure'; Component = $Component; ExitCode = 1; Selected = $null; Reason = $decision.Reason; Attempts = @($decision.Attempts); PolicyBlocked = $decision.PolicyBlocked }
    }

    $currentPath = Get-InstallerRuntimeCurrentExecutablePath
    $selectedPath = [System.IO.Path]::GetFullPath([string]$decision.Selected.Path)
    $currentApartment = [string][Threading.Thread]::CurrentThread.GetApartmentState()
    $requiresStaHandoff = ($Component -eq 'WindowsGui' -and $currentApartment -ne 'STA')
    if (-not $AlwaysLaunchApplication -and -not $requiresStaHandoff -and $currentPath.Equals($selectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{ Action = 'Continue'; Component = $Component; ExitCode = $null; Selected = $decision.Selected; Reason = ''; Attempts = @($decision.Attempts) }
    }

    $launchFailures = New-Object 'System.Collections.Generic.List[string]'
    $compatibleCandidates = @($decision.Attempts | Where-Object { $_.IsCompatible } | ForEach-Object { $_.Candidate })
    if ($compatibleCandidates.Count -eq 0) {
        $compatibleCandidates = @($decision.Selected)
    }
    foreach ($candidate in $compatibleCandidates) {
        $oldPath = $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH
        $oldComponent = $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT
        $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH = [string]$candidate.Path
        $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT = $Component
        try {
            if ($LaunchInvoker) {
                $launchResult = & $LaunchInvoker $candidate $ApplicationPath $ScriptArguments $Component
                if ($null -ne $launchResult -and [bool]$launchResult.Started) {
                    return [PSCustomObject]@{ Action = 'Exit'; Component = $Component; ExitCode = [int]$launchResult.ExitCode; Selected = $candidate; Reason = ''; Attempts = @($decision.Attempts) }
                }
                $launchReason = if ($null -ne $launchResult -and $launchResult.Reason) { [string]$launchResult.Reason } else { 'The compatible engine could not start the application.' }
                $launchFailures.Add(('{0}: {1}' -f $candidate.Path, $launchReason))
            }
            else {
                $nativeArguments = @('-NoProfile')
                if ($Component -eq 'WindowsGui') {
                    $nativeArguments += '-STA'
                }
                $nativeArguments += @('-File', $ApplicationPath) + @($ScriptArguments)
                # The caller assigns this function's return value. Send the
                # child CLI output to the active host so that assignment does
                # not swallow its stdout, while leaving native stderr and
                # interactive input attached to the parent process.
                & $candidate.Path @nativeArguments | Out-Host
                $childExitCode = $LASTEXITCODE
                if ($null -eq $childExitCode) {
                    $childExitCode = 0
                }
                return [PSCustomObject]@{ Action = 'Exit'; Component = $Component; ExitCode = [int]$childExitCode; Selected = $candidate; Reason = ''; Attempts = @($decision.Attempts) }
            }
        }
        catch {
            $launchFailures.Add(('{0}: {1}' -f $candidate.Path, $_.Exception.Message))
        }
        finally {
            $env:APP_INSTALLER_RUNTIME_HANDOFF_PATH = $oldPath
            $env:APP_INSTALLER_RUNTIME_HANDOFF_COMPONENT = $oldComponent
        }
    }

    $failureText = if ($launchFailures.Count -gt 0) { $launchFailures -join ' ' } else { 'No compatible engine could start the application.' }
    return [PSCustomObject]@{ Action = 'Failure'; Component = $Component; ExitCode = 1; Selected = $null; Reason = $failureText; Attempts = @($decision.Attempts); PolicyBlocked = $false }
}

Export-ModuleMember -Function Get-InstallerRuntimeCandidates, Get-InstallerRuntimeCurrentExecutablePath, Test-InstallerRuntimeCandidatePath, Invoke-InstallerRuntimeProbe, Test-InstallerRuntimeProbe, Resolve-InstallerRuntime, ConvertTo-InstallerRuntimeArgumentArray, ConvertTo-InstallerRuntimeWindowsArgument, Test-InstallerRuntimeHandoff, Invoke-InstallerRuntimeEntry
