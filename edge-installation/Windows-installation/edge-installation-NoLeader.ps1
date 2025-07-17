Write-Host "`n========== Starting Cribl Edge Setup ==========" -ForegroundColor Cyan

# -------------------------
# Step 1: Define Variables
# -------------------------
$CriblMode = "managed-edge"
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$CriblInstallDir = "C:\Program Files\Cribl"
$InstanceDir = "C:\ProgramData\Cribl\local\_system"
$MsiPath = "edge-installation\Windows-installation\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "$env:WINDIR\Temp\cribl-msiexec-install.log"
$ConfigSource = "edge-installation\Windows-installation\configs"
$ConfigTarget = "$CriblInstallDir\local\edge"

# -------------------------
# Step 2: Leader Connection
# -------------------------
$LeaderFlow = Read-Host "Do you have a connection to the leader? (y/n)"
if ($LeaderFlow -eq "y") {
    $CriblMasterHost = Read-Host "Enter Leader IP (e.g., 10.2.3.173)"
    $CriblMasterPort = "4200"
    $Fleet = Read-Host "Enter sub-fleet name"
    
    $UseSocksProxy = Read-Host "Are you using SOCKS proxy? (y/n)"
    if ($UseSocksProxy -eq "y") {
        $CriblProxyDisabled = "false"
        $SocksProxyIP = Read-Host "Enter SOCKS Proxy IP"
        $SocksProxyPort = Read-Host "Enter SOCKS Proxy Port"
    } else {
        $CriblProxyDisabled = "true"
        $SocksProxyIP = "None"
        $SocksProxyPort = "None"
    }
} else {
    $CriblMasterHost = "cribl.master"
    $CriblMasterPort = "4200"
    $Fleet = "default"
    $CriblProxyDisabled = "true"
    $SocksProxyIP = "proxy.host"
    $SocksProxyPort = "12345"
}

# -------------------------
# Step 3: HTTP Proxy Setup
# -------------------------
$UseHttpProxy = Read-Host "Are you using HTTP/HTTPS proxy? (y/n)"
if ($UseHttpProxy -eq "y") {
    $HttpProxyIP = Read-Host "Enter HTTP Proxy IP"
    $HttpProxyPort = Read-Host "Enter HTTP Proxy Port"
}

# -------------------------
# Step 4: Auth Token
# -------------------------
do {
    if ($LeaderFlow -eq "y") {
      $CriblAuthToken = Read-Host "Enter On-Prem Cribl Auth Token"
    }
} while ([string]::IsNullOrWhiteSpace($CriblAuthToken))

# -------------------------
# Step 5: Install Cribl MSI
# -------------------------
if (-Not (Test-Path $MsiPath)) {
    Write-Host "ERROR: MSI file not found at $MsiPath" -ForegroundColor Red
    exit 1
}

Write-Host "`nInstalling Cribl Edge MSI..."
$Arguments = @(
    "/i", "`"$MsiPath`"",
    "/qn",
    "MODE=`"$CriblMode`"",
    "HOSTNAME=`"$CriblMasterHost`"",
    "PORT=`"$CriblMasterPort`"",
    "FLEET=`"$Fleet`"",
    "AUTH=`"$CriblAuthToken`"",
    "TLS=`"false`"",
    "USERNAME=`"LocalSystem`"",
    "APPLICATIONROOTDIRECTORY=`"$CriblInstallDir`"",
    "/l*v", "`"$LogPath`""
)

Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow

# -------------------------
# Step 6: Start Cribl (Standalone Mode) and Encrypt Token
# -------------------------
if ($LeaderFlow -ne "y") {
    Write-Host "`nStarting Cribl manually in standalone mode..."
    & "$CriblInstallDir\bin\cribl.exe" start
    Start-Sleep -Seconds 3

    $SecretPath = "$CriblInstallDir\local\cribl\auth\cribl.secret"
    $EncryptCmd = "$CriblInstallDir\bin\cribl.exe encrypt -v $CriblAuthToken -s $SecretPath"
    $HashedToken = Invoke-Expression $EncryptCmd
    Write-Host "Token encrypted for use in instance.yml"
} else {
    $HashedToken = $CriblAuthToken
    Write-Host "Using plain token for managed-edge mode"
}

# -------------------------
# Step 7: Create instance.yml
# -------------------------
if (-Not (Test-Path $InstanceDir)) {
    New-Item -Path $InstanceDir -ItemType Directory -Force | Out-Null
}

$YamlContent = @"
distributed:
  mode: $CriblMode
  master:
    host: $CriblMasterHost
    port: $CriblMasterPort
    proxy:
      disabled: $CriblProxyDisabled
      type: 5
      host: $SocksProxyIP
      port: $SocksProxyPort
    authToken: "$HashedToken"
    tls:
      disabled: false
  group: $Fleet
"@

$YamlPath = Join-Path $InstanceDir "instance.yml"
$YamlContent | Set-Content -Path $YamlPath -Encoding UTF8
Write-Host "`ninstance.yml created at $YamlPath"

# -------------------------
# Step 8: Set HTTP Proxy in Registry (if needed)
# -------------------------
$criblRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Cribl"
if ($UseHttpProxy -eq "y" -and $HttpProxyIP -and $HttpProxyPort) {
    $envVars = @(
        "HTTP_PROXY=http://${HttpProxyIP}:${HttpProxyPort}",
        "HTTPS_PROXY=https://${HttpProxyIP}:${HttpProxyPort}"
    )
    if (Test-Path $criblRegPath) {
        New-ItemProperty -Path $criblRegPath -Name "Environment" -Value $envVars -PropertyType MultiString -Force | Out-Null
        Write-Host "HTTP proxy environment variables set in registry."
    }
}

# -------------------------
# Step 9: Copy Configs (Standalone Mode)
# -------------------------
if ($LeaderFlow -ne "y") {
    Write-Host "`nWaiting 1 minute before applying configuration..."
    for ($i = 1; $i -le 6; $i++) {
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 10
    }

    if (Test-Path $ConfigSource) {
        Copy-Item -Path "$ConfigSource\*" -Destination $ConfigTarget -Recurse -Force
        Write-Host "`nConfiguration files copied to $ConfigTarget"
    } else {
        Write-Warning "Config source folder not found: $ConfigSource"
    }
}

# -------------------------
# Step 10: Enable and Restart Cribl Service
# -------------------------
Set-Service -Name "Cribl" -StartupType Automatic

Write-Host "`nRestarting Cribl service..." -ForegroundColor Yellow
try {
    Stop-Service -Name "Cribl" -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    Start-Service -Name "Cribl" -ErrorAction Stop
    Start-Sleep -Seconds 10

    $ServiceStatus = (Get-Service -Name "Cribl").Status
    if ($ServiceStatus -eq "Running") {
        Write-Host "Cribl service restarted successfully." -ForegroundColor Green
        Write-Host "`n========== Cribl Edge Setup Completed ==========" -ForegroundColor Green
    } else {
        Write-Error "Cribl service failed to start."
        exit 1
    }
} catch {
    Write-Error "Failed to restart Cribl service: $_"
    exit 1
}
