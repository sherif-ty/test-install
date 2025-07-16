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

Write-Host ""
$proxyAnswer = Read-Host "Do you want to use a proxy? Choose:`n[1] HTTP/S only`n[2] HTTP/S and SOCKS`n[Enter] for No Proxy"

switch ($proxyAnswer) {
    "1" {
        $UseProxy = $true
        $EnableTLS = $false
        $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
        $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
        Write-Host "Configured HTTP proxy: $HttpProxyIP`:$HttpProxyPort"
    }
    "2" {
        $UseProxy = $true
        $EnableTLS = $true
        $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
        $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
        Write-Host "Configured HTTP proxy: $HttpProxyIP`:$HttpProxyPort"
        $SocksProxyIP = Read-Host "Enter SOCKS Proxy IP"
        $SocksProxyPort = Read-Host "Enter SOCKS Proxy Port"
        Write-Host "Configured SOCKS proxy: $SocksProxyIP`:$SocksProxyPort"
    }
    default {
        Write-Host "No proxy will be configured." -ForegroundColor Yellow
    }
}

# =========================
# Ask for Leader IP and Token
# =========================
Write-Host ""
$LeaderIP = Read-Host "Enter the Cribl Leader IP or hostname"
$LeaderToken = Read-Host "Enter the Cribl Leader Auth Token"

# =========================
# Cribl Configuration Parameters
# =========================
$FleetName = "default_fleet"
$MsiPath = "C:\Users\$env:USERNAME\Desktop\test-install\Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"

Write-Host ""
Write-Host "Leader IP: $LeaderIP"
Write-Host "Leader Token: $LeaderToken"
Write-Host "Fleet Name: $FleetName"
Write-Host "TLS Enabled: $EnableTLS"
Write-Host "MSI Path: $MsiPath"

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

Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow

# =========================
# Write instance.yml (always overwrite)
# =========================
$InstanceDir = "C:\ProgramData\Cribl\local\_system"
$InstanceFile = Join-Path $InstanceDir "instance.yml"

Write-Host ""
Write-Host "Creating instance.yml at $InstanceFile"

if (-Not (Test-Path $InstanceDir)) {
    New-Item -Path $InstanceDir -ItemType Directory -Force | Out-Null
    Write-Host "Created directory: $InstanceDir"
}

$EnableTlsDisabled = if ($EnableTLS) { "false" } else { "true" }

# Compose YAML dynamically
$YamlLines = @()
$YamlLines += "distributed:"
$YamlLines += "  mode: managed-edge"
$YamlLines += "  master:"
$YamlLines += "    host: $LeaderIP"
$YamlLines += "    port: 4200"

# Only write proxy block if SOCKS proxy is configured
if ($SocksProxyIP -and $SocksProxyPort) {
    $YamlLines += "    proxy:"
    $YamlLines += "      disabled: false"
    $YamlLines += "      type: 5"
    $YamlLines += "      host: $SocksProxyIP"
    $YamlLines += "      port: $SocksProxyPort"
}

$YamlLines += "    authToken: $LeaderToken"
$YamlLines += "    tls:"
$YamlLines += "      disabled: $EnableTlsDisabled"
$YamlLines += "  group: $FleetName"

$YamlContent = $YamlLines -join "`n"

Write-Host ""
Write-Host "YAML content to write:"
Write-Host $YamlContent

$YamlContent | Set-Content -Path $InstanceFile -Encoding UTF8
Write-Host "instance.yml written successfully."

# =========================
# Restart Cribl Service
# =========================
Write-Host ""
Write-Host "Restarting Cribl service..." -ForegroundColor Yellow

try {
    Write-Host "Stopping Cribl service..."
    Stop-Service -Name "Cribl" -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    Write-Host "Starting Cribl service..."
    Start-Service -Name "Cribl" -ErrorAction Stop
    Write-Host "Cribl service restarted successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to restart Cribl service: $_"
}

# =========================
# Set HTTP Proxy in Registry (AFTER install)
# =========================
$criblRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Cribl"

if ($UseProxy -and $HttpProxyIP -and $HttpProxyPort) {
    $envVars = @(
        "HTTP_PROXY=http://${HttpProxyIP}:${HttpProxyPort}",
        "HTTPS_PROXY=https://${HttpProxyIP}:${HttpProxyPort}"
    )

    if (Test-Path $criblRegPath) {
        New-ItemProperty -Path $criblRegPath -Name "Environment" -Value $envVars -PropertyType MultiString -Force | Out-Null
        Write-Host ""
        Write-Host "HTTP proxy environment variables set in registry:"
        $envVars | ForEach-Object { Write-Host $_ }
    } else {
        Write-Warning "Cribl registry path not found after install. Skipping registry proxy configuration."
    }
} else {
    if (Test-Path $criblRegPath) {
        Remove-ItemProperty -Path $criblRegPath -Name "Environment" -ErrorAction SilentlyContinue
        Write-Host "Removed previous proxy settings from registry."
    }
}

Write-Host ""
Write-Host "========== Cribl Edge Setup Finished ==========" -ForegroundColor Cyan
