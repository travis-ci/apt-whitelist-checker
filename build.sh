#! /usr/bin/env bash

source `dirname $0`/common.sh

PKG=$1

export DEBIAN_FRONTEND=noninteractive
fold_start apt_src "Add APT sources"
cd
wget https://raw.githubusercontent.com/travis-ci/apt-source-whitelist/master/ubuntu.json
old_IFS=$IFS
IFS=$'\t'
jq -r '.[]|[.alias,.sourceline,.key_url]|@tsv' ubuntu.json | \
while read -r Alias SourceLine KeyURL; do
        echo "------------------------------"
        echo "Adding ${Alias}"
        if [[ "${KeyURL}" != "" ]]; then
                curl -sSL ${KeyURL} | sudo -E env LANG=C.UTF-8 apt-key add - || continue;
        fi
        sudo -E env LANG=C.UTF-8 apt-add-repository -ys ${SourceLine}
done
IFS=${old_IFS}
mkdir -p /var/tmp/deb-sources
cd /var/tmp/deb-sources
sudo apt-get update -qq &>/dev/null
fold_end apt_src

fold_start fetch_src_pkg "Fetching source package for ${PKG}"
apt-cache policy ${PKG}
apt-get source ${PKG} 2>&1 | tee apt-get-result.log
fold_end fetch_src_pkg

if egrep 'Unable to (find a source package for|locate package)' apt-get-result.log 2>/dev/null; then
	exit $EXIT_SOURCE_NOT_FOUND
fi

fold_start list_pkg "Finding packages"
for d in $(find . -name debian) ; do
  pushd $d &>/dev/null && \
    grep ^Package control | awk -F: '{ print $2 }' | xargs echo ;
  popd &>/dev/null ;
done | xargs echo > packages
fold_end list_pkg

if grep -R -i -H -C5 -E --color 'set(uid|euid|gid)' --exclude install-sh . 2>/dev/null; then
	warn "Suspicious bits found"
	exit $EXIT_SOURCE_HAS_SETUID
else
	notice "No setuid bits found"
	exit 0
fi
