#! /usr/bin/env bash

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

EXIT_SUCCSS=0
EXIT_SOURCE_NOT_FOUND=1
EXIT_SOURCE_HAS_SETUID=2
EXIT_NOTHING_TO_COMMIT=3

function notice() {
	msg=$1
	echo -e "\n${ANSI_GREEN}${msg}${ANSI_RESET}\n"
}

function warn() {
	msg=$1
	echo -e "\n${ANSI_RED}${msg}${ANSI_RESET}\n"
}

function fold_start() {
  echo -e "travis_fold:start:$1\033[33;1m$2\033[0m"
}

function fold_end() {
  echo -e "\ntravis_fold:end:$1\r"
}
