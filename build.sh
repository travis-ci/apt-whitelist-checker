#! /usr/bin/env bash

PKG=$1

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

export DEBIAN_FRONTEND=noninteractive
wget https://raw.githubusercontent.com/travis-ci/apt-source-whitelist/master/ubuntu.json
ruby -rjson -e 'json=JSON.parse(File.read("ubuntu.json")); json.each {|src| system "curl -sSL #{src["key_url"].untaint.inspect} | sudo apt-key add -" if src["key_url"]; system "sudo -E apt-add-repository -y #{src["sourceline"].untaint.inspect}" }'
mkdir -p /var/tmp/deb-sources
cd /var/tmp/deb-sources
sudo apt-get update -qq
apt-get source ${PKG}
grep -R -i -E 'set(uid|euid|gid)' . 2>/dev/null || echo -e "\n\n${ANSI_GREEN}no setuid bits found${ANSI_CLEAR}\n\n"