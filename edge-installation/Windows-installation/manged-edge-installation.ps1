Write-Host "========== Starting Cribl Edge Setup ==========" -ForegroundColor Cyan

# =========================
# Ask if Using Proxy
# =========================
$proxyAnswer = Read-Host "Are you using a proxy? (y/n)"
Write-Host "Proxy answer: $proxyAnswer"

if ($proxyAnswer -eq "y") {
    $UseProxy = $true
    $EnableTLS = $true  # TLS enabled when proxy is used
    $ProxyType = Read-Host "Proxy type? (http/socks)"
    Write-Host "Proxy type selected: $ProxyType"

    if ($ProxyType -eq "http") {
        $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
        $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
        $SocksProxyIP = ""
        $SocksProxyPort = ""
        Write-Host "HTTP Proxy set to: ${HttpProxyIP}:${HttpProxyPort}"
    } elseif ($ProxyType -eq "socks") {
        $SocksProxyIP = Read-Host "Enter SOCKS Proxy IP"
        $SocksProxyPort = Read-Host "Enter SOCKS Proxy Port"
        $HttpProxyIP = ""
        $HttpProxyPort = ""
        Write-Host "SOCKS Proxy set to: ${SocksProxyIP}:${SocksProxyPort}"
    } else {
        Write-Host "Invalid proxy type entered. Proceeding without proxy." -ForegroundColor Yellow
        $UseProxy = $false
        $EnableTLS = $false
        $HttpProxyIP = ""
        $HttpProxyPort = ""
        $SocksProxyIP = ""
        $SocksProxyPort = ""
    }
} else {
    Write-Host "Proxy not enabled." -ForegroundColor Yellow
    $UseProxy = $false
    $EnableTLS = $false
    $HttpProxyIP = ""
    $HttpProxyPort = ""
    $SocksProxyIP = ""
    $SocksProxyPort = ""
}

# =========================
# Cribl Configuration Parameters
# =========================
$LeaderIP = "leaderip"
$EdgeToken = "token"
$FleetName = "default_fleet"
$MsiPath = "C:\Users\Administrator\test-install\Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"

Write-Host "Leader IP: $LeaderIP"
Write-Host "Edge Token: $EdgeToken"
Write-Host "Fleet: $FleetName"
Write-Host "TLS Enabled: $EnableTLS"
Write-Host "MSI Path: $MsiPath"

# =========================
# Set Proxy Environment Variables
# =========================
if ($UseProxy -and $HttpProxyIP -and $HttpProxyPort) {
    $envVars = @(
        "HTTP_PROXY=http://${HttpProxyIP}:${HttpProxyPort}",
        "HTTPS_PROXY=https://${HttpProxyIP}:${HttpProxyPort}"
    )
    $criblRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Cribl"
    if (Test-Path $criblRegistryPath) {
        Set-ItemProperty -Path $criblRegistryPath -Name Environment -Value $envVars
        Write-Host "HTTP Proxy environment variables configured:"
        $envVars | ForEach-Object { Write-Host $_ }
    } else {
        Write-Warning "Cribl registry path not found. Skipping registry proxy configuration."
    }
} else {
    Write-Host "No HTTP proxy environment variables applied."
}

# =========================
# Install Cribl MSI
# =========================
if (-Not (Test-Path $MsiPath)) {
    Write-Host "ERROR: MSI file not found at path: $MsiPath" -ForegroundColor Red
    exit 1
}

Write-Host "Running Cribl Edge MSI installation..."
$Arguments = @(
    "/i", "`"$MsiPath`"",
    "/qn",
    "MODE=`"mode-managed-edge`"",
    "HOSTNAME=`"$LeaderIP`"",
    "PORT=`"4200`"",
    "FLEET=`"$FleetName`"",
    "AUTH=`"$EdgeToken`"",
    "TLS=`"$($EnableTLS.ToString().ToLower())`"",
    "USERNAME=`"LocalSystem`"",
    "APPLICATIONROOTDIRECTORY=`"C:\Program Files\Cribl\`"",
    "/l*v", "`"$LogPath`""
)
Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow

# =========================
# Write instance.yml if missing
# =========================
$InstanceDir = "C:\ProgramData\Cribl\local\_system"
$InstanceFile = Join-Path $InstanceDir "instance.yml"

if (-Not (Test-Path $InstanceFile)) {
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
    authToken: $EdgeToken
    tls:
      disabled: $(!($EnableTLS))
  group: $FleetName
"@

    Write-Host "Writing YAML content to instance.yml..."
    $YamlContent | Set-Content -Path $InstanceFile -Encoding UTF8
    Write-Host "instance.yml written successfully."
} else {
    Write-Host "instance.yml already exists — skipping creation."
}

# =========================
# Restart Cribl Service
# =========================
Write-Host "Restarting Cribl service..." -ForegroundColor Cyan
try {
    Stop-Service -Name "cribl" -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    Start-Service -Name "cribl" -ErrorAction Stop
    Write-Host "Cribl service restarted successfully." -ForegroundColor Green
} catch {
    Write-Warning "Cribl service restart failed: $_"
}

# =========================
# Run edge-configuration.ps1
# =========================
$EdgeConfigScript = "C:\Users\Administrator\test-install\edge-installation\Windows-installation\edge-configuration.ps1"

if (Test-Path $EdgeConfigScript) {
    Write-Host "Running edge-configuration.ps1..." -ForegroundColor Cyan
    try {
        & $EdgeConfigScript
        Write-Host "edge-configuration.ps1 completed." -ForegroundColor Green
    } catch {
        Write-Error "Failed to run edge-configuration.ps1: $_"
    }
} else {
    Write-Warning "edge-configuration.ps1 not found at $EdgeConfigScript"
}

Write-Host "========== Cribl Edge Setup Finished ==========" -ForegroundColor Cyan
