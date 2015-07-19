#! /usr/bin/env bash

PKG=$1

echo <<EOF | sshpass -p travis -t -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ssh travis@$(< docker_ip_address)
mkdir -p /var/tmp/deb-sources
cd /var/tmp/deb-sources
sudo apt-get update -qq
apt-get source ${PKG}
grep -R -i -E 'set(uid|euid|gid)' . || echo no setuid bits found
exit
EOF
