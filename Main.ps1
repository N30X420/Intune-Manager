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

$script:AppVersion = "v1.0"
$script:GitHubRepoUrl = "https://github.com/N30X420/Intune-Manager"
$script:GitHubTagsApiUrl = "https://api.github.com/repos/N30X420/Intune-Manager/tags"
$script:SettingsPath = Join-Path $scriptRoot "Settings.json"
$script:AppCulture = [System.Globalization.CultureInfo]::GetCultureInfo("en-GB")
$deviceGroup.Location = New-Object System.Drawing.Point(12, 110)
$deviceGroup.Size = New-Object System.Drawing.Size(1140, 466)
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $script:AppCulture

if ([System.Globalization.CultureInfo]::DefaultThreadCurrentCulture -ne $null) {
    [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $script:AppCulture
    [System.Globalization.CultureInfo]::DefaultThreadCurrentUICulture = $script:AppCulture
}

function Get-DefaultUiSettings {
    return [ordered]@{
        LogEnabled            = $LogEnabled
        LogPath               = $LogPath
        DeviceLimit           = $DeviceLimit
        AuthMode              = "Interactive"
        TenantId              = ""
        ClientId              = ""
        ClientSecretPlainText = ""
        CertificateThumbprint = ""
        CertificateName       = ""
    }
}

function Load-UiSettings {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Defaults
    )

    $settings = [ordered]@{
        LogEnabled            = [bool]$Defaults.LogEnabled
        LogPath               = [string]$Defaults.LogPath
        DeviceLimit           = [int]$Defaults.DeviceLimit
        AuthMode              = [string]$Defaults.AuthMode
        TenantId              = [string]$Defaults.TenantId
        ClientId              = [string]$Defaults.ClientId
        ClientSecretPlainText = [string]$Defaults.ClientSecretPlainText
        CertificateThumbprint = [string]$Defaults.CertificateThumbprint
        CertificateName       = [string]$Defaults.CertificateName
    }

    if (Test-Path -Path $script:SettingsPath) {
        try {
            $raw = Get-Content -Path $script:SettingsPath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $loaded = $raw | ConvertFrom-Json -ErrorAction Stop

                if ($loaded.PSObject.Properties.Name -contains "LogEnabled") {
                    $settings.LogEnabled = [bool]$loaded.LogEnabled
                }

                if ($loaded.PSObject.Properties.Name -contains "LogPath" -and -not [string]::IsNullOrWhiteSpace([string]$loaded.LogPath)) {
                    $settings.LogPath = [string]$loaded.LogPath
                }

                if ($loaded.PSObject.Properties.Name -contains "DeviceLimit") {
                    $settings.DeviceLimit = [int]$loaded.DeviceLimit
                }

                if ($loaded.PSObject.Properties.Name -contains "AuthMode" -and -not [string]::IsNullOrWhiteSpace([string]$loaded.AuthMode)) {
                    $settings.AuthMode = [string]$loaded.AuthMode
                }

                if ($loaded.PSObject.Properties.Name -contains "TenantId") {
                    $settings.TenantId = [string]$loaded.TenantId
                }

                if ($loaded.PSObject.Properties.Name -contains "ClientId") {
                    $settings.ClientId = [string]$loaded.ClientId
                }

                if ($loaded.PSObject.Properties.Name -contains "ClientSecretPlainText") {
                    $settings.ClientSecretPlainText = [string]$loaded.ClientSecretPlainText
                }

                if ($loaded.PSObject.Properties.Name -contains "CertificateThumbprint") {
                    $settings.CertificateThumbprint = [string]$loaded.CertificateThumbprint
                }

                if ($loaded.PSObject.Properties.Name -contains "CertificateName") {
                    $settings.CertificateName = [string]$loaded.CertificateName
                }
            }
        }
        catch {
            Write-Warning "Unable to read saved settings from '$($script:SettingsPath)'. Using defaults. $($_.Exception.Message)"
        }
    }

    if ($PSBoundParameters.ContainsKey("LogEnabled")) {
        $settings.LogEnabled = [bool]$LogEnabled
    }

    if ($PSBoundParameters.ContainsKey("LogPath") -and -not [string]::IsNullOrWhiteSpace($LogPath)) {
        $settings.LogPath = [string]$LogPath
    }

    if ($PSBoundParameters.ContainsKey("DeviceLimit")) {
        $settings.DeviceLimit = [int]$DeviceLimit
    }

    if ($settings.DeviceLimit -lt 0) {
        $settings.DeviceLimit = 0
    }

    $validAuthModes = @("Interactive", "AppOnlySecret", "AppOnlyCertificate")
    if ($validAuthModes -notcontains $settings.AuthMode) {
        $settings.AuthMode = "Interactive"
    }

    return $settings
}

function Save-UiSettings {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    try {
        $payload = [ordered]@{
            LogEnabled            = [bool]$Settings.LogEnabled
            LogPath               = [string]$Settings.LogPath
            DeviceLimit           = [int]$Settings.DeviceLimit
            AuthMode              = [string]$Settings.AuthMode
            TenantId              = [string]$Settings.TenantId
            ClientId              = [string]$Settings.ClientId
            ClientSecretPlainText = [string]$Settings.ClientSecretPlainText
            CertificateThumbprint = [string]$Settings.CertificateThumbprint
            CertificateName       = [string]$Settings.CertificateName
        }

        $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $script:SettingsPath -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to save settings to '$($script:SettingsPath)'. $($_.Exception.Message)"
    }
}

function Convert-TagToVersion {
    param([string]$Tag)

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        return $null
    }

    $normalized = $Tag.Trim()
    if ($normalized.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }

    if ($normalized.Contains("-")) {
        $normalized = $normalized.Split("-")[0]
    }

    if ($normalized -notmatch "^\d+(\.\d+){0,3}$") {
        return $null
    }

    try {
        return [version]$normalized
    }
    catch {
        return $null
    }
}

function Get-LatestGitHubTag {
    try {
        $headers = @{ "User-Agent" = "IntuneManager/$($script:AppVersion)" }
        $tags = Invoke-RestMethod -Method GET -Uri $script:GitHubTagsApiUrl -Headers $headers -ErrorAction Stop

        if (-not $tags) {
            return $null
        }

        foreach ($tag in @($tags)) {
            if ($tag.name) {
                return [string]$tag.name
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

. (Join-Path $scriptRoot "Functions.ps1")
. (Join-Path $scriptRoot "Auth.ps1")

$script:UiSettings = Load-UiSettings -Defaults (Get-DefaultUiSettings)

Set-IntuneAppConfiguration `
    -LogEnabled $script:UiSettings.LogEnabled `
    -LogPath $script:UiSettings.LogPath `
    -DefaultDeviceLimit $script:UiSettings.DeviceLimit

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

function Show-SplashScreen {
    $splash = New-Object System.Windows.Forms.Form
    $splash.FormBorderStyle = "None"
    $splash.StartPosition = "CenterScreen"
    $splash.Size = New-Object System.Drawing.Size(520, 280)
    $splash.BackColor = [System.Drawing.Color]::White
    $splash.TopMost = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Intune Management Console"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(30, 40)
    $splash.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = "Splash content placeholder - customize this screen as needed."
    $subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $subtitle.AutoSize = $true
    $subtitle.Location = New-Object System.Drawing.Point(32, 95)
    $splash.Controls.Add($subtitle)

    $version = New-Object System.Windows.Forms.Label
    $version.Text = "Version $($script:AppVersion)"
    $version.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $version.AutoSize = $true
    $version.Location = New-Object System.Drawing.Point(32, 130)
    $splash.Controls.Add($version)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1400
    $timer.Add_Tick({
        $timer.Stop()
        $splash.Close()
    })

    $splash.Add_Shown({ $timer.Start() })
    [void]$splash.ShowDialog()
}

Show-SplashScreen

$form = New-Object System.Windows.Forms.Form
$form.Text = "Intune Management Console"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(980, 680)

$font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Font = $font

$authGroup = New-Object System.Windows.Forms.GroupBox
$authGroup.Text = "Connection"
$authGroup.Location = New-Object System.Drawing.Point(12, 12)
$authGroup.Size = New-Object System.Drawing.Size(1140, 90)
$authGroup.Anchor = "Top,Left,Right"
$form.Controls.Add($authGroup)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = "Connect"
$btnConnect.Location = New-Object System.Drawing.Point(920, 26)
$btnConnect.Size = New-Object System.Drawing.Size(100, 28)
$btnConnect.Anchor = "Top,Right"
$authGroup.Controls.Add($btnConnect)

$btnAuthSettings = New-Object System.Windows.Forms.Button
$btnAuthSettings.Text = "Authentication"
$btnAuthSettings.Location = New-Object System.Drawing.Point(700, 26)
$btnAuthSettings.Size = New-Object System.Drawing.Size(110, 28)
$btnAuthSettings.Anchor = "Top,Right"
$authGroup.Controls.Add($btnAuthSettings)

$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Text = "Settings"
$btnSettings.Location = New-Object System.Drawing.Point(810, 26)
$btnSettings.Size = New-Object System.Drawing.Size(100, 28)
$btnSettings.Anchor = "Top,Right"
$authGroup.Controls.Add($btnSettings)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Not connected"
$lblStatus.Location = New-Object System.Drawing.Point(16, 32)
$lblStatus.Size = New-Object System.Drawing.Size(670, 22)
$authGroup.Controls.Add($lblStatus)

$deviceGroup = New-Object System.Windows.Forms.GroupBox
$deviceGroup.Text = "Managed Devices"
$deviceGroup.Location = New-Object System.Drawing.Point(12, 110)
$deviceGroup.Size = New-Object System.Drawing.Size(1140, 466)
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

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(395, 25)
$btnRefresh.Size = New-Object System.Drawing.Size(95, 28)
$deviceGroup.Controls.Add($btnRefresh)

$lblDeviceAction = New-Object System.Windows.Forms.Label
$lblDeviceAction.Text = "Action"
$lblDeviceAction.Location = New-Object System.Drawing.Point(510, 30)
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
$cmbDeviceAction.Location = New-Object System.Drawing.Point(565, 27)
$cmbDeviceAction.Size = New-Object System.Drawing.Size(255, 24)
$deviceGroup.Controls.Add($cmbDeviceAction)

$btnRunDeviceAction = New-Object System.Windows.Forms.Button
$btnRunDeviceAction.Text = "Run"
$btnRunDeviceAction.Location = New-Object System.Drawing.Point(835, 25)
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

$lblVersion = New-Object System.Windows.Forms.Label
$lblVersion.Text = "Version $($script:AppVersion)"
$lblVersion.AutoSize = $true
$lblVersion.Location = New-Object System.Drawing.Point(990, 104)
$lblVersion.Anchor = "Bottom,Right"
$outputGroup.Controls.Add($lblVersion)

function Add-OutputLine {
    param([string]$Message)

    $txtOutput.AppendText(("[{0}] {1}{2}" -f (Get-Date -Format "dd-MM-yyyy HH:mm:ss"), $Message, [Environment]::NewLine))
}

function Check-ForUpdates {
    param([bool]$ShowWhenCurrent = $false)

    $latestTag = Get-LatestGitHubTag
    if ([string]::IsNullOrWhiteSpace($latestTag)) {
        if ($ShowWhenCurrent) {
            [System.Windows.Forms.MessageBox]::Show(
                "No GitHub tags were found yet.",
                "Update Check",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }

        return $false
    }

    $currentVersion = Convert-TagToVersion -Tag $script:AppVersion
    $latestVersion = Convert-TagToVersion -Tag $latestTag

    if ($currentVersion -and $latestVersion -and $latestVersion -gt $currentVersion) {
        $message = "A newer version is available.`r`n`r`nCurrent: $($script:AppVersion)`r`nLatest:  $latestTag`r`n`r`nRepository:`r`n$($script:GitHubRepoUrl)"
        Add-OutputLine "Update available: $latestTag"
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Update Available",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        return $true
    }

    if ($ShowWhenCurrent) {
        [System.Windows.Forms.MessageBox]::Show(
            "You are running the latest version ($($script:AppVersion)).",
            "Update Check",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }

    return $false
}

function Apply-UiSettings {
    try {
        Set-IntuneAppConfiguration `
            -LogEnabled $script:UiSettings.LogEnabled `
            -LogPath $script:UiSettings.LogPath `
            -DefaultDeviceLimit $script:UiSettings.DeviceLimit

        Save-UiSettings -Settings $script:UiSettings
        Add-OutputLine "Settings applied."
    }
    catch {
        Show-AppError -Message "Failed to apply settings." -Exception $_
    }
}

function Show-SettingsDialog {
    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = "Settings"
    $settingsForm.StartPosition = "CenterParent"
    $settingsForm.Size = New-Object System.Drawing.Size(680, 280)
    $settingsForm.FormBorderStyle = "FixedDialog"
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false

    $settingsFont = New-Object System.Drawing.Font("Segoe UI", 9)
    $settingsForm.Font = $settingsFont

    $chkSettingsLogEnabled = New-Object System.Windows.Forms.CheckBox
    $chkSettingsLogEnabled.Text = "Enable Log"
    $chkSettingsLogEnabled.Checked = $script:UiSettings.LogEnabled
    $chkSettingsLogEnabled.Location = New-Object System.Drawing.Point(20, 20)
    $chkSettingsLogEnabled.Size = New-Object System.Drawing.Size(120, 24)
    $settingsForm.Controls.Add($chkSettingsLogEnabled)

    $lblSettingsLogPath = New-Object System.Windows.Forms.Label
    $lblSettingsLogPath.Text = "Log Path"
    $lblSettingsLogPath.Location = New-Object System.Drawing.Point(20, 60)
    $lblSettingsLogPath.Size = New-Object System.Drawing.Size(70, 22)
    $settingsForm.Controls.Add($lblSettingsLogPath)

    $txtSettingsLogPath = New-Object System.Windows.Forms.TextBox
    $txtSettingsLogPath.Text = [string]$script:UiSettings.LogPath
    $txtSettingsLogPath.Location = New-Object System.Drawing.Point(95, 57)
    $txtSettingsLogPath.Size = New-Object System.Drawing.Size(460, 24)
    $settingsForm.Controls.Add($txtSettingsLogPath)

    $btnBrowseLogPath = New-Object System.Windows.Forms.Button
    $btnBrowseLogPath.Text = "Browse"
    $btnBrowseLogPath.Location = New-Object System.Drawing.Point(560, 55)
    $btnBrowseLogPath.Size = New-Object System.Drawing.Size(85, 28)
    $settingsForm.Controls.Add($btnBrowseLogPath)

    $lblSettingsDeviceLimit = New-Object System.Windows.Forms.Label
    $lblSettingsDeviceLimit.Text = "Device Limit"
    $lblSettingsDeviceLimit.Location = New-Object System.Drawing.Point(20, 100)
    $lblSettingsDeviceLimit.Size = New-Object System.Drawing.Size(80, 22)
    $settingsForm.Controls.Add($lblSettingsDeviceLimit)

    $numSettingsDeviceLimit = New-Object System.Windows.Forms.NumericUpDown
    $numSettingsDeviceLimit.Location = New-Object System.Drawing.Point(95, 97)
    $numSettingsDeviceLimit.Size = New-Object System.Drawing.Size(100, 24)
    $numSettingsDeviceLimit.Minimum = 0
    $numSettingsDeviceLimit.Maximum = 10000
    $numSettingsDeviceLimit.Value = [decimal]([Math]::Min([Math]::Max([int]$script:UiSettings.DeviceLimit, 0), 10000))
    $settingsForm.Controls.Add($numSettingsDeviceLimit)

    $btnCheckUpdates = New-Object System.Windows.Forms.Button
    $btnCheckUpdates.Text = "Check for updates"
    $btnCheckUpdates.Location = New-Object System.Drawing.Point(20, 140)
    $btnCheckUpdates.Size = New-Object System.Drawing.Size(150, 30)
    $settingsForm.Controls.Add($btnCheckUpdates)

    $btnSaveSettings = New-Object System.Windows.Forms.Button
    $btnSaveSettings.Text = "Save"
    $btnSaveSettings.Location = New-Object System.Drawing.Point(480, 185)
    $btnSaveSettings.Size = New-Object System.Drawing.Size(80, 30)
    $settingsForm.Controls.Add($btnSaveSettings)

    $btnCancelSettings = New-Object System.Windows.Forms.Button
    $btnCancelSettings.Text = "Cancel"
    $btnCancelSettings.Location = New-Object System.Drawing.Point(565, 185)
    $btnCancelSettings.Size = New-Object System.Drawing.Size(80, 30)
    $settingsForm.Controls.Add($btnCancelSettings)

    $btnBrowseLogPath.Add_Click({
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Title = "Select log file path"
        $dialog.Filter = "Log files (*.log)|*.log|All files (*.*)|*.*"
        $dialog.FileName = if ([string]::IsNullOrWhiteSpace($txtSettingsLogPath.Text)) { "IntuneManagement.log" } else { [IO.Path]::GetFileName($txtSettingsLogPath.Text) }

        if (-not [string]::IsNullOrWhiteSpace($txtSettingsLogPath.Text)) {
            try {
                $existingDir = Split-Path -Path $txtSettingsLogPath.Text -Parent
                if (-not [string]::IsNullOrWhiteSpace($existingDir) -and (Test-Path -Path $existingDir)) {
                    $dialog.InitialDirectory = $existingDir
                }
            }
            catch {
                # Keep default initial directory.
            }
        }

        if ($dialog.ShowDialog($settingsForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtSettingsLogPath.Text = $dialog.FileName
        }
    })

    $btnCheckUpdates.Add_Click({
        try {
            [void](Check-ForUpdates -ShowWhenCurrent $true)
        }
        catch {
            Show-AppError -Message "Failed to check for updates." -Exception $_
        }
    })

    $btnSaveSettings.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtSettingsLogPath.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Log path cannot be empty.",
                "Settings",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $script:UiSettings.LogEnabled = $chkSettingsLogEnabled.Checked
        $script:UiSettings.LogPath = $txtSettingsLogPath.Text.Trim()
        $script:UiSettings.DeviceLimit = [int]$numSettingsDeviceLimit.Value

        Apply-UiSettings
        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $settingsForm.Close()
    })

    $btnCancelSettings.Add_Click({
        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $settingsForm.Close()
    })

    [void]$settingsForm.ShowDialog($form)
}

function Get-AuthenticationSummaryText {
    $mode = [string]$script:UiSettings.AuthMode
    if ([string]::IsNullOrWhiteSpace($mode)) {
        $mode = "Interactive"
    }

    $summary = "Not connected (Auth mode: $mode"

    if (-not [string]::IsNullOrWhiteSpace([string]$script:UiSettings.TenantId)) {
        $summary += "; Tenant: $($script:UiSettings.TenantId)"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$script:UiSettings.ClientId)) {
        $summary += "; Client: $($script:UiSettings.ClientId)"
    }

    $summary += ")"
    return $summary
}

function Show-AuthenticationDialog {
    $authForm = New-Object System.Windows.Forms.Form
    $authForm.Text = "Authentication"
    $authForm.StartPosition = "CenterParent"
    $authForm.Size = New-Object System.Drawing.Size(730, 280)
    $authForm.FormBorderStyle = "FixedDialog"
    $authForm.MaximizeBox = $false
    $authForm.MinimizeBox = $false

    $authFont = New-Object System.Drawing.Font("Segoe UI", 9)
    $authForm.Font = $authFont

    $lblAuthMode = New-Object System.Windows.Forms.Label
    $lblAuthMode.Text = "Mode"
    $lblAuthMode.Location = New-Object System.Drawing.Point(20, 20)
    $lblAuthMode.Size = New-Object System.Drawing.Size(80, 22)
    $authForm.Controls.Add($lblAuthMode)

    $cmbAuthMode = New-Object System.Windows.Forms.ComboBox
    $cmbAuthMode.DropDownStyle = "DropDownList"
    $cmbAuthMode.Items.AddRange(@("Interactive", "AppOnlySecret", "AppOnlyCertificate"))
    $selectedMode = [string]$script:UiSettings.AuthMode
    if ($cmbAuthMode.Items -notcontains $selectedMode) {
        $selectedMode = "Interactive"
    }
    $cmbAuthMode.SelectedItem = $selectedMode
    $cmbAuthMode.Location = New-Object System.Drawing.Point(105, 17)
    $cmbAuthMode.Size = New-Object System.Drawing.Size(180, 24)
    $authForm.Controls.Add($cmbAuthMode)

    $lblTenantId = New-Object System.Windows.Forms.Label
    $lblTenantId.Text = "Tenant ID"
    $lblTenantId.Location = New-Object System.Drawing.Point(20, 58)
    $lblTenantId.Size = New-Object System.Drawing.Size(80, 22)
    $authForm.Controls.Add($lblTenantId)

    $txtTenantId = New-Object System.Windows.Forms.TextBox
    $txtTenantId.Text = [string]$script:UiSettings.TenantId
    $txtTenantId.Location = New-Object System.Drawing.Point(105, 55)
    $txtTenantId.Size = New-Object System.Drawing.Size(290, 24)
    $authForm.Controls.Add($txtTenantId)

    $lblClientId = New-Object System.Windows.Forms.Label
    $lblClientId.Text = "Client ID"
    $lblClientId.Location = New-Object System.Drawing.Point(410, 58)
    $lblClientId.Size = New-Object System.Drawing.Size(70, 22)
    $authForm.Controls.Add($lblClientId)

    $txtClientId = New-Object System.Windows.Forms.TextBox
    $txtClientId.Text = [string]$script:UiSettings.ClientId
    $txtClientId.Location = New-Object System.Drawing.Point(485, 55)
    $txtClientId.Size = New-Object System.Drawing.Size(220, 24)
    $authForm.Controls.Add($txtClientId)

    $lblClientSecret = New-Object System.Windows.Forms.Label
    $lblClientSecret.Text = "Client Secret"
    $lblClientSecret.Location = New-Object System.Drawing.Point(20, 96)
    $lblClientSecret.Size = New-Object System.Drawing.Size(80, 22)
    $authForm.Controls.Add($lblClientSecret)

    $txtClientSecret = New-Object System.Windows.Forms.TextBox
    $txtClientSecret.Text = [string]$script:UiSettings.ClientSecretPlainText
    $txtClientSecret.Location = New-Object System.Drawing.Point(105, 93)
    $txtClientSecret.Size = New-Object System.Drawing.Size(290, 24)
    $txtClientSecret.UseSystemPasswordChar = $true
    $authForm.Controls.Add($txtClientSecret)

    $lblCertThumb = New-Object System.Windows.Forms.Label
    $lblCertThumb.Text = "Cert Thumbprint"
    $lblCertThumb.Location = New-Object System.Drawing.Point(20, 134)
    $lblCertThumb.Size = New-Object System.Drawing.Size(90, 22)
    $authForm.Controls.Add($lblCertThumb)

    $txtCertThumb = New-Object System.Windows.Forms.TextBox
    $txtCertThumb.Text = [string]$script:UiSettings.CertificateThumbprint
    $txtCertThumb.Location = New-Object System.Drawing.Point(105, 131)
    $txtCertThumb.Size = New-Object System.Drawing.Size(290, 24)
    $authForm.Controls.Add($txtCertThumb)

    $lblCertName = New-Object System.Windows.Forms.Label
    $lblCertName.Text = "Cert Subject"
    $lblCertName.Location = New-Object System.Drawing.Point(410, 134)
    $lblCertName.Size = New-Object System.Drawing.Size(75, 22)
    $authForm.Controls.Add($lblCertName)

    $txtCertName = New-Object System.Windows.Forms.TextBox
    $txtCertName.Text = [string]$script:UiSettings.CertificateName
    $txtCertName.Location = New-Object System.Drawing.Point(485, 131)
    $txtCertName.Size = New-Object System.Drawing.Size(220, 24)
    $authForm.Controls.Add($txtCertName)

    $btnSaveAuth = New-Object System.Windows.Forms.Button
    $btnSaveAuth.Text = "Save"
    $btnSaveAuth.Location = New-Object System.Drawing.Point(540, 188)
    $btnSaveAuth.Size = New-Object System.Drawing.Size(80, 30)
    $authForm.Controls.Add($btnSaveAuth)

    $btnCancelAuth = New-Object System.Windows.Forms.Button
    $btnCancelAuth.Text = "Cancel"
    $btnCancelAuth.Location = New-Object System.Drawing.Point(625, 188)
    $btnCancelAuth.Size = New-Object System.Drawing.Size(80, 30)
    $authForm.Controls.Add($btnCancelAuth)

    $updateAuthFieldState = {
        $mode = [string]$cmbAuthMode.SelectedItem
        $txtClientSecret.Enabled = ($mode -eq "AppOnlySecret")
        $txtCertThumb.Enabled = ($mode -eq "AppOnlyCertificate")
        $txtCertName.Enabled = ($mode -eq "AppOnlyCertificate")
    }

    $cmbAuthMode.Add_SelectedIndexChanged({ & $updateAuthFieldState })
    & $updateAuthFieldState

    $btnSaveAuth.Add_Click({
        $script:UiSettings.AuthMode = [string]$cmbAuthMode.SelectedItem
        $script:UiSettings.TenantId = $txtTenantId.Text.Trim()
        $script:UiSettings.ClientId = $txtClientId.Text.Trim()
        $script:UiSettings.ClientSecretPlainText = $txtClientSecret.Text
        $script:UiSettings.CertificateThumbprint = $txtCertThumb.Text.Trim()
        $script:UiSettings.CertificateName = $txtCertName.Text.Trim()

        Save-UiSettings -Settings $script:UiSettings
        $lblStatus.Text = Get-AuthenticationSummaryText

        Add-OutputLine "Authentication settings saved."
        $authForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $authForm.Close()
    })

    $btnCancelAuth.Add_Click({
        $authForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $authForm.Close()
    })

    [void]$authForm.ShowDialog($form)
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
    $btnAuthSettings.Enabled = -not $Busy
    $btnSettings.Enabled = -not $Busy
    $btnRefresh.Enabled = -not $Busy
    $cmbDeviceAction.Enabled = -not $Busy
    $btnRunDeviceAction.Enabled = -not $Busy
    [System.Windows.Forms.Application]::DoEvents()
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

$btnAuthSettings.Add_Click({
    Show-AuthenticationDialog
})

$btnSettings.Add_Click({
    Show-SettingsDialog
})

$btnConnect.Add_Click({
    Set-BusyState -Busy $true

    try {
        $mode = [string]$script:UiSettings.AuthMode
        if ([string]::IsNullOrWhiteSpace($mode)) {
            $mode = "Interactive"
        }

        $connectParams = @{
            AuthMode = $mode
        }

        if (-not [string]::IsNullOrWhiteSpace($script:UiSettings.TenantId)) {
            $connectParams.TenantId = [string]$script:UiSettings.TenantId
        }

        if (-not [string]::IsNullOrWhiteSpace($script:UiSettings.ClientId)) {
            $connectParams.ClientId = [string]$script:UiSettings.ClientId
        }

        if ($mode -eq "AppOnlySecret") {
            $connectParams.ClientSecret = ConvertTo-SecureString -String $script:UiSettings.ClientSecretPlainText -AsPlainText -Force
        }

        if ($mode -eq "AppOnlyCertificate") {
            if (-not [string]::IsNullOrWhiteSpace($script:UiSettings.CertificateThumbprint)) {
                $connectParams.CertificateThumbprint = [string]$script:UiSettings.CertificateThumbprint
            }

            if (-not [string]::IsNullOrWhiteSpace($script:UiSettings.CertificateName)) {
                $connectParams.CertificateName = [string]$script:UiSettings.CertificateName
            }
        }

        $context = Connect-IntuneGraph @connectParams

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
            -LogEnabled $script:UiSettings.LogEnabled `
            -LogPath $script:UiSettings.LogPath `
            -DefaultDeviceLimit $script:UiSettings.DeviceLimit

        $devices = @(Get-IntuneManagedDevices -SearchText $txtSearch.Text -Top $script:UiSettings.DeviceLimit)
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

$form.Add_Shown({
    try {
        [void](Check-ForUpdates -ShowWhenCurrent $false)
    }
    catch {
        Write-IntuneLog -Message "Automatic update check failed." -Level "WARN" -Exception $_
    }
})

$lblStatus.Text = Get-AuthenticationSummaryText
Add-OutputLine "Ready. Install Microsoft.Graph if the SDK is not already available."
Write-IntuneLog -Message "Intune Management Console started."

[void][System.Windows.Forms.Application]::Run($form)
