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

case $CHECK_RESULT in
	$EXIT_SUCCSS)
		echo -e "${ANSI_GREEN}No suspicious bits found. Creating a PR.${ANSI_RESET}"
		echo https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls
		BRANCH="apt-package-whitelist-test-${ISSUE_NUMBER}"
		pushd ../apt-package-whitelist
		git checkout -b $BRANCH
		env TICKET=${ISSUE_NUMBER} make resolve
		git push origin $BRANCH
		popd
		COMMENT="Ran tests and found no setuid bits.\n\nSee${BUILD_URL}"
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "{\"title\":\"Pull request for ${PACKAGE}\",\"body\":\"${COMMENT}\",\"head\":\"${BRANCH}\",\"base\":\"master\"}" \
			https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls
		;;
	$EXIT_SOURCE_HAS_SETUID)
		echo -e "${ANSI_RED}Found occurrences of setuid.${ANSI_RESET}"
		echo ${GITHUB_ISSUES_URL}/comments
		COMMENT="Ran tests and found setuid bits.\n\nSee ${BUILD_URL}."
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "{\"body\":\"${COMMENT}\"}" \
			${GITHUB_ISSUES_URL}/comments
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "[\"apt-whitelist-check-run\"]" \
			${GITHUB_ISSUES_URL}/labels
		;;
	$EXIT_SOURCE_NOT_FOUND)
		echo -e "${ANSI_RED}Source not found.${ANSI_RESET}"
		echo ${GITHUB_ISSUES_URL}/comments
		echo ${GITHUB_ISSUES_URL}/labels
		COMMENT="Ran tests, but could not found source package. Either the source package for ${PACKAGE} does not exist, or needs an APT source.\n\nSee ${BUILD_URL}."
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "{\"body\":\"${COMMENT}\"}" \
			${GITHUB_ISSUES_URL}/comments
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "[\"apt-source-whitelist\",\"apt-whitelist-check-run\"]" \
			${GITHUB_ISSUES_URL}/labels
		;;
	*)
		echo -e "${ANSI_RED}Something unexpected happened.${ANSI_RESET}"
		exit $CHECK_RESULT
		;;
esac
