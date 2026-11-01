# Pin the reviewed UTF-8 guide after normalizing CRLF and CR to LF.
$script:ApprovedInstructionContentSha256 = '2eab59fe032ebae3d1a1fafa6490cdce232cf8b32d9e4b078f759ec3509cab65'
$script:MaximumInstructionContentLength = 524288
$script:SafeInstructionCss = @'
body { font-family: Segoe UI, Arial, sans-serif; line-height: 1.55; margin: 20px; color: #252525; background: #ffffff; }
h1, h2, h3, h4 { color: #17365d; }
a { color: #005a9e; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; }
code, pre { font-family: Consolas, monospace; }
table { border-collapse: collapse; max-width: 100%; }
th, td { border: 1px solid #808080; padding: 6px; text-align: left; }
'@

function Get-AllowedExternalNavigationUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -match '[\x00-\x20\x7f]') {
        return $null
    }

    try {
        $decodedUrl = [System.Uri]::UnescapeDataString($Url)
    }
    catch {
        return $null
    }
    if ($decodedUrl -match '[\x00-\x20\x7f]') {
        return $null
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) {
        return $null
    }

    if ($uri.Scheme -ieq 'https') {
        if ([string]::IsNullOrWhiteSpace($uri.Host) -or -not [string]::IsNullOrEmpty($uri.UserInfo)) {
            return $null
        }
        return $uri
    }

    if ($uri.Scheme -ieq 'mailto' -and $Url.StartsWith('mailto:', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $uri
    }

    return $null
}

function Invoke-AllowedExternalNavigation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [scriptblock]$OpenAction
    )

    $uri = Get-AllowedExternalNavigationUri -Url $Url
    if ($null -eq $uri) {
        return $false
    }

    $null = & $OpenAction $uri.AbsoluteUri
    return $true
}

function New-InstructionDocumentResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocumentText,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    return [PSCustomObject]@{
        DocumentText = $DocumentText
        Status = $Status
        Reason = $Reason
    }
}

function New-StaticInstructionDocument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $html = '<!DOCTYPE html><html><head><meta charset="utf-8"/><title>App Installer Instructions</title></head><body><h1>Instructions unavailable</h1><p>The bundled instructions could not be verified or read. Review the local README.md file for product guidance.</p></body></html>'
    return New-InstructionDocumentResult -DocumentText $html -Status 'Fallback' -Reason $Reason
}

function Add-SafeInstructionNode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$SourceNode,

        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$TargetDocument,

        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$TargetParent
    )

    if ($SourceNode.NodeType -eq [System.Xml.XmlNodeType]::Text -or
        $SourceNode.NodeType -eq [System.Xml.XmlNodeType]::CDATA) {
        $null = $TargetParent.AppendChild($TargetDocument.CreateTextNode($SourceNode.Value))
        return
    }
    if ($SourceNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        return
    }

    $tagName = $SourceNode.LocalName.ToLowerInvariant()
    $blockedTags = @(
        'applet', 'audio', 'base', 'button', 'canvas', 'embed', 'form', 'frame', 'frameset',
        'iframe', 'img', 'input', 'link', 'math', 'meta', 'object', 'option', 'picture',
        'script', 'select', 'source', 'style', 'svg', 'template', 'textarea', 'track', 'video'
    )
    if ($blockedTags -contains $tagName) {
        return
    }

    $allowedTags = @(
        'a', 'blockquote', 'br', 'code', 'div', 'em', 'h1', 'h2', 'h3', 'h4', 'hr',
        'li', 'ol', 'p', 'pre', 'strong', 'table', 'tbody', 'td', 'th', 'thead', 'tr', 'ul'
    )
    if ($allowedTags -notcontains $tagName) {
        foreach ($childNode in $SourceNode.ChildNodes) {
            Add-SafeInstructionNode -SourceNode $childNode -TargetDocument $TargetDocument -TargetParent $TargetParent
        }
        return
    }

    $targetNode = $TargetDocument.CreateElement($tagName)
    if ($tagName -eq 'a') {
        $hrefAttribute = $SourceNode.Attributes['href']
        if ($null -ne $hrefAttribute) {
            $uri = Get-AllowedExternalNavigationUri -Url ([System.Net.WebUtility]::HtmlDecode($hrefAttribute.Value))
            if ($null -ne $uri) {
                $targetNode.SetAttribute('href', $uri.AbsoluteUri)
            }
        }
    }

    $null = $TargetParent.AppendChild($targetNode)
    foreach ($childNode in $SourceNode.ChildNodes) {
        Add-SafeInstructionNode -SourceNode $childNode -TargetDocument $TargetDocument -TargetParent $targetNode
    }
}

function ConvertTo-SanitizedInstructionDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content) -or $Content.Length -gt $script:MaximumInstructionContentLength) {
        return New-StaticInstructionDocument -Reason 'empty-or-oversized-content'
    }

    $normalizedContent = [regex]::Replace($Content, '(?is)<!DOCTYPE\s+html\s*>', '')
    $normalizedContent = [regex]::Replace($normalizedContent, '(?is)<(?<tag>br|hr)\b(?<attributes>[^>]*)>', {
        param($match)
        $tagName = $match.Groups['tag'].Value.ToLowerInvariant()
        $attributes = $match.Groups['attributes'].Value.TrimEnd()
        if ($attributes.EndsWith('/')) {
            return ('<{0}{1}>' -f $tagName, $attributes)
        }
        return ('<{0}{1} />' -f $tagName, $attributes)
    })

    $reader = $null
    try {
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null

        $sourceDocument = New-Object System.Xml.XmlDocument
        $sourceDocument.XmlResolver = $null
        $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($normalizedContent)), $settings)
        $sourceDocument.Load($reader)
        if ($null -eq $sourceDocument.DocumentElement -or $sourceDocument.DocumentElement.LocalName -ine 'html') {
            return New-StaticInstructionDocument -Reason 'malformed-html'
        }
        $sourceBody = $sourceDocument.SelectSingleNode("/*[local-name()='html']/*[local-name()='body']")
        if ($null -eq $sourceBody) {
            return New-StaticInstructionDocument -Reason 'malformed-html'
        }

        $safeDocument = New-Object System.Xml.XmlDocument
        $safeDocument.XmlResolver = $null
        $htmlNode = $safeDocument.CreateElement('html')
        $null = $safeDocument.AppendChild($htmlNode)

        $headNode = $safeDocument.CreateElement('head')
        $null = $htmlNode.AppendChild($headNode)
        $metaNode = $safeDocument.CreateElement('meta')
        $metaNode.SetAttribute('charset', 'utf-8')
        $null = $headNode.AppendChild($metaNode)
        $titleNode = $safeDocument.CreateElement('title')
        $null = $titleNode.AppendChild($safeDocument.CreateTextNode('App Installer Instructions'))
        $null = $headNode.AppendChild($titleNode)
        $styleNode = $safeDocument.CreateElement('style')
        $null = $styleNode.AppendChild($safeDocument.CreateTextNode($script:SafeInstructionCss))
        $null = $headNode.AppendChild($styleNode)

        $bodyNode = $safeDocument.CreateElement('body')
        $null = $htmlNode.AppendChild($bodyNode)
        foreach ($sourceNode in $sourceBody.ChildNodes) {
            Add-SafeInstructionNode -SourceNode $sourceNode -TargetDocument $safeDocument -TargetParent $bodyNode
        }

        return New-InstructionDocumentResult -DocumentText ('<!DOCTYPE html>' + $safeDocument.DocumentElement.OuterXml) -Status 'Sanitized' -Reason 'content-allowlisted'
    }
    catch {
        return New-StaticInstructionDocument -Reason 'malformed-html'
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
    }
}

function Get-TrustedInstructionDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return New-StaticInstructionDocument -Reason 'source-unavailable'
        }

        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        $content = $encoding.GetString($bytes)
        if ($content.StartsWith([string][char]0xFEFF, [System.StringComparison]::Ordinal)) {
            $content = $content.Substring(1)
        }
        $normalizedContent = $content -replace "`r`n?", "`n"
        $normalizedBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedContent)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actualHash = [System.BitConverter]::ToString($sha256.ComputeHash($normalizedBytes)).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha256.Dispose()
        }
        if ($actualHash -cne $script:ApprovedInstructionContentSha256) {
            return New-StaticInstructionDocument -Reason 'source-digest-mismatch'
        }

        $result = ConvertTo-SanitizedInstructionDocument -Content $normalizedContent
        if ($result.Status -ne 'Sanitized') {
            return $result
        }

        return New-InstructionDocumentResult -DocumentText $result.DocumentText -Status 'Loaded' -Reason 'verified-local-payload'
    }
    catch {
        return New-StaticInstructionDocument -Reason 'source-read-failed'
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-SanitizedInstructionDocument',
    'Get-AllowedExternalNavigationUri',
    'Get-TrustedInstructionDocument',
    'Invoke-AllowedExternalNavigation'
)
