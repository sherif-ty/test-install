import platform
import subprocess
import threading

def set_proxy_environment(proxy_ip):
    ps_script = f"""
    $socksenvironment = [string[]]@(
        "CRIBL_DIST_WORKER_PROXY=socks5://{proxy_ip}:1080",
        "HTTP_PROXY=http://{proxy_ip}:8080",
        "HTTPS_PROXY=https://{proxy_ip}:8080"
    )
    Set-ItemProperty HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Cribl -Name Environment -Value $socksenvironment
    Write-Host "Environment variables set successfully."
    """
    subprocess.run(["powershell", "-Command", ps_script], capture_output=True, text=True)

def run_command(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    print(f"Standard error: {result.stderr}")
    if result.returncode == 0:
        print("Installation done successfully.")
        subprocess.run('some_command_to_disable_tls', shell=True)
    else:
        raise RuntimeError(f"Installation failed with return code {result.returncode}")

def install_windows():
    proxy_ip = input("Enter the SOCKS proxy IP (e.g., 192.168.1.136): ")
    leader_ip = input("Enter the Leader IP: ")
    edge_token = input("Enter the Edge Token: ")
    fleet_name = input("Enter the Fleet Name: ")
    tls = input("Enable TLS? (true/false): ").lower()

    set_proxy_environment(proxy_ip)

    config = {
        "For_Windows_cribl_pkg_url": "Artifacts\\Windows Package\\cribl-4.10.0-22f23292-win32-x64.msi",
        "LEADER_IP": leader_ip,
        "EDGE_TOKEN": edge_token,
        "FLEET_NAME": fleet_name,
        "TLS": tls,
        "LOG_PATH": "C:\\Windows\\Temp\\cribl-msiexec-0000000000000.log"
    }

    command = (
        f'msiexec /i "{config["For_Windows_cribl_pkg_url"]}" /qn '
        f'MODE="mode-managed-edge" HOSTNAME="{config["LEADER_IP"]}" PORT="4200" '
        f'AUTH="{config["EDGE_TOKEN"]}" FLEET="{config["FLEET_NAME"]}" '
        f'TLS="{config["TLS"]}" USERNAME="LocalSystem" '
        f'APPLICATIONROOTDIRECTORY="C:\\Program Files\\Cribl\\" '
        f'/l*v "{config["LOG_PATH"]}"'
    )

    if platform.system() == "Windows":
        print(f"Running command: {command}")
        thread = threading.Thread(target=run_command, args=(command,))
        thread.start()
    else:
        print("This script must be run in a Windows environment.")

if __name__ == "__main__":
    install_windows()
