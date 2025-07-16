# Cribl Edge Windows Installer Script

Write-Host "========== Starting Cribl Edge Setup ==========" -ForegroundColor Cyan

# =========================
# Service Account Selection
# =========================

Write-Host ""
Write-Host "Choose the account Cribl Edge service will run under:"
Write-Host "[1] LocalSystem (Default)"
Write-Host "[2] Custom Service Account (domain\\username)"
$serviceChoice = Read-Host "Enter your choice (1 or 2)"

$CriblUsername = "LocalSystem"
$CriblPassword = ""
$UnsecurePassword = ""

if ($serviceChoice -eq "2") {
    $CriblUsername = Read-Host "Enter the service account username (domain\\username)"
    $CriblPassword = Read-Host "Enter the service account password" -AsSecureString

    # Convert SecureString to plain text
    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CriblPassword)
    )

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

$proxyAnswer = Read-Host "Are you using a proxy? (y/n)"
if ($proxyAnswer -eq "y") {
    $ProxyType = Read-Host "Proxy type? (http/socks)"
    $UseProxy = $true
    $EnableTLS = $true

    if ($ProxyType -eq "http") {
        $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
        $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
        Write-Host "HTTP Proxy configured: ${HttpProxyIP}:${HttpProxyPort}"
    }
    elseif ($ProxyType -eq "socks") {
        $SocksProxyIP = Read-Host "Enter SOCKS Proxy IP"
        $SocksProxyPort = Read-Host "Enter SOCKS Proxy Port"
        Write-Host "SOCKS Proxy configured: ${SocksProxyIP}:${SocksProxyPort}"
    }
    else {
        Write-Warning "Invalid proxy type entered. Skipping proxy config."
        $UseProxy = $false
        $EnableTLS = $false
    }
} else {
    Write-Host "Proxy not enabled." -ForegroundColor Yellow
}

# =========================
# Ask User for Leader Token
# =========================

$LeaderIP = "127.0.0.1"
$LeaderToken = Read-Host "Enter the ONPrem Leader Token"

# =========================
# Cribl Configuration Parameters
# =========================

$FleetName = "default_fleet"
$MsiPath = "C:\Users\$env:USERNAME\Desktop\test-install\Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"

Write-Host ""
Write-Host "Configuration:"
Write-Host "Leader IP         : $LeaderIP"
Write-Host "Leader Token      : $LeaderToken"
Write-Host "Fleet             : $FleetName"
Write-Host "TLS Enabled       : $EnableTLS"
Write-Host "MSI Path          : $MsiPath"

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
} else {
    # Remove previous proxy settings if not using proxy
    if (Test-Path $criblRegistryPath) {
        Remove-ItemProperty -Path $criblRegistryPath -Name Environment -ErrorAction SilentlyContinue
        Write-Host "Removed previous proxy environment variables from registry."
    }
}

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
# Write instance.yml if missing
# =========================

$InstanceDir = "C:\ProgramData\Cribl\local\_system"
$InstanceFile = Join-Path $InstanceDir "instance.yml"

if (-Not (Test-Path $InstanceFile)) {
    Write-Host ""
    Write-Host "Creating instance.yml at $InstanceFile"

    if (-Not (Test-Path $InstanceDir)) {
        New-Item -Path $InstanceDir -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $InstanceDir"
    }

    $ProxyDisabled = if ($UseProxy -and $SocksProxyIP -and $SocksProxyPort) { "false" } else { "true" }

    $YamlContent = @"
distributed:
  mode: managed-edge
  master:
    host: $LeaderIP
    port: 4200
    proxy:
      disabled: $ProxyDisabled
      type: 5
      host: ${SocksProxyIP}
      port: ${SocksProxyPort}
    authToken: $LeaderToken
    tls:
      disabled: $(!($EnableTLS))
  group: $FleetName
"@

    $YamlContent | Set-Content -Path $InstanceFile -Encoding UTF8
    Write-Host "instance.yml written successfully."
} else {
    Write-Host "instance.yml already exists — skipping creation."
}

# =========================
# Copy edge-configuration
# =========================

# Dynamically determine user profile and desktop path
$UserProfile = $env:USERPROFILE
$DesktopPath = Join-Path $UserProfile "Desktop"

# Path to the config folder (dynamic)
$ConfigSource = Join-Path $DesktopPath "test-install\edge-installation\Windows-installation\configs"

# Destination path for Cribl Edge config
$ConfigDest = "C:\ProgramData\Cribl\local\edge"

if (Test-Path $ConfigSource) {
    Write-Host "Copying Edge configuration files..."

    if (-Not (Test-Path $ConfigDest)) {
        New-Item -Path $ConfigDest -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $ConfigDest"
    }

    Copy-Item -Path "$ConfigSource\*" -Destination $ConfigDest -Recurse -Force
    Write-Host "Edge configuration copied successfully to $ConfigDest"
} else {
    Write-Warning "Config folder not found at $ConfigSource. Skipping Edge configuration copy."
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
