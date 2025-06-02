import sys
import platform
from python_windows_installation import install_windows
from python_linux_installation import install_linux

#---------------------------------Functions----------------------------------------#
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
    proxy_port = validate_input(f"Enter your {proxy_type} proxy port: ")
    return proxy_ip, proxy_port

def collect_user_config():
    fleet = validate_input("Please enter your Fleet/Subfleet: ")
    token = validate_input("Please enter authentication token provided to you: ")

    while True:
        use_proxy = input("Are you using Proxy?  ('y' or 'n') : ").strip().lower()
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
            print("Wrong input! Please enter only 'y' or 'n'. Let's try again.")

    print(f"\n-----------------------------------------------------")
    print(f"Let us review what you have entered...")
    print(f"Your fleet will be : {fleet}")
    print(f"Your token will be : {token}")
    if use_proxy == 'n':
        print(f"You are not using any proxy settings")
    else:
        print(f"You are using proxy settings as follows:")
        print(f"Your SOCKS proxy is {socks_proxy_ip}:{socks_proxy_port}")
        print(f"Your HTTP/HTTPS proxy is {https_proxy_ip}:{https_proxy_port}") 
    print(f"-----------------------------------------------------")

    while True:
        happy = input("Are you happy?  ('y' or 'n') : ").strip().lower()
        if happy == 'y':
            break
        elif happy == 'n':
            print("Let's re-enter the configuration.")
            return collect_user_config()
        else:
            print("Please enter 'y' or 'n'.")

    return {
        "fleet": fleet,
        "token": token,
        "socks_proxy_ip": socks_proxy_ip,
        "socks_proxy_port": socks_proxy_port,
        "https_proxy_ip": https_proxy_ip,
        "https_proxy_port": https_proxy_port,
        "use_proxy": use_proxy
    }

#-------------------------------------Main----------------------------------------#
def main():
    try:
        user_config = collect_user_config()
        system_type = platform.system().lower()
        if system_type == "windows":
            install_windows(user_config)
        elif system_type == "linux":
            install_linux(user_config)
        else:
            raise ValueError(f"Unsupported environment: {system_type}")
    except Exception as error:
        print(f"\nInstallation failed: {error}")
        sys.exit(1)

if __name__ == "__main__":
    main()
