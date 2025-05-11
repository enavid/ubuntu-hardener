# 🔐 Ubuntu Security Hardening Script

This script automates basic Ubuntu server hardening steps. It interactively asks for user input to customize the setup.

---

## 🚀 Quick Run

Run this one-liner on your Ubuntu server:

```bash
curl -O https://raw.githubusercontent.com/enavid/ubuntu-hardener/main/harden.sh | bash
chmod +x harden.sh
./harden.sh
```

---

## 🛡️ What the Script Does

1. **Updates all packages** using `apt update && apt upgrade`
2. **Prompts for a new SSH port** and configures it
3. **Prompts for firewall ports to allow** (e.g., `80,443,22`)
4. **Installs UFW firewall** and applies your custom rules
5. **Optionally creates a new user** and adds them to the sudo group
6. **Disables root login over SSH** for better security
7. **Restarts SSH service** to apply changes
8. **Performs basic cleanup** with `apt autoremove`

---

## ⚠️ Important Notes

- Make sure the **new SSH port** is allowed in your cloud provider’s firewall or security group before running this script.
- After the script finishes, you will no longer be able to log in as root via SSH.
- It is strongly recommended to create a **new sudo user** for administrative access.

---

## 🧩 Requirements

- Ubuntu server
- Must be run as `root` or with `sudo`
