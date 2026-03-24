#!/bin/bash
# Fix netplan for dual on-prem/Azure compatibility
# Uses DHCP which works in both environments
# On-prem DHCP server assigns 10.20.0.36, Azure DHCP assigns Azure IP

echo 'ViseFin2026' | sudo -S rm -f /etc/netplan/60-static.yaml /etc/netplan/50-cloud-init.yaml /etc/netplan/90-hotplug-azure.yaml

echo 'ViseFin2026' | sudo -S tee /etc/netplan/01-network.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF

echo 'ViseFin2026' | sudo -S netplan apply 2>&1
ip addr show eth0 | grep 'inet '
echo "NETPLAN_FIXED"
