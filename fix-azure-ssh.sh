#!/bin/bash
mkdir -p /home/visefin/.ssh
chmod 700 /home/visefin/.ssh
# Add all keys from host
cat >> /home/visefin/.ssh/authorized_keys <<'KEYS'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC0MyCenPsLWIhvBsd4+KqFAJo+FBBzuRzGYkbkKXd28zvTdTLQCCQbfPcl5mLjoEl8bgjS5uoemOc19atmoxUDvvW39F0G7k68vfaUuYp68y9g3+N2v2FFI1OziKcMWn+b/RLxHZba5lVsaPM4xEQ6bdEDUiGJ/X18qfBJCF/B8obJ3f7x6UVBcsLbI53pPQtGbC+sRCVAGTXZ4OGoyEndNXoQvVocD3veaJFdCb1Z1ZRxkYdpug6J3Dp+eQRBI3+W3gD8FU/5sZPBzf9HdfUNhXdIyJjMfFTNFQAtSlkupcayprah4z0kRjGOPzBM9QJrGT6dVhul6QpP529+n3Wczkbmqti87FQdHWZA94BvfBr0D+y4HT/IUsehF/RuFDBwR9Xw5X9YgwXIoTVBUdsSoOHlYoEneSHHykyvcnPbxSgKKlIE6yz0k/3WEgNoQR+vx0OgWx/XVQ/m92e+8I86DOAcR0o1qyBXDhbXs+V4F53HMZLRINshPJ8RtAiMQIKutJuYT6L/QkXC5rnmeFY4H0Woyf/6L/Rgg7KjdVTum27sDBEikGJivdHTZXUQVc+GoSFBex2Wr/UysAbwYUGq9dbl6fe7yNzQT1BVG4dnK8EVty/GdzrzoekesGgxte/oxMVbWmP3FThLbuXv75yUc9qk2wUtjOGCMRh8v5f7vQ== dr-sync-key
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+gER4DmyvSM/9pJfZnWlr9/OXbvEAnmffrGg3DE3Kgxsid4SW2bVQomRwVWMAJetDUy+KeQFUVXEhzS1B5mGTK6hieBZChbhgvyh+IYJxQ4G5fM27LYmrpU3lhzPpBHnnFj1SuMdzpNvoZ2DydAxalrEKPBmYTBL8J7A8dMhd9rehyaSwj6N0cOH8UbSYkgwkc0MR7B8V2Z+VkoBQAMlHGOQ+00dBDsTUw8NsaoYlECaBhM9SWAvcIUnzkETkH7kDpcMJEnOzBsjFiuxGtlOimojEUX2GL5AzxAUemG9ZKTVV7EnGncFyAWOKs7LoMB2Ou/7/6shSe3ABCJqgLH6V
KEYS
sort -u /home/visefin/.ssh/authorized_keys -o /home/visefin/.ssh/authorized_keys
chmod 600 /home/visefin/.ssh/authorized_keys
chown -R visefin:visefin /home/visefin/.ssh
# Enable password auth
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
echo "SSH_CONFIGURED"
cat /home/visefin/.ssh/authorized_keys | wc -l
