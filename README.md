# apt-whitelist-checker

This is a repository to automate testing [APT package whitelisting requests](https://github.com/travis-ci/apt-package-whitelist).

## Why?

APT packages need to be checked before being added to the list,
but that involves some tedious setup and manual labor.
This repository aims to automate the tedious part, and
human part more accessible.

This is useful for only the maintainers of Travis CI repositories.

## How This Works

First, you need to set up:

    `GITHUB_OAUTH_TOKEN`: You'd probably want to create one especially for use with this repo; https://github.com/settings/tokens

Then, run:

```sh-session
$ env REPO=travis-ci ruby run_tests.rb
```

This would go through the list of open GitHub issues in `REPO`:
https://github.com/travis-ci/travis-ci/issues
and print out what it intends to do.

Specifically, it looks for tickets with the title of the form: `APT whitelist request for X`
or `APT source whitelist request for Y`.
For the latter, it will add a label and move on.
For the former, it will make a commit to this repository, and make a push to this repository.

The push, then, will trigger a build, as defined in `.travis.yml`.

The build, in turn, adds the APT sources to a Docker container,
downloads the source package in question and run:

```
grep -R -i -H -C5 -E --color 'set(uid|euid|gid)' --exclude install-sh .
```

(See [`build.sh`](build.sh).)

If no such occurrence is found, a comment is posted, and a PR suggesting the addition
is created on the APT package whitelist repo.

If there are, a comment is posted on the original request issue, along with the list of
packages the source package provides, and the build URL showing the problem.

If no source package matching the given name is found, the label `apt-source-whitelist` is
added to the issue, and a comment is posted.

#### CI setup

This repository's `run` branch is configured to automate the execution of the check
described above.
See https://travis-ci.org/travis-ci/apt-whitelist-checker/branches.

### REPO environment variable

The environment variable `REPO` controls which repository to look for the issues.
Historically, it was `travis-ci`, but the noise from issues became a problem, so we
will be moving to `apt-package-whitelist`.
For the time being, both will have to be monitored.
