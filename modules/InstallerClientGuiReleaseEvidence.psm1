function Get-InstallerClientGuiEvidenceProperty {
    param(
        [Parameter()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Add-InstallerClientGuiEvidenceError {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ErrorMessages,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [void]$ErrorMessages.Add($Message)
}

function New-InstallerClientGuiEvidenceResult {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ErrorMessages,

        [Parameter(Mandatory = $true)]
        [string]$SourceRevision,

        [Parameter()]
        [object]$Record
    )

    [PSCustomObject][ordered]@{
        IsReady = ($ErrorMessages.Count -eq 0)
        SourceRevision = $SourceRevision
        Record = $Record
        Errors = @($ErrorMessages.ToArray())
    }
}

function Test-InstallerClientGuiEvidenceText {
    param(
        [Parameter()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ErrorMessages
    )

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -match '^(?i:NOT RUN|TBD|TODO)(?:$|[\s:])') {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $ErrorMessages -Message ("{0} is missing or remains a placeholder." -f $FieldName)
        return $false
    }

    return $true
}

function Get-InstallerClientGuiEvidenceAssembly {
    param(
        [Parameter()]
        [object]$Assemblies,

        [Parameter(Mandatory = $true)]
        [string]$AssemblyKey,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ErrorMessages,

        [Parameter(Mandatory = $true)]
        [string]$EngineId
    )

    $identity = Get-InstallerClientGuiEvidenceProperty -InputObject $Assemblies -Name $AssemblyKey
    if (-not (Test-InstallerClientGuiEvidenceText -Value $identity -FieldName ("{0} assemblies.{1}" -f $EngineId, $AssemblyKey) -ErrorMessages $ErrorMessages)) {
        return $null
    }

    $namePattern = switch ($AssemblyKey) {
        'System.Windows.Forms' { '^System\.Windows\.Forms,' }
        'System.Drawing' { '^System\.Drawing(?:\.Common)?,' }
        'System.Web' { '^System\.Web(?:\.HttpUtility)?,' }
        default { '^$' }
    }
    $assemblyPattern = '(?i)' + $namePattern + '\s*Version=(?<version>\d+(?:\.\d+){1,3})(?:,|$)'
    $match = [regex]::Match([string]$identity, $assemblyPattern)
    if (-not $match.Success) {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $ErrorMessages -Message ("{0} assemblies.{1} must contain the loaded full assembly identity and version." -f $EngineId, $AssemblyKey)
        return $null
    }

    if ([string]$identity -notmatch '(?i),\s*Culture=(?:neutral|[^,\s]+),\s*PublicKeyToken=(?:null|[a-f0-9]{16})(?:,|$)') {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $ErrorMessages -Message ("{0} assemblies.{1} must include the full Culture and PublicKeyToken identity fields." -f $EngineId, $AssemblyKey)
        return $null
    }

    try {
        return [version]$match.Groups['version'].Value
    }
    catch {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $ErrorMessages -Message ("{0} assemblies.{1} has an invalid assembly version." -f $EngineId, $AssemblyKey)
        return $null
    }
}

function Test-InstallerClientGuiReleaseEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EvidencePath,

        [Parameter(Mandatory = $true)]
        [string]$SourceRevision,

        [Parameter(Mandatory = $true)]
        [string]$CompatibilityPath,

        [Parameter()]
        [datetimeoffset]$AsOfUtc = [datetimeoffset]::UtcNow
    )

    $errorMessages = New-Object 'System.Collections.Generic.List[string]'
    $record = $null

    if ($SourceRevision -cnotmatch '^[0-9a-fA-F]{40}$') {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'The release source revision must be a full 40-character Git commit SHA.'
    }

    if (-not (Test-Path -LiteralPath $CompatibilityPath -PathType Leaf)) {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'compatibility.json is missing; supported host and runtime requirements cannot be checked.'
    }
    else {
        try {
            $compatibility = Get-Content -LiteralPath $CompatibilityPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'compatibility.json is invalid JSON; supported host and runtime requirements cannot be checked.'
        }
    }

    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'The supported-client evidence record is missing.'
    }
    else {
        try {
            $evidence = Get-Content -LiteralPath $EvidencePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'The supported-client evidence record is invalid JSON.'
        }
    }

    if ($errorMessages.Count -gt 0) {
        return New-InstallerClientGuiEvidenceResult -ErrorMessages $errorMessages -SourceRevision $SourceRevision -Record $null
    }

    if ([int](Get-InstallerClientGuiEvidenceProperty -InputObject $evidence -Name 'schemaVersion') -ne 1) {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'The supported-client evidence schemaVersion must be 1.'
    }

    $records = @(Get-InstallerClientGuiEvidenceProperty -InputObject $evidence -Name 'records')
    if ($records.Count -eq 0) {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'The supported-client evidence record has no revision-bound records.'
        return New-InstallerClientGuiEvidenceResult -ErrorMessages $errorMessages -SourceRevision $SourceRevision -Record $null
    }

    $matchingRecords = @($records | Where-Object {
        [string]$_.sourceRevision -ieq $SourceRevision
    })
    if ($matchingRecords.Count -eq 0) {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("No supported-client evidence record matches release source revision {0}." -f $SourceRevision)
        return New-InstallerClientGuiEvidenceResult -ErrorMessages $errorMessages -SourceRevision $SourceRevision -Record $null
    }
    if ($matchingRecords.Count -ne 1) {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("Expected exactly one supported-client evidence record for source revision {0}; found {1}." -f $SourceRevision, $matchingRecords.Count)
    }

    $record = $matchingRecords[0]
    $now = $AsOfUtc.ToUniversalTime()

    $coreEndOfSupportText = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $compatibility.engines.powerShellCore -Name 'endOfSupport')
    $coreEndOfSupport = [datetime]::MinValue
    if ($coreEndOfSupportText -notmatch '^\d{4}-\d{2}-\d{2}$') {
        Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'compatibility.json engines.powerShellCore.endOfSupport must be a yyyy-MM-dd date.'
    }
    else {
        try {
            $coreEndOfSupport = [datetime]::ParseExact(
                $coreEndOfSupportText,
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None
            ).Date
            if ($now.UtcDateTime.Date -gt $coreEndOfSupport) {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("PowerShell Core {0} is outside its support window as of {1:yyyy-MM-dd}." -f $compatibility.engines.powerShellCore.version, $now.UtcDateTime)
            }
        }
        catch {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message 'compatibility.json engines.powerShellCore.endOfSupport must be a real calendar date.'
        }
    }

    $engineIds = @('Desktop-5.1', ('Core-{0}' -f [string]$compatibility.engines.powerShellCore.version))
    $engines = Get-InstallerClientGuiEvidenceProperty -InputObject $record -Name 'engines'
    foreach ($engineId in $engineIds) {
        $row = Get-InstallerClientGuiEvidenceProperty -InputObject $engines -Name $engineId
        if ($null -eq $row) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("Required client evidence row {0} is missing." -f $engineId)
            continue
        }

        $timestampText = Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'recordedAtUtc'
        $timestamp = [datetimeoffset]::MinValue
        $timestampIsValid = $false
        if ($timestampText -is [datetime]) {
            if ($timestampText.Kind -eq [DateTimeKind]::Utc) {
                $timestamp = [datetimeoffset]$timestampText
                $timestampIsValid = $true
            }
        }
        elseif ($timestampText -is [datetimeoffset]) {
            $timestamp = [datetimeoffset]$timestampText
            $timestampIsValid = ($timestamp.Offset -eq [timespan]::Zero)
        }
        elseif ($timestampText -is [string] -and
            $timestampText -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$') {
            $timestampIsValid = [datetimeoffset]::TryParse(
                $timestampText,
                [Globalization.CultureInfo]::InvariantCulture,
                ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal),
                [ref]$timestamp
            )
        }
        if (-not $timestampIsValid) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} recordedAtUtc must be a real UTC timestamp ending in Z." -f $engineId)
        }
        elseif ($timestamp -gt $now) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} recordedAtUtc cannot be in the future." -f $engineId)
        }

        $evidenceLocation = Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'evidenceLocation'
        [void](Test-InstallerClientGuiEvidenceText -Value $evidenceLocation -FieldName ("{0} evidenceLocation" -f $engineId) -ErrorMessages $errorMessages)

        $hostEvidence = Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'host'
        $operatingSystem = Get-InstallerClientGuiEvidenceProperty -InputObject $hostEvidence -Name 'operatingSystem'
        if ($operatingSystem -cne 'Windows 11') {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} host.operatingSystem must be Windows 11; a Server result cannot satisfy client evidence." -f $engineId)
        }
        if ([string](Get-InstallerClientGuiEvidenceProperty -InputObject $hostEvidence -Name 'productType') -cne [string]$compatibility.windowsClient.productType -or
            [string](Get-InstallerClientGuiEvidenceProperty -InputObject $hostEvidence -Name 'installationType') -cne [string]$compatibility.windowsClient.installationType) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} host productType and installationType must identify a Windows client; Server evidence is rejected." -f $engineId)
        }

        $hostEdition = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $hostEvidence -Name 'edition')
        $editionIds = @{ Home = 'Core'; Pro = 'Professional' }
        if (-not $editionIds.ContainsKey($hostEdition) -or
            $compatibility.windowsClient.supportedEditionIds -notcontains [string]$editionIds[$hostEdition]) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} host.edition must be Home or Pro." -f $engineId)
        }

        $hostArchitecture = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $hostEvidence -Name 'architecture')
        if ($hostArchitecture.ToUpperInvariant() -cne [string]$compatibility.windowsClient.architecture) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} host.architecture must be x64." -f $engineId)
        }

        $displayVersion = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $hostEvidence -Name 'displayVersion')
        $buildValue = Get-InstallerClientGuiEvidenceProperty -InputObject $hostEvidence -Name 'build'
        $buildNumber = 0
        $parsedBuild = [int]::TryParse([string]$buildValue, [ref]$buildNumber)
        $supportedReleases = @($compatibility.windowsClient.releases | Where-Object {
            [string]$_.displayVersion -ceq $displayVersion -and $parsedBuild -and [int]$_.build -eq $buildNumber
        })
        if ($supportedReleases.Count -ne 1) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} host release and build must exactly match a Windows 11 client row in compatibility.json." -f $engineId)
        }
        else {
            $endOfSupportText = [string]$supportedReleases[0].consumerEndOfSupport
            try {
                $endOfSupport = [datetime]::ParseExact(
                    $endOfSupportText,
                    'yyyy-MM-dd',
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None
                ).Date
                if ($now.UtcDateTime.Date -gt $endOfSupport) {
                    Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} host Windows 11 {1} is outside the compatibility window as of {2:yyyy-MM-dd}." -f $engineId, $displayVersion, $now.UtcDateTime)
                }
            }
            catch {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("compatibility.json has an invalid end-of-support date for Windows 11 {0}." -f $displayVersion)
            }
        }

        $engine = Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'engine'
        if ([string](Get-InstallerClientGuiEvidenceProperty -InputObject $engine -Name 'id') -cne $engineId) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} engine.id must equal its row identifier." -f $engineId)
        }
        if ([string](Get-InstallerClientGuiEvidenceProperty -InputObject $engine -Name 'processArchitecture').ToUpperInvariant() -cne [string]$compatibility.windowsClient.architecture) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} engine.processArchitecture must be x64." -f $engineId)
        }
        [void](Test-InstallerClientGuiEvidenceText -Value (Get-InstallerClientGuiEvidenceProperty -InputObject $engine -Name 'executable') -FieldName ("{0} engine.executable" -f $engineId) -ErrorMessages $errorMessages)

        $engineEdition = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $engine -Name 'edition')
        $engineVersionText = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $engine -Name 'version')
        $expectedEdition = if ($engineId -eq 'Desktop-5.1') { [string]$compatibility.engines.windowsPowerShell.edition } else { [string]$compatibility.engines.powerShellCore.edition }
        if ($engineEdition -cne $expectedEdition) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} engine.edition must be {1}; the recorded row names a different engine." -f $engineId, $expectedEdition)
        }
        $engineVersion = $null
        try {
            $engineVersion = [version]$engineVersionText
        }
        catch {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} engine.version must be a valid version string." -f $engineId)
        }
        if ($null -ne $engineVersion) {
            if ($engineId -eq 'Desktop-5.1') {
                if ($engineVersion.Major -ne [int]$compatibility.engines.windowsPowerShell.major -or
                    $engineVersion.Minor -ne [int]$compatibility.engines.windowsPowerShell.minor) {
                    Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} engine.version must be Windows PowerShell Desktop 5.1." -f $engineId)
                }
            }
            elseif ($engineVersionText -cne [string]$compatibility.engines.powerShellCore.version) {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} engine.version must be the pinned PowerShell Core {1}." -f $engineId, $compatibility.engines.powerShellCore.version)
            }
        }

        $staConfirmed = Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'staConfirmed'
        if ($staConfirmed -isnot [bool] -or -not [bool]$staConfirmed) {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} staConfirmed must be true." -f $engineId)
        }

        $runtime = Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'runtime'
        $runtimeVersionText = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $runtime -Name 'version')
        $runtimeVersion = $null
        try {
            $runtimeVersion = [version]$runtimeVersionText
        }
        catch {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} runtime.version must be a valid version string." -f $engineId)
        }

        if ($engineId -eq 'Desktop-5.1') {
            $desktopPrerequisite = $compatibility.runtimePrerequisites.windowsPowerShellGui
            if ([string](Get-InstallerClientGuiEvidenceProperty -InputObject $runtime -Name 'name') -cne [string]$desktopPrerequisite.name) {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} runtime.name must be .NET Framework." -f $engineId)
            }
            $releaseValue = Get-InstallerClientGuiEvidenceProperty -InputObject $runtime -Name 'release'
            $releaseNumber = 0
            if (-not [int]::TryParse([string]$releaseValue, [ref]$releaseNumber) -or $releaseNumber -lt [int]$desktopPrerequisite.minimumRelease) {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} runtime.release must be .NET Framework release {1} or later." -f $engineId, $desktopPrerequisite.minimumRelease)
            }
            $minimumRuntimeVersion = [version]$desktopPrerequisite.minimumVersion
            if ($null -eq $runtimeVersion -or $runtimeVersion -lt $minimumRuntimeVersion) {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} runtime.version must be .NET Framework {1} or later." -f $engineId, $desktopPrerequisite.minimumVersion)
            }
        }
        else {
            $corePrerequisite = $compatibility.runtimePrerequisites.powerShellCoreGui
            if ([string](Get-InstallerClientGuiEvidenceProperty -InputObject $runtime -Name 'name') -cne 'Windows Desktop runtime' -or
                [string](Get-InstallerClientGuiEvidenceProperty -InputObject $runtime -Name 'family') -cne [string]$corePrerequisite.runtimeFamily) {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} runtime must identify {1}." -f $engineId, $corePrerequisite.runtimeFamily)
            }
            if ($null -eq $runtimeVersion -or $runtimeVersion.Major -ne [int]$corePrerequisite.runtimeMajor) {
                Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} runtime.version must have major version {1}." -f $engineId, $corePrerequisite.runtimeMajor)
            }
        }

        $assemblies = Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'assemblies'
        $assemblyVersions = @{}
        foreach ($assemblyKey in @('System.Windows.Forms', 'System.Drawing', 'System.Web')) {
            $assemblyVersions[$assemblyKey] = Get-InstallerClientGuiEvidenceAssembly -Assemblies $assemblies -AssemblyKey $assemblyKey -ErrorMessages $errorMessages -EngineId $engineId
        }
        if ($engineId -eq ('Core-{0}' -f [string]$compatibility.engines.powerShellCore.version)) {
            $requiredAssemblyMajor = [int]$compatibility.runtimePrerequisites.powerShellCoreGui.runtimeMajor
            foreach ($assemblyKey in @('System.Windows.Forms', 'System.Drawing')) {
                $assemblyVersion = $assemblyVersions[$assemblyKey]
                if ($null -ne $assemblyVersion -and $assemblyVersion.Major -ne $requiredAssemblyMajor) {
                    Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} assemblies.{1} must match Windows Desktop runtime major {2}." -f $engineId, $assemblyKey, $requiredAssemblyMajor)
                }
            }
        }

        $capabilityResult = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'capabilityResult')
        if ($capabilityResult -cne 'PASS') {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} capabilityResult must be PASS; found '{1}'." -f $engineId, $capabilityResult)
        }
        $startupMode = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'startupMode')
        if ($startupMode -cne 'Isolated') {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} startupMode must be Isolated." -f $engineId)
        }
        $startupResult = [string](Get-InstallerClientGuiEvidenceProperty -InputObject $row -Name 'isolatedStartupResult')
        if ($startupResult -cne 'PASS') {
            Add-InstallerClientGuiEvidenceError -ErrorMessages $errorMessages -Message ("{0} isolatedStartupResult must be PASS; found '{1}'." -f $engineId, $startupResult)
        }
    }

    New-InstallerClientGuiEvidenceResult -ErrorMessages $errorMessages -SourceRevision $SourceRevision -Record $record
}

Export-ModuleMember -Function Test-InstallerClientGuiReleaseEvidence
