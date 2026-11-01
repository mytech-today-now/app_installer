<#
.SYNOPSIS
    Builds validated WinGet executable and argument specifications.

.DESCRIPTION
    This module is the single source for WinGet package identity and source
    validation, exact matching, operation options, and executable argument
    construction. Callers retain their own orchestration, presentation, and
    retry timing.
#>

function Test-WingetPackageIdentifier {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object]$PackageId
    )

    return ($PackageId -is [string] -and [regex]::IsMatch(
            $PackageId,
            '\A[A-Za-z0-9][A-Za-z0-9._+-]*\z',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        ))
}

function Test-WingetPackageSource {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Source
    )

    return ($Source -is [string] -and $Source -cin @('winget', 'msstore'))
}

function Get-WingetPackageSourceMappings {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Manifest,

        [string]$ManifestPath
    )

    if ($null -eq $Manifest) {
        if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
            $ManifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\apps-manifest.json'))
        }
        if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
            throw "Required application catalog is missing: $ManifestPath"
        }
        try {
            $Manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "The complete application catalog could not be loaded. $($_.Exception.Message)"
        }
    }

    if ($null -eq $Manifest.apps -or @($Manifest.apps).Count -eq 0) {
        throw 'The application catalog does not contain an apps collection.'
    }

    $mappings = @()
    foreach ($catalogApp in $Manifest.apps) {
        if ($null -eq $catalogApp.packages) {
            throw "Application '$($catalogApp.name)' does not contain a packages object."
        }

        $wingetIdProperty = $catalogApp.packages.PSObject.Properties['winget']
        $wingetSourceProperty = $catalogApp.packages.PSObject.Properties['wingetSource']
        $wingetId = if ($wingetIdProperty) { $wingetIdProperty.Value } else { $null }
        $wingetSource = if ($wingetSourceProperty) { $wingetSourceProperty.Value } else { $null }

        if ($null -eq $wingetId -or ([string]$wingetId).Length -eq 0) {
            if ($null -ne $wingetSource) {
                throw "Application '$($catalogApp.name)' declares a WinGet source without a WinGet package ID."
            }
            continue
        }

        if (-not (Test-WingetPackageIdentifier -PackageId $wingetId)) {
            throw "Application '$($catalogApp.name)' has an invalid WinGet package ID."
        }
        if (-not (Test-WingetPackageSource -Source $wingetSource)) {
            throw "Application '$($catalogApp.name)' must declare a supported WinGet source (winget or msstore)."
        }

        $existingMapping = @($mappings | Where-Object { $_.PackageId -ieq [string]$wingetId })
        if ($existingMapping.Count -gt 0 -and $existingMapping[0].Source -cne $wingetSource) {
            throw "WinGet package ID '$wingetId' is mapped to conflicting sources."
        }
        if ($existingMapping.Count -eq 0) {
            $mappings += [pscustomobject]@{
                PackageId = [string]$wingetId
                Source = [string]$wingetSource
            }
        }
    }

    return [object[]]$mappings
}

function Get-WingetPackageSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [string]$ManifestPath
    )

    $mappings = @(Get-WingetPackageSourceMappings -ManifestPath $ManifestPath)
    $matches = @($mappings | Where-Object { $_.PackageId -ceq $PackageId })
    if ($matches.Count -eq 0) {
        throw "WinGet package ID '$PackageId' has no source mapping in apps-manifest.json. No package command was run."
    }

    $sources = @($matches | ForEach-Object { [string]$_.Source } | Select-Object -Unique)
    if ($sources.Count -ne 1 -or [string]::IsNullOrWhiteSpace($sources[0])) {
        throw "WinGet package ID '$PackageId' has ambiguous or missing source metadata. No package command was run."
    }

    return $sources[0]
}

function Resolve-WingetPackageSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [AllowNull()]
        [string]$DeclaredSource,

        [string]$ManifestPath
    )

    $catalogSource = Get-WingetPackageSource -PackageId $PackageId -ManifestPath $ManifestPath
    if (-not [string]::IsNullOrWhiteSpace($DeclaredSource) -and $DeclaredSource -cne $catalogSource) {
        throw "WinGet package ID '$PackageId' declares source '$DeclaredSource' but the catalog maps it to '$catalogSource'. No package command was run."
    }

    return $catalogSource
}

function New-WingetPackageCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'upgrade', 'uninstall', 'show', 'list')]
        [string]$Operation,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$PackageId,

        [AllowNull()]
        [string]$Source,

        [ValidateSet('--silent', '--force', '--disable-interactivity', '--interactive')]
        [string[]]$ApprovedOptions = @()
    )

    $hasPackageId = -not [string]::IsNullOrWhiteSpace($PackageId)
    if ($hasPackageId -and -not (Test-WingetPackageIdentifier -PackageId $PackageId)) {
        throw 'The WinGet package ID does not match the accepted identifier format. No package command was run.'
    }
    if (-not $hasPackageId -and $Operation -notin @('upgrade', 'list')) {
        throw "WinGet operation '$Operation' requires a package ID. No package command was run."
    }
    if ($hasPackageId -and -not (Test-WingetPackageSource -Source $Source)) {
        throw 'A supported explicit WinGet source is required. No package command was run.'
    }
    if (-not $hasPackageId -and -not [string]::IsNullOrWhiteSpace($Source)) {
        throw "WinGet operation '$Operation' cannot set a package source without a package ID. No package command was run."
    }

    $allowedOptions = switch ($Operation) {
        'install' { @('--silent', '--disable-interactivity') }
        'upgrade' { @('--silent', '--force', '--disable-interactivity', '--interactive') }
        'uninstall' { @('--silent', '--disable-interactivity') }
        'show' { @('--disable-interactivity') }
        'list' { @('--disable-interactivity') }
    }
    foreach ($option in $ApprovedOptions) {
        if ($option -cnotin $allowedOptions) {
            throw "WinGet option '$option' is not approved for '$Operation'. No package command was run."
        }
    }
    if (@($ApprovedOptions | Select-Object -Unique).Count -ne @($ApprovedOptions).Count) {
        throw 'Duplicate WinGet options are not allowed. No package command was run.'
    }
    if ($ApprovedOptions -contains '--interactive' -and
        ($ApprovedOptions -contains '--silent' -or $ApprovedOptions -contains '--disable-interactivity')) {
        throw 'Interactive WinGet mode cannot be combined with silent or disabled-interactivity options. No package command was run.'
    }

    $arguments = @($Operation)
    if ($hasPackageId) {
        $arguments += @('--id', $PackageId)
        if ($Source -ceq 'winget') {
            $arguments += '--exact'
        }
        $arguments += @('--source', $Source)
    }
    if ($ApprovedOptions.Count -gt 0) {
        $arguments += $ApprovedOptions
    }

    return [pscustomobject]@{
        Executable = 'winget'
        Arguments = [string[]]$arguments
        Operation = $Operation
        PackageId = if ($hasPackageId) { $PackageId } else { $null }
        Source = if ($hasPackageId) { $Source } else { $null }
    }
}

Export-ModuleMember -Function @(
    'Test-WingetPackageIdentifier',
    'Test-WingetPackageSource',
    'Get-WingetPackageSourceMappings',
    'Get-WingetPackageSource',
    'Resolve-WingetPackageSource',
    'New-WingetPackageCommand'
)
