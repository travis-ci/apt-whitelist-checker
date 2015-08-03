#! /usr/bin/env bash

source `dirname $0`/common.sh

SSH_OPTS='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q'

BUILD_URL="https://travis-ci.org/${TRAVIS_REPO_SLUG}/builds/${TRAVIS_BUILD_ID}"
ISSUE_REPO=${ISSUE_REPO:-"apt-package-whitelist"} # name of the repo that has issues, under "travis-ci"
GITHUB_ISSUES_URL="https://api.github.com/repos/travis-ci/${ISSUE_REPO}/issues/${ISSUE_NUMBER}"

echo "Pushing build.sh"
sshpass -p travis scp $SSH_OPTS build.sh  travis@$(< docker_ip_address):.
sshpass -p travis scp $SSH_OPTS common.sh travis@$(< docker_ip_address):.
sshpass -p travis scp $SSH_OPTS add_sources.rb travis@$(< docker_ip_address):.
echo "Running build.sh"
sshpass -p travis ssh -n -t -t $SSH_OPTS travis@$(< docker_ip_address) "bash build.sh ${PACKAGE}"

CHECK_RESULT=$?

if [ $CHECK_RESULT -ne $EXIT_SOURCE_NOT_FOUND ]; then
	sshpass -p travis scp $SSH_OPTS travis@$(< ${TRAVIS_BUILD_DIR}/docker_ip_address):/var/tmp/deb-sources/packages .
fi

case $CHECK_RESULT in
	$EXIT_SUCCSS)
		notice "No suspicious bits found."
		notice "Setting up Git"
		git clone https://github.com/travis-ci/apt-package-whitelist.git
		cp packages apt-package-whitelist # so make_pr.sh can find it
		pushd apt-package-whitelist
		env GITHUB_OAUTH_TOKEN=${GITHUB_OAUTH_TOKEN} ./make_pr.sh -y ${ISSUE_REPO} ${ISSUE_NUMBER}
		if [ $? -eq $EXIT_NOTHING_TO_COMMIT ]; then
			COMMIT=$(git blame ubuntu-precise | grep ${PACKAGE} | cut -f1 -d' ' | sort | uniq | head -1)
			curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
				-d "{ \"body\": \"***This is an automated comment.***\r\n\r\nFailed to create a commit and a PR. This usually means that there has been a commit that resolved this request.\r\nInparticular, check https://github.com/travis-ci/apt-package-whitelist/commit/${COMMIT}\" }" \
				${GITHUB_ISSUES_URL}/comments
		fi
		popd
		;;
	$EXIT_SOURCE_HAS_SETUID)
		warn "Found occurrences of setuid."
		echo -e "\n\n"
		echo -e "If these occurrences of \`setuid\`/\`seteuid\`/\`setgid\` are deemed harmless, add the following packages: $(< packages)\n"
		notice "Setting up Git"
		git clone https://github.com/travis-ci/apt-package-whitelist.git
		cp packages apt-package-whitelist # so make_pr.sh can find it
		pushd apt-package-whitelist
		env GITHUB_OAUTH_TOKEN=${GITHUB_OAUTH_TOKEN} ./make_pr.sh -s -y ${ISSUE_REPO} ${ISSUE_NUMBER}
		cat <<-EOF > comment_payload
{
	"body" : "***This is an automated comment.***\r\n\r\nRan tests and found setuid bits by purely textual search. Further analysis is required.\r\n\r\nIf these are found to be benign, examine http://github.com/travis-ci/apt-package-whitelist/tree/test-apt-package-whitelist-${ISSUE_NUMBER} and its PR.\r\n\r\nPackages found: $(< packages)\r\n\r\nSee ${BUILD_URL} for details."
}
		EOF
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d @comment_payload \
			${GITHUB_ISSUES_URL}/comments
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "[\"apt-whitelist-check-run\"]" \
			${GITHUB_ISSUES_URL}/labels
		pushd
		;;
	$EXIT_SOURCE_NOT_FOUND)
		warn "Source not found."
		cat <<-EOF > comment_payload
{
	"body" : "***This is an automated comment.***\r\n\r\nRan tests, but could not found source package. Either the source package for ${PACKAGE} does not exist, or the package needs an APT source. If you wisht to add an APT source, please follow the directions on https://github.com/travis-ci/apt-source-whitelist#source-approval-process. Build results: ${BUILD_URL}."
}
		EOF
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d @comment_payload \
			${GITHUB_ISSUES_URL}/comments
		curl -X POST -sS -H "Content-Type: application/json" -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
			-d "[\"apt-source-whitelist\",\"apt-whitelist-check-run\"]" \
			${GITHUB_ISSUES_URL}/labels
		;;
	*)
		warn "Something unexpected happened. Status: ${CHECK_RESULT}"
		;;
esac

exit $CHECK_RESULT
