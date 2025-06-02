
# CRIBL-EDGE-INSTALLATION: Manage Cribl Edge with Python, Ansible, Linux-Bash, Windows-Bat.

 An automation tool toolkit designed to streamline the management of your Cribl environment. This project enables you to install and manage Cribl Edge nodes, orchestrate fleet operations, and configure environments using a combination of Python, Ansible, Linux Bash, and Windows Batch scripts. It leverages Cribl's API to provide scalable, scriptable control over your observability pipeline infrastructure.

This repository is modular, starting with an **Edge installer**, and will continue to expand into a full-featured toolkit for Cribl automation.

---

## Version 2.1.0

### Release Notes
Modular Installation Options
We’ve broken out the installation process into dedicated modules for each method. Whether you prefer working with Python, Ansible, Bash scripts, or Windows batch files, you now have a clean, organized module tailored to your workflow.

Included Artifacts
To make deployments even smoother, we’ve added installation artifacts for both Linux and Windows. These packages are ready to use and help speed up the setup process across different environments.
### Upcoming Changes
- Make the script set the environment proxy inside the system registry for Windows, systemd for Linux
- Dynamically create Fleets/Sub-Fleets if not found
- Manage and assign Edge nodes (move, remove, label)
- Upload and sync packs or pipelines
- Secure API integration with login token management
- Create separate module for each environment

## 1. Cribl Edge Installer

Modular Installation Support
The toolkit now includes dedicated modules for each installation method:
Python
Ansible
Linux Bash
Windows Batch
Each module is self-contained and includes its own README.md file with clear, step-by-step instructions to help you get started quickly and confidently.

Pre-Packaged Artifacts
We’ve added installation artifacts for both Linux and Windows platforms. These packages are ready to use and help streamline deployments across different systems.

during the installation the script will ask for crible leader Ip, socks proxy IP, cribl token.   
---
## Project Structure

```
CRIBL-EDGE-INSTALLATION
├── Python-installation           # python installation logic
├── Ansibl-installation           # Ansibl installation logic
├── linux-installation            # Linux installation logic
├── windows-installation          # Windows installation logic
└── README.md                     # You're reading it
```
---
---

## How to Run

```bash
git clone https://github.vodafone.com/VFGroup-TSS-AnalyticsCoE/Cribl-Edge-Installation.git
cd cribl-edge-installation
```
Choose Your Preferred Module Navigate to the folder of the method you want to use:

python/
ansible/
bash/
windows-batch/
Read the Instructions Each module contains a README.md file with detailed setup and execution steps tailored to that method.

Run the Installer Follow the instructions in the selected module’s README to execute the installation process. Make sure you have the required dependencies installed (e.g., Python 3.x, Ansible, Bash, etc.).
---

## Supported Environments 

| Environment | Action |
|------------|--------|
| **Linux** | Performs full automated installation, including Cribl-provided `install-edge.sh` logic |
| **Windows** | Prints a PowerShell command for manual execution |
| **Ansible** | Prints a `Ansible` command for manual use |
| **Python** | Prints a `Python` command for use  |

---

## Notes

- Ensure your Cribl Leader allows registration from the node you're running this on
- Use a fresh Edge token for each install (tokens are often single-use)
- This project is meant for testing, automation, and bootstrapping
---
# test-install
