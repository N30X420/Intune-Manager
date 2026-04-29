#requires -Version 5.1

param(
    [bool]$LogEnabled = $true,
    [string]$LogPath = "",
    [int]$DeviceLimit = 200
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $scriptRoot "Logs\IntuneManagement.log"
}

. (Join-Path $scriptRoot "Functions.ps1")
. (Join-Path $scriptRoot "Auth.ps1")

Set-IntuneAppConfiguration -LogEnabled $LogEnabled -LogPath $LogPath -DefaultDeviceLimit $DeviceLimit

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-IntuneLog -Message "Unable to load Windows Forms assemblies." -Level "ERROR" -Exception $_
    throw "Windows Forms could not be loaded. Run this app on Windows with Windows PowerShell 5.1 or PowerShell 7 for Windows."
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Intune Management Console"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(980, 680)

$font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Font = $font

$authGroup = New-Object System.Windows.Forms.GroupBox
$authGroup.Text = "Authentication"
$authGroup.Location = New-Object System.Drawing.Point(12, 12)
$authGroup.Size = New-Object System.Drawing.Size(1140, 150)
$authGroup.Anchor = "Top,Left,Right"
$form.Controls.Add($authGroup)

$lblAuthMode = New-Object System.Windows.Forms.Label
$lblAuthMode.Text = "Mode"
$lblAuthMode.Location = New-Object System.Drawing.Point(16, 31)
$lblAuthMode.Size = New-Object System.Drawing.Size(90, 22)
$authGroup.Controls.Add($lblAuthMode)

$cmbAuthMode = New-Object System.Windows.Forms.ComboBox
$cmbAuthMode.DropDownStyle = "DropDownList"
$cmbAuthMode.Items.AddRange(@("Interactive", "AppOnlySecret", "AppOnlyCertificate"))
$cmbAuthMode.SelectedIndex = 0
$cmbAuthMode.Location = New-Object System.Drawing.Point(112, 28)
$cmbAuthMode.Size = New-Object System.Drawing.Size(170, 24)
$authGroup.Controls.Add($cmbAuthMode)

$lblTenantId = New-Object System.Windows.Forms.Label
$lblTenantId.Text = "Tenant ID"
$lblTenantId.Location = New-Object System.Drawing.Point(300, 31)
$lblTenantId.Size = New-Object System.Drawing.Size(80, 22)
$authGroup.Controls.Add($lblTenantId)

$txtTenantId = New-Object System.Windows.Forms.TextBox
$txtTenantId.Location = New-Object System.Drawing.Point(390, 28)
$txtTenantId.Size = New-Object System.Drawing.Size(290, 24)
$txtTenantId.Anchor = "Top,Left"
$authGroup.Controls.Add($txtTenantId)

$lblClientId = New-Object System.Windows.Forms.Label
$lblClientId.Text = "Client ID"
$lblClientId.Location = New-Object System.Drawing.Point(700, 31)
$lblClientId.Size = New-Object System.Drawing.Size(80, 22)
$authGroup.Controls.Add($lblClientId)

$txtClientId = New-Object System.Windows.Forms.TextBox
$txtClientId.Location = New-Object System.Drawing.Point(790, 28)
$txtClientId.Size = New-Object System.Drawing.Size(210, 24)
$authGroup.Controls.Add($txtClientId)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = "Connect"
$btnConnect.Location = New-Object System.Drawing.Point(1020, 26)
$btnConnect.Size = New-Object System.Drawing.Size(100, 28)
$btnConnect.Anchor = "Top,Right"
$authGroup.Controls.Add($btnConnect)

$lblSecret = New-Object System.Windows.Forms.Label
$lblSecret.Text = "Client Secret"
$lblSecret.Location = New-Object System.Drawing.Point(16, 70)
$lblSecret.Size = New-Object System.Drawing.Size(90, 22)
$authGroup.Controls.Add($lblSecret)

$txtClientSecret = New-Object System.Windows.Forms.TextBox
$txtClientSecret.Location = New-Object System.Drawing.Point(112, 67)
$txtClientSecret.Size = New-Object System.Drawing.Size(300, 24)
$txtClientSecret.UseSystemPasswordChar = $true
$authGroup.Controls.Add($txtClientSecret)

$lblCertThumb = New-Object System.Windows.Forms.Label
$lblCertThumb.Text = "Cert Thumbprint"
$lblCertThumb.Location = New-Object System.Drawing.Point(430, 70)
$lblCertThumb.Size = New-Object System.Drawing.Size(110, 22)
$authGroup.Controls.Add($lblCertThumb)

$txtCertThumb = New-Object System.Windows.Forms.TextBox
$txtCertThumb.Location = New-Object System.Drawing.Point(545, 67)
$txtCertThumb.Size = New-Object System.Drawing.Size(250, 24)
$authGroup.Controls.Add($txtCertThumb)

$lblCertName = New-Object System.Windows.Forms.Label
$lblCertName.Text = "Cert Subject"
$lblCertName.Location = New-Object System.Drawing.Point(815, 70)
$lblCertName.Size = New-Object System.Drawing.Size(90, 22)
$authGroup.Controls.Add($lblCertName)

$txtCertName = New-Object System.Windows.Forms.TextBox
$txtCertName.Location = New-Object System.Drawing.Point(910, 67)
$txtCertName.Size = New-Object System.Drawing.Size(210, 24)
$authGroup.Controls.Add($txtCertName)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Not connected"
$lblStatus.Location = New-Object System.Drawing.Point(16, 112)
$lblStatus.Size = New-Object System.Drawing.Size(760, 22)
$authGroup.Controls.Add($lblStatus)

$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = "Logging"
$logGroup.Location = New-Object System.Drawing.Point(12, 170)
$logGroup.Size = New-Object System.Drawing.Size(1140, 68)
$logGroup.Anchor = "Top,Left,Right"
$form.Controls.Add($logGroup)

$chkLogEnabled = New-Object System.Windows.Forms.CheckBox
$chkLogEnabled.Text = "Enabled"
$chkLogEnabled.Checked = $script:IntuneAppSettings.LogEnabled
$chkLogEnabled.Location = New-Object System.Drawing.Point(16, 28)
$chkLogEnabled.Size = New-Object System.Drawing.Size(90, 24)
$logGroup.Controls.Add($chkLogEnabled)

$lblLogPath = New-Object System.Windows.Forms.Label
$lblLogPath.Text = "Log Path"
$lblLogPath.Location = New-Object System.Drawing.Point(120, 30)
$lblLogPath.Size = New-Object System.Drawing.Size(75, 22)
$logGroup.Controls.Add($lblLogPath)

$txtLogPath = New-Object System.Windows.Forms.TextBox
$txtLogPath.Text = $script:IntuneAppSettings.LogPath
$txtLogPath.Location = New-Object System.Drawing.Point(200, 27)
$txtLogPath.Size = New-Object System.Drawing.Size(800, 24)
$txtLogPath.Anchor = "Top,Left,Right"
$logGroup.Controls.Add($txtLogPath)

$btnApplyLog = New-Object System.Windows.Forms.Button
$btnApplyLog.Text = "Apply"
$btnApplyLog.Location = New-Object System.Drawing.Point(1020, 25)
$btnApplyLog.Size = New-Object System.Drawing.Size(100, 28)
$btnApplyLog.Anchor = "Top,Right"
$logGroup.Controls.Add($btnApplyLog)

$deviceGroup = New-Object System.Windows.Forms.GroupBox
$deviceGroup.Text = "Managed Devices"
$deviceGroup.Location = New-Object System.Drawing.Point(12, 246)
$deviceGroup.Size = New-Object System.Drawing.Size(1140, 330)
$deviceGroup.Anchor = "Top,Bottom,Left,Right"
$form.Controls.Add($deviceGroup)

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Search"
$lblSearch.Location = New-Object System.Drawing.Point(16, 30)
$lblSearch.Size = New-Object System.Drawing.Size(55, 22)
$deviceGroup.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(75, 27)
$txtSearch.Size = New-Object System.Drawing.Size(300, 24)
$deviceGroup.Controls.Add($txtSearch)

$lblLimit = New-Object System.Windows.Forms.Label
$lblLimit.Text = "Limit"
$lblLimit.Location = New-Object System.Drawing.Point(395, 30)
$lblLimit.Size = New-Object System.Drawing.Size(40, 22)
$deviceGroup.Controls.Add($lblLimit)

$numLimit = New-Object System.Windows.Forms.NumericUpDown
$numLimit.Location = New-Object System.Drawing.Point(440, 27)
$numLimit.Size = New-Object System.Drawing.Size(80, 24)
$numLimit.Minimum = 0
$numLimit.Maximum = 10000
$numLimit.Value = $script:IntuneAppSettings.DefaultDeviceLimit
$deviceGroup.Controls.Add($numLimit)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(540, 25)
$btnRefresh.Size = New-Object System.Drawing.Size(95, 28)
$deviceGroup.Controls.Add($btnRefresh)

$lblDeviceAction = New-Object System.Windows.Forms.Label
$lblDeviceAction.Text = "Action"
$lblDeviceAction.Location = New-Object System.Drawing.Point(650, 30)
$lblDeviceAction.Size = New-Object System.Drawing.Size(50, 22)
$deviceGroup.Controls.Add($lblDeviceAction)

$cmbDeviceAction = New-Object System.Windows.Forms.ComboBox
$cmbDeviceAction.DropDownStyle = "DropDownList"
$cmbDeviceAction.Items.AddRange(@(
    "View compliance details",
    "List non-compliant devices",
    "Get local admin password",
    "Reset local admin password",
    "Get BitLocker keys",
    "Reset BitLocker keys",
    "Sync device",
    "Remote wipe"
))
$cmbDeviceAction.SelectedIndex = 0
$cmbDeviceAction.Location = New-Object System.Drawing.Point(705, 27)
$cmbDeviceAction.Size = New-Object System.Drawing.Size(255, 24)
$deviceGroup.Controls.Add($cmbDeviceAction)

$btnRunDeviceAction = New-Object System.Windows.Forms.Button
$btnRunDeviceAction.Text = "Run"
$btnRunDeviceAction.Location = New-Object System.Drawing.Point(975, 25)
$btnRunDeviceAction.Size = New-Object System.Drawing.Size(95, 28)
$deviceGroup.Controls.Add($btnRunDeviceAction)

$gridDevices = New-Object System.Windows.Forms.DataGridView
$gridDevices.Location = New-Object System.Drawing.Point(16, 66)
$gridDevices.Size = New-Object System.Drawing.Size(1104, 244)
$gridDevices.Anchor = "Top,Bottom,Left,Right"
$gridDevices.ReadOnly = $true
$gridDevices.AllowUserToAddRows = $false
$gridDevices.AllowUserToDeleteRows = $false
$gridDevices.MultiSelect = $false
$gridDevices.SelectionMode = "FullRowSelect"
$gridDevices.AutoSizeColumnsMode = "Fill"
$gridDevices.RowHeadersVisible = $false
$gridDevices.AutoGenerateColumns = $true
$deviceGroup.Controls.Add($gridDevices)

$outputGroup = New-Object System.Windows.Forms.GroupBox
$outputGroup.Text = "Output"
$outputGroup.Location = New-Object System.Drawing.Point(12, 584)
$outputGroup.Size = New-Object System.Drawing.Size(1140, 126)
$outputGroup.Anchor = "Bottom,Left,Right"
$form.Controls.Add($outputGroup)

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(16, 26)
$txtOutput.Size = New-Object System.Drawing.Size(1104, 82)
$txtOutput.Anchor = "Top,Bottom,Left,Right"
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = "Vertical"
$txtOutput.ReadOnly = $true
$outputGroup.Controls.Add($txtOutput)

function Add-OutputLine {
    param([string]$Message)

    $txtOutput.AppendText(("[{0}] {1}{2}" -f (Get-Date -Format "HH:mm:ss"), $Message, [Environment]::NewLine))
}

function Show-AppError {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$Exception
    )

    Write-IntuneLog -Message $Message -Level "ERROR" -Exception $Exception
    Add-OutputLine "$Message $($Exception.Exception.Message)"
    [System.Windows.Forms.MessageBox]::Show(
        "$Message`r`n`r`n$($Exception.Exception.Message)",
        "Intune Management Console",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Set-BusyState {
    param([bool]$Busy)

    $form.UseWaitCursor = $Busy
    $btnConnect.Enabled = -not $Busy
    $btnRefresh.Enabled = -not $Busy
    $cmbDeviceAction.Enabled = -not $Busy
    $btnRunDeviceAction.Enabled = -not $Busy
    $btnApplyLog.Enabled = -not $Busy
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-AuthFieldState {
    $mode = [string]$cmbAuthMode.SelectedItem

    $txtClientSecret.Enabled = ($mode -eq "AppOnlySecret")
    $txtCertThumb.Enabled = ($mode -eq "AppOnlyCertificate")
    $txtCertName.Enabled = ($mode -eq "AppOnlyCertificate")
}

function Get-SelectedDevice {
    if ($gridDevices.SelectedRows.Count -gt 0) {
        return $gridDevices.SelectedRows[0].DataBoundItem
    }

    if ($gridDevices.CurrentRow) {
        return $gridDevices.CurrentRow.DataBoundItem
    }

    return $null
}

function Get-SelectedDeviceOrPrompt {
    $device = Get-SelectedDevice
    if ($device) {
        return $device
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Select a device first.",
        "Intune Management Console",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    return $null
}

function Confirm-DeviceAction {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message
    )

    return [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) -eq [System.Windows.Forms.DialogResult]::Yes
}

function Set-DeviceGridData {
    param([object[]]$Devices)

    $deviceList = New-Object System.Collections.ArrayList
    foreach ($device in $Devices) {
        [void]$deviceList.Add($device)
    }

    $gridDevices.DataSource = $null
    $gridDevices.DataSource = $deviceList

    if ($gridDevices.Columns["Id"]) {
        $gridDevices.Columns["Id"].Visible = $false
    }

    if ($gridDevices.Columns["AzureADDeviceId"]) {
        $gridDevices.Columns["AzureADDeviceId"].Visible = $false
    }

    foreach ($column in $gridDevices.Columns) {
        $column.AutoSizeMode = "Fill"
    }
}

function Invoke-DeviceAction {
    $action = [string]$cmbDeviceAction.SelectedItem
    if ([string]::IsNullOrWhiteSpace($action)) {
        return
    }

    Set-BusyState -Busy $true

    try {
        switch ($action) {
            "View compliance details" {
                $device = Get-SelectedDeviceOrPrompt
                if (-not $device) {
                    return
                }

                $status = Get-IntuneDeviceComplianceStatus -ManagedDeviceId $device.Id
                $policyDetails = ""

                if ($status.CompliancePolicyStates -and $status.CompliancePolicyStates.Count -gt 0) {
                    $policyDetails = $status.CompliancePolicyStates | Format-Table -AutoSize | Out-String
                }
                else {
                    $policyDetails = "No compliance policy state details returned."
                }

                Add-OutputLine "Compliance for '$($status.DeviceName)': $($status.ComplianceState)"
                Add-OutputLine $policyDetails.Trim()
            }
            "List non-compliant devices" {
                $devices = @(Get-IntuneNonCompliantDevices)
                $gridRows = @(
                    $devices | Select-Object `
                        @{ Name = "Id"; Expression = { $_.Id } },
                        @{ Name = "DeviceName"; Expression = { $_.DeviceName } },
                        @{ Name = "AzureADDeviceId"; Expression = { $_.AzureADDeviceId } },
                        @{ Name = "UserPrincipalName"; Expression = { $_.UserPrincipalName } },
                        @{ Name = "ComplianceState"; Expression = { $_.ComplianceState } },
                        @{ Name = "NonCompliantPolicies"; Expression = {
                            @($_.NonCompliantPolicies | ForEach-Object { $_.DisplayName }) -join ", "
                        } }
                )

                Set-DeviceGridData -Devices $gridRows
                Add-OutputLine "Loaded $($gridRows.Count) non-compliant device(s)."
            }
            "Get local admin password" {
                $device = Get-SelectedDeviceOrPrompt
                if (-not $device) {
                    return
                }

                $credentials = @(Get-IntuneDeviceLocalAdminPassword -ManagedDeviceId $device.Id)
                if ($credentials.Count -eq 0) {
                    Add-OutputLine "No local admin password returned for '$($device.DeviceName)'."
                }
                else {
                    foreach ($credential in $credentials) {
                        Add-OutputLine "Local admin password for '$($device.DeviceName)' [$($credential.AccountName)]: $($credential.Password)"
                    }
                }
            }
            "Reset local admin password" {
                $device = Get-SelectedDeviceOrPrompt
                if (-not $device) {
                    return
                }

                if (-not (Confirm-DeviceAction -Title "Confirm Local Admin Password Reset" -Message "Reset the local admin password for '$($device.DeviceName)'?")) {
                    Add-OutputLine "Local admin password reset cancelled for '$($device.DeviceName)'."
                    return
                }

                Reset-IntuneDeviceLocalAdminPassword -ManagedDeviceId $device.Id | Out-Null
                Add-OutputLine "Local admin password reset submitted for '$($device.DeviceName)'."
            }
            "Get BitLocker keys" {
                $device = Get-SelectedDeviceOrPrompt
                if (-not $device) {
                    return
                }

                $keys = @(Get-IntuneDeviceBitLockerKeys -ManagedDeviceId $device.Id)
                if ($keys.Count -eq 0) {
                    Add-OutputLine "No BitLocker keys returned for '$($device.DeviceName)'."
                }
                else {
                    foreach ($key in $keys) {
                        $keyId = if ($key.id) { $key.id } else { "UnknownKeyId" }
                        $recoveryKey = if ($key.key) { $key.key } elseif ($key.recoveryKey) { $key.recoveryKey } else { "Not exposed by Graph response." }
                        $volumeType = if ($key.VolumeType) { $key.VolumeType } else { "UnknownVolumeType" }
                        Add-OutputLine "BitLocker key for '$($device.DeviceName)' [$keyId/$volumeType]: $recoveryKey"
                    }
                }
            }
            "Reset BitLocker keys" {
                $device = Get-SelectedDeviceOrPrompt
                if (-not $device) {
                    return
                }

                if (-not (Confirm-DeviceAction -Title "Confirm BitLocker Key Rotation" -Message "Rotate the BitLocker recovery keys for '$($device.DeviceName)'?")) {
                    Add-OutputLine "BitLocker key rotation cancelled for '$($device.DeviceName)'."
                    return
                }

                Reset-IntuneDeviceBitLockerKeys -ManagedDeviceId $device.Id | Out-Null
                Add-OutputLine "BitLocker key rotation submitted for '$($device.DeviceName)'."
            }
            "Sync device" {
                $device = Get-SelectedDeviceOrPrompt
                if (-not $device) {
                    return
                }

                Sync-IntuneDevice -ManagedDeviceId $device.Id | Out-Null
                Add-OutputLine "Device sync submitted for '$($device.DeviceName)'."
            }
            "Remote wipe" {
                $device = Get-SelectedDeviceOrPrompt
                if (-not $device) {
                    return
                }

                if (-not (Confirm-DeviceAction -Title "Confirm Remote Wipe" -Message "Remote wipe '$($device.DeviceName)'? This action is destructive and cannot be undone.")) {
                    Add-OutputLine "Remote wipe cancelled for '$($device.DeviceName)'."
                    Write-IntuneLog -Message "Remote wipe cancelled by user for device '$($device.Id)'." -Level "WARN"
                    return
                }

                Invoke-IntuneDeviceWipe -ManagedDeviceId $device.Id -Confirm:$false | Out-Null
                Add-OutputLine "Remote wipe submitted for '$($device.DeviceName)'."
            }
        }
    }
    catch {
        Show-AppError -Message "Failed to run device action '$action'." -Exception $_
    }
    finally {
        Set-BusyState -Busy $false
    }
}

$cmbAuthMode.Add_SelectedIndexChanged({
    Update-AuthFieldState
})

$btnApplyLog.Add_Click({
    try {
        Set-IntuneAppConfiguration `
            -LogEnabled $chkLogEnabled.Checked `
            -LogPath $txtLogPath.Text `
            -DefaultDeviceLimit ([int]$numLimit.Value)

        Add-OutputLine "Logging configuration applied."
    }
    catch {
        Show-AppError -Message "Failed to apply logging configuration." -Exception $_
    }
})

$btnConnect.Add_Click({
    Set-BusyState -Busy $true

    try {
        $mode = [string]$cmbAuthMode.SelectedItem
        $connectParams = @{
            AuthMode = $mode
        }

        if (-not [string]::IsNullOrWhiteSpace($txtTenantId.Text)) {
            $connectParams.TenantId = $txtTenantId.Text.Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($txtClientId.Text)) {
            $connectParams.ClientId = $txtClientId.Text.Trim()
        }

        if ($mode -eq "AppOnlySecret") {
            $connectParams.ClientSecret = ConvertTo-SecureString -String $txtClientSecret.Text -AsPlainText -Force
        }

        if ($mode -eq "AppOnlyCertificate") {
            if (-not [string]::IsNullOrWhiteSpace($txtCertThumb.Text)) {
                $connectParams.CertificateThumbprint = $txtCertThumb.Text.Trim()
            }

            if (-not [string]::IsNullOrWhiteSpace($txtCertName.Text)) {
                $connectParams.CertificateName = $txtCertName.Text.Trim()
            }
        }

        $context = Connect-IntuneGraph @connectParams
        if ($mode -eq "AppOnlySecret") {
            $txtClientSecret.Clear()
        }

        $lblStatus.Text = "Connected: Tenant=$($context.TenantId); AuthType=$($context.AuthType)"
        Add-OutputLine "Connected to Microsoft Graph."
    }
    catch {
        $lblStatus.Text = "Connection failed"
        Show-AppError -Message "Failed to connect to Microsoft Graph." -Exception $_
    }
    finally {
        Set-BusyState -Busy $false
    }
})

$btnRefresh.Add_Click({
    Set-BusyState -Busy $true

    try {
        Set-IntuneAppConfiguration `
            -LogEnabled $chkLogEnabled.Checked `
            -LogPath $txtLogPath.Text `
            -DefaultDeviceLimit ([int]$numLimit.Value)

        $devices = @(Get-IntuneManagedDevices -SearchText $txtSearch.Text -Top ([int]$numLimit.Value))
        Set-DeviceGridData -Devices $devices
        Add-OutputLine "Loaded $($devices.Count) managed device(s)."
    }
    catch {
        Show-AppError -Message "Failed to retrieve managed devices." -Exception $_
    }
    finally {
        Set-BusyState -Busy $false
    }
})

$btnRunDeviceAction.Add_Click({
    Invoke-DeviceAction
})

$txtSearch.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $btnRefresh.PerformClick()
        $_.SuppressKeyPress = $true
    }
})

Update-AuthFieldState
Add-OutputLine "Ready. Install Microsoft.Graph if the SDK is not already available."
Write-IntuneLog -Message "Intune Management Console started."

[void][System.Windows.Forms.Application]::Run($form)
