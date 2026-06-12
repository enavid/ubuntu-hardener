# Ubuntu Security Hardening Script

A shell script that automates essential security hardening for a fresh Ubuntu server. Interactive prompts let you customize the setup without editing any files.

---

## Quick Start

> **Before running:** open your cloud provider's firewall/security group and allow the new SSH port you plan to use. Otherwise you will be locked out after the script runs.

Download and review the script first, then run it as root:

```bash
curl -Ls https://raw.githubusercontent.com/enavid/ubuntu-hardener/main/harden.sh -o harden.sh
cat harden.sh          # review before executing
sudo bash harden.sh
```

---

## What It Does

### System
| Step | Action |
|------|--------|
| 1 | `apt update && apt upgrade && apt dist-upgrade` |
| 2 | Install `unattended-upgrades` for automatic security patches |
| 3 | `apt autoremove && apt autoclean` |

### Firewall (UFW)
| Step | Action |
|------|--------|
| 4 | Install and enable UFW |
| 5 | Default: deny incoming, allow outgoing |
| 6 | Open custom TCP/UDP ports you specify |
| 7 | Always keeps the new SSH port open (prevents lockout) |

### SSH Hardening
| Step | Action |
|------|--------|
| 8 | Change SSH port to a custom port you choose |
| 9 | Disable root login (`PermitRootLogin no`) |
| 10 | Enable `PubkeyAuthentication yes` |
| 11 | Check for existing SSH keys on root and new user |
| 12 | Disable password auth only if a key is found — otherwise ask |
| 13 | Set `MaxAuthTries 3` |
| 14 | Disable X11 and TCP forwarding |
| 15 | Configure idle session timeout (5 min) |
| 16 | Validate config with `sshd -t` before restarting |
| 17 | Auto-backup `sshd_config` before any changes |

### Access Control
| Step | Action |
|------|--------|
| 16 | Optionally create a new sudo user |

### Intrusion Prevention
| Step | Action |
|------|--------|
| 17 | Install and configure `fail2ban` |
| 18 | SSH: 5 failed attempts → 72-hour ban |

### Kernel Hardening (sysctl)
| Step | Action |
|------|--------|
| 19 | IP spoofing protection (`rp_filter`) |
| 20 | SYN flood protection (`tcp_syncookies`) |
| 21 | Disable IP source routing |
| 22 | Ignore and disable ICMP redirects |
| 23 | Log suspicious (martian) packets |
| 24 | TCP time-wait assassination protection |

---

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04
- Must be run as `root`

---

## Important Warnings

**SSH key check is built in.**
Before disabling password authentication, the script checks whether an `authorized_keys` file exists for root or the new user. If no key is found, it warns you and asks for confirmation — so you won't be accidentally locked out. To be safe, add your key before running:

```bash
ssh-keygen -t ed25519 -C "your@email.com"
ssh-copy-id root@your-server
```

**Cloud firewall / security groups.**
Most cloud providers (AWS, Hetzner, DigitalOcean, etc.) have a firewall layer outside the OS. Allow your new SSH port there *before* running the script.

**Password authentication is disabled.**
After the script runs, SSH login with a password will be rejected. Only key-based login works.

---

## Logs

All actions are logged to `/var/log/hardening.log` with timestamps.

```bash
cat /var/log/hardening.log
```

---

## After Running

Reconnect on the new SSH port to verify everything works before rebooting:

```bash
ssh -p <new-port> user@your-server
```

Then reboot when prompted (or manually):

```bash
sudo reboot
```
