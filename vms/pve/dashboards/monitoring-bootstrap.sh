#!/bin/bash
# PVE startup hook for the monitoring CT (runs as root INSIDE the container
# on every start). This provider version cannot pass a #cloud-config
# user-data file to CTs, so this hook is the guarantee layer: it makes the
# prerequisites of the provisioning pipeline (static IP, DNS, sshd,
# management key) idempotent and self-healing, even if the template's
# cloud-init network/user setup did not apply.
#
# NOTE: rendered via Terraform templatefile(). A bare "$" is literal, but a
# "$" followed by "{" starts a Terraform interpolation; use the $${ escape
# for bash braced vars (e.g. $${IP}).
set -u

IP=192.168.51.206
CIDR=24
GW=192.168.51.1
KEY="${monitoring_public_key}"

# First non-lo interface (PVE net0, usually enp1s0)
IFACE=$(ip -br link show | awk '$1 != "lo" {print $1; exit}')

# --- 1. Static IP + default route (live, then persist for ifupdown) --------
ip link set "$IFACE" up
if ! ip -4 addr show dev "$IFACE" | grep -q "inet $${IP}/"; then
  ip addr add $${IP}/$${CIDR} dev "$IFACE"
fi
if ! ip route show | grep -q "default via $${GW}"; then
  ip route add default via $${GW}
fi
printf 'auto lo\niface lo inet loopback\n\nauto %s\niface %s inet static\n    address %s\n    netmask 255.255.255.0\n    gateway %s\n' \
  "$IFACE" "$IFACE" "$IP" "$GW" > /etc/network/interfaces
grep -q "nameserver $${GW}" /etc/resolv.conf || echo "nameserver $${GW}" >> /etc/resolv.conf

# --- 2. SSH installed and running ------------------------------------------
if ! pgrep -x sshd >/dev/null 2>&1; then
  if ! command -v sshd >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq openssh-server
  fi
  systemctl enable ssh 2>/dev/null
  systemctl start ssh 2>/dev/null || /usr/sbin/sshd
fi

# --- 3. Management key (same key as the VM cloud-init snippets) -------------
install -d -m 700 -o root -g root /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
grep -qF "$KEY" /root/.ssh/authorized_keys || echo "$KEY" >> /root/.ssh/authorized_keys
