#! /usr/bin/env bash

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

EXIT_SUCCSS=0
EXIT_SOURCE_NOT_FOUND=1
EXIT_SOURCE_HAS_SETUID=2

function notice() {
	msg=$1
	echo -e "${ANSI_GREEN}${msg}${ANSI_RESET}"
}

function warn() {
	msg=$1
	echo -e "${ANSI_RED}${msg}${ANSI_RESET}"
}
