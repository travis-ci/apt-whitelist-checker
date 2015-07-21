#! /usr/bin/env bash

source `dirname $0`/common.sh

SSH_OPTS='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

BUILD_URL="https://travis-ci.org/${TRAVIS_REPO_SLUG}/builds/${TRAVIS_BUILD_ID}"
ISSUE_REPO=${ISSUE_REPO:-"travis-ci"}
GITHUB_ISSUES_URL="https://api.github.com/repos/travis-ci/${ISSUE_REPO}/issues/${ISSUE_NUMBER}"

echo "Pushing build.sh"
sshpass -p travis scp $SSH_OPTS build.sh  travis@$(< docker_ip_address):.
sshpass -p travis scp $SSH_OPTS common.sh travis@$(< docker_ip_address):.
echo "Running build.sh"
sshpass -p travis ssh -n -t -t $SSH_OPTS travis@$(< docker_ip_address) "bash build.sh ${PACKAGE}"

CHECK_RESULT=$?

case $CHECK_RESULT in
	$EXIT_SUCCSS)
		notice "No suspicious bits found. Creating a PR."
		BRANCH="apt-package-whitelist-test-${ISSUE_NUMBER}"
		notice "Setting up Git"
		git clone https://github.com/travis-ci/apt-package-whitelist.git
		pushd apt-package-whitelist
		git config credential.helper "store --file=.git/credentials"
		echo "https://${GITHUB_OAUTH_TOKEN}:@github.com" > .git/credentials 2>/dev/null
		git config --global user.email "contact@travis-ci.com"
		git config --global user.name "Travis CI APT package tester"
		git checkout -b $BRANCH
		ISSUE_PACKAGE=${PACKAGE}
		for p in $(sshpass -p travis ssh -n -t -t $SSH_OPTS travis@$(< ${TRAVIS_BUILD_DIR}/docker_ip_address) "for d in \$(find /var/tmp/deb-sources -type d -name debian) ; do pushd \$d &>/dev/null && grep ^Package control | awk -F: '{ print \$2 }' | xargs echo ; popd &>/dev/null ; done"); do
			echo "Adding ${p}"
			env PACKAGE=${p} make add
		done
		env TICKET=${ISSUE_NUMBER} PACKAG=${ISSUE_PACKAGE} make resolve
		git push origin $BRANCH
		COMMENT="For travis-ci/${ISSUE_REPO}#${ISSUE_NUMBER}.\n\nRan tests and found no setuid bits.\n\n See ${BUILD_URL}"
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "{\"title\":\"Pull request for ${ISSUE_PACKAGE}\",\"body\":\"${COMMENT}\",\"head\":\"${BRANCH}\",\"base\":\"master\"}" \
			https://api.github.com/repos/travis-ci/apt-package-whitelist/pulls
		popd
		;;
	$EXIT_SOURCE_HAS_SETUID)
		warn "Found occurrences of setuid."
		COMMENT="Ran tests and found setuid bits.\n\nSee ${BUILD_URL}."
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "{\"body\":\"${COMMENT}\"}" \
			${GITHUB_ISSUES_URL}/comments
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "[\"apt-whitelist-check-run\"]" \
			${GITHUB_ISSUES_URL}/labels
		;;
	$EXIT_SOURCE_NOT_FOUND)
		warn "Source not found."
		COMMENT="Ran tests, but could not found source package. Either the source package for ${PACKAGE} does not exist, or needs an APT source.\n\nSee ${BUILD_URL}."
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "{\"body\":\"${COMMENT}\"}" \
			${GITHUB_ISSUES_URL}/comments
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "[\"apt-source-whitelist\",\"apt-whitelist-check-run\"]" \
			${GITHUB_ISSUES_URL}/labels
		;;
	*)
		warn "Something unexpected happened."
		exit $CHECK_RESULT
		;;
esac
