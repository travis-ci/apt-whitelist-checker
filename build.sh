#! /usr/bin/env bash

PKG=$1

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

EXIT_SOURCE_NOT_FOUND=1
EXIT_SOURCE_HAS_SETUID=2

echo -e "${ANSI_GREEN}Install RVM & Ruby${ANSI_RESET}"
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
\curl -sSL https://get.rvm.io | bash -s stable
rvm use --binary --fuzzy --install 2.1.5

export DEBIAN_FRONTEND=noninteractive
echo -e "${ANSI_GREEN}Fetching apt-source-whitelist data${ANSI_RESET}"
wget https://raw.githubusercontent.com/travis-ci/apt-source-whitelist/master/ubuntu.json
echo -e "${ANSI_GREEN}Applying apt-source-whitelist data"
ruby -rjson -e 'json=JSON.parse(File.read("ubuntu.json")); json.each {|src| puts "Adding #{src["key_url"].untaint.inspect}"; system "curl -sSL #{src["key_url"].untaint.inspect} | sudo apt-key add - &>/dev/null" || puts("Failed") if src["key_url"]; puts "Adding repository #{src["sourceline"].untaint.inspect}"; system("sudo -E apt-add-repository -y #{src["sourceline"].untaint.inspect}) || puts("failed")" }'
mkdir -p /var/tmp/deb-sources
cd /var/tmp/deb-sources
sudo apt-get update -qq

echo -e "${ANSI_GREEN}Fetching source package for ${PKG}${ANSI_RESET}"
apt-get source ${PKG} 2>&1 | tee apt-get-result.log

if egrep 'Unable to find a source package for' apt-get-result.log 2>/dev/null; then
	exit $EXIT_SOURCE_NOT_FOUND
fi

if find . ! -name install.sh -a -type f -exec grep -i -H -C5 -E --color 'set(uid|euid|gid)' {} \; 2>/dev/null; then
	echo -e "${ANSI_RED}Suspicious bits found${ANSI_RESET}"
	exit $EXIT_SOURCE_HAS_SETUID
else
	echo -e "${ANSI_GREEN}No setuid bits found${ANSI_RESET}"
	exit 0
fi
