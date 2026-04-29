# Shared configuration, logging, and Intune device actions.

if (-not $script:IntuneAppSettings) {
    $script:IntuneAppSettings = [ordered]@{
        LogEnabled        = $true
        LogPath           = Join-Path $PSScriptRoot "Logs\IntuneManagement.log"
        DefaultDeviceLimit = 200
    }
}

function Set-IntuneAppConfiguration {
    [CmdletBinding()]
    param(
        [bool]$LogEnabled = $script:IntuneAppSettings.LogEnabled,

        [string]$LogPath = $script:IntuneAppSettings.LogPath,

        [int]$DefaultDeviceLimit = $script:IntuneAppSettings.DefaultDeviceLimit
    )

    $script:IntuneAppSettings.LogEnabled = $LogEnabled
    $script:IntuneAppSettings.LogPath = $LogPath
    $script:IntuneAppSettings.DefaultDeviceLimit = $DefaultDeviceLimit

    Write-IntuneLog -Message "Configuration updated. LogEnabled=$LogEnabled; LogPath=$LogPath; DefaultDeviceLimit=$DefaultDeviceLimit."
}

function Write-IntuneLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [System.Management.Automation.ErrorRecord]$Exception
    )

    if (-not $script:IntuneAppSettings.LogEnabled) {
        return
    }

    try {
        $logPath = $script:IntuneAppSettings.LogPath
        $logDirectory = Split-Path -Path $logPath -Parent

        if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $exceptionText = ""
        if ($Exception) {
            $exceptionText = " Exception=$($Exception.Exception.Message)"
        }

        $line = "{0} [{1}] {2}{3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message, $exceptionText
        Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to write to Intune management log. $($_.Exception.Message)"
    }
}

function Test-IntuneGraphConnection {
    [CmdletBinding()]
    param()

    try {
        $context = Get-MgContext -ErrorAction Stop
        if (-not $context) {
            throw "No active Microsoft Graph context found."
        }

        return $context
    }
    catch {
        Write-IntuneLog -Message "No active Microsoft Graph connection." -Level "ERROR" -Exception $_
        throw "Connect to Microsoft Graph before running Intune actions."
    }
}

function Get-IntuneManagedDevices {
    [CmdletBinding()]
    param(
        [string]$SearchText,

        [int]$Top = $script:IntuneAppSettings.DefaultDeviceLimit
    )

    try {
        Test-IntuneGraphConnection | Out-Null
        Write-IntuneLog -Message "Retrieving Intune managed devices. SearchText='$SearchText'; Top=$Top."

        $properties = @(
            "id",
            "deviceName",
            "azureADDeviceId",
            "userPrincipalName",
            "operatingSystem",
            "osVersion",
            "complianceState",
            "managementState",
            "lastSyncDateTime",
            "serialNumber",
            "model",
            "manufacturer"
        )

        if ($Top -gt 0) {
            $devices = @(Get-MgDeviceManagementManagedDevice -Property $properties -Top $Top -ErrorAction Stop)
        }
        else {
            $devices = @(Get-MgDeviceManagementManagedDevice -Property $properties -All -ErrorAction Stop)
        }

        if (-not [string]::IsNullOrWhiteSpace($SearchText)) {
            $devices = @(
                $devices | Where-Object {
                    $_.DeviceName -like "*$SearchText*" -or
                    $_.UserPrincipalName -like "*$SearchText*" -or
                    $_.SerialNumber -like "*$SearchText*"
                }
            )
        }

        $result = @(
            $devices | Select-Object `
                @{ Name = "Id"; Expression = { $_.Id } },
                @{ Name = "DeviceName"; Expression = { $_.DeviceName } },
                @{ Name = "AzureADDeviceId"; Expression = { $_.AzureADDeviceId } },
                @{ Name = "UserPrincipalName"; Expression = { $_.UserPrincipalName } },
                @{ Name = "OperatingSystem"; Expression = { $_.OperatingSystem } },
                @{ Name = "OSVersion"; Expression = { $_.OSVersion } },
                @{ Name = "ComplianceState"; Expression = { $_.ComplianceState } },
                @{ Name = "ManagementState"; Expression = { $_.ManagementState } },
                @{ Name = "LastSyncDateTime"; Expression = { $_.LastSyncDateTime } },
                @{ Name = "SerialNumber"; Expression = { $_.SerialNumber } },
                @{ Name = "Manufacturer"; Expression = { $_.Manufacturer } },
                @{ Name = "Model"; Expression = { $_.Model } }
        )

        Write-IntuneLog -Message "Retrieved $($result.Count) Intune managed device(s)."
        return $result
    }
    catch {
        Write-IntuneLog -Message "Failed to retrieve Intune managed devices." -Level "ERROR" -Exception $_
        throw
    }
}

function Resolve-IntuneManagedDeviceIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId
    )

    try {
        Test-IntuneGraphConnection | Out-Null

        $device = Get-MgDeviceManagementManagedDevice `
            -ManagedDeviceId $ManagedDeviceId `
            -Property @("id", "deviceName", "azureADDeviceId") `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($device.AzureADDeviceId)) {
            throw "Managed device '$ManagedDeviceId' is not linked to a Microsoft Entra device ID."
        }

        $directoryDeviceId = $device.AzureADDeviceId
        $azureAdObjectId = $device.AzureADDeviceId

        $mappingResolved = $false

        try {
            $escapedAzureAdObjectId = [System.Uri]::EscapeDataString($azureAdObjectId)
            $directoryDevice = Invoke-MgGraphRequest `
                -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/devices/$escapedAzureAdObjectId?`$select=id,deviceId,displayName" `
                -ErrorAction Stop

            if ($directoryDevice) {
                if (-not [string]::IsNullOrWhiteSpace($directoryDevice.deviceId)) {
                    $directoryDeviceId = $directoryDevice.deviceId
                }

                if (-not [string]::IsNullOrWhiteSpace($directoryDevice.id)) {
                    $azureAdObjectId = $directoryDevice.id
                }

                $mappingResolved = $true
            }
        }
        catch {
            # Some tenants return azureADDeviceId as deviceId, not the directory object id.
            # If direct lookup fails, attempt resolution by deviceId filter.
            try {
                $escapedFilterValue = $directoryDeviceId.Replace("'", "''")
                $lookupUri = "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$escapedFilterValue'&`$select=id,deviceId,displayName"
                $lookupResponse = Invoke-MgGraphRequest -Method GET -Uri $lookupUri -ErrorAction Stop
                $directoryDevice = @($lookupResponse.value) | Select-Object -First 1

                if ($directoryDevice) {
                    if (-not [string]::IsNullOrWhiteSpace($directoryDevice.deviceId)) {
                        $directoryDeviceId = $directoryDevice.deviceId
                    }

                    if (-not [string]::IsNullOrWhiteSpace($directoryDevice.id)) {
                        $azureAdObjectId = $directoryDevice.id
                    }

                    $mappingResolved = $true
                }
            }
            catch {
                # keep fallback values
            }
        }

        if (-not $mappingResolved) {
            Write-IntuneLog -Message "Unable to resolve directory device mapping for '$ManagedDeviceId'. Using managed device AzureADDeviceId directly."
        }

        return [pscustomobject]@{
            ManagedDeviceId   = $device.Id
            DeviceName        = $device.DeviceName
            AzureADDeviceId   = $device.AzureADDeviceId
            AzureAdObjectId   = $azureAdObjectId
            DirectoryDeviceId = $directoryDeviceId
        }
    }
    catch {
        Write-IntuneLog -Message "Failed to resolve device identity for managed device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}

function Invoke-IntuneDeviceWipe {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId,

        [bool]$KeepEnrollmentData = $false,

        [bool]$KeepUserData = $false,

        [bool]$PersistEsimDataPlan = $false,

        [string]$MacOsUnlockCode,

        [ValidateSet("", "doNotObliterate", "obliterateWithWarning", "always")]
        [string]$ObliterationBehavior = ""
    )

    try {
        Test-IntuneGraphConnection | Out-Null

        if (-not $PSCmdlet.ShouldProcess($ManagedDeviceId, "Remote wipe Intune managed device")) {
            Write-IntuneLog -Message "Remote wipe skipped by ShouldProcess for device '$ManagedDeviceId'." -Level "WARN"
            return $false
        }

        $escapedDeviceId = [System.Uri]::EscapeDataString($ManagedDeviceId)
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$escapedDeviceId/wipe"

        $body = [ordered]@{
            keepEnrollmentData = $KeepEnrollmentData
            keepUserData       = $KeepUserData
            persistEsimDataPlan = $PersistEsimDataPlan
        }

        if (-not [string]::IsNullOrWhiteSpace($MacOsUnlockCode)) {
            $body.macOsUnlockCode = $MacOsUnlockCode
        }

        if (-not [string]::IsNullOrWhiteSpace($ObliterationBehavior)) {
            $body.obliterationBehavior = $ObliterationBehavior
        }

        Write-IntuneLog -Message "Sending remote wipe request for device '$ManagedDeviceId'." -Level "WARN"

        Invoke-MgGraphRequest `
            -Method POST `
            -Uri $uri `
            -Body ($body | ConvertTo-Json -Depth 5) `
            -ContentType "application/json" `
            -ErrorAction Stop | Out-Null

        Write-IntuneLog -Message "Remote wipe request submitted for device '$ManagedDeviceId'." -Level "WARN"
        return $true
    }
    catch {
        Write-IntuneLog -Message "Failed to submit remote wipe request for device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}

function Get-IntuneDeviceComplianceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId
    )

    try {
        Test-IntuneGraphConnection | Out-Null
        Write-IntuneLog -Message "Retrieving compliance status for device '$ManagedDeviceId'."

        $device = Get-MgDeviceManagementManagedDevice `
            -ManagedDeviceId $ManagedDeviceId `
            -Property @("id", "deviceName", "userPrincipalName", "complianceState", "managementState", "lastSyncDateTime") `
            -ErrorAction Stop

        $policyStates = @()

        try {
            if (Get-Command -Name Get-MgDeviceManagementManagedDeviceCompliancePolicyState -ErrorAction SilentlyContinue) {
                $policyStates = @(Get-MgDeviceManagementManagedDeviceCompliancePolicyState -ManagedDeviceId $ManagedDeviceId -ErrorAction Stop)
            }
            else {
                $escapedDeviceId = [System.Uri]::EscapeDataString($ManagedDeviceId)
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$escapedDeviceId/deviceCompliancePolicyStates"
                $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop

                if ($response.value) {
                    $policyStates = @($response.value)
                }
            }
        }
        catch {
            Write-IntuneLog -Message "Unable to retrieve compliance policy states for device '$ManagedDeviceId'. Returning device compliance summary only." -Level "WARN" -Exception $_
        }

        $selectedPolicyStates = @(
            $policyStates | Select-Object `
                @{ Name = "DisplayName"; Expression = { $_.DisplayName } },
                @{ Name = "State"; Expression = { $_.State } },
                @{ Name = "PlatformType"; Expression = { $_.PlatformType } },
                @{ Name = "SettingCount"; Expression = { $_.SettingCount } },
                @{ Name = "LastReportedDateTime"; Expression = { $_.LastReportedDateTime } }
        )

        $result = [pscustomobject]@{
            Id                   = $device.Id
            DeviceName           = $device.DeviceName
            UserPrincipalName    = $device.UserPrincipalName
            ComplianceState      = $device.ComplianceState
            ManagementState      = $device.ManagementState
            LastSyncDateTime     = $device.LastSyncDateTime
            CompliancePolicyStates = $selectedPolicyStates
        }

        Write-IntuneLog -Message "Compliance status for device '$ManagedDeviceId' is '$($result.ComplianceState)'."
        return $result
    }
    catch {
        Write-IntuneLog -Message "Failed to retrieve compliance status for device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}

# function to view all non compliant devices with their compliance state and the policies they are non compliant with. This is for testing and demonstration purposes only, not intended for production use.
function Get-IntuneNonCompliantDevices {
    [CmdletBinding()]
    param()

    try {
        Test-IntuneGraphConnection | Out-Null
        Write-IntuneLog -Message "Retrieving non-compliant Intune managed devices."

        $devices = @(Get-MgDeviceManagementManagedDevice -Property @("id", "deviceName", "azureADDeviceId", "userPrincipalName", "complianceState") -All -ErrorAction Stop)
        $nonCompliantDevices = $devices | Where-Object { $_.ComplianceState -ne "compliant" }

        $result = @()
        foreach ($device in $nonCompliantDevices) {
            $policyStates = @()

            try {
                if (Get-Command -Name Get-MgDeviceManagementManagedDeviceCompliancePolicyState -ErrorAction SilentlyContinue) {
                    $policyStates = @(Get-MgDeviceManagementManagedDeviceCompliancePolicyState -ManagedDeviceId $device.Id -ErrorAction Stop)
                }
                else {
                    $escapedDeviceId = [System.Uri]::EscapeDataString($device.Id)
                    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$escapedDeviceId/deviceCompliancePolicyStates"
                    $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop

                    if ($response.value) {
                        $policyStates = @($response.value)
                    }
                }
            }
            catch {
                Write-IntuneLog -Message "Unable to retrieve compliance policy states for device '$($device.Id)'. Skipping policy details." -Level "WARN" -Exception $_
            }

            $selectedPolicyStates = @(
                $policyStates | Select-Object `
                    @{ Name = "DisplayName"; Expression = { $_.DisplayName } },
                    @{ Name = "State"; Expression = { $_.State } },
                    @{ Name = "PlatformType"; Expression = { $_.PlatformType } },
                    @{ Name = "SettingCount"; Expression = { $_.SettingCount } },
                    @{ Name = "LastReportedDateTime"; Expression = { $_.LastReportedDateTime } }
            )

            $result += [pscustomobject]@{
                Id                   = $device.Id
                DeviceName           = $device.DeviceName
                AzureADDeviceId      = $device.AzureADDeviceId
                UserPrincipalName    = $device.UserPrincipalName
                ComplianceState      = $device.ComplianceState
                NonCompliantPolicies  = $selectedPolicyStates | Where-Object { $_.State -ne "compliant" }
            }
        }
        return $result
    }
    catch {
        Write-IntuneLog -Message "Failed to retrieve non-compliant devices." -Level "ERROR" -Exception $_
        throw
    }
}

# function to get local admin password for a device
function Get-IntuneDeviceLocalAdminPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId
    )

    try {
        $identity = Resolve-IntuneManagedDeviceIdentity -ManagedDeviceId $ManagedDeviceId
        Write-IntuneLog -Message "Retrieving local admin password for device '$($identity.DeviceName)' using directory device ID '$($identity.DirectoryDeviceId)'."

        $response = $null

        try {
            $response = Get-MgDirectoryDeviceLocalCredential `
                -DeviceLocalCredentialInfoId $identity.DirectoryDeviceId `
                -Property @("id", "deviceName", "lastBackupDateTime", "refreshDateTime", "credentials") `
                -ErrorAction Stop
        }
        catch {
            # Fallback to raw request with an explicit User-Agent header if cmdlet execution fails.
            $escapedDeviceId = [System.Uri]::EscapeDataString($identity.DirectoryDeviceId)
            $uri = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials/$escapedDeviceId?`$select=id,deviceName,lastBackupDateTime,refreshDateTime,credentials"
            $response = Invoke-MgGraphRequest `
                -Method GET `
                -Uri $uri `
                -Headers @{ "User-Agent" = "IntuneManager/1.0" } `
                -ErrorAction Stop
        }

        $credentials = @($response.credentials)

        if ($credentials.Count -eq 0) {
            Write-IntuneLog -Message "No local admin password found for device '$($identity.DeviceName)'." -Level "WARN"
            return @()
        }

        $latestCredential = $credentials |
            Sort-Object -Property @{ Expression = { $_.backupDateTime }; Descending = $true } |
            Select-Object -First 1

        $result = foreach ($credential in @($latestCredential)) {
            $decodedPassword = $null
            if (-not [string]::IsNullOrWhiteSpace($credential.passwordBase64)) {
                try {
                    $passwordBytes = [Convert]::FromBase64String($credential.passwordBase64)
                    $decodedPassword = [System.Text.Encoding]::UTF8.GetString($passwordBytes).TrimEnd([char]0)

                    if ($decodedPassword -match "`0") {
                        $decodedPassword = [System.Text.Encoding]::Unicode.GetString($passwordBytes).TrimEnd([char]0)
                    }
                }
                catch {
                    $decodedPassword = $credential.passwordBase64
                }
            }

            [pscustomobject]@{
                ManagedDeviceId   = $identity.ManagedDeviceId
                AzureADDeviceId   = $identity.AzureADDeviceId
                DirectoryDeviceId = $identity.DirectoryDeviceId
                DeviceName        = $response.deviceName
                LastBackupDateTime = $response.lastBackupDateTime
                RefreshDateTime   = $response.refreshDateTime
                AccountName       = $credential.accountName
                AccountSid        = $credential.accountSid
                BackupDateTime    = $credential.backupDateTime
                Password          = $decodedPassword
                PasswordBase64    = $credential.passwordBase64
            }
        }

        Write-IntuneLog -Message "Successfully retrieved local admin password for device '$($identity.DeviceName)'."
        return @($result)
    }
    catch {
        Write-IntuneLog -Message "Failed to retrieve local admin password for device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}

# function to reset local admin password for a device
function Reset-IntuneDeviceLocalAdminPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId
    )

    try {
        Test-IntuneGraphConnection | Out-Null
        Write-IntuneLog -Message "Resetting local admin password for device '$ManagedDeviceId'."

        $escapedDeviceId = [System.Uri]::EscapeDataString($ManagedDeviceId)
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$escapedDeviceId/rotateLocalAdminPassword"

        Invoke-MgGraphRequest -Method POST -Uri $uri -ErrorAction Stop | Out-Null

        Write-IntuneLog -Message "Successfully reset local admin password for device '$ManagedDeviceId'."
        return $true
    }
    catch {
        Write-IntuneLog -Message "Failed to reset local admin password for device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}

#function to get bitlocker recovery keys for a device
function Get-IntuneDeviceBitLockerKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId
    )

    try {
        $identity = Resolve-IntuneManagedDeviceIdentity -ManagedDeviceId $ManagedDeviceId
        Write-IntuneLog -Message "Retrieving BitLocker recovery keys for device '$($identity.DeviceName)' using Entra device ID '$($identity.AzureADDeviceId)'."

        $candidateDeviceIds = @($identity.AzureADDeviceId, $identity.DirectoryDeviceId) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique

        $keySummaries = @()
        foreach ($candidateDeviceId in $candidateDeviceIds) {
            try {
                $candidateKeys = @(
                    Get-MgInformationProtectionBitlockerRecoveryKey `
                        -Filter "deviceId eq '$candidateDeviceId'" `
                        -All `
                        -ErrorAction Stop
                )

                if ($candidateKeys.Count -gt 0) {
                    $keySummaries = $candidateKeys
                    Write-IntuneLog -Message "Found $($candidateKeys.Count) BitLocker key summary record(s) using device ID '$candidateDeviceId'."
                    break
                }
            }
            catch {
                Write-IntuneLog -Message "BitLocker key filter query failed for device ID '$candidateDeviceId'. Trying next strategy." -Level "WARN" -Exception $_
            }
        }

        if ($keySummaries.Count -eq 0) {
            try {
                $allKeys = @(Get-MgInformationProtectionBitlockerRecoveryKey -All -ErrorAction Stop)
                $keySummaries = @($allKeys | Where-Object { $candidateDeviceIds -contains $_.DeviceId })
                if ($keySummaries.Count -gt 0) {
                    Write-IntuneLog -Message "Recovered BitLocker key summary records via unfiltered fallback query."
                }
            }
            catch {
                Write-IntuneLog -Message "Unable to list BitLocker key summaries for fallback matching." -Level "WARN" -Exception $_
            }
        }

        if ($keySummaries.Count -eq 0) {
            Write-IntuneLog -Message "No BitLocker keys found for device '$($identity.DeviceName)'." -Level "WARN"
            return @()
        }

        $result = foreach ($keySummary in $keySummaries) {
            $detail = $null
            $resolvedKeyValue = $null

            try {
                $detail = Get-MgInformationProtectionBitlockerRecoveryKey `
                    -BitlockerRecoveryKeyId $keySummary.Id `
                    -Property "key" `
                    -ErrorAction SilentlyContinue

                if ($detail) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$detail.key)) {
                        $resolvedKeyValue = [string]$detail.key
                    }
                    elseif ($detail.PSObject.Properties.Name -contains "AdditionalProperties" -and $detail.AdditionalProperties) {
                        if ($detail.AdditionalProperties.ContainsKey("key")) {
                            $resolvedKeyValue = [string]$detail.AdditionalProperties["key"]
                        }
                    }
                }
            }
            catch {
                Write-IntuneLog -Message "Unable to read BitLocker key value for key '$($keySummary.Id)' via SDK detail query." -Level "WARN" -Exception $_
            }

            [pscustomobject]@{
                ManagedDeviceId = $identity.ManagedDeviceId
                AzureADDeviceId = $identity.AzureADDeviceId
                DirectoryDeviceId = $identity.DirectoryDeviceId
                DeviceName      = $identity.DeviceName
                Id              = $keySummary.Id
                DeviceId        = $keySummary.DeviceId
                CreatedDateTime = $keySummary.CreatedDateTime
                VolumeType      = $keySummary.VolumeType
                Key             = $resolvedKeyValue
            }
        }

        Write-IntuneLog -Message "Successfully retrieved $($result.Count) BitLocker key(s) for device '$($identity.DeviceName)'."
        return @($result)
    }
    catch {
        Write-IntuneLog -Message "Failed to retrieve BitLocker keys for device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}

#function to reset bitlocker recovery keys for a device
function Reset-IntuneDeviceBitLockerKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId
    )

    try {
        Test-IntuneGraphConnection | Out-Null
        Write-IntuneLog -Message "Resetting BitLocker recovery keys for device '$ManagedDeviceId'."

        $escapedDeviceId = [System.Uri]::EscapeDataString($ManagedDeviceId)
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$escapedDeviceId/rotateBitLockerKeys"

        Invoke-MgGraphRequest -Method POST -Uri $uri -ErrorAction Stop | Out-Null

        Write-IntuneLog -Message "Successfully reset BitLocker keys for device '$ManagedDeviceId'."
        return $true
    }
    catch {
        Write-IntuneLog -Message "Failed to reset BitLocker keys for device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}

#funtion to initiate sync for a device
function Sync-IntuneDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedDeviceId
    )

    try {
        Test-IntuneGraphConnection | Out-Null
        Write-IntuneLog -Message "Initiating sync for device '$ManagedDeviceId'."

        $escapedDeviceId = [System.Uri]::EscapeDataString($ManagedDeviceId)
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$escapedDeviceId/syncDevice"

        Invoke-MgGraphRequest -Method POST -Uri $uri -ErrorAction Stop | Out-Null

        Write-IntuneLog -Message "Successfully initiated sync for device '$ManagedDeviceId'."
        return $true
    }
    catch {
        Write-IntuneLog -Message "Failed to initiate sync for device '$ManagedDeviceId'." -Level "ERROR" -Exception $_
        throw
    }
}
