#!/bin/bash
echo 'visefin ALL=(ALL) NOPASSWD: /usr/bin/rsync' > /etc/sudoers.d/dr-sync
chmod 440 /etc/sudoers.d/dr-sync
cat /etc/sudoers.d/dr-sync
echo "SUDOERS_CONFIGURED"
