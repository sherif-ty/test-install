
# Cribl-Py: Manage Cribl with Python

`cribl-py` is a Python-based automation tool designed to help you manage various aspects of your Cribl environment — from installing Cribl Edge nodes to managing fleets and configurations via API.

This repository is modular, starting with an **Edge installer**, and will continue to expand into a full-featured toolkit for Cribl automation.

---

## Version 2.0.0

### Release Notes
- Fixed the Windows installation script
- Added a small note for users to check the environment OS in the config file and, in case they are using Windows. `
### Upcoming Changes
- Make the script set the environment proxy inside the system registry for Windows, systemd for Linux
- Dynamically create Fleets/Sub-Fleets if not found
- Manage and assign Edge nodes (move, remove, label)
- Upload and sync packs or pipelines
- Secure API integration with login token management
- Create separate module for each environment

## 1. Cribl Edge Installer

This module provides a simple and automated way to install Cribl Edge across different environments including Linux, Windows, Docker, and Kubernetes with Python.

It supports:

during the installation the script will ask for crible leader Ip, socks proxy Ip, cribl token.   
---

## What this does

This Python-based installer:

1. Checks connectivity to the Cribl Leader
2. Prepares the system (Linux only: creates user, sets permissions)
3. Automatically downloads and installs Cribl Edge
4. Registers the Edge node with the Cribl Leader
5. Supports multiple deployment options:
   - Linux (auto-install and register)
   - Windows (generates a PowerShell command)
   - Docker (generates `docker run` command)
   - Kubernetes (generates `helm install` command)

---

## Project Structure

```
CRIBL-EDGE-INSTALLATION/
|-Python-installation
├── edge-installation/
├── docker_installation.py        # Docker installation logic
├── kubernetes_installation.py    # Kubernetes installation logic
├── linux_installation.py         # Linux installation logic
├── windows_installation.py       # Windows installation logic
├── main.py                       # Main script
├── requirements.txt              # Python dependencies (currently empty or 'requests' if needed)
├── run.sh                        # Optional shell wrapper to execute the script
└── README.md                     # You're reading it
```

---
---

## How to Run

### Option 1: Direct Python Execution

```bash
python3 main.py
```

### Option 2: Shell Wrapper

```bash
sh run.sh
```

This will:
- Install any Python dependencies from `requirements.txt`
- Run the installer and will ask for crible leader Ip, socks proxy Ip, cribl token.

---

## Supported Environments to Configure by Python

| Environment | Action |
|------------|--------|
| **Linux** | Performs full automated installation, including Cribl-provided `install-edge.sh` logic |
| **Windows** | Prints a PowerShell command for manual execution |
| **Docker** | Prints a `docker run` command for manual use |
| **Kubernetes** | Prints a `helm install` command for use with Helm charts |

---

## Notes

- Ensure your Cribl Leader allows registration from the node you're running this on
- Use a fresh Edge token for each install (tokens are often single-use)
- This project is meant for testing, automation, and bootstrapping
---
