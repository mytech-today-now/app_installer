Set-StrictMode -Version Latest

function Get-ReleaseProtectionValue {
    param(
        [AllowNull()]
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

    return ,$property.Value
}

function Test-ReleaseProtectionArray {
    param(
        [AllowNull()]
        [object]$Value
    )

    return ($Value -is [System.Array])
}

function Add-ReleaseProtectionTextError {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors,

        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Field
    )

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        [void]$Errors.Add(('{0} is missing or empty.' -f $Field))
    }
}

function Test-InstallerReleaseProtectionReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VerificationPath,

        [Parameter(Mandatory = $true)]
        [string]$EvidenceRoot,

        [Parameter()]
        [string]$ExpectedRepository = 'mytech-today-now/app_installer'
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $record = $null

    if (-not (Test-Path -LiteralPath $VerificationPath -PathType Leaf)) {
        [void]$errors.Add(('Verification record is missing: {0}.' -f $VerificationPath))
        return [PSCustomObject]@{
            IsReady = $false
            Record = $null
            Errors = $errors.ToArray()
            ObservedAtUtc = $null
            EvidencePath = $null
        }
    }

    try {
        $record = Get-Content -LiteralPath $VerificationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        [void]$errors.Add(('Verification record is not valid JSON: {0}' -f $_.Exception.Message))
        return [PSCustomObject]@{
            IsReady = $false
            Record = $null
            Errors = $errors.ToArray()
            ObservedAtUtc = $null
            EvidencePath = $null
        }
    }

    if ($null -eq $record) {
        [void]$errors.Add('Verification record must contain a JSON object.')
        return [PSCustomObject]@{
            IsReady = $false
            Record = $null
            Errors = $errors.ToArray()
            ObservedAtUtc = $null
            EvidencePath = $null
        }
    }

    $schemaVersion = Get-ReleaseProtectionValue -InputObject $record -Name 'schemaVersion'
    $hasSupportedSchemaVersion = ($schemaVersion -is [int] -or $schemaVersion -is [long]) -and $schemaVersion -eq 1
    if (-not $hasSupportedSchemaVersion) {
        [void]$errors.Add('schemaVersion must be 1.')
    }

    $repository = Get-ReleaseProtectionValue -InputObject $record -Name 'repository'
    if ($repository -isnot [string] -or $repository -cne $ExpectedRepository) {
        [void]$errors.Add(('repository must exactly match {0}.' -f $ExpectedRepository))
    }

    $status = Get-ReleaseProtectionValue -InputObject $record -Name 'status'
    if ($status -isnot [string] -or $status -cne 'VERIFIED') {
        [void]$errors.Add('Remote settings status must be VERIFIED; NOT VERIFIED blocks release readiness.')
    }

    $observedAtUtc = $null
    $observedAtText = Get-ReleaseProtectionValue -InputObject $record -Name 'observedAtUtc'
    $parsedObservedAt = [DateTimeOffset]::MinValue
    $utcTimestampFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    $hasValidObservedAt = $false
    if ($observedAtText -is [datetime] -and $observedAtText.Kind -eq [DateTimeKind]::Utc) {
        $parsedObservedAt = [DateTimeOffset]::new($observedAtText)
        $hasValidObservedAt = $true
    }
    elseif ($observedAtText -is [DateTimeOffset] -and $observedAtText.Offset -eq [TimeSpan]::Zero) {
        $parsedObservedAt = $observedAtText
        $hasValidObservedAt = $true
    }
    elseif ($observedAtText -is [string] -and $observedAtText -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') {
        $hasValidObservedAt = [DateTimeOffset]::TryParseExact(
            $observedAtText,
            $utcTimestampFormat,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$parsedObservedAt
        )
    }
    if (-not $hasValidObservedAt) {
        [void]$errors.Add('observedAtUtc must be a valid ISO-8601 UTC timestamp ending in Z.')
    }
    else {
        $observedAtUtc = $parsedObservedAt.ToUniversalTime()
        $nowUtc = [DateTimeOffset]::UtcNow
        if ($observedAtUtc -gt $nowUtc) {
            [void]$errors.Add('Remote settings observation timestamp is in the future.')
        }
        elseif (($nowUtc - $observedAtUtc) -gt [TimeSpan]::FromDays(30)) {
            [void]$errors.Add('Remote settings observation is stale; the maximum age is 30 days.')
        }
    }

    $evidence = Get-ReleaseProtectionValue -InputObject $record -Name 'evidence'
    $evidenceLocation = Get-ReleaseProtectionValue -InputObject $evidence -Name 'location'
    $evidenceHash = Get-ReleaseProtectionValue -InputObject $evidence -Name 'sha256'
    $resolvedEvidencePath = $null
    if ($evidenceLocation -isnot [string] -or [string]::IsNullOrWhiteSpace($evidenceLocation)) {
        [void]$errors.Add('evidence.location must identify a durable evidence file relative to the evidence root.')
    }
    elseif ([System.IO.Path]::IsPathRooted($evidenceLocation)) {
        [void]$errors.Add('evidence.location must be relative to the evidence root.')
    }
    elseif ($evidenceHash -isnot [string] -or $evidenceHash -notmatch '^[A-Fa-f0-9]{64}$') {
        [void]$errors.Add('evidence.sha256 must contain the SHA-256 digest of the evidence file.')
    }
    else {
        try {
            $rootPath = [System.IO.Path]::GetFullPath($EvidenceRoot)
            $rootPrefix = $rootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            $resolvedEvidencePath = [System.IO.Path]::GetFullPath((Join-Path -Path $rootPath -ChildPath $evidenceLocation))
            if (-not $resolvedEvidencePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$errors.Add('evidence.location resolves outside the evidence root.')
                $resolvedEvidencePath = $null
            }
            elseif (-not (Test-Path -LiteralPath $resolvedEvidencePath -PathType Leaf)) {
                [void]$errors.Add(('Durable evidence file is missing: {0}.' -f $evidenceLocation))
                $resolvedEvidencePath = $null
            }
            else {
                $actualHash = (Get-FileHash -LiteralPath $resolvedEvidencePath -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($actualHash -ine $evidenceHash) {
                    [void]$errors.Add('evidence.sha256 does not match the durable evidence file.')
                }
            }
        }
        catch {
            [void]$errors.Add(('Evidence location could not be validated: {0}' -f $_.Exception.Message))
            $resolvedEvidencePath = $null
        }
    }

    $settings = Get-ReleaseProtectionValue -InputObject $record -Name 'settings'
    $rulesets = Get-ReleaseProtectionValue -InputObject $settings -Name 'rulesets'
    $activeTagRulesetCount = 0
    if (-not (Test-ReleaseProtectionArray -Value $rulesets) -or $rulesets.Count -eq 0) {
        [void]$errors.Add('settings.rulesets must record every applicable ruleset and at least one active tag ruleset.')
    }
    else {
        for ($index = 0; $index -lt $rulesets.Count; $index++) {
            $ruleset = $rulesets[$index]
            $prefix = 'settings.rulesets[{0}]' -f $index
            foreach ($field in @('id', 'name', 'source', 'target', 'enforcement')) {
                $value = Get-ReleaseProtectionValue -InputObject $ruleset -Name $field
                Add-ReleaseProtectionTextError -Errors $errors -Value $value -Field ('{0}.{1}' -f $prefix, $field)
            }

            $target = Get-ReleaseProtectionValue -InputObject $ruleset -Name 'target'
            $enforcement = Get-ReleaseProtectionValue -InputObject $ruleset -Name 'enforcement'
            if ($target -is [string] -and $target -ceq 'tag' -and $enforcement -is [string] -and $enforcement -ceq 'active') {
                $activeTagRulesetCount++
            }

            foreach ($patternField in @('includePatterns', 'excludePatterns')) {
                $patterns = Get-ReleaseProtectionValue -InputObject $ruleset -Name $patternField
                if (-not (Test-ReleaseProtectionArray -Value $patterns)) {
                    [void]$errors.Add(('{0}.{1} must be an observed array, including an empty array when none apply.' -f $prefix, $patternField))
                }
                elseif ($patternField -ceq 'includePatterns' -and $patterns.Count -eq 0) {
                    [void]$errors.Add(('{0}.includePatterns must include the exact tag pattern.' -f $prefix))
                }
                else {
                    for ($patternIndex = 0; $patternIndex -lt $patterns.Count; $patternIndex++) {
                        if ($patterns[$patternIndex] -isnot [string] -or [string]::IsNullOrWhiteSpace($patterns[$patternIndex])) {
                            [void]$errors.Add(('{0}.{1}[{2}] is missing or empty.' -f $prefix, $patternField, $patternIndex))
                        }
                    }
                }
            }
        }

        if ($activeTagRulesetCount -eq 0) {
            [void]$errors.Add('At least one applicable tag ruleset must have active enforcement.')
        }
    }

    $mutationControls = Get-ReleaseProtectionValue -InputObject $settings -Name 'tagMutationControls'
    if ($null -eq $mutationControls) {
        [void]$errors.Add('settings.tagMutationControls must record tag creation, update, and deletion controls.')
    }
    else {
        foreach ($field in @('creationRestricted', 'updatesRestricted', 'deletionsRestricted')) {
            $value = Get-ReleaseProtectionValue -InputObject $mutationControls -Name $field
            if ($value -isnot [bool]) {
                [void]$errors.Add(('settings.tagMutationControls.{0} must be observed as true or false.' -f $field))
            }
            elseif ($field -ne 'creationRestricted' -and -not $value) {
                [void]$errors.Add(('settings.tagMutationControls.{0} must be true to block ordinary tag mutation.' -f $field))
            }
        }

        $mutationScope = Get-ReleaseProtectionValue -InputObject $mutationControls -Name 'scope'
        Add-ReleaseProtectionTextError -Errors $errors -Value $mutationScope -Field 'settings.tagMutationControls.scope'
    }

    $tagApproval = Get-ReleaseProtectionValue -InputObject $settings -Name 'tagApprovalControl'
    if ($null -eq $tagApproval) {
        [void]$errors.Add('settings.tagApprovalControl must record the tag approval control or an explicit N/A determination.')
    }
    else {
        $approvalStatus = Get-ReleaseProtectionValue -InputObject $tagApproval -Name 'status'
        if ($approvalStatus -isnot [string] -or $approvalStatus -cnotin @('configured', 'not-applicable')) {
            [void]$errors.Add('settings.tagApprovalControl.status must be configured or not-applicable.')
        }

        $approvalDetails = Get-ReleaseProtectionValue -InputObject $tagApproval -Name 'details'
        Add-ReleaseProtectionTextError -Errors $errors -Value $approvalDetails -Field 'settings.tagApprovalControl.details'
    }

    $defaultBranchApproval = Get-ReleaseProtectionValue -InputObject $settings -Name 'defaultBranchApproval'
    if ($null -eq $defaultBranchApproval) {
        [void]$errors.Add('settings.defaultBranchApproval must record the default-branch review controls for release-workflow changes.')
    }
    else {
        $branch = Get-ReleaseProtectionValue -InputObject $defaultBranchApproval -Name 'branch'
        Add-ReleaseProtectionTextError -Errors $errors -Value $branch -Field 'settings.defaultBranchApproval.branch'

        $requiredApprovalsValue = Get-ReleaseProtectionValue -InputObject $defaultBranchApproval -Name 'requiredApprovals'
        $requiredApprovals = -1
        $hasRequiredApprovals = ($requiredApprovalsValue -is [int] -or $requiredApprovalsValue -is [long]) -and $requiredApprovalsValue -ge 0
        if ($hasRequiredApprovals) {
            $requiredApprovals = [int]$requiredApprovalsValue
        }
        if (-not $hasRequiredApprovals) {
            [void]$errors.Add('settings.defaultBranchApproval.requiredApprovals must be an observed non-negative integer.')
        }

        $requiredReviewers = Get-ReleaseProtectionValue -InputObject $defaultBranchApproval -Name 'requiredReviewers'
        if (-not (Test-ReleaseProtectionArray -Value $requiredReviewers)) {
            [void]$errors.Add('settings.defaultBranchApproval.requiredReviewers must be an observed array.')
        }
        else {
            for ($reviewerIndex = 0; $reviewerIndex -lt $requiredReviewers.Count; $reviewerIndex++) {
                if ($requiredReviewers[$reviewerIndex] -isnot [string] -or [string]::IsNullOrWhiteSpace($requiredReviewers[$reviewerIndex])) {
                    [void]$errors.Add(('settings.defaultBranchApproval.requiredReviewers[{0}] is missing or empty.' -f $reviewerIndex))
                }
            }
        }

        $codeOwnerReviewRequired = Get-ReleaseProtectionValue -InputObject $defaultBranchApproval -Name 'codeOwnerReviewRequired'
        if ($codeOwnerReviewRequired -isnot [bool]) {
            [void]$errors.Add('settings.defaultBranchApproval.codeOwnerReviewRequired must be observed as true or false.')
        }
        elseif ($hasRequiredApprovals -and $requiredApprovals -eq 0 -and -not $codeOwnerReviewRequired) {
            [void]$errors.Add('The default branch must have at least one approval control for release-workflow changes.')
        }
    }

    $bypassActors = Get-ReleaseProtectionValue -InputObject $settings -Name 'bypassActors'
    if (-not (Test-ReleaseProtectionArray -Value $bypassActors)) {
        [void]$errors.Add('settings.bypassActors must record every bypass actor and mode; use an empty array when none exist.')
    }
    else {
        for ($actorIndex = 0; $actorIndex -lt $bypassActors.Count; $actorIndex++) {
            $actor = $bypassActors[$actorIndex]
            foreach ($field in @('identity', 'mode')) {
                $value = Get-ReleaseProtectionValue -InputObject $actor -Name $field
                Add-ReleaseProtectionTextError -Errors $errors -Value $value -Field ('settings.bypassActors[{0}].{1}' -f $actorIndex, $field)
            }
        }
    }

    $actionsPermissions = Get-ReleaseProtectionValue -InputObject $settings -Name 'actionsPermissions'
    if ($null -eq $actionsPermissions) {
        [void]$errors.Add('settings.actionsPermissions must record effective repository and organization Actions permission settings.')
    }
    else {
        $defaultPermission = Get-ReleaseProtectionValue -InputObject $actionsPermissions -Name 'repositoryDefaultGITHUBTokenPermission'
        if ($defaultPermission -isnot [string] -or $defaultPermission -cnotin @('read-only', 'read-write')) {
            [void]$errors.Add('settings.actionsPermissions.repositoryDefaultGITHUBTokenPermission must be read-only or read-write.')
        }

        $canApprovePullRequests = Get-ReleaseProtectionValue -InputObject $actionsPermissions -Name 'actionsCanApprovePullRequests'
        if ($canApprovePullRequests -isnot [bool]) {
            [void]$errors.Add('settings.actionsPermissions.actionsCanApprovePullRequests must be observed as true or false.')
        }

        $organizationPolicy = Get-ReleaseProtectionValue -InputObject $actionsPermissions -Name 'organizationPolicy'
        if ($null -eq $organizationPolicy) {
            [void]$errors.Add('settings.actionsPermissions.organizationPolicy must record the inherited organization or enterprise policy.')
        }
        else {
            $organizationApplies = Get-ReleaseProtectionValue -InputObject $organizationPolicy -Name 'applies'
            if ($organizationApplies -isnot [bool]) {
                [void]$errors.Add('settings.actionsPermissions.organizationPolicy.applies must be observed as true or false.')
            }

            $organizationSummary = Get-ReleaseProtectionValue -InputObject $organizationPolicy -Name 'summary'
            Add-ReleaseProtectionTextError -Errors $errors -Value $organizationSummary -Field 'settings.actionsPermissions.organizationPolicy.summary'
        }

        $additionalScopes = Get-ReleaseProtectionValue -InputObject $actionsPermissions -Name 'additionalEffectiveTokenScopes'
        if (-not (Test-ReleaseProtectionArray -Value $additionalScopes)) {
            [void]$errors.Add('settings.actionsPermissions.additionalEffectiveTokenScopes must be an observed array.')
        }
        else {
            for ($scopeIndex = 0; $scopeIndex -lt $additionalScopes.Count; $scopeIndex++) {
                if ($additionalScopes[$scopeIndex] -isnot [string] -or [string]::IsNullOrWhiteSpace($additionalScopes[$scopeIndex])) {
                    [void]$errors.Add(('settings.actionsPermissions.additionalEffectiveTokenScopes[{0}] is missing or empty.' -f $scopeIndex))
                }
            }
        }
    }

    return [PSCustomObject]@{
        IsReady = ($errors.Count -eq 0)
        Record = $record
        Errors = $errors.ToArray()
        ObservedAtUtc = $observedAtUtc
        EvidencePath = $resolvedEvidencePath
    }
}

Export-ModuleMember -Function Test-InstallerReleaseProtectionReadiness
