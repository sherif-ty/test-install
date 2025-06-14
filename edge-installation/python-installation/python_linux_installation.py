import os
import platform
import subprocess
import tarfile
import shutil

def install_linux(user_config):
    cribl_user = "cribladm"
    cribl_group = "cribladm"
    install_dir = "/opt/cribl"
    service_file = "/etc/systemd/system/cribl-edge.service"

    use_proxy = user_config.get("use_proxy", "n")
    socks_proxy_ip = user_config.get("socks_proxy_ip", "")
    socks_proxy_port = user_config.get("socks_proxy_port", "")
    https_proxy_ip = user_config.get("https_proxy_ip", "")
    https_proxy_port = user_config.get("https_proxy_port", "")
    fleet = user_config.get("fleet", "")
    token = user_config.get("token", "")

    master_host = "10.0.27.71"
    master_port = "4200"
    worker_mode = "managed-edge"
    tls_disabled = "false"

    def run(cmd):
        subprocess.run(cmd, shell=True, check=True)

    def resolve_group_id(group):
        try:
            return subprocess.check_output(["getent", "group", group]).decode().split(":")[2].strip()
        except Exception:
            return None

    # Detect system architecture
    arch = platform.machine().lower()

    # Map architecture to the appropriate Cribl tarball
    if arch == "x86_64":
        tgz_filename = "cribl-4.10.1-45136dbb-linux-x64.tgz"
    elif arch in ("aarch64", "arm64"):
        tgz_filename = "cribl-4.10.1-45136dbb-linux-arm64.tgz"
    else:
        raise RuntimeError(f"Unsupported system architecture: {arch}")

    # Construct the full path to the tarball relative to current working directory
    tgz_path = os.path.abspath("../../Artifacts/Linux_Package/" + tgz_filename)

    print("Creating Cribl user and group...")
    if shutil.which("useradd"):
        try:
            run(f"id -u {cribl_user} || useradd {cribl_user} -m -U -c 'Cribl user'")
        except subprocess.CalledProcessError:
            print("User creation failed, continuing...")

    group_id = resolve_group_id(cribl_group)
    if not group_id:
        run(f"groupadd {cribl_group}")
        group_id = resolve_group_id(cribl_group)

    print(f"Extracting Cribl tarball from {tgz_path}...")
    os.makedirs(install_dir, exist_ok=True)
    with tarfile.open(tgz_path, "r:gz") as tar:
        tar.extractall(path="/opt")

    # Rename the extracted folder if needed
    for name in os.listdir("/opt"):
        if name.startswith("cribl-") and os.path.isdir(os.path.join("/opt", name)):
            extracted_path = os.path.join("/opt", name)
            if extracted_path != install_dir:
                shutil.move(extracted_path, install_dir)
            break

    print("Configuring Cribl instance...")
    os.makedirs(f"{install_dir}/local/_system", exist_ok=True)
    instance_config_path = f"{install_dir}/local/_system/instance.yml"

    with open(instance_config_path, "w") as f:
        f.write("distributed:\n")
        f.write(f"  mode: {worker_mode}\n")
        f.write("  master:\n")
        f.write(f"    host: {master_host}\n")
        f.write(f"    port: {master_port}\n")
        if use_proxy == "y":
            f.write("    proxy:\n")
            f.write("      disabled: false\n")
            f.write("      type: 5\n")
            f.write(f"      host: {socks_proxy_ip}\n")
            f.write(f"      port: {socks_proxy_port}\n")
        f.write(f"    authToken: {token}\n")
        f.write(f"    tls:\n      disabled: {tls_disabled}\n")
        f.write(f"  group: {fleet}\n")
        f.write("  tags: []\n")

    print("Setting permissions...")
    run(f"chown -R {cribl_user}:{cribl_group} {install_dir}")

    print("Enabling Cribl service...")
    run(f"{install_dir}/bin/cribl boot-start enable -u {cribl_user}")

    if use_proxy == "y":
        print("Adding proxy settings to systemd service file...")
        proxy_env = f"Environment=HTTP_PROXY=http://{https_proxy_ip}:{https_proxy_port}\\nEnvironment=HTTPS_PROXY=https://{https_proxy_ip}:{https_proxy_port}"
        run(f"sed -i '/^\[Service\]/a {proxy_env}' {service_file}")
        run("systemctl daemon-reexec")
        run("systemctl daemon-reload")

    # print("Starting Cribl as the specified user...")
    # run(f"su - {cribl_user} -c '{install_dir}/bin/cribl start'")
    print("Restarting Cribl service using systemd...")
    run("systemctl restart cribl-edge")

