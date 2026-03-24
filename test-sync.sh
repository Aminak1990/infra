#!/bin/bash
echo 'ViseFin2026' | sudo -S mkdir -p /root/.ssh
echo 'ViseFin2026' | sudo -S ssh-keyscan -H 20.12.203.14 >> /tmp/azure_keys 2>/dev/null
echo 'ViseFin2026' | sudo -S cp /tmp/azure_keys /root/.ssh/known_hosts
echo 'ViseFin2026' | sudo -S rsync -az --stats -e "ssh -i /root/.ssh/id_rsa_drsync -o StrictHostKeyChecking=no" /etc/ visefin@20.12.203.14:/tmp/test_sync/ 2>&1
echo "SYNC_RESULT=$?"
