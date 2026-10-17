function New-ResponsiveForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [int]$Width,

        [Parameter(Mandatory = $true)]
        [int]$Height,

        [int]$MinWidth = 0,
        [int]$MinHeight = 0,
        [string]$StartPosition = 'CenterScreen',
        [bool]$Resizable = $true,
        [Parameter(Mandatory = $true)]
        [PSObject]$ScaleInfo
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size($Width, $Height)
    $form.StartPosition = [System.Enum]::Parse([System.Windows.Forms.FormStartPosition], $StartPosition, $true)
    $form.FormBorderStyle = if ($Resizable) {
        [System.Windows.Forms.FormBorderStyle]::Sizable
    }
    else {
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    }
    $form.MaximizeBox = $Resizable
    $form.MinimizeBox = $true

    if ($MinWidth -gt 0 -or $MinHeight -gt 0) {
        $form.MinimumSize = New-Object System.Drawing.Size($MinWidth, $MinHeight)
    }

    $scaleFactor = 1.0
    if ($ScaleInfo -and $ScaleInfo.TotalScale -gt 0) {
        $scaleFactor = [double]$ScaleInfo.TotalScale
    }

    $form.Tag = @{
        ScaleInfo      = $ScaleInfo
        ScaleFactor    = $scaleFactor
        BaseDimensions = @{
            MinFormWidth  = $MinWidth
            MinFormHeight = $MinHeight
            Margin        = [Math]::Max(1, [int](20 * $scaleFactor))
        }
        FormWidth      = $form.ClientSize.Width
        FormHeight     = $form.ClientSize.Height
    }

    return $form
}

Export-ModuleMember -Function New-ResponsiveForm
