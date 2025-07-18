Write-Host "========== Starting Cribl Edge Setup ==========" -ForegroundColor Cyan

# =========================
# Load Configuration File
# =========================
$UserProfile = [Environment]::GetFolderPath("UserProfile")
$ConfigPath = Join-Path $UserProfile "Cribl-Edge-Installation\edge-installation\Windows-installation\connection-info.txt"

if (-Not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Configuration file not found at $ConfigPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigPath | Where-Object { $_ -notmatch '^#' -and $_ -match '=' } |
    ForEach-Object {
        $parts = $_ -split '=', 2
        @{ Key = $parts[0].Trim(); Value = $parts[1].Trim() }
    } | Group-Object -AsHashTable -AsString

# =========================
# Service Account
# =========================
$CriblUsername = "LocalSystem"
$CriblPassword = ""
$UnsecurePassword = ""

if ($config["USE_SERVICE_ACCOUNT"] -match 'yes|YES') {
    $CriblUsername = $config["SERVICE_USERNAME"]
    $UnsecurePassword = $config["SERVICE_PASSWORD"]
    $CriblPassword = ConvertTo-SecureString $UnsecurePassword -AsPlainText -Force
    Write-Host "Service account selected: $CriblUsername"
} else {
    Write-Host "Using LocalSystem as Cribl Edge service account."
}

# =========================
# Proxy Configuration
# =========================
$UseProxy = $false
$EnableTLS = $false
$HttpProxyIP = ""
$HttpProxyPort = ""
$SocksProxyIP = ""
$SocksProxyPort = ""

if ($config["USE_PROXY"] -match 'yes|YES') {
    $UseProxy = $true
    $proxyType = $config["PROXY_TYPE"].ToLower()

    if ($proxyType -eq "http" -or $proxyType -eq "http+socks") {
        $HttpProxyIP = $config["HTTP_PROXY_IP"]
        $HttpProxyPort = $config["HTTP_PROXY_PORT"]
        $EnableTLS = $true
    }

    if ($proxyType -eq "http+socks") {
        $SocksProxyIP = $config["SOCKS_PROXY_IP"]
        $SocksProxyPort = $config["SOCKS_PROXY_PORT"]
    }
}

# Optional TLS override
if ($config.ContainsKey("ENABLE_TLS")) {
    $EnableTLS = $config["ENABLE_TLS"] -match 'yes|YES'
}

# =========================
# Cribl Configuration
# =========================
$LeaderIP = $config["LEADER_IP"]
$LeaderToken = $config["LEADER_TOKEN"]
$FleetName = if ($config.ContainsKey("FLEET_NAME")) { $config["FLEET_NAME"] } else { "default_fleet" }

# Static paths
$MsiPath = "C:\Users\$env:USERNAME\Desktop\test-install\Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"

Write-Host ""
Write-Host "Configuration:"
Write-Host "Leader IP/URL     : $LeaderIP"
Write-Host "Leader Token      : $LeaderToken"
Write-Host "Fleet             : $FleetName"
Write-Host "TLS Enabled       : $EnableTLS"
Write-Host "MSI Path          : $MsiPath"

# =========================
# Install Cribl MSI
# =========================
if (-Not (Test-Path $MsiPath)) {
    Write-Host "ERROR: MSI file not found at path: $MsiPath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Running Cribl Edge MSI installation..."

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
    "APPLICATIONROOTDIRECTORY=`"C:\Program Files\Cribl\`"",
    "/l*v", "`"$LogPath`""
)

if ($CriblUsername -ne "LocalSystem" -and $UnsecurePassword) {
    $Arguments += "PASSWORD=`"$UnsecurePassword`""
}

Write-Host "MSIEXEC Arguments:"
$Arguments | ForEach-Object { Write-Host $_ }

Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow

# =========================
# Write instance.yml
# =========================
$InstanceDir = "C:\ProgramData\Cribl\local\_system"
$InstanceFile = Join-Path $InstanceDir "instance.yml"

Write-Host ""
Write-Host "Creating or updating instance.yml at $InstanceFile"

if (-Not (Test-Path $InstanceDir)) {
    New-Item -Path $InstanceDir -ItemType Directory -Force | Out-Null
    Write-Host "Created directory: $InstanceDir"
}

$YamlContent = @"
distributed:
  mode: managed-edge
  master:
    host: $LeaderIP
    port: 4200
    authToken: $LeaderToken
    tls:
      disabled: $(!($EnableTLS))
    resiliency: none
  group: $FleetName
"@

if ($UseProxy -and $SocksProxyIP -and $SocksProxyPort) {
    $ProxyConfig = @"
    proxy:
      disabled: false
      type: 5
      host: $SocksProxyIP
      port: $SocksProxyPort
"@
    $YamlContent = $YamlContent -replace "(\s*port:.*)", "$1`n$ProxyConfig"
} elseif ($UseProxy) {
    $ProxyConfig = @"
    proxy:
      disabled: true
"@
    $YamlContent = $YamlContent -replace "(\s*port:.*)", "$1`n$ProxyConfig"
}

$YamlContent | Set-Content -Path $InstanceFile -Encoding UTF8
Write-Host "instance.yml written successfully."

# =========================
# Write Proxy Environment Variables (if any)
# =========================
$criblRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Cribl"

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

# =========================
# Restart Cribl Service
# =========================
Write-Host ""
Write-Host "Restarting Cribl service..."

try {
    Stop-Service -Name "cribl" -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    Start-Service -Name "cribl" -ErrorAction Stop
    Write-Host "Cribl service restarted successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to restart Cribl service: $_"
}

Write-Host ""
Write-Host "========== Cribl Edge Setup Finished ==========" -ForegroundColor Cyan
