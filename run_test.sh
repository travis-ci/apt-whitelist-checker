#! /usr/bin/env bash

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

EXIT_SUCCSS=0
EXIT_SOURCE_NOT_FOUND=1
EXIT_SOURCE_HAS_SETUID=2
SSH_OPTS='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

BUILD_URL="https://travis-ci.org/${TRAVIS_REPO_SLUG}/builds/${TRAVIS_BUILD_ID}"
GITHUB_ISSUES_URL="https://api.github.com/repos/travis-ci/travis-ci/issues/${ISSUE_NUMBER}"

echo "Pushing build.sh"
sshpass -p travis scp $SSH_OPTS build.sh travis@$(< docker_ip_address):.
echo "Running build.sh"
sshpass -p travis ssh -n -t -t $SSH_OPTS travis@$(< docker_ip_address) "bash build.sh ${PACKAGE}"

CHECK_RESULT=$?

function notice() {
	msg=$1
	echo -e "${ANSI_GREEN}${msg}${ANSI_RESET}"
}

function warn() {
	msg=$1
	echo -e "${ANSI_RED}${msg}${ANSI_RESET}"
}

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
		env TICKET=${ISSUE_NUMBER} make resolve
		git push origin $BRANCH
		COMMENT="Ran tests and found no setuid bits.\n\n See${BUILD_URL}"
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "{\"title\":\"Pull request for ${PACKAGE}; closes travis-ci/travis-ci##{ISSUE_NUMBER}\",\"body\":\"${COMMENT}\",\"head\":\"${BRANCH}\",\"base\":\"master\"}" \
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
