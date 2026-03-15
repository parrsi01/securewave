#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

ADMIN_USER="${ADMIN_USER:-securewave}"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  ufw \
  fail2ban \
  nginx \
  certbot \
  python3-certbot-nginx \
  unattended-upgrades \
  docker.io \
  docker-compose-plugin

systemctl enable --now docker

if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${ADMIN_USER}"
  usermod -aG sudo,docker "${ADMIN_USER}"

  if [ -f /root/.ssh/authorized_keys ]; then
    install -d -m 700 "/home/${ADMIN_USER}/.ssh"
    cp /root/.ssh/authorized_keys "/home/${ADMIN_USER}/.ssh/authorized_keys"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
    chmod 600 "/home/${ADMIN_USER}/.ssh/authorized_keys"
  fi
fi

cat <<'EOF' > /etc/ssh/sshd_config.d/securewave.conf
PasswordAuthentication no
PermitRootLogin prohibit-password
EOF
systemctl reload ssh

install -d -m 0755 /etc/fail2ban/jail.d
cat <<'EOF' > /etc/fail2ban/jail.d/securewave-sshd.local
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF

cat <<'EOF' > /etc/sysctl.d/99-securewave.conf
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.src_valid_mark=1
EOF
sysctl --system

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 51820/udp
ufw allow 1194/udp
ufw allow 500/udp
ufw allow 4500/udp
ufw --force enable

systemctl enable --now fail2ban
cat <<'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades
systemctl enable nginx >/dev/null 2>&1 || true

echo "Bootstrap complete."
echo "Next: deploy application and configure WireGuard."
