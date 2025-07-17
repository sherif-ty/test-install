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
if ($proxyAnswer -eq "y" -or $proxyAnswer -eq "Y") {
    Write-Host ""
    Write-Host "Select Proxy Type:"
    Write-Host "[1] HTTP/HTTPS only"
    Write-Host "[2] HTTP/HTTPS and SOCKS"
    Write-Host "[Enter] No proxy"
    $proxyTypeAnswer = Read-Host "Enter your choice (1/2 or press Enter)"

    if ($proxyTypeAnswer -eq "1") {
        $UseProxy = $true
        $EnableTLS = $true
        $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
        $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
        # Validate HTTP proxy inputs
        if ([string]::IsNullOrWhiteSpace($HttpProxyIP) -or [string]::IsNullOrWhiteSpace($HttpProxyPort)) {
            Write-Host "ERROR: HTTP Proxy IP and Port cannot be empty." -ForegroundColor Red
            exit 1
        }
        Write-Host "HTTP proxy configured: ${HttpProxyIP}:${HttpProxyPort}"
    }
    elseif ($proxyTypeAnswer -eq "2") {
        $UseProxy = $true
        $EnableTLS = $true
        $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
        $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
        $SocksProxyIP = Read-Host "Enter SOCKS Proxy IP"
        $SocksProxyPort = Read-Host "Enter SOCKS Proxy Port"
        # Validate required proxy inputs
        if ([string]::IsNullOrWhiteSpace($HttpProxyIP) -or [string]::IsNullOrWhiteSpace($HttpProxyPort) -or
            [string]::IsNullOrWhiteSpace($SocksProxyIP) -or [string]::IsNullOrWhiteSpace($SocksProxyPort)) {
            Write-Host "ERROR: Proxy IP and Port values cannot be empty." -ForegroundColor Red
            exit 1
        }
        Write-Host "HTTP proxy configured: ${HttpProxyIP}:${HttpProxyPort}"
        Write-Host "SOCKS proxy configured: ${SocksProxyIP}:${SocksProxyPort}"
    } else {
        Write-Host "No proxy selected. Proceeding without proxy..." -ForegroundColor Yellow
    }
} else {
    Write-Host "Proxy not enabled." -ForegroundColor Yellow
}

# =========================
# Ask User for Leader IP/URL and Token
# =========================
$LeaderIP = Read-Host "Enter the Leader IP or URL"
$LeaderToken = Read-Host "Enter the cribl Leader Token"

# =========================
# Cribl Configuration Parameters
# =========================
$FleetName = "default_fleet"
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

# Base YAML content
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

# Add SOCKS proxy settings if provided
if ($UseProxy -and $SocksProxyIP -and $SocksProxyPort) {
    $ProxyConfig = @"
    proxy:
      disabled: false
      type: 5
      host: $SocksProxyIP
      port: $SocksProxyPort
"@
    # Insert proxy config after port to maintain YAML structure and correct indentation
    $YamlContent = $YamlContent -replace "(\s*port:.*)", "$1`n$ProxyConfig"
} elseif ($UseProxy) {
    # Explicitly disable proxy if only HTTP proxy is used
    $ProxyConfig = @"
    proxy:
      disabled: true
"@
    $YamlContent = $YamlContent -replace "(\s*port:.*)", "$1`n$ProxyConfig"
}

# Debugging output to verify proxy settings
Write-Host "Proxy Settings: UseProxy=$UseProxy, SocksProxyIP=$SocksProxyIP, SocksProxyPort=$SocksProxyPort"

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