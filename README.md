# Intune Management Console

Small modular PowerShell Windows Forms app for Microsoft Intune device management through the Microsoft Graph PowerShell SDK.

## Files

- `Auth.ps1`: Connects to Microsoft Graph with interactive auth, app-only client secret auth, or app-only certificate auth.
- `Functions.ps1`: Logging, device retrieval, remote wipe, and compliance status functions.
- `Main.ps1`: Simple Windows Forms user interface.

## Prerequisite

Install the Microsoft Graph PowerShell SDK:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Run

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Main.ps1
```

Optional logging variables:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Main.ps1 -LogEnabled $true -LogPath "C:\Temp\IntuneManagement.log" -DeviceLimit 200
```

In the UI, set the device limit to `0` to retrieve all managed devices.

## Permissions

Interactive authentication requests these delegated scopes:

- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementManagedDevices.ReadWrite.All`
- `DeviceManagementManagedDevices.PrivilegedOperations.All`

For app-only authentication, grant matching Microsoft Graph application permissions to the app registration and provide admin consent. The remote wipe action requires privileged Intune device permissions and the signed-in/admin identity must be allowed to perform remote device actions in Intune.
