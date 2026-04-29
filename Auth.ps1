# Microsoft Graph authentication helpers for the Intune management app.

function Write-AuthLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [System.Management.Automation.ErrorRecord]$Exception
    )

    if (Get-Command -Name Write-IntuneLog -ErrorAction SilentlyContinue) {
        Write-IntuneLog -Message $Message -Level $Level -Exception $Exception
    }
}

function Add-UserGraphModulePaths {
    [CmdletBinding()]
    param()

    $runningOnWindows = $env:OS -eq "Windows_NT"
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        $runningOnWindows = [bool]$IsWindows
    }

    if (-not $runningOnWindows) {
        return
    }

    $documentsPath = [Environment]::GetFolderPath("MyDocuments")
    $candidatePaths = @(
        (Join-Path $documentsPath "PowerShell\Modules"),
        (Join-Path $documentsPath "WindowsPowerShell\Modules")
    )

    $pathSeparator = [IO.Path]::PathSeparator
    $currentPaths = @($env:PSModulePath -split [Regex]::Escape([string]$pathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    foreach ($candidatePath in $candidatePaths) {
        if ((Test-Path -Path $candidatePath) -and ($currentPaths -notcontains $candidatePath)) {
            $env:PSModulePath = "$candidatePath$pathSeparator$env:PSModulePath"
            $currentPaths += $candidatePath
            Write-AuthLog -Message "Added module path '$candidatePath' for Microsoft Graph discovery."
        }
    }
}

function Assert-GraphSdkAvailable {
    [CmdletBinding()]
    param()

    Add-UserGraphModulePaths

    $requiredModules = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.DeviceManagement"
    )

    foreach ($moduleName in $requiredModules) {
        try {
            Import-Module -Name $moduleName -ErrorAction Stop
            Write-AuthLog -Message "Loaded module '$moduleName'."
        }
        catch {
            Write-AuthLog -Message "Missing required Microsoft Graph SDK module '$moduleName'." -Level "ERROR" -Exception $_
            throw "Microsoft Graph PowerShell SDK module '$moduleName' is not available in this PowerShell host. Install it in this host, or restart the app after installation. Example: Install-Module Microsoft.Graph -Scope CurrentUser"
        }
    }
}

function Connect-IntuneGraph {
    [CmdletBinding()]
    param(
        [ValidateSet("Interactive", "AppOnlySecret", "AppOnlyCertificate")]
        [string]$AuthMode = "Interactive",

        [string]$TenantId,

        [string]$ClientId,

        [System.Security.SecureString]$ClientSecret,

        [string]$CertificateThumbprint,

        [string]$CertificateName,

        [string[]]$Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementManagedDevices.ReadWrite.All",
            "DeviceManagementManagedDevices.PrivilegedOperations.All",
            "DeviceLocalCredential.Read.All",
            "BitlockerKey.Read.All"
        )
    )

    try {
        Assert-GraphSdkAvailable
        Write-AuthLog -Message "Connecting to Microsoft Graph using auth mode '$AuthMode'."

        switch ($AuthMode) {
            "Interactive" {
                $connectParams = @{
                    Scopes       = $Scopes
                    ContextScope = "Process"
                    NoWelcome    = $true
                    ErrorAction  = "Stop"
                }

                if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
                    $connectParams.TenantId = $TenantId
                }

                if (-not [string]::IsNullOrWhiteSpace($ClientId)) {
                    $connectParams.ClientId = $ClientId
                }

                Connect-MgGraph @connectParams
            }

            "AppOnlySecret" {
                if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientId) -or -not $ClientSecret) {
                    throw "Tenant ID, Client ID, and Client Secret are required for app-only secret authentication."
                }

                $credential = [System.Management.Automation.PSCredential]::new($ClientId, $ClientSecret)

                Connect-MgGraph `
                    -TenantId $TenantId `
                    -ClientSecretCredential $credential `
                    -ContextScope Process `
                    -NoWelcome `
                    -ErrorAction Stop
            }

            "AppOnlyCertificate" {
                if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientId)) {
                    throw "Tenant ID and Client ID are required for app-only certificate authentication."
                }

                if ([string]::IsNullOrWhiteSpace($CertificateThumbprint) -and [string]::IsNullOrWhiteSpace($CertificateName)) {
                    throw "Certificate thumbprint or certificate subject name is required for app-only certificate authentication."
                }

                $connectParams = @{
                    TenantId     = $TenantId
                    ClientId     = $ClientId
                    ContextScope = "Process"
                    NoWelcome    = $true
                    ErrorAction  = "Stop"
                }

                if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
                    $connectParams.CertificateThumbprint = $CertificateThumbprint
                }
                else {
                    $connectParams.CertificateName = $CertificateName
                }

                Connect-MgGraph @connectParams
            }
        }

        $context = Get-MgContext -ErrorAction Stop
        Write-AuthLog -Message "Connected to tenant '$($context.TenantId)' using '$($context.AuthType)' authentication."
        return $context
    }
    catch {
        Write-AuthLog -Message "Failed to connect to Microsoft Graph." -Level "ERROR" -Exception $_
        throw
    }
}

function Disconnect-IntuneGraph {
    [CmdletBinding()]
    param()

    try {
        Disconnect-MgGraph -ErrorAction Stop | Out-Null
        Write-AuthLog -Message "Disconnected from Microsoft Graph."
    }
    catch {
        Write-AuthLog -Message "Failed to disconnect from Microsoft Graph." -Level "ERROR" -Exception $_
        throw
    }
}
