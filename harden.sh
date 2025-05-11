#!/bin/bash
set -e

# Define ANSI colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}[*] Updating system packages...${NC}"
apt update && apt upgrade -y && apt dist-upgrade -y

# Ask for SSH port
read -p "$(echo -e ${YELLOW}Enter the new SSH port you want to use (e.g., 2222): ${NC})" SSH_PORT

# Ask for firewall ports
read -p "$(echo -e ${YELLOW}Enter comma-separated TCP ports to allow (e.g., 22,80,443): ${NC})" TCP_PORTS
read -p "$(echo -e ${YELLOW}Enter comma-separated UDP ports to allow (optional, e.g., 53,123): ${NC})" UDP_PORTS

echo -e "${BLUE}[*] Installing and configuring UFW firewall...${NC}"
apt install ufw -y
ufw default deny incoming
ufw default allow outgoing

# Ensure SSH port is added to TCP_PORTS
if [[ "$TCP_PORTS" != *"$SSH_PORT"* ]]; then
  TCP_PORTS="$TCP_PORTS,$SSH_PORT"
fi

# Allow TCP ports
IFS=',' read -ra TCP <<< "$TCP_PORTS"
for port in "${TCP[@]}"; do
    ufw allow "$port"/tcp
done

# Allow UDP ports if specified
IFS=',' read -ra UDP <<< "$UDP_PORTS"
for port in "${UDP[@]}"; do
    ufw allow "$port"/udp
done

ufw enable

# Change SSH port
echo -e "${BLUE}[*] Changing SSH port to $SSH_PORT...${NC}"
sed -i "s/^#Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config

# Ask to create a new user
read -p "$(echo -e ${YELLOW}Do you want to create a new sudo user? (y/n): ${NC})" CREATE_USER
if [[ "$CREATE_USER" == "y" || "$CREATE_USER" == "Y" ]]; then
    read -p "$(echo -e ${YELLOW}Enter the new username: ${NC})" NEW_USER
    adduser "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    echo -e "${GREEN}[+] User $NEW_USER created and added to sudo group.${NC}"
fi

# Disable root login
echo -e "${BLUE}[*] Disabling root login via SSH...${NC}"
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

# Clean up
echo -e "${BLUE}[*] Removing unnecessary packages...${NC}"
apt autoremove -y
apt autoclean -y

# Restart SSH service
systemctl restart ssh

# Install fail2ban if not installed
if ! command -v fail2ban-server &>/dev/null; then
    echo -e "${BLUE}[*] Installing fail2ban...${NC}"
    apt install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
fi

# Configure fail2ban
echo -e "${BLUE}[*] Configuring Fail2Ban...${NC}"
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 72h
findtime = 10m
EOF

systemctl restart fail2ban

echo -e "${GREEN}[✓] Fail2Ban configured: users with 5 failed SSH attempts will be blocked for 72 hours.${NC}"

# Final message
echo -e "${GREEN}[✓] Security hardening completed. Rebooting now...${NC}"

# Show details
echo -e "${GREEN}"
echo "-----------------------------------------"
echo "  Security hardening summary:"
echo " - System updated (apt + dist-upgrade)"
echo " - SSH port set to: $SSH_PORT"
echo " - UFW firewall installed and configured"
echo "   • TCP ports allowed: $TCP_PORTS"
if [[ ! -z "$UDP_PORTS" ]]; then
  echo "   • UDP ports allowed: $UDP_PORTS"
fi
echo " - Root SSH login disabled"
[[ ! -z "$NEW_USER" ]] && echo " - New sudo user created: $NEW_USER"
echo " - Fail2Ban installed and configured"
echo "-----------------------------------------"
echo -e "${NC}"

# Reboot server
read -p "$(echo -e ${YELLOW}Do you want to reboot now to apply all changes? (y/n): ${NC})" REBOOT_CONFIRM
if [[ "$REBOOT_CONFIRM" == "y" || "$REBOOT_CONFIRM" == "Y" ]]; then
    echo -e "${BLUE}Rebooting now...${NC}"
    reboot now
else
    echo -e "${YELLOW}Reboot skipped. Please reboot manually later to apply all settings properly.${NC}"
fi

