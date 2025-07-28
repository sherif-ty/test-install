# ================== Cribl Edge Setup Script ==================

Write-Host "========== Starting Cribl Edge Setup ==========" -ForegroundColor Cyan

# Load Configuration File
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir "connection-info.txt"
Write-Host "Loading config from: $ConfigPath"

if (-Not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Configuration file not found." -ForegroundColor Red
    exit 1
}

$config = @{}
Get-Content $ConfigPath | ForEach-Object {
    if ($_ -notmatch '^\s*#' -and $_ -match '=') {
        $key, $value = $_ -split '=', 2
        $cleanValue = $value -replace '\s*#.*$', ''
        $config[$key.Trim()] = $cleanValue.Trim()
    }
}
Write-Host "DEBUG: Configuration loaded: $($config.Keys -join ', ')"

# Service Account
$CriblUsername = "LocalSystem"
$UnsecurePassword = ""
if ($config["USE_SERVICE_ACCOUNT"] -match 'yes|true') {
    $CriblUsername = $config["SERVICE_USERNAME"]
    $UnsecurePassword = $config["SERVICE_PASSWORD"]
    if (-not $CriblUsername -or -not $UnsecurePassword) {
        Write-Host "ERROR: SERVICE_USERNAME and SERVICE_PASSWORD are required when USE_SERVICE_ACCOUNT is yes." -ForegroundColor Red
        exit 1
    }
    Write-Host "Using custom service account: $CriblUsername"
} else {
    Write-Host "Using LocalSystem as Cribl Edge service account."
}
Write-Host "DEBUG: Service account configured: $CriblUsername"

# Proxy Configuration
$UseProxy = $false
$EnableTLS = $false
$HttpProxyIP = $config["HTTP_PROXY_IP"]
$HttpProxyPort = $config["HTTP_PROXY_PORT"]
$SocksProxyIP = $config["SOCKS_PROXY_IP"]
$SocksProxyPort = $config["SOCKS_PROXY_PORT"]
$ProxyType = $config["PROXY_TYPE"]

if ($config["USE_PROXY"] -match 'yes|true') {
    $UseProxy = $true
    Write-Host "DEBUG: Proxy enabled with type: $ProxyType"
}

# TLS
if ($config["ENABLE_TLS"] -match 'yes|true') {
    $EnableTLS = $true
}
Write-Host "DEBUG: TLS enabled: $EnableTLS"

# Cribl Leader Info
$LeaderIP = $config["LEADER_IP"]
$LeaderToken = $config["LEADER_TOKEN"]
if (-not $LeaderIP -or -not $LeaderToken) {
    Write-Host "ERROR: LEADER_IP and LEADER_TOKEN are required." -ForegroundColor Red
    exit 1
}
Write-Host "DEBUG: Leader IP: $LeaderIP, Token: $LeaderToken"

# Optional Settings
$FleetName = $config["FLEET_NAME"]
if (-not $FleetName) { $FleetName = "default_fleet" }
Write-Host "DEBUG: Fleet name set to: $FleetName"

# Install Cribl MSI
$AppRoot = $config["APPLICATIONROOTDIRECTORY"]
$CurrentDir = Get-Location
$MsiPath = Join-Path $CurrentDir "Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"
Write-Host "DEBUG: MSI path: $MsiPath"

if (-Not (Test-Path $MsiPath)) {
    Write-Host "ERROR: MSI file not found at path: $MsiPath" -ForegroundColor Red
    exit 1
}

$Arguments = @(
    "/i", "`"$MsiPath`"",
    "/qn",
    "MODE=`"mode-managed-edge`"",
    "HOSTNAME=`"$LeaderIP`"",
    "PORT=`"4200`"",
    "FLEET=`"$FleetName`"",
    "AUTH=`"$LeaderToken`"",
    "TLS=`"$($EnableTLS.ToString().ToLower())`"",
    "USERNAME=`"$CriblUsername`"",
    "APPLICATIONROOTDIRECTORY=`"$AppRoot`"",
    "/l*v", "`"$LogPath`""
)
if ($CriblUsername -ne "LocalSystem" -and $UnsecurePassword) {
    $Arguments += "PASSWORD=`"$UnsecurePassword`""
}
Write-Host "DEBUG: MSI arguments prepared"
Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow
Write-Host "DEBUG: MSI installation triggered"

# Write instance.yml
$InstanceDir = "C:\ProgramData\Cribl\local\_system"
$InstanceFile = Join-Path $InstanceDir "instance.yml"
Write-Host "DEBUG: Writing instance.yml to $InstanceFile"

if (-not (Test-Path $InstanceDir)) {
    New-Item -Path $InstanceDir -ItemType Directory -Force | Out-Null
}

$Yaml = @()
$Yaml += "distributed:"
$Yaml += "  mode: managed-edge"
$Yaml += "  master:"
$Yaml += "    host: $LeaderIP"
$Yaml += "    port: 4200"
$Yaml += "    authToken: $LeaderToken"
$Yaml += "    tls:"
$Yaml += "      disabled: $(!($EnableTLS).ToString().ToLower())"
$Yaml += "    resiliency: none"
$Yaml += "  group: $FleetName"

if ($UseProxy -and $ProxyType -match 'http\+socks') {
    if ($SocksProxyIP -and $SocksProxyPort) {
        $Yaml += "   proxy:"
        $Yaml += "       host: $SocksProxyIP"
        $Yaml += "       port: $SocksProxyPort"
        $Yaml += "       type: 5"
    }
}

$Yaml | Set-Content -Path $InstanceFile -Encoding UTF8
Write-Host "DEBUG: instance.yml written"

# Set HTTP proxy in registry
$criblRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Cribl"
Write-Host "DEBUG: Registry path for Cribl: $criblRegistryPath"
if ($UseProxy -and ($ProxyType -match 'http' -or $ProxyType -match 'http\+socks') -and $HttpProxyIP -and $HttpProxyPort -and (Test-Path $criblRegistryPath)) {
    $envVars = @(
        "HTTP_PROXY=http://${HttpProxyIP}:${HttpProxyPort}",
        "HTTPS_PROXY=http://${HttpProxyIP}:${HttpProxyPort}"
    )
    New-ItemProperty -Path $criblRegistryPath -Name Environment -Value $envVars -PropertyType MultiString -Force | Out-Null
    Write-Host "DEBUG: Proxy environment variables set in registry"
}

# Restart Cribl Service
Write-Host "DEBUG: Attempting to restart Cribl service..."
$criblService = Get-Service | Where-Object { $_.DisplayName -like "*Cribl*" -or $_.Name -like "*Cribl*" } | Select-Object -First 1

if ($criblService) {
    Stop-Service -Name $criblService.Name -Force
    Start-Sleep -Seconds 5
    Start-Service -Name $criblService.Name
    Write-Host "Cribl service '$($criblService.Name)' restarted successfully." -ForegroundColor Green
} else {
    Write-Warning "Cribl service not found. Skipping restart."
}

Write-Host "========== Cribl Edge Setup Finished ==========" -ForegroundColor Cyan
