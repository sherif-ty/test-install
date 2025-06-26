# =========================
# Configuration Parameters
# =========================
$UseProxy = $true  # Set to $false to skip proxy configuration

# Proxy settings
$SocksProxyIP = "192.168.1.136"
$SocksProxyPort = "8080"
$HttpProxyIP = "192.168.1.100"
$HttpProxyPort = "8080"

# Cribl settings
$LeaderIP = "10.2.3.173"
$EdgeToken = "your-edge-token"
$FleetName = "your-fleet-name"
$EnableTLS = $true  # Set to $false to disable TLS

# =========================
# Set HTTP/HTTPS Proxy Environment Variables
# =========================
if ($UseProxy) {
    $envVars = @(
        "HTTP_PROXY=http://$HttpProxyIP:$HttpProxyPort",
        "HTTPS_PROXY=https://$HttpProxyIP:$HttpProxyPort"
    )
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Cribl" -Name Environment -Value $envVars
    Write-Host "Proxy environment variables set."
} else {
    $SocksProxyIP = "None"
    $SocksProxyPort = "None"
    Write-Host "Skipping proxy configuration."
}

# =========================
# Install Cribl MSI
# =========================
$MsiPath = "Artifacts\Windows Package\cribl-4.12.1-b6dd700c-win32-x64.msi"
$LogPath = "C:\Windows\Temp\cribl-msiexec-0000000000000.log"
$Command = "msiexec /i `"$MsiPath`" /qn MODE=`"mode-managed-edge`" HOSTNAME=`"$LeaderIP`" PORT=`"4200`" AUTH=`"$EdgeToken`" FLEET=`"$FleetName`""

if ($EnableTLS) {
    $Command += " TLS=`"true`""
}

$Command += " USERNAME=`"LocalSystem`" APPLICATIONROOTDIRECTORY=`"C:\Program Files\Cribl\`" /l*v `"$LogPath`""

Write-Host "Running installation command..."
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $Command -Wait

# =========================
# Write instance.yml
# =========================
$InstanceDir = "C:\ProgramData\Cribl\local\_system"
$InstanceFile = Join-Path $InstanceDir "instance.yml"

if (-not (Test-Path $InstanceDir)) {
    New-Item -Path $InstanceDir -ItemType Directory -Force | Out-Null
}

$YamlContent = @"
distributed:
  mode: managed-edge
  master:
    host: $LeaderIP
    port: 4200
    proxy:
      disabled: false
      type: 5
      host: $SocksProxyIP
      port: $SocksProxyPort
    authToken: $EdgeToken
    tls:
      disabled: $(!($EnableTLS))
  group: $FleetName
"@

$YamlContent | Set-Content -Path $InstanceFile -Encoding UTF8
Write-Host "instance.yml written to $InstanceFile"
