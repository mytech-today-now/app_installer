Set-StrictMode -Version 2.0

function Get-InstallerExeBuildFileObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [PSCustomObject]@{
            Exists = $false
            FileVersion = ''
            Sha256 = ''
            SignatureStatus = ''
            SignerSubject = ''
        }
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $signatureStatus = 'Unavailable'
    $signerSubject = ''
    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        $signatureStatus = [string]$signature.Status
        if ($null -ne $signature.SignerCertificate) {
            $signerSubject = [string]$signature.SignerCertificate.Subject
        }
    }
    catch {
        $signatureStatus = 'Unavailable'
    }

    return [PSCustomObject]@{
        Exists = $true
        FileVersion = [string]$item.VersionInfo.FileVersion
        Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        SignatureStatus = $signatureStatus
        SignerSubject = $signerSubject
    }
}

function Get-InstallerExeMachineArchitecture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'Missing'
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 64) {
            return 'Invalid'
        }
        $reader = New-Object System.IO.BinaryReader($stream)
        $stream.Position = 0
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            return 'Invalid'
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or ($peOffset + 6) -gt $stream.Length) {
            return 'Invalid'
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            return 'Invalid'
        }
        $machine = $reader.ReadUInt16()
        switch ($machine) {
            0x8664 { return 'X64' }
            0x014c { return 'X86' }
            0xAA64 { return 'ARM64' }
            default { return ('Unknown-0x{0:X4}' -f $machine) }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-InstallerExeBuildContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$SeedPath
    )

    $hostExecutable = (Get-Process -Id $PID -ErrorAction Stop).Path
    $hostObservation = Get-InstallerExeBuildFileObservation -Path $hostExecutable
    $compilerAssemblies = @()
    foreach ($assemblyPin in @($Configuration.host.compiler.assemblies)) {
        $assemblyPath = Join-Path $PSHOME ([string]$assemblyPin.name)
        $observation = Get-InstallerExeBuildFileObservation -Path $assemblyPath
        $compilerAssemblies += [PSCustomObject]@{
            Name = [string]$assemblyPin.name
            FileVersion = $observation.FileVersion
            Sha256 = $observation.Sha256
            SignatureStatus = $observation.SignatureStatus
            SignerSubject = $observation.SignerSubject
            Exists = $observation.Exists
        }
    }

    $runtimeFiles = @()
    $programFilesRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    foreach ($runtimePin in @($Configuration.host.dotnetRuntime.runtimeFiles)) {
        $relativePath = ([string]$runtimePin.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if ([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath.Split([char[]]@('\', '/')) -contains '..') {
            throw 'The build configuration contains an unsafe .NET runtime path.'
        }
        $runtimePath = Join-Path (Join-Path $programFilesRoot 'dotnet') $relativePath
        $observation = Get-InstallerExeBuildFileObservation -Path $runtimePath
        $runtimeFiles += [PSCustomObject]@{
            Path = [string]$runtimePin.path
            FileVersion = $observation.FileVersion
            Sha256 = $observation.Sha256
            SignatureStatus = $observation.SignatureStatus
            SignerSubject = $observation.SignerSubject
            Exists = $observation.Exists
        }
    }

    $makeCabPath = Join-Path $env:WINDIR ([string]$Configuration.packager.makeCab.relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $expandPath = Join-Path $env:WINDIR ([string]$Configuration.packager.expand.relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $makeCabObservation = Get-InstallerExeBuildFileObservation -Path $makeCabPath
    $expandObservation = Get-InstallerExeBuildFileObservation -Path $expandPath
    $seedObservation = Get-InstallerExeBuildFileObservation -Path $SeedPath

    return [PSCustomObject]@{
        Host = [PSCustomObject]@{
            IsWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
            WindowsBuild = [System.Environment]::OSVersion.Version.Build
            OsArchitecture = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
            ProcessArchitecture = [string][System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
        }
        PowerShell = [PSCustomObject]@{
            Edition = [string]$PSVersionTable.PSEdition
            Version = [string]$PSVersionTable.PSVersion
            File = $hostObservation
        }
        DotNetRuntime = [PSCustomObject]@{
            Version = [System.Environment]::Version.ToString()
            Files = $runtimeFiles
        }
        Compiler = [PSCustomObject]@{
            Name = [string]$Configuration.host.compiler.name
            Version = if ($compilerAssemblies.Count -gt 0) { $compilerAssemblies[0].FileVersion } else { '' }
            Assemblies = $compilerAssemblies
        }
        Packager = [PSCustomObject]@{
            MakeCab = $makeCabObservation
            Expand = $expandObservation
        }
        Seed = [PSCustomObject]@{
            File = $seedObservation
            Architecture = Get-InstallerExeMachineArchitecture -Path $SeedPath
        }
    }
}

function Test-InstallerExeBuildContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if ([int]$Configuration.schemaVersion -ne 1) {
        $errors.Add('Unsupported build configuration schema version.')
    }
    if ([string]$Configuration.artifact.architecture -ne 'X64' -or [string]$Configuration.host.architecture -ne 'X64') {
        $errors.Add('The build configuration must target x64 on an x64 host.')
    }
    if ([string]$Configuration.artifact.format -ne 'Unsigned IExpress self-extracting package' -or
        [string]$Configuration.artifact.entryPoint -ne 'install.bat' -or
        [bool]$Configuration.artifact.bundledPowerShellRuntime) {
        $errors.Add('The build configuration does not match the current unsigned IExpress compatibility contract.')
    }

    if (-not [bool]$Context.Host.IsWindows) {
        $errors.Add('The executable can only be built on Windows.')
    }
    if (@($Configuration.host.windowsBuilds | ForEach-Object { [int]$_ }) -notcontains [int]$Context.Host.WindowsBuild) {
        $errors.Add(('Windows build {0} is not pinned for executable builds.' -f $Context.Host.WindowsBuild))
    }
    if ([string]$Context.Host.OsArchitecture -ne 'X64' -or [string]$Context.Host.ProcessArchitecture -ne 'X64') {
        $errors.Add('The build host and process must both be x64.')
    }
    if ([string]$Context.PowerShell.Edition -ne [string]$Configuration.host.powerShell.edition -or
        [string]$Context.PowerShell.Version -ne [string]$Configuration.host.powerShell.version) {
        $errors.Add(('PowerShell {0} {1} is required.' -f $Configuration.host.powerShell.edition, $Configuration.host.powerShell.version))
    }
    if ([string]$Context.DotNetRuntime.Version -ne [string]$Configuration.host.dotnetRuntime.version) {
        $errors.Add(('.NET runtime {0} is required.' -f $Configuration.host.dotnetRuntime.version))
    }

    $powerShellPin = $Configuration.host.powerShell
    $powerShellFile = $Context.PowerShell.File
    if (-not [bool]$powerShellFile.Exists -or
        [string]$powerShellFile.FileVersion -ne [string]$powerShellPin.fileVersion -or
        [string]$powerShellFile.Sha256 -ne [string]$powerShellPin.sha256 -or
        [string]$powerShellFile.SignatureStatus -ne [string]$powerShellPin.signatureStatus -or
        [string]$powerShellFile.SignerSubject -ne [string]$powerShellPin.signerSubject) {
        $errors.Add('The PowerShell executable does not match its pinned Microsoft release.')
    }

    if ([string]$Context.Compiler.Name -ne [string]$Configuration.host.compiler.name -or
        [string]$Context.Compiler.Version -ne [string]$Configuration.host.compiler.version) {
        $errors.Add('The bundled Roslyn compiler version does not match the pin.')
    }
    $sdkRequirement = $Configuration.host.compiler.PSObject.Properties['dotnetSdkRequired']
    if ($null -eq $sdkRequirement -or [bool]$sdkRequirement.Value) {
        $errors.Add('The build configuration must not require a separate .NET SDK.')
    }
    $actualCompilerAssemblies = @($Context.Compiler.Assemblies)
    foreach ($assemblyPin in @($Configuration.host.compiler.assemblies)) {
        $assembly = @($actualCompilerAssemblies | Where-Object { [string]$_.Name -eq [string]$assemblyPin.name }) | Select-Object -First 1
        if ($null -eq $assembly -or -not [bool]$assembly.Exists -or
            [string]$assembly.FileVersion -ne [string]$Configuration.host.compiler.version -or
            [string]$assembly.Sha256 -ne [string]$assemblyPin.sha256 -or
            [string]$assembly.SignatureStatus -ne 'Valid' -or
            [string]$assembly.SignerSubject -ne [string]$assemblyPin.signerSubject) {
            $errors.Add(('Pinned compiler assembly is missing or does not match: {0}' -f $assemblyPin.name))
        }
    }

    foreach ($runtimePin in @($Configuration.host.dotnetRuntime.runtimeFiles)) {
        $runtimeFile = @($Context.DotNetRuntime.Files | Where-Object { [string]$_.Path -eq [string]$runtimePin.path }) | Select-Object -First 1
        if ($null -eq $runtimeFile -or -not [bool]$runtimeFile.Exists -or
            [string]$runtimeFile.FileVersion -ne [string]$runtimePin.fileVersion -or
            [string]$runtimeFile.Sha256 -ne [string]$runtimePin.sha256 -or
            [string]$runtimeFile.SignatureStatus -ne 'Valid' -or
            [string]$runtimeFile.SignerSubject -ne [string]$runtimePin.signerSubject) {
            $errors.Add(('Pinned .NET runtime file is missing or does not match: {0}' -f $runtimePin.path))
        }
    }

    foreach ($toolName in @('makeCab', 'expand')) {
        $toolPin = $Configuration.packager.$toolName
        $toolObservation = if ($toolName -eq 'makeCab') { $Context.Packager.MakeCab } else { $Context.Packager.Expand }
        if ($null -eq $toolObservation -or -not [bool]$toolObservation.Exists -or
            [string]$toolObservation.FileVersion -ne [string]$toolPin.fileVersion -or
            [string]$toolObservation.Sha256 -ne [string]$toolPin.sha256 -or
            [string]$toolObservation.SignatureStatus -ne 'Valid' -or
            [string]$toolObservation.SignerSubject -ne [string]$toolPin.signerSubject) {
            $errors.Add(('Pinned Windows packaging tool is missing or does not match: {0}' -f $toolName))
        }
    }

    $seedPin = $Configuration.seed
    if (-not [bool]$Context.Seed.File.Exists -or
        [string]$Context.Seed.File.FileVersion -ne [string]$seedPin.fileVersion -or
        [string]$Context.Seed.File.Sha256 -ne [string]$seedPin.sha256 -or
        [string]$Context.Seed.File.SignatureStatus -ne [string]$seedPin.signatureStatus -or
        -not [string]::IsNullOrEmpty([string]$Context.Seed.File.SignerSubject) -or
        [string]$Context.Seed.Architecture -ne [string]$seedPin.machine) {
        $errors.Add('The IExpress seed is missing, changed, signed, or has the wrong architecture.')
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors.ToArray())
    }
}

function Test-InstallerExeVersionContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText,

        [Parameter(Mandatory = $true)]
        [string]$GuiSource,

        [Parameter(Mandatory = $true)]
        [string]$CliSource,

        [Parameter(Mandatory = $true)]
        [string]$ReadmeText
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $stableSemVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    $guiVersionDeclarations = [regex]::Matches($VersionText, '(?m)^[ \t]*\*\*GUI Version:\*\*[ \t]*(.*?)[ \t]*$')
    $cliVersionDeclarations = [regex]::Matches($VersionText, '(?m)^[ \t]*\*\*CLI Version:\*\*[ \t]*(.*?)[ \t]*$')
    $guiScriptDeclarations = [regex]::Matches($GuiSource, '(?m)^[ \t]*\$script:ScriptVersion[ \t]*=[ \t]*(.*?)[ \t]*$')
    $cliScriptDeclarations = [regex]::Matches($CliSource, '(?m)^[ \t]*\$script:ScriptVersion[ \t]*=[ \t]*(.*?)[ \t]*$')
    $guiHeaderDeclarations = [regex]::Matches($GuiSource, '(?m)^[ \t]*Version[ \t]*:[ \t]*(.*?)[ \t]*$')
    $cliHeaderDeclarations = [regex]::Matches($CliSource, '(?m)^[ \t]*Version[ \t]*:[ \t]*(.*?)[ \t]*$')

    if ($guiVersionDeclarations.Count -ne 1) {
        $errors.Add('VERSION must contain exactly one current GUI Version declaration.')
    }
    if ($cliVersionDeclarations.Count -ne 1) {
        $errors.Add('VERSION must contain exactly one current CLI Version declaration.')
    }

    $guiVersion = if ($guiVersionDeclarations.Count -eq 1) { ([string]$guiVersionDeclarations[0].Groups[1].Value).Trim() } else { '' }
    $cliVersion = if ($cliVersionDeclarations.Count -eq 1) { ([string]$cliVersionDeclarations[0].Groups[1].Value).Trim() } else { '' }
    foreach ($entry in @(@{ Name = 'GUI'; Value = $guiVersion }, @{ Name = 'CLI'; Value = $cliVersion })) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { continue }
        if ([string]$entry.Value -cnotmatch $stableSemVerPattern) {
            $errors.Add(('The {0} version in VERSION must use stable MAJOR.MINOR.PATCH semantic version syntax; prereleases and build metadata are unsupported.' -f $entry.Name))
        }
    }

    $getScriptVersion = {
        param([System.Text.RegularExpressions.MatchCollection]$Declarations, [string]$Name)
        if ($Declarations.Count -ne 1) {
            $errors.Add(('The {0} script must contain exactly one ScriptVersion assignment.' -f $Name))
            return ''
        }
        $literal = [regex]::Match(([string]$Declarations[0].Groups[1].Value).Trim(), '^(?:''(?<single>[^'']*)''|\"(?<double>[^\"]*)\")$')
        if (-not $literal.Success) {
            $errors.Add(('The {0} ScriptVersion assignment must be one quoted version literal.' -f $Name))
            return ''
        }
        if ($literal.Groups['single'].Success) { return [string]$literal.Groups['single'].Value }
        return [string]$literal.Groups['double'].Value
    }
    $guiScriptVersion = & $getScriptVersion $guiScriptDeclarations 'GUI'
    $cliScriptVersion = & $getScriptVersion $cliScriptDeclarations 'CLI'
    foreach ($entry in @(@{ Name = 'GUI'; Value = $guiScriptVersion }, @{ Name = 'CLI'; Value = $cliScriptVersion })) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { continue }
        if ([string]$entry.Value -cnotmatch $stableSemVerPattern) {
            $errors.Add(('The {0} ScriptVersion must use stable MAJOR.MINOR.PATCH semantic version syntax.' -f $entry.Name))
        }
    }

    if ($guiHeaderDeclarations.Count -ne 1 -or ([string]$guiHeaderDeclarations[0].Groups[1].Value).Trim() -cne $guiScriptVersion) {
        $errors.Add('The GUI script header version must match its ScriptVersion assignment.')
    }
    if ($cliHeaderDeclarations.Count -ne 1 -or ([string]$cliHeaderDeclarations[0].Groups[1].Value).Trim() -cne $cliScriptVersion) {
        $errors.Add('The CLI script header version must match its ScriptVersion assignment.')
    }
    if ($guiVersion -cne $guiScriptVersion) {
        $errors.Add('The GUI script version does not match VERSION.')
    }
    if ($cliVersion -cne $cliScriptVersion) {
        $errors.Add('The CLI script version does not match VERSION.')
    }

    $readmeVersionDeclarations = [regex]::Matches($ReadmeText, '(?m)^[ \t]*\*\*Version:\*\*[ \t]*(.*?)[ \t]*$')
    if ($readmeVersionDeclarations.Count -eq 0) {
        $errors.Add('README.md must declare the current GUI and CLI versions.')
    }
    foreach ($declaration in $readmeVersionDeclarations) {
        $readmeMapping = [regex]::Match(([string]$declaration.Groups[1].Value).Trim(), '^(?<gui>[^\s]+)\s+\(GUI\)\s*/\s*(?<cli>[^\s]+)\s+\(CLI\)$')
        if (-not $readmeMapping.Success -or
            $readmeMapping.Groups['gui'].Value -cne $guiVersion -or
            $readmeMapping.Groups['cli'].Value -cne $cliVersion) {
            $errors.Add('Every current version declaration in README.md must match the GUI and CLI versions in VERSION.')
            break
        }
    }
    $readmeReleaseMappings = [regex]::Matches($ReadmeText, '(?m)^[ \t]*\*\*Release version mapping:\*\*[ \t]*GUI[ \t]*(?<gui>[^\s]+)[ \t]*/[ \t]*CLI[ \t]*(?<cli>[^\s]+)[ \t]*\r?$')
    if ($readmeReleaseMappings.Count -ne 1 -or
        ([string]$readmeReleaseMappings[0].Groups['gui'].Value).Trim() -cne $guiVersion -or
        ([string]$readmeReleaseMappings[0].Groups['cli'].Value).Trim() -cne $cliVersion) {
        $errors.Add('README.md must contain one current release version mapping matching VERSION.')
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        GuiVersion = $guiVersion
        CliVersion = $cliVersion
        Errors = @($errors.ToArray())
    }
}

function Test-InstallerExeCompatibilityContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Compatibility,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $executable = $Compatibility.windowsExecutable
    if ([string]$executable.format -cne [string]$Configuration.artifact.format -or
        [string]$executable.entryPoint -cne [string]$Configuration.artifact.entryPoint -or
        [bool]$executable.bundledPowerShellRuntime -ne [bool]$Configuration.artifact.bundledPowerShellRuntime -or
        [string]$executable.buildScript -cne 'tools/Build-InstallerExe.ps1' -or
        [string]$executable.metadataScript -cne 'tools/Set-InstallerExeMetadata.ps1') {
        $errors.Add('compatibility.json does not match the executable build configuration.')
    }
    $provisioning = $executable.runtimeDiscovery.provisioning
    if ([string]$provisioning.version -cne [string]$Configuration.host.powerShell.version -or
        [string]$provisioning.architecture -cne 'X64' -or
        [string]$provisioning.sha256 -cne [string]$Configuration.host.powerShell.distributionSha256 -or
        [string]$provisioning.source -cne [string]$Configuration.host.powerShell.distributionUrl) {
        $errors.Add('compatibility.json does not match the pinned PowerShell release asset.')
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors.ToArray())
    }
}

function Assert-InstallerExeBuildOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string]$SeedPath,

        [Parameter()]
        [string[]]$ProtectedOutputPaths = @()
    )

    $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
    if (-not [string]::Equals([System.IO.Path]::GetExtension($outputFullPath), '.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The executable output path must end in .exe.'
    }

    foreach ($protectedPath in @($SeedPath) + @($ProtectedOutputPaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$protectedPath)) { continue }
        $protectedFullPath = [System.IO.Path]::GetFullPath([string]$protectedPath)
        if ([string]::Equals($outputFullPath, $protectedFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('The output path is reserved for a tracked legacy artifact: {0}' -f $protectedFullPath)
        }
    }

    $manifestPath = $outputFullPath + '.build.json'
    if (Test-Path -LiteralPath $outputFullPath) {
        throw "The output already exists. Choose a new versioned path: $outputFullPath"
    }
    if (Test-Path -LiteralPath $manifestPath) {
        throw "A build manifest already exists for this output. Choose a new versioned path: $manifestPath"
    }

    return [PSCustomObject]@{
        OutputPath = $outputFullPath
        ManifestPath = $manifestPath
        OutputDirectory = [System.IO.Path]::GetDirectoryName($outputFullPath)
    }
}

function New-InstallerExeBuildInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Files
    )

    $fileByPath = @{}
    $paths = @()
    foreach ($file in $Files) {
        $path = ([string]$file.Path).Replace('\', '/')
        $fileByPath[$path.ToLowerInvariant()] = $file
        $paths += $path
    }
    [System.Array]::Sort($paths, [System.StringComparer]::OrdinalIgnoreCase)
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        $file = $fileByPath[$path.ToLowerInvariant()]
        $item = Get-Item -LiteralPath ([string]$file.Source) -Force -ErrorAction Stop
        $records.Add([PSCustomObject][ordered]@{
            path = $path
            length = [long]$item.Length
            sha256 = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        })
    }
    return @($records.ToArray())
}

function Get-InstallerExeBuildInventorySha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Inventory
    )

    $json = ConvertTo-Json -InputObject @($Inventory) -Depth 5 -Compress
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $encoding.GetBytes($json)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Assert-InstallerExeUnsignedArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SignatureStatus,

        [Parameter()]
        [AllowEmptyString()]
        [string]$SignerSubject = ''
    )

    if ($SignatureStatus -cne 'NotSigned' -or -not [string]::IsNullOrEmpty($SignerSubject)) {
        throw 'The executable must remain unsigned and have no signer certificate.'
    }
}

function Test-InstallerExeContainedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

Export-ModuleMember -Function @(
    'Get-InstallerExeBuildFileObservation',
    'Get-InstallerExeMachineArchitecture',
    'Get-InstallerExeBuildContext',
    'Test-InstallerExeBuildContext',
    'Test-InstallerExeVersionContract',
    'Test-InstallerExeCompatibilityContract',
    'Assert-InstallerExeBuildOutputPath',
    'New-InstallerExeBuildInventory',
    'Get-InstallerExeBuildInventorySha256',
    'Assert-InstallerExeUnsignedArtifact',
    'Test-InstallerExeContainedPath'
)
