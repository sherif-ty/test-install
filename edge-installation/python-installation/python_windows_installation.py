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
        # Placeholder: replace with actual command if TLS disabling is needed
        subprocess.run('echo TLS disabled (placeholder)', shell=True)
    else:
        raise RuntimeError(f"Installation failed with return code {result.returncode}")

def install_windows(user_config):
    if platform.system() != "Windows":
        print("This script must be run in a Windows environment.")
        return

    # Prompt for missing info not handled in main
    leader_ip = input("Enter the Leader IP: ")
    tls = input("Enable TLS? (true/false): ").strip().lower()

    proxy_ip = user_config["socks_proxy_ip"]
    edge_token = user_config["token"]
    fleet_name = user_config["fleet"]

    if user_config["use_proxy"] == "y":
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

    print(f"Running command: {command}")
    thread = threading.Thread(target=run_command, args=(command,))
    thread.start()

if __name__ == "__main__":
    # Dummy test user_config
    test_config = {
        "fleet": "TestFleet",
        "token": "your_token_here",
        "socks_proxy_ip": "192.168.1.1",
        "socks_proxy_port": "1080",
        "https_proxy_ip": "192.168.1.1",
        "https_proxy_port": "8080",
        "use_proxy": "y"
    }
    install_windows(test_config)
