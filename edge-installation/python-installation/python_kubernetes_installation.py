def install_kubernetes(config):
    print("Kubernetes Helm command:")
    command = (
        f"helm install --repo \"https://criblio.github.io/helm-charts/\" "
        f"--version \"^{config['CRIBL_VERSION']}\" --create-namespace "
        f"-n \"cribl\" --set \"cribl.leader=tcp://{config['EDGE_TOKEN']}@{config['LEADER_IP']}?group={config['FLEET_NAME']}\" "
        f"\"cribl-edge\" edge"
    )
    print(command)
