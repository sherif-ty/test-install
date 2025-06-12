import sys
import platform

# These imports should be adjusted if directory structure changes
from python_windows_installation import install_windows
from python_linux_installation import install_linux

# -------------------- Helper Functions -------------------- #

def get_user_input(prompt, default=None):
    user_input = input(prompt).strip()
    return user_input if user_input else default

def validate_input(prompt):
    while True:
        value = input(prompt).strip()
        if value:
            return value
        print("Input cannot be empty. Please try again.")

def get_proxy_details(proxy_type):
    proxy_ip = validate_input(f"Enter the {proxy_type} proxy IP: ")
    proxy_port = validate_input(f"Enter the {proxy_type} proxy port: ")
    return proxy_ip, proxy_port

def collect_user_config():
    print("\nWelcome to the Cribl Edge Installer")
    print("-----------------------------------")

    fleet = validate_input("Enter your Fleet or Subfleet name: ")
    token = validate_input("Enter the authentication token you were given: ")

    while True:
        use_proxy = input("Will this node use a proxy? (y/n): ").strip().lower()
        if use_proxy == 'y':
            socks_proxy_ip, socks_proxy_port = get_proxy_details("SOCKS")
            https_proxy_ip, https_proxy_port = get_proxy_details("HTTPS")
            break
        elif use_proxy == 'n':
            socks_proxy_ip = "None"
            socks_proxy_port = "None"
            https_proxy_ip = "None"
            https_proxy_port = "None"
            break
        else:
            print("Please answer with 'y' for yes or 'n' for no.")

    print("\nConfiguration Summary:")
    print("-----------------------")
    print(f"Fleet/Subfleet: {fleet}")
    print(f"Authentication Token: {token}")
    if use_proxy == 'y':
        print("Proxy Settings:")
        print(f"  SOCKS Proxy: {socks_proxy_ip}:{socks_proxy_port}")
        print(f"  HTTPS Proxy: {https_proxy_ip}:{https_proxy_port}")
    else:
        print("Proxy: Not in use")

    print("-----------------------")
    while True:
        confirm = input("Do you want to proceed with these settings? (y/n): ").strip().lower()
        if confirm == 'y':
            break
        elif confirm == 'n':
            print("\nLet's re-enter the configuration.")
            return collect_user_config()
        else:
            print("Please enter 'y' to continue or 'n' to reconfigure.")

    return {
        "fleet": fleet,
        "token": token,
        "socks_proxy_ip": socks_proxy_ip,
        "socks_proxy_port": socks_proxy_port,
        "https_proxy_ip": https_proxy_ip,
        "https_proxy_port": https_proxy_port,
        "use_proxy": use_proxy
    }

# ------------------------ Main Entry ------------------------ #

def main():
    try:
        user_config = collect_user_config()
        system_type = platform.system().lower()

        if system_type == "windows":
            install_windows(user_config)
        elif system_type == "linux":
            install_linux(user_config)
        else:
            raise ValueError(f"This script does not support your OS: {system_type}")

    except Exception as error:
        print("\nAn error occurred during installation:")
        print(error)
        sys.exit(1)

if __name__ == "__main__":
    main()
