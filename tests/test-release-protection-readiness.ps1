#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'modules\InstallerReleaseProtectionReadiness.psm1'
Import-Module -Name $modulePath -Force -DisableNameChecking
$script:assertionCount = 0
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('app-installer-release-protection-' + [guid]::NewGuid().ToString('N'))

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) {
        throw ('FAIL: {0}' -f $Message)
    }
}

function New-ValidReadinessRecord {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ObservedAtUtc,

        [Parameter(Mandatory = $true)]
        [string]$EvidenceHash
    )

    return [PSCustomObject]@{
        schemaVersion = 1
        repository = 'mytech-today-now/app_installer'
        status = 'VERIFIED'
        observedAtUtc = $ObservedAtUtc
        evidence = [PSCustomObject]@{
            location = 'observations\remote-settings.json'
            sha256 = $EvidenceHash
        }
        settings = [PSCustomObject]@{
            rulesets = @(
                [PSCustomObject]@{
                    id = '123456'
                    name = 'Version tags'
                    source = 'mytech-today-now/app_installer'
                    target = 'tag'
                    enforcement = 'active'
                    includePatterns = @('refs/tags/v*')
                    excludePatterns = @()
                }
            )
            tagMutationControls = [PSCustomObject]@{
                creationRestricted = $false
                updatesRestricted = $true
                deletionsRestricted = $true
                scope = 'Ruleset 123456 for refs/tags/v*'
            }
            tagApprovalControl = [PSCustomObject]@{
                status = 'not-applicable'
                details = 'N/A for tag rulesets; default-branch review controls workflow changes.'
            }
            defaultBranchApproval = [PSCustomObject]@{
                branch = 'main'
                requiredApprovals = 1
                requiredReviewers = @('release-reviewers')
                codeOwnerReviewRequired = $true
            }
            bypassActors = @()
            actionsPermissions = [PSCustomObject]@{
                repositoryDefaultGITHUBTokenPermission = 'read-only'
                actionsCanApprovePullRequests = $false
                organizationPolicy = [PSCustomObject]@{
                    applies = $false
                    summary = 'No organization or enterprise override applies; repository settings control.'
                }
                additionalEffectiveTokenScopes = @()
            }
        }
    }
}

function Invoke-ReadinessFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object]$Record
    )

    $recordPath = Join-Path $tempRoot ($Name + '.json')
    $json = ConvertTo-Json -InputObject $Record -Depth 20
    Set-Content -LiteralPath $recordPath -Value $json -Encoding UTF8
    return Test-InstallerReleaseProtectionReadiness -VerificationPath $recordPath -EvidenceRoot $tempRoot
}

try {
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'observations') -Force | Out-Null
    $evidencePath = Join-Path $tempRoot 'observations\remote-settings.json'
    Set-Content -LiteralPath $evidencePath -Value '{"fixture":"synthetic remote settings observation"}' -Encoding UTF8
    $evidenceHash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash
    $currentUtc = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)

    $completeRecord = New-ValidReadinessRecord -ObservedAtUtc $currentUtc -EvidenceHash $evidenceHash
    $complete = Invoke-ReadinessFixture -Name 'complete' -Record $completeRecord
    Assert-Condition -Condition ($complete.IsReady -and $complete.Errors.Count -eq 0 -and $complete.EvidencePath -eq $evidencePath) -Message ('A complete, current, evidence-backed record passes. Errors: {0}; evidence path: {1}' -f ($complete.Errors -join ' | '), $complete.EvidencePath)

    $incompleteRecord = New-ValidReadinessRecord -ObservedAtUtc $currentUtc -EvidenceHash $evidenceHash
    $incompleteRecord.settings.actionsPermissions.repositoryDefaultGITHUBTokenPermission = $null
    $incomplete = Invoke-ReadinessFixture -Name 'incomplete' -Record $incompleteRecord
    Assert-Condition -Condition (-not $incomplete.IsReady -and ($incomplete.Errors -join ' ') -match 'repositoryDefaultGITHUBTokenPermission') -Message 'An incomplete required Actions setting fails with a field-specific error.'

    $invalidSchemaRecord = New-ValidReadinessRecord -ObservedAtUtc $currentUtc -EvidenceHash $evidenceHash
    $invalidSchemaRecord.schemaVersion = '1'
    $invalidSchema = Invoke-ReadinessFixture -Name 'invalid-schema' -Record $invalidSchemaRecord
    Assert-Condition -Condition (-not $invalidSchema.IsReady -and ($invalidSchema.Errors -join ' ') -match 'schemaVersion must be 1') -Message 'A string or unsupported schema version fails.'

    $malformedStatusRecord = New-ValidReadinessRecord -ObservedAtUtc $currentUtc -EvidenceHash $evidenceHash
    $malformedStatusRecord.status = @()
    $malformedStatus = Invoke-ReadinessFixture -Name 'malformed-status' -Record $malformedStatusRecord
    Assert-Condition -Condition (-not $malformedStatus.IsReady -and ($malformedStatus.Errors -join ' ') -match 'status must be VERIFIED') -Message 'A non-string readiness status fails.'

    $weakMutationRecord = New-ValidReadinessRecord -ObservedAtUtc $currentUtc -EvidenceHash $evidenceHash
    $weakMutationRecord.settings.tagMutationControls.updatesRestricted = $false
    $weakMutationRecord.settings.tagMutationControls.deletionsRestricted = $false
    $weakMutation = Invoke-ReadinessFixture -Name 'weak-tag-mutation' -Record $weakMutationRecord
    Assert-Condition -Condition (-not $weakMutation.IsReady -and ($weakMutation.Errors -join ' ') -match 'updatesRestricted must be true' -and ($weakMutation.Errors -join ' ') -match 'deletionsRestricted must be true') -Message 'Tag update and deletion controls must both block ordinary mutation.'

    $staleRecord = New-ValidReadinessRecord -ObservedAtUtc '2000-01-01T00:00:00Z' -EvidenceHash $evidenceHash
    $stale = Invoke-ReadinessFixture -Name 'stale' -Record $staleRecord
    Assert-Condition -Condition (-not $stale.IsReady -and ($stale.Errors -join ' ') -match 'stale; the maximum age is 30 days') -Message 'A record older than 30 days fails.'

    $notVerifiedRecord = New-ValidReadinessRecord -ObservedAtUtc $currentUtc -EvidenceHash $evidenceHash
    $notVerifiedRecord.status = 'NOT VERIFIED'
    $notVerifiedFixture = Invoke-ReadinessFixture -Name 'not-verified' -Record $notVerifiedRecord
    Assert-Condition -Condition (-not $notVerifiedFixture.IsReady -and ($notVerifiedFixture.Errors -join ' ') -match 'NOT VERIFIED blocks release readiness') -Message 'A complete-shaped record with NOT VERIFIED status fails.'

    $notVerifiedPath = Join-Path $repositoryRoot 'RELEASE_PROTECTION_VERIFICATION.json'
    $notVerified = Test-InstallerReleaseProtectionReadiness -VerificationPath $notVerifiedPath -EvidenceRoot $repositoryRoot
    Assert-Condition -Condition (-not $notVerified.IsReady -and ($notVerified.Errors -join ' ') -match 'status must be VERIFIED' -and ($notVerified.Errors -join ' ') -match 'settings.rulesets') -Message 'The current NOT VERIFIED record and its unobserved settings block readiness.'

    $missingTimestampRecord = New-ValidReadinessRecord -ObservedAtUtc '' -EvidenceHash $evidenceHash
    $missingTimestamp = Invoke-ReadinessFixture -Name 'missing-timestamp' -Record $missingTimestampRecord
    Assert-Condition -Condition (-not $missingTimestamp.IsReady -and ($missingTimestamp.Errors -join ' ') -match 'observedAtUtc') -Message 'A missing UTC observation timestamp fails.'

    $badEvidenceRecord = New-ValidReadinessRecord -ObservedAtUtc $currentUtc -EvidenceHash ('0' * 64)
    $badEvidence = Invoke-ReadinessFixture -Name 'bad-evidence-digest' -Record $badEvidenceRecord
    Assert-Condition -Condition (-not $badEvidence.IsReady -and ($badEvidence.Errors -join ' ') -match 'does not match the durable evidence file') -Message 'An evidence digest that does not match the file fails.'

    Write-Host ('Release protection readiness checks passed ({0} assertions).' -f $script:assertionCount) -ForegroundColor Cyan
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
