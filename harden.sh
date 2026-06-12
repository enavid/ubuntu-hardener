#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'

LOG_FILE="/var/log/hardening.log"

log() {
    echo -e "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${2:-$1}" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

error_exit() {
    log "${RED}[!] $1${NC}" "ERROR: $1"
    exit 1
}

# Root check
[[ $EUID -ne 0 ]] && error_exit "This script must be run as root."

log "${BLUE}[*] Starting Ubuntu hardening — log: $LOG_FILE${NC}"

log "${BLUE}[*] Updating system packages...${NC}"
apt update && apt upgrade -y && apt dist-upgrade -y

# --- SSH Port ---
while true; do
    read -p "$(echo -e "${YELLOW}Enter the new SSH port (1024-65535): ${NC}")" SSH_PORT
    SSH_PORT=$(echo "$SSH_PORT" | tr -d ' ')
    [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1024 && SSH_PORT <= 65535 )) && break
    log "${RED}[!] Invalid port. Enter a number between 1024 and 65535.${NC}"
done

# --- Firewall Ports ---
read -p "$(echo -e "${YELLOW}Enter comma-separated TCP ports to allow (e.g., 80,443): ${NC}")" TCP_PORTS_RAW
read -p "$(echo -e "${YELLOW}Enter comma-separated UDP ports to allow (optional, e.g., 53,123): ${NC}")" UDP_PORTS_RAW

TCP_PORTS=$(echo "$TCP_PORTS_RAW" | tr -d ' ')
UDP_PORTS=$(echo "$UDP_PORTS_RAW" | tr -d ' ')

log "${BLUE}[*] Installing and configuring UFW firewall...${NC}"
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing

# Ensure SSH port is in TCP_PORTS
if [[ "$TCP_PORTS" != *"$SSH_PORT"* ]]; then
    TCP_PORTS="${TCP_PORTS:+$TCP_PORTS,}$SSH_PORT"
fi

IFS=',' read -ra TCP_ARR <<< "$TCP_PORTS"
for port in "${TCP_ARR[@]}"; do
    [[ -n "$port" ]] && ufw allow "$port"/tcp
done

IFS=',' read -ra UDP_ARR <<< "$UDP_PORTS"
for port in "${UDP_ARR[@]}"; do
    [[ -n "$port" ]] && ufw allow "$port"/udp
done

ufw --force enable

# --- SSH Hardening ---
log "${BLUE}[*] Hardening SSH configuration...${NC}"

SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
log "${GREEN}[+] sshd_config backed up.${NC}"

set_sshd() {
    local key="$1" value="$2"
    if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
        sed -i "s/^#\?${key}.*/${key} ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

set_sshd "Port"                  "$SSH_PORT"
set_sshd "PermitRootLogin"       "no"
set_sshd "PasswordAuthentication" "no"
set_sshd "PubkeyAuthentication"  "yes"
set_sshd "MaxAuthTries"          "3"
set_sshd "X11Forwarding"         "no"
set_sshd "AllowTcpForwarding"    "no"
set_sshd "ClientAliveInterval"   "300"
set_sshd "ClientAliveCountMax"   "2"

sshd -t || error_exit "sshd_config has errors. SSH not restarted. Check ${SSHD_CONFIG}.bak.*"

# --- New User ---
read -p "$(echo -e "${YELLOW}Do you want to create a new sudo user? (y/n): ${NC}")" CREATE_USER
NEW_USER=""
if [[ "$CREATE_USER" == "y" || "$CREATE_USER" == "Y" ]]; then
    read -p "$(echo -e "${YELLOW}Enter the new username: ${NC}")" NEW_USER
    NEW_USER=$(echo "$NEW_USER" | tr -d ' ')
    if [[ -z "$NEW_USER" ]]; then
        log "${YELLOW}[!] No username entered, skipping user creation.${NC}"
        NEW_USER=""
    else
        adduser "$NEW_USER"
        usermod -aG sudo "$NEW_USER"
        log "${GREEN}[+] User $NEW_USER created and added to sudo group.${NC}"
        echo ""
        log "${YELLOW}[!] WARNING: PasswordAuthentication is disabled.${NC}"
        log "${YELLOW}    Add your SSH public key to /home/$NEW_USER/.ssh/authorized_keys${NC}"
        log "${YELLOW}    before closing this session, or you will be locked out.${NC}"
        echo ""
    fi
fi

# --- Cleanup ---
log "${BLUE}[*] Removing unnecessary packages...${NC}"
apt autoremove -y
apt autoclean -y

# --- Restart SSH ---
systemctl restart ssh
log "${GREEN}[+] SSH restarted on port $SSH_PORT.${NC}"

# --- fail2ban ---
if ! command -v fail2ban-server &>/dev/null; then
    log "${BLUE}[*] Installing fail2ban...${NC}"
    apt install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
fi

log "${BLUE}[*] Configuring Fail2Ban...${NC}"
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled  = true
port     = $SSH_PORT
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
bantime  = 72h
findtime = 10m
EOF

systemctl restart fail2ban
log "${GREEN}[+] Fail2Ban configured: 5 failed attempts → 72h ban.${NC}"

# --- Unattended Upgrades ---
log "${BLUE}[*] Enabling automatic security updates...${NC}"
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
log "${GREEN}[+] Automatic security updates enabled.${NC}"

# --- Kernel / sysctl Hardening ---
log "${BLUE}[*] Applying kernel hardening (sysctl)...${NC}"
SYSCTL_FILE="/etc/sysctl.d/99-hardening.conf"
cat > "$SYSCTL_FILE" <<EOF
# IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Disable IP source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Disable sending ICMP redirects
net.ipv4.conf.all.send_redirects = 0

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1

# Protect against time-wait assassination
net.ipv4.tcp_rfc1337 = 1
EOF

sysctl -p "$SYSCTL_FILE"
log "${GREEN}[+] Kernel hardening applied.${NC}"

# --- Summary ---
log "${GREEN}[✓] Security hardening completed.${NC}"
echo -e "${GREEN}"
echo "-----------------------------------------"
echo "  Security hardening summary:"
echo " - System updated (apt + dist-upgrade)"
echo " - SSH port: $SSH_PORT"
echo " - SSH: root login disabled, password auth disabled"
echo " - SSH: MaxAuthTries=3, X11/TCP forwarding off"
echo " - UFW firewall configured"
echo "   • TCP ports: $TCP_PORTS"
[[ -n "$UDP_PORTS" ]] && echo "   • UDP ports: $UDP_PORTS"
[[ -n "$NEW_USER" ]] && echo " - New sudo user created: $NEW_USER"
echo " - Fail2Ban: 5 attempts → 72h ban"
echo " - Automatic security updates enabled"
echo " - Kernel hardening applied (sysctl)"
echo " - Full log: $LOG_FILE"
echo "-----------------------------------------"
echo -e "${NC}"

# --- Reboot ---
read -p "$(echo -e "${YELLOW}Reboot now to apply all changes? (y/n): ${NC}")" REBOOT_CONFIRM
if [[ "$REBOOT_CONFIRM" == "y" || "$REBOOT_CONFIRM" == "Y" ]]; then
    log "${BLUE}Rebooting...${NC}"
    reboot now
else
    log "${YELLOW}Reboot skipped. Please reboot manually to apply all settings.${NC}"
fi
