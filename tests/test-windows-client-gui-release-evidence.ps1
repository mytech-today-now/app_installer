# Verifies the release gate with synthetic evidence records only.
# This test does not inspect the current host, run a GUI, or provision a runtime.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\InstallerClientGuiReleaseEvidence.psm1'
$compatibilityPath = Join-Path $repositoryRoot 'compatibility.json'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-client-evidence-' + [guid]::NewGuid().ToString('N'))))
$sourceRevision = 'a' * 40
$asOfUtc = [datetimeoffset]::Parse('2026-11-04T20:00:00Z', [Globalization.CultureInfo]::InvariantCulture)
$utf8 = [System.Text.UTF8Encoding]::new($false)
$assertionCount = 0

if (-not $tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary evidence fixture directory is outside the system temporary directory.'
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

    $script:assertionCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function New-ValidClientEvidenceRow {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Desktop-5.1', 'Core-7.6.9')]
        [string]$EngineId
    )

    if ($EngineId -eq 'Desktop-5.1') {
        $engine = [PSCustomObject][ordered]@{
            id = 'Desktop-5.1'
            edition = 'Desktop'
            version = '5.1.26300.9818'
            processArchitecture = 'X64'
            executable = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        }
        $runtime = [PSCustomObject][ordered]@{
            name = '.NET Framework'
            version = '4.8.1'
            release = 533325
        }
        $assemblies = [PSCustomObject][ordered]@{
            'System.Windows.Forms' = 'System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'
            'System.Drawing' = 'System.Drawing, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'
            'System.Web' = 'System.Web, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'
        }
        $evidenceLocation = 'evidence/windows-client-gui/desktop-5.1.txt'
    }
    else {
        $engine = [PSCustomObject][ordered]@{
            id = 'Core-7.6.9'
            edition = 'Core'
            version = '7.6.9'
            processArchitecture = 'X64'
            executable = 'C:\Program Files\PowerShell\7\pwsh.exe'
        }
        $runtime = [PSCustomObject][ordered]@{
            name = 'Windows Desktop runtime'
            family = 'Microsoft.WindowsDesktop.App'
            version = '10.0.14'
        }
        $assemblies = [PSCustomObject][ordered]@{
            'System.Windows.Forms' = 'System.Windows.Forms, Version=10.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'
            'System.Drawing' = 'System.Drawing.Common, Version=10.0.0.0, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51'
            'System.Web' = 'System.Web.HttpUtility, Version=10.0.0.0, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51'
        }
        $evidenceLocation = 'evidence/windows-client-gui/core-7.6.9.txt'
    }

    [PSCustomObject][ordered]@{
        recordedAtUtc = '2026-11-04T18:30:00Z'
        evidenceLocation = $evidenceLocation
        host = [PSCustomObject][ordered]@{
            operatingSystem = 'Windows 11'
            displayVersion = '26H2'
            build = 26300
            edition = 'Home'
            productType = 'WinNT'
            installationType = 'Client'
            architecture = 'X64'
        }
        engine = $engine
        staConfirmed = $true
        runtime = $runtime
        assemblies = $assemblies
        capabilityResult = 'PASS'
        startupMode = 'Isolated'
        isolatedStartupResult = 'PASS'
    }
}

function New-ValidClientEvidenceRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Revision
    )

    [PSCustomObject][ordered]@{
        sourceRevision = $Revision
        engines = [PSCustomObject][ordered]@{
            'Desktop-5.1' = New-ValidClientEvidenceRow -EngineId 'Desktop-5.1'
            'Core-7.6.9' = New-ValidClientEvidenceRow -EngineId 'Core-7.6.9'
        }
    }
}

function Invoke-EvidenceFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object[]]$Records,

        [Parameter()]
        [string]$Revision = $sourceRevision,

        [Parameter()]
        [datetimeoffset]$Date = $asOfUtc
    )

    $fixturePath = Join-Path $tempRoot ($Name + '.json')
    $document = [PSCustomObject][ordered]@{
        schemaVersion = 1
        records = @($Records)
    }
    [System.IO.File]::WriteAllText($fixturePath, (ConvertTo-Json -InputObject $document -Depth 12), $utf8)
    Test-InstallerClientGuiReleaseEvidence -EvidencePath $fixturePath -SourceRevision $Revision -CompatibilityPath $compatibilityPath -AsOfUtc $Date
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop

try {
    $completeRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $complete = Invoke-EvidenceFixture -Name 'complete' -Records @($completeRecord)
    Assert-Condition -Condition ($complete.IsReady -and $complete.Errors.Count -eq 0 -and $complete.Record.sourceRevision -ceq $sourceRevision) -Message ('Complete evidence for both engines is accepted and tied to the release source revision. Errors: {0}' -f ($complete.Errors -join ' '))

    $placeholderRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $placeholderRecord.engines.'Desktop-5.1'.evidenceLocation = 'NOT RUN - pending client checks'
    $placeholder = Invoke-EvidenceFixture -Name 'placeholder' -Records @($placeholderRecord)
    Assert-Condition -Condition (-not $placeholder.IsReady -and ($placeholder.Errors -join ' ') -match 'Desktop-5\.1 evidenceLocation is missing or remains a placeholder') -Message 'Evidence locations that retain a NOT RUN placeholder block release readiness.'

    $oldRuntimeRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $oldRuntimeRecord.engines.'Desktop-5.1'.runtime.version = '4.0.0.0'
    $oldRuntime = Invoke-EvidenceFixture -Name 'old-desktop-runtime' -Records @($oldRuntimeRecord)
    Assert-Condition -Condition (-not $oldRuntime.IsReady -and ($oldRuntime.Errors -join ' ') -match 'Desktop-5\.1 runtime.version must be .NET Framework 4.7.2 or later') -Message 'The recorded .NET Framework version must meet the minimum even when its release number claims otherwise.'

    $partialAssemblyRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $partialAssemblyRecord.engines.'Core-7.6.9'.assemblies.'System.Windows.Forms' = 'System.Windows.Forms, Version=10.0.0.0'
    $partialAssembly = Invoke-EvidenceFixture -Name 'partial-assembly-identity' -Records @($partialAssemblyRecord)
    Assert-Condition -Condition (-not $partialAssembly.IsReady -and ($partialAssembly.Errors -join ' ') -match 'Core-7\.6\.9 assemblies.System.Windows.Forms must include the full Culture and PublicKeyToken identity fields') -Message 'A short assembly name and version without the remaining full identity fields is rejected.'

    $missingRowRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $missingRowRecord.engines = [PSCustomObject][ordered]@{
        'Desktop-5.1' = $missingRowRecord.engines.'Desktop-5.1'
    }
    $missingRow = Invoke-EvidenceFixture -Name 'missing-row' -Records @($missingRowRecord)
    Assert-Condition -Condition (-not $missingRow.IsReady -and ($missingRow.Errors -join ' ') -match 'Core-7\.6\.9.*missing') -Message 'A missing Core 7.6.9 row blocks release readiness and names the missing engine.'

    $notRunRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $notRunRecord.engines.'Desktop-5.1'.capabilityResult = 'NOT RUN'
    $notRun = Invoke-EvidenceFixture -Name 'not-run' -Records @($notRunRecord)
    Assert-Condition -Condition (-not $notRun.IsReady -and ($notRun.Errors -join ' ') -match 'Desktop-5\.1 capabilityResult must be PASS') -Message 'A NOT RUN client capability result blocks release readiness.'

    $wrongHostRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $wrongHostRecord.engines.'Desktop-5.1'.host.operatingSystem = 'Windows Server 2025'
    $wrongHostRecord.engines.'Desktop-5.1'.host.productType = 'ServerNT'
    $wrongHostRecord.engines.'Desktop-5.1'.host.installationType = 'Server'
    $wrongHost = Invoke-EvidenceFixture -Name 'wrong-host' -Records @($wrongHostRecord)
    Assert-Condition -Condition (-not $wrongHost.IsReady -and ($wrongHost.Errors -join ' ') -match 'Windows 11.*Server result cannot satisfy client evidence') -Message 'Windows Server metadata cannot satisfy a supported-client evidence row.'

    $wrongEngineRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $wrongEngineRecord.engines.'Core-7.6.9'.engine.edition = 'Desktop'
    $wrongEngineRecord.engines.'Core-7.6.9'.engine.version = '5.1.26300.9818'
    $wrongEngine = Invoke-EvidenceFixture -Name 'wrong-engine' -Records @($wrongEngineRecord)
    Assert-Condition -Condition (-not $wrongEngine.IsReady -and ($wrongEngine.Errors -join ' ') -match 'Core-7\.6\.9 engine\.edition must be Core') -Message 'A row recorded under the wrong PowerShell engine is rejected.'

    $staleRevisionRecord = New-ValidClientEvidenceRecord -Revision ('b' * 40)
    $staleRevision = Invoke-EvidenceFixture -Name 'stale-revision' -Records @($staleRevisionRecord)
    Assert-Condition -Condition (-not $staleRevision.IsReady -and ($staleRevision.Errors -join ' ') -match 'No supported-client evidence record matches release source revision') -Message 'Evidence for a different source revision cannot satisfy the release gate.'

    $failedRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $failedRecord.engines.'Desktop-5.1'.capabilityResult = 'FAIL'
    $failedRecord.engines.'Core-7.6.9'.isolatedStartupResult = 'FAIL'
    $failed = Invoke-EvidenceFixture -Name 'failed' -Records @($failedRecord)
    Assert-Condition -Condition (-not $failed.IsReady -and ($failed.Errors -join ' ') -match 'Desktop-5\.1 capabilityResult must be PASS' -and ($failed.Errors -join ' ') -match 'Core-7\.6\.9 isolatedStartupResult must be PASS') -Message 'Failed capability or isolated startup evidence blocks release readiness.'

    $expiredRecord = New-ValidClientEvidenceRecord -Revision $sourceRevision
    $expiredRecord.engines.'Desktop-5.1'.host.displayVersion = '25H2'
    $expiredRecord.engines.'Desktop-5.1'.host.build = 26200
    $expired = Invoke-EvidenceFixture -Name 'expired-release' -Records @($expiredRecord) -Date ([datetimeoffset]::Parse('2027-10-13T00:00:00Z', [Globalization.CultureInfo]::InvariantCulture))
    Assert-Condition -Condition (-not $expired.IsReady -and ($expired.Errors -join ' ') -match 'Windows 11 25H2 is outside the compatibility window') -Message 'A Windows client release past its support date cannot satisfy release readiness.'

    Write-Host ("Supported-client release evidence checks passed ({0} assertions)." -f $assertionCount) -ForegroundColor Cyan
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
