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

Write-Host ""
$proxyAnswer = Read-Host "Do you want to use an HTTP proxy? [y/N]"

if ($proxyAnswer -match '^[Yy]$') {
    $UseProxy = $true
    $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
    $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
    Write-Host "Configured HTTP proxy: $HttpProxyIP`:$HttpProxyPort"
} else {
    Write-Host "No proxy will be configured." -ForegroundColor Yellow
}

# =========================
# Cribl Configuration Parameters
# =========================
$LeaderIP = "cribl.maser"
$EdgeToken = Read-Host "Enter the OnPrem Cribl Leader Token"
$FleetName = "default_fleet"

# Dynamically resolve paths
$CurrentDir = Get-Location
$MsiPath = Join-Path $CurrentDir "Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$SourceConfigPath = Join-Path $CurrentDir "edge-installation\Windows-installation\configs"
$DestConfigPath = "C:\ProgramData\Cribl\local\edge"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"

Write-Host ""
Write-Host "Leader IP: $LeaderIP"
Write-Host "Fleet Name: $FleetName"
Write-Host "TLS Enabled: $EnableTLS"
Write-Host "MSI Path: $MsiPath"
Write-Host "Source Config Path: $SourceConfigPath"
Write-Host "Destination Config Path: $DestConfigPath"

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
    "AUTH=`"$EdgeToken`"",
    "TLS=`"$($EnableTLS.ToString().ToLower())`"",
    "USERNAME=`"$CriblUsername`"",
    "APPLICATIONROOTDIRECTORY=`"C:\Program Files\Cribl\`"",
    "/l*v", "`"$LogPath`""
)

if ($CriblUsername -ne "LocalSystem" -and $UnsecurePassword) {
    $Arguments += "PASSWORD=`"$UnsecurePassword`""
}

Write-Host ""
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

    $YamlContent = @"
distributed:
  mode: managed-edge
  master:
    host: $LeaderIP
    port: 4200
    proxy:
      disabled: $(!($UseProxy))
    authToken: $EdgeToken
    tls:
      disabled: $(!($EnableTLS))
  group: $FleetName
"@

    Write-Host ""
    Write-Host "YAML content to write:"
    Write-Host $YamlContent

    $YamlContent | Set-Content -Path $InstanceFile -Encoding UTF8
    Write-Host "instance.yml written successfully."
}

# =========================
# Set HTTP Proxy Environment Variables (if applicable)
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
        Write-Warning "Cribl registry path not found. Skipping registry proxy configuration."
    }
} else {
    if (Test-Path $criblRegPath) {
        Remove-ItemProperty -Path $criblRegPath -Name "Environment" -ErrorAction SilentlyContinue
        Write-Host "Removed previous proxy settings from registry."
    }
}


# =========================
# Copy configuration files to Cribl local edge
# =========================
Write-Host "Checking configuration source path..." -ForegroundColor Cyan
if (Test-Path $SourceConfigPath) {
    Write-Host "Copying Edge configuration from $SourceConfigPath to $DestConfigPath..." -ForegroundColor Cyan
    try {
        Copy-Item -Path "$SourceConfigPath\*" -Destination $DestConfigPath -Recurse -Force
        Write-Host "Edge configuration copied successfully to $DestConfigPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to copy edge configuration: $_"
    }
} else {
    Write-Warning "Source configuration path not found: $SourceConfigPath"
}
# =========================
# Write cribl.yml if missing
# =========================
$CriblYmlPath = "C:\ProgramData\Cribl\local\edge\cribl.yml"

if (-Not (Test-Path $CriblYmlPath)) {
    Write-Host ""
    Write-Host "Creating cribl.yml at $CriblYmlPath"

    $CriblYmlContent = @"
api:
  protocol: http1.1
  retryCount: 120
  retrySleepSecs: 5
  baseUrl: ""
  disabled: true
  listenOnPort: false
  workerRemoteAccess: false
  revokeOnRoleChange: true
  authTokenTTL: 3600
  idleSessionTTL: 3600
  headers: {}
  apiCache:
    disabled: false
  ssl:
    disabled: true
  host: 127.0.0.1
  port: 9420
  loginRateLimit: 2/second
  ssoRateLimit: 2/second
auth:
  type: local
  filter_type: email_whitelist
system:
  upgrade: api
  restart: api
  installType: standalone
  intercom: true
  backups:
    backupsDirectory: \$CRIBL_STATE_DIR/backups
    backupPersistence: 24h
  rollback:
    rollbackEnabled: true
    rollbackTimeout: 30000
    rollbackRetries: 5
    checkInterval: 1000
upgradeSettings:
  upgradeSource: cdn
  disableAutomaticUpgrade: true
  enableLegacyEdgeUpgrade: false
upgradeGroupSettings:
  quantity: 100
  isRolling: true
  retryDelay: 1000
  retryCount: 5
rollback: {}
backups: {}
sockets: {}
sni:
  disableSNIRouting: false
pii:
  enablePiiDetection: false
"@

    $CriblYmlContent | Set-Content -Path $CriblYmlPath -Encoding UTF8
    Write-Host "cribl.yml written successfully." -ForegroundColor Green
}

# =========================
# Final Restart
# =========================
Write-Host "Restarting Cribl service..." -ForegroundColor Cyan
try {
    Restart-Service -Name cribl -Force -ErrorAction Stop
    Write-Host "Cribl service restarted successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to restart Cribl service. Please check the service manually."
}

Write-Host "`n========== Cribl Edge Setup Finished ==========" -ForegroundColor Cyan
