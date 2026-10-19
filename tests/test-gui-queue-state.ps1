#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$guiPath = Join-Path $repositoryRoot 'app-installer.ps1'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('app-installer-queue-state-' + [guid]::NewGuid().ToString('N'))))
$statePath = Join-Path $tempRoot 'queue-state.json'
$manifestPath = Join-Path $tempRoot 'apps-manifest.json'
$checkCount = 0

if (-not $tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary queue-state directory is outside the system temporary directory.'
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

function Write-TestQueueState {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Queue,

        [int]$SchemaVersion = 1,
        [string]$Version = '2.0.6',
        [int]$CurrentIndex = 0,
        [bool]$IsPaused = $false
    )

    $state = [PSCustomObject]@{
        SchemaVersion = $SchemaVersion
        Version = $Version
        Timestamp = [DateTime]::UtcNow.ToString('o')
        CurrentIndex = $CurrentIndex
        IsPaused = $IsPaused
        Queue = @($Queue)
    }
    $json = $state | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($script:statePath, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
}

function Write-TestLegacyQueueState {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Queue,

        [int]$CurrentIndex = 0,
        [bool]$IsPaused = $false
    )

    $state = [PSCustomObject]@{
        Version = '2.0.6'
        Timestamp = [DateTime]::UtcNow.ToString('o')
        CurrentIndex = $CurrentIndex
        IsPaused = $IsPaused
        Queue = @($Queue)
    }
    [System.IO.File]::WriteAllText($script:statePath, ($state | ConvertTo-Json -Depth 10), (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
}

function Safe-TestPath {
    param([string]$Path)
    return [System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path)
}

function Write-Log {
    param([string]$Message, [string]$Level)
    $script:logMessages += "$Level $Message"
}

$astTokens = $null
$parseErrors = $null
$guiAst = [System.Management.Automation.Language.Parser]::ParseFile($guiPath, [ref]$astTokens, [ref]$parseErrors)
if ($parseErrors) {
    throw "GUI source did not parse before queue-state tests: $($parseErrors[0].Message)"
}

$requiredFunctions = @(
    'Get-QueueStateManifest',
    'Resolve-QueueStateApplication',
    'Get-QueueStateNextIndex',
    'Set-QueueStateRecoveryFailure',
    'Save-QueueState',
    'Load-QueueState',
    'Show-RestoredQueueReview'
)
$functionAsts = @($guiAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $requiredFunctions -contains $node.Name
}, $true))
foreach ($functionName in $requiredFunctions) {
    $functionAst = $functionAsts | Where-Object { $_.Name -ceq $functionName } | Select-Object -First 1
    if (-not $functionAst) {
        throw "Queue-state function was not found: $functionName"
    }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}

$script:ScriptVersion = '2.0.6'
$script:QueueStateSchemaVersion = 1
$script:QueueStatePath = $statePath
$script:QueueStateManifestPath = $manifestPath
$script:QueueStateManifestCachePath = $null
$script:QueueStateManifestCache = $null
$script:QueueStateLoadStatus = 'NotLoaded'
$script:QueueStateRecoveryMessage = ''
$script:HasRestoredQueue = $false
$script:CurrentQueueIndex = 0
$script:IsPaused = $false
$script:IsInstalling = $false
$script:StatusLabel = $null
$script:installerCallCount = 0
$script:packageManagerCallCount = 0

$script:Applications = @(
    [PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Category = 'Test'; Description = 'Alpha test app' }
    [PSCustomObject]@{ Name = 'Beta'; ScriptName = 'beta.ps1'; WingetId = 'Tests.Beta'; Category = 'Test'; Description = 'Beta test app' }
    [PSCustomObject]@{ Name = 'Gamma'; ScriptName = 'gamma.ps1'; WingetId = 'Tests.Gamma'; Category = 'Test'; Description = 'Gamma test app' }
)

function Install-Application {
    param($App)
    $script:installerCallCount++
    return $true
}

function winget {
    $script:packageManagerCallCount++
}

$script:reviewQueueResult = $null
function Show-QueueManagementDialog {
    param([array]$Queue)
    if ($null -ne $script:reviewQueueResult) {
        return ,$script:reviewQueueResult
    }
    return ,$Queue
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $manifest = [PSCustomObject]@{
        version = 'test'
        apps = @(
            [PSCustomObject]@{ name = 'alpha'; displayName = 'Alpha'; packages = [PSCustomObject]@{ winget = 'Tests.Alpha' } }
            [PSCustomObject]@{ name = 'beta'; displayName = 'Beta'; packages = [PSCustomObject]@{ winget = 'Tests.Beta' } }
            [PSCustomObject]@{ name = 'gamma'; displayName = 'Gamma'; packages = [PSCustomObject]@{ winget = 'Tests.Gamma' } }
        )
    }
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))

    $guiContent = [System.IO.File]::ReadAllText($guiPath)
    $startupStart = $guiContent.IndexOf('# Initial load - detect installed applications', [System.StringComparison]::Ordinal)
    $startupEnd = $guiContent.IndexOf('# Display additional marketing information', $startupStart, [System.StringComparison]::Ordinal)
    $startupBlock = $guiContent.Substring($startupStart, $startupEnd - $startupStart)
    Assert-Condition -Condition ($startupBlock.Contains('Load-QueueState') -and -not $startupBlock.Contains('Install-Application') -and -not $startupBlock.Contains('Install-SelectedApplications')) -Message 'Startup loads saved state without invoking an installer'

    $reviewAst = $functionAsts | Where-Object { $_.Name -ceq 'Show-RestoredQueueReview' } | Select-Object -First 1
    Assert-Condition -Condition (-not $reviewAst.Extent.Text.Contains('Install-Application') -and -not $reviewAst.Extent.Text.Contains('Install-SelectedApplications') -and -not $reviewAst.Extent.Text.Contains('winget')) -Message 'The startup review helper contains no package execution path'
    $installClickStart = $guiContent.IndexOf('$installButton.Add_Click({', [System.StringComparison]::Ordinal)
    $installClickEnd = $guiContent.IndexOf('})', $installClickStart, [System.StringComparison]::Ordinal)
    $installClickBlock = $guiContent.Substring($installClickStart, $installClickEnd - $installClickStart)
    Assert-Condition -Condition ($installClickBlock.Contains('Install-SelectedApplications')) -Message 'Installation remains attached to the explicit Install Selected click'

    $script:InstallationQueue = @(
        [PSCustomObject]@{ Name = 'Beta'; ScriptName = 'beta.ps1'; WingetId = 'Tests.Beta'; Category = 'Test'; Description = 'Beta test app'; QueueStatus = 'Processed' }
        [PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Category = 'Test'; Description = 'Alpha test app'; QueueStatus = 'InProgress' }
        [PSCustomObject]@{ Name = 'Gamma'; ScriptName = 'gamma.ps1'; WingetId = 'Tests.Gamma'; Category = 'Test'; Description = 'Gamma test app'; QueueStatus = 'Pending' }
    )
    $script:CurrentQueueIndex = 1
    $script:IsPaused = $false
    Assert-Condition -Condition (Save-QueueState) -Message 'Queue save writes a validated schema-versioned state file'
    $savedText = [System.IO.File]::ReadAllText($statePath)
    $savedObject = $savedText | ConvertFrom-Json
    Assert-Condition -Condition ($savedObject.SchemaVersion -eq 1 -and $savedObject.Queue.Count -eq 3) -Message 'Saved state contains the schema version and each queue item'

    $script:InstallationQueue = @()
    $script:CurrentQueueIndex = 0
    $script:IsPaused = $false
    $script:QueueStateManifestCachePath = $null
    $script:QueueStateManifestCache = $null
    $validRestore = Load-QueueState
    if (-not $validRestore) {
        Write-Host "[DEBUG] $($script:logMessages -join ' | ')" -ForegroundColor Yellow
    }
    Assert-Condition -Condition $validRestore -Message 'A valid saved queue restores after a simulated restart'
    $restoredNames = @($script:InstallationQueue | ForEach-Object { $_.Name })
    $restoredStatuses = @($script:InstallationQueue | ForEach-Object { $_.QueueStatus })
    Assert-Condition -Condition (($restoredNames -join ',') -ceq 'Beta,Alpha,Gamma') -Message 'Restore preserves original queue order'
    Assert-Condition -Condition (($restoredStatuses -join ',') -ceq 'Processed,InProgress,Pending' -and $script:CurrentQueueIndex -eq 1) -Message 'Restore preserves valid per-item progress and current index'

    $script:reviewQueueResult = @($script:InstallationQueue)
    Assert-Condition -Condition (Show-RestoredQueueReview) -Message 'The recovered queue can be handed to the existing review dialog'
    Assert-Condition -Condition ($script:HasRestoredQueue -and $script:InstallationQueue.Count -eq 3) -Message 'Reviewed queue stays pending for a later Install click'
    Assert-Condition -Condition ($script:installerCallCount -eq 0 -and $script:packageManagerCallCount -eq 0) -Message 'Save, restart, restore, and review execute no installer or package-manager command'

    $legacyQueue = @(
        [PSCustomObject]@{ Name = 'Beta'; ScriptName = 'beta.ps1'; WingetId = 'Tests.Beta'; Category = 'Test'; Description = 'Beta app' }
        [PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Category = 'Test'; Description = 'Alpha app' }
        [PSCustomObject]@{ Name = 'Gamma'; ScriptName = 'gamma.ps1'; WingetId = 'Tests.Gamma'; Category = 'Test'; Description = 'Gamma app' }
    )
    Write-TestLegacyQueueState -Queue $legacyQueue -CurrentIndex 1 -IsPaused $true
    $legacyText = [System.IO.File]::ReadAllText($statePath)
    $legacyRestore = Load-QueueState
    Assert-Condition -Condition ($legacyRestore -and $script:QueueStateRecoveryMessage.Contains('Older saved queue')) -Message 'The known previous queue schema is recovered when its installer version matches'
    Assert-Condition -Condition ((@($script:InstallationQueue | ForEach-Object { $_.QueueStatus }) -join ',') -ceq 'Processed,Paused,Pending' -and $script:CurrentQueueIndex -eq 1 -and $script:IsPaused) -Message 'Legacy queue progress is derived from its saved index and pause flag'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $legacyText) -Message 'Legacy state is not rewritten before the user reviews it'
    $script:reviewQueueResult = $null
    $legacyReview = Show-RestoredQueueReview
    $migratedState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-Condition -Condition ($legacyReview -and $migratedState.SchemaVersion -eq 1) -Message 'A reviewed legacy queue is saved using the current schema'

    $script:InstallationQueue = @(
        [PSCustomObject]@{ Name = 'Beta'; ScriptName = 'beta.ps1'; WingetId = 'Tests.Beta'; Category = 'Test'; Description = 'Beta test app'; QueueStatus = 'Processed' }
        [PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Category = 'Test'; Description = 'Alpha test app'; QueueStatus = 'InProgress' }
        [PSCustomObject]@{ Name = 'Gamma'; ScriptName = 'gamma.ps1'; WingetId = 'Tests.Gamma'; Category = 'Test'; Description = 'Gamma test app'; QueueStatus = 'Pending' }
    )
    $script:CurrentQueueIndex = 1
    $script:IsPaused = $true
    $pausedSave = Save-QueueState
    if (-not $pausedSave) {
        Write-Host "[DEBUG] $($script:logMessages -join ' | ')" -ForegroundColor Yellow
    }
    Assert-Condition -Condition $pausedSave -Message 'An active item is saved as paused when pause state is set'
    $pausedState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-Condition -Condition ($pausedState.IsPaused -and $pausedState.Queue[1].Status -ceq 'Paused') -Message 'Saved pause state is reflected on the active queue item'
    $script:InstallationQueue = @()
    $script:CurrentQueueIndex = 0
    $script:IsPaused = $false
    $pausedRestore = Load-QueueState
    Assert-Condition -Condition ($pausedRestore -and $script:IsPaused -and $script:InstallationQueue[1].QueueStatus -ceq 'Paused') -Message 'Pause state is retained across restart'

    $backupPath = "$statePath.bak"
    Move-Item -LiteralPath $statePath -Destination $backupPath
    $backupText = [System.IO.File]::ReadAllText($backupPath)
    $script:InstallationQueue = @()
    $script:CurrentQueueIndex = 0
    $script:IsPaused = $false
    $backupRestore = Load-QueueState
    Assert-Condition -Condition ($backupRestore -and $script:QueueStateRecoveryMessage.Contains('backup')) -Message 'A complete replacement backup recovers when the primary file is absent'
    Assert-Condition -Condition (-not [System.IO.File]::Exists($statePath) -and [System.IO.File]::ReadAllText($backupPath) -ceq $backupText) -Message 'Backup recovery reads without deleting or rewriting the backup'
    $script:reviewQueueResult = $null
    $backupReview = Show-RestoredQueueReview
    Assert-Condition -Condition ($backupReview -and [System.IO.File]::Exists($statePath) -and -not [System.IO.File]::Exists($backupPath)) -Message 'A confirmed review commits recovered backup state back to the primary path'

    Remove-Item -LiteralPath $statePath -Force
    $script:InstallationQueue = @([PSCustomObject]@{ Name = 'Gamma'; ScriptName = 'gamma.ps1'; WingetId = 'Tests.Gamma'; Category = 'Test'; Description = 'Gamma test app'; QueueStatus = 'Pending' })
    $script:CurrentQueueIndex = 0
    $script:IsPaused = $false
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:QueueStateLoadStatus -eq 'Missing' -and $script:InstallationQueue.Count -eq 0 -and $script:QueueStateRecoveryMessage.Length -gt 0) -Message 'Missing state keeps an empty queue and sets a concise recovery status'

    [System.IO.File]::WriteAllText($statePath, '{', (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
    $corruptText = [System.IO.File]::ReadAllText($statePath)
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'Corrupt JSON falls back to an empty queue'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $corruptText -and $script:QueueStateRecoveryMessage.Length -gt 0) -Message 'Corrupt state remains untouched and produces a recovery message'

    $partialText = '{"SchemaVersion":1,"Version":"2.0.6","Queue":['
    [System.IO.File]::WriteAllText($statePath, $partialText, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'A partial JSON write is rejected safely'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $partialText) -Message 'Partial state is not deleted or rewritten during recovery'

    $validPending = @(
        [PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Status = 'Pending' }
    )
    Write-TestQueueState -Queue $validPending -Version '0.0.0' -CurrentIndex 0
    $staleText = [System.IO.File]::ReadAllText($statePath)
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'A stale installer version is rejected'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $staleText) -Message 'Stale state is preserved for recovery or inspection'

    Write-TestQueueState -Queue @([PSCustomObject]@{ Name = 'Unknown'; ScriptName = 'unknown.ps1'; WingetId = 'Tests.Unknown'; Status = 'Pending' })
    $unknownText = [System.IO.File]::ReadAllText($statePath)
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'An unknown app identity is rejected'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $unknownText) -Message 'Unknown app state remains untouched'

    $originalAlphaId = $script:Applications[0].WingetId
    $script:Applications[0].WingetId = 'Tests.NotInManifest'
    Write-TestQueueState -Queue @([PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.NotInManifest'; Status = 'Pending' })
    $manifestMismatchText = [System.IO.File]::ReadAllText($statePath)
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'An app ID absent from the current manifest is rejected'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $manifestMismatchText) -Message 'Manifest-mismatched state remains untouched'
    $script:Applications[0].WingetId = $originalAlphaId

    Write-TestQueueState -Queue @([PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; Status = 'Pending' })
    $missingIdText = [System.IO.File]::ReadAllText($statePath)
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'A queue item missing its app ID is rejected'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $missingIdText) -Message 'Queue state with a missing app ID remains untouched'

    Write-TestQueueState -Queue @(
        [PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Status = 'Pending' }
        [PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Status = 'Pending' }
    )
    $duplicateText = [System.IO.File]::ReadAllText($statePath)
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'Duplicate app entries reject the whole queue'
    Assert-Condition -Condition ([System.IO.File]::ReadAllText($statePath) -ceq $duplicateText) -Message 'Duplicate queue state remains untouched'

    Write-TestQueueState -Queue @([PSCustomObject]@{ Name = 'Alpha'; ScriptName = 'alpha.ps1'; WingetId = 'Tests.Alpha'; Status = 'Succeeded' })
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'An unsupported per-item status is rejected'

    Write-TestQueueState -Queue $validPending -SchemaVersion 99
    Assert-Condition -Condition (-not (Load-QueueState) -and $script:InstallationQueue.Count -eq 0) -Message 'An unsupported schema version is rejected'

    Assert-Condition -Condition ($script:installerCallCount -eq 0 -and $script:packageManagerCallCount -eq 0) -Message 'Invalid recovery cases execute no installer or package-manager command'
    Write-Host "Completed $checkCount GUI queue-state checks." -ForegroundColor Cyan
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
