#! /usr/bin/env bash

PKG=$1
HOST=$2

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

echo <<EOF | sshpass -p travis ssh -t -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no travis@${HOST}
mkdir -p /var/tmp/deb-sources
cd /var/tmp/deb-sources
sudo apt-get update -qq
apt-get source ${PKG}
grep -R -i -E 'set(uid|euid|gid)' . || echo no setuid bits found
exit
EOF
