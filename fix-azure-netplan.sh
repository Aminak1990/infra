#!/bin/bash
mount /dev/sda1 /mnt/repair 2>/dev/null
rm -f /mnt/repair/etc/netplan/60-static.yaml /mnt/repair/etc/netplan/50-cloud-init.yaml
cat > /mnt/repair/etc/netplan/01-network.yaml <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
echo "=== NETPLAN FILES ==="
ls /mnt/repair/etc/netplan/
echo "=== CONTENT ==="
cat /mnt/repair/etc/netplan/01-network.yaml
umount /mnt/repair
echo "DONE"
