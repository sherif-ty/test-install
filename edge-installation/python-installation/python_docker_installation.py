def install_docker(config):
    print("Docker installation command:")
    command = (
        f"docker run -d --privileged "
        f"-e \"CRIBL_DIST_MASTER_URL=tcp://{config['EDGE_TOKEN']}@{config['LEADER_IP']}:4200?group={config['FLEET_NAME']}\" "
        f"-e \"CRIBL_DIST_MODE=managed-edge\" "
        f"-e \"CRIBL_EDGE=1\" "
        f"-p 9420:9420 "
        f"-v \"/:/hostfs:ro\" "
        f"--restart unless-stopped "
        f"--name \"cribl-edge\" "
        f"cribl/cribl:{config['CRIBL_VERSION']}"
    )
    print(command)
