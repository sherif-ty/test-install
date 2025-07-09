# =========================
# User Context Selection
# =========================
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$runAs = Read-Host "Do you want to run this script as Administrator or Local user? (admin/local)"

if ($runAs -eq "local" -and $IsAdmin) {
    $username = Read-Host "Enter local username (e.g., .\username)"
    $password = Read-Host "Enter password" -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential($username, $password)
    $scriptPath = $MyInvocation.MyCommand.Definition
    Write-Host "Re-launching script as local user $username..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Credential $cred -Wait
    exit
}
elseif ($runAs -eq "admin" -and -not $IsAdmin) {
    Write-Host "This script must be run as Administrator. Please right-click and choose 'Run as Administrator'." -ForegroundColor Red
    exit
}

Write-Host "========== Starting Cribl Edge Setup ==========" -ForegroundColor Cyan

# =========================
# Ask if Using Proxy
# =========================
$proxyAnswer = Read-Host "Are you using a proxy? (y/n)"
Write-Host "Proxy answer: $proxyAnswer"

if ($proxyAnswer -eq "y") {
    $UseProxy = $true
    $EnableTLS = $true
    $ProxyType = Read-Host "Proxy type? (http/socks)"
    Write-Host "Proxy type selected: $ProxyType"

    if ($ProxyType -eq "http") {
        $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
        $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
        $SocksProxyIP = ""
        $SocksProxyPort = ""
        Write-Host "HTTP Proxy set to: ${HttpProxyIP}:${HttpProxyPort}"
    }
    elseif ($ProxyType -eq "socks") {
        $SocksProxyIP = Read-Host "Enter SOCKS Proxy IP"
        $SocksProxyPort = Read-Host "Enter SOCKS Proxy Port"
        $HttpProxyIP = ""
        $HttpProxyPort = ""
        Write-Host "SOCKS Proxy set to: ${SocksProxyIP}:${SocksProxyPort}"
    }
    else {
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
$LeaderIP = "3.149.172.97"
$EdgeToken = "bNaNETXqnAck0vi4rJfXzqke8Rfp8Hz6"
$FleetName = "default_fleet"
$MsiPath = "C:\Users\Administrator\test-install\Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"

Write-Host "Leader IP: $LeaderIP"
Write-Host "Edge Token: $EdgeToken"
Write-Host "Fleet: $FleetName"
Write-Host "TLS Enabled: $EnableTLS"
Write-Host "MSI Path: $MsiPath"

# =========================
# Set Proxy Environment Variables (HTTP Only)
# =========================
if ($UseProxy -and $HttpProxyIP -and $HttpProxyPort) {
    $envVars = @(
        "HTTP_PROXY=http://${HttpProxyIP}:${HttpProxyPort}",
        "HTTPS_PROXY=https://${HttpProxyIP}:${HttpProxyPort}"
    )

    $criblRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Cribl"
    if (Test-Path $criblRegPath) {
        Set-ItemProperty -Path $criblRegPath -Name Environment -Value $envVars
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

Write-Host "MSIEXEC Arguments:"
$Arguments | ForEach-Object { Write-Host $_ }

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

    Write-Host "YAML content to write:"
    Write-Host $YamlContent

    $YamlContent | Set-Content -Path $InstanceFile -Encoding UTF8
    Write-Host "instance.yml written successfully."
} else {
    Write-Host "instance.yml already exists — skipping creation."
}

# =========================
# Restart Cribl Service
# =========================
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

Write-Host "========== Cribl Edge Setup Finished ==========" -ForegroundColor Green
