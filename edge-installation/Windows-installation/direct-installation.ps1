Write-Host "========== Starting Cribl Edge Setup ==========" -ForegroundColor Cyan

# Load Configuration File
$UserProfile = [Environment]::GetFolderPath("UserProfile")
$ConfigPath = Join-Path $UserProfile "test-install\\edge-installation\\Windows-installation\\connection-info.txt"

if (-Not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Configuration file not found at $ConfigPath" -ForegroundColor Red
    exit 1
}

$config = @{}
Get-Content $ConfigPath | ForEach-Object {
    if ($_ -notmatch '^\s*#' -and $_ -match '=') {
        $key, $value = $_ -split '=', 2
        $config[$key.Trim()] = $value.Trim()
    }
}

# Service Account
$CriblUsername = "LocalSystem"
$UnsecurePassword = ""
$CriblPassword = ""

if ($config["USE_SERVICE_ACCOUNT"] -match 'yes|YES') {
    $CriblUsername = $config["SERVICE_USERNAME"]
    $UnsecurePassword = $config["SERVICE_PASSWORD"]
    $CriblPassword = ConvertTo-SecureString $UnsecurePassword -AsPlainText -Force
    Write-Host "Service account selected: $CriblUsername"
} else {
    Write-Host "Using LocalSystem as Cribl Edge service account."
}

# Proxy Configuration
$UseProxy = $false
$EnableTLS = $false
$HttpProxyIP = ""
$HttpProxyPort = ""
$SocksProxyIP = ""
$SocksProxyPort = ""

if ($config["USE_PROXY"] -match 'yes|YES') {
    $UseProxy = $true
    $proxyType = $config["PROXY_TYPE"].ToLower()

    if ($proxyType -in @("http", "http+socks")) {
        $HttpProxyIP = $config["HTTP_PROXY_IP"]
        $HttpProxyPort = $config["HTTP_PROXY_PORT"]
        $EnableTLS = $true
    }

    if ($proxyType -eq "http+socks") {
        $SocksProxyIP = $config["SOCKS_PROXY_IP"]
        $SocksProxyPort = $config["SOCKS_PROXY_PORT"]
    }
}

if ($config.ContainsKey("ENABLE_TLS")) {
    $EnableTLS = $config["ENABLE_TLS"] -match 'yes|YES'
}

# Cribl Configuration
if (-not $config.ContainsKey("LEADER_IP") -or -not $config.ContainsKey("LEADER_TOKEN")) {
    Write-Host "ERROR: LEADER_IP or LEADER_TOKEN missing from config." -ForegroundColor Red
    exit 1
}

$LeaderIP = $config["LEADER_IP"]
$LeaderToken = $config["LEADER_TOKEN"]
$FleetName = if ($config.ContainsKey("FLEET_NAME")) { $config["FLEET_NAME"] } else { "default_fleet" }

Write-Host "`nConfiguration:"
Write-Host "Leader IP/URL     : $LeaderIP"
Write-Host "Leader Token      : $LeaderToken"
Write-Host "Fleet             : $FleetName"
Write-Host "TLS Enabled       : $EnableTLS"

# Install Cribl MSI
$MsiPath = "C:\\Users\\$env:USERNAME\\test-install\\Artifacts\\Windows Package\\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = \"$env:WINDIR\\Temp\\cribl-msiexec-install.log\"

if (-Not (Test-Path $MsiPath)) {
    Write-Host "ERROR: MSI file not found at path: $MsiPath" -ForegroundColor Red
    exit 1
}

Write-Host "`nRunning Cribl Edge MSI installation..."

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
    "APPLICATIONROOTDIRECTORY=`"C:\\Program Files\\Cribl\\`"",
    "/l*v", "`"$LogPath`""
)

if ($CriblUsername -ne "LocalSystem" -and $UnsecurePassword) {
    $Arguments += "PASSWORD=`"$UnsecurePassword`""
}

Write-Host "`nMSIEXEC Arguments:"
$Arguments | ForEach-Object { Write-Host $_ }

Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow

# Write instance.yml
$InstanceDir = "C:\\ProgramData\\Cribl\\local\\_system"
$InstanceFile = Join-Path $InstanceDir "instance.yml"

Write-Host "`nCreating or updating instance.yml at $InstanceFile"

if (-Not (Test-Path $InstanceDir)) {
    New-Item -Path $InstanceDir -ItemType Directory -Force | Out-Null
    Write-Host "Created directory: $InstanceDir"
}

$YamlLines = @()
$YamlLines += "distributed:"
$YamlLines += "  mode: managed-edge"
$YamlLines += "  master:"
$YamlLines += "    host: $LeaderIP"
$YamlLines += "    port: 4200"
$YamlLines += "    authToken: $LeaderToken"
$YamlLines += "    tls:"
$YamlLines += "      disabled: $(!($EnableTLS).ToString().ToLower())"
$YamlLines += "    resiliency: none"
$YamlLines += "  group: $FleetName"

if ($UseProxy) {
    $YamlLines += "  proxy:"
    if ($SocksProxyIP -and $SocksProxyPort) {
        $YamlLines += "    disabled: false"
        $YamlLines += "    type: 5"
        $YamlLines += "    host: $SocksProxyIP"
        $YamlLines += "    port: $SocksProxyPort"
    } else {
        $YamlLines += "    disabled: true"
    }
}

$YamlLines | Set-Content -Path $InstanceFile -Encoding UTF8
Write-Host "instance.yml written successfully."

# Write Proxy Environment Variables (if any)
$criblRegistryPath = "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Cribl"

if ($UseProxy -and $HttpProxyIP -and $HttpProxyPort) {
    $envVars = @(
        "HTTP_PROXY=http://${HttpProxyIP}:${HttpProxyPort}",
        "HTTPS_PROXY=https://${HttpProxyIP}:${HttpProxyPort}"
    )

    if (Test-Path $criblRegistryPath) {
        New-ItemProperty -Path $criblRegistryPath -Name Environment -Value $envVars -PropertyType MultiString -Force | Out-Null
        Write-Host "HTTP proxy environment variables set in registry:"
        $envVars | ForEach-Object { Write-Host $_ }
    } else {
        Write-Warning "Cribl registry path not found. Skipping proxy registry configuration."
    }
}

# Restart Cribl Service
Write-Host "`nRestarting Cribl service..."

try {
    Stop-Service -Name "cribl" -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    Start-Service -Name "cribl" -ErrorAction Stop
    Write-Host "Cribl service restarted successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to restart Cribl service: $_"
}

Write-Host "`n========== Cribl Edge Setup Finished ==========" -ForegroundColor Cyan
