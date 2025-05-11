#!/bin/bash

set -e

echo "[*] Updating system packages..."
apt update && apt upgrade -y && apt dist-upgrade

# Ask for SSH port
read -p "Enter the new SSH port you want to use (e.g., 2222): " SSH_PORT

# Ask for firewall ports
read -p "Enter comma-separated ports to allow through the firewall (e.g., 80,443,$SSH_PORT): " FIREWALL_PORTS

# Install UFW and configure
echo "[*] Installing and configuring UFW firewall..."
apt install ufw -y
ufw default deny incoming
ufw default allow outgoing

# Add SSH port to firewall list if not already included
if [[ "$FIREWALL_PORTS" != *"$SSH_PORT"* ]]; then
  FIREWALL_PORTS="$FIREWALL_PORTS,$SSH_PORT"
fi

# Allow user-defined ports
IFS=',' read -ra PORTS <<< "$FIREWALL_PORTS"
for port in "${PORTS[@]}"; do
    ufw allow "$port"/tcp
done
ufw enable

# Change SSH port
echo "[*] Changing SSH port to $SSH_PORT..."
sed -i "s/^#Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config

# Ask to create a new user
read -p "Do you want to create a new sudo user? (y/n): " CREATE_USER
if [[ "$CREATE_USER" == "y" || "$CREATE_USER" == "Y" ]]; then
    read -p "Enter the new username: " NEW_USER
    adduser "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    echo "[+] User $NEW_USER created and added to sudo group."
fi

# Disable root login
echo "[*] Disabling root login via SSH..."
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

# Restart SSH
systemctl restart sshd

# Clean up
echo "[*] Removing unnecessary packages..."
apt autoremove -y
apt autoclean -y

echo "[✓] Security hardening completed."
