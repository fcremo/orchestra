#!/bin/false

# Defines common variables and functions

BOLD="\e[1m"
RED="\e[31m"
RESET="\e[0m"

function log() {
    echo -en "${BOLD}" > /dev/stderr
    echo -n '[+]' "$1" > /dev/stderr
    echo -e "${RESET}" > /dev/stderr
}

function log_err() {
    echo -en "${BOLD}${RED}" > /dev/stderr
    echo -n '[!]' "$1" > /dev/stderr
    echo -e "${RESET}" > /dev/stderr
}

(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0
if [[ $SOURCED == 0 ]]; then
    log_err "This script must be sourced, not invoked directly"
    exit 1
fi

ORCHESTRA_ROOT="$(realpath "$CI_SCRIPTS_ROOT/../..")"
ORCHESTRA_DOTDIR="$ORCHESTRA_ROOT/.orchestra"
USER_OPTIONS="$ORCHESTRA_DOTDIR/config/user_options.yml"

BRANCHES_TO_TRY=()
# Add custom branch
if [[ -n "$COMPONENT_TARGET_BRANCH" ]] && ! [[ "$COMPONENT_TARGET_BRANCH" =~ ^(next-develop|develop|next-master|master)$ ]]; then
    BRANCHES_TO_TRY+=("$COMPONENT_TARGET_BRANCH")
    if [[ "${COMPONENT_TARGET_BRANCH:0:5}" == "next-" ]] && ! [[ "$IGNORE_ALL_NEXT_BRANCHES" == 1 ]]; then
        BRANCHES_TO_TRY+=("${COMPONENT_TARGET_BRANCH:5}")
    fi
fi
# Add default branches
if [[ "$IGNORE_ALL_NEXT_BRANCHES" == 1 ]]; then
    BRANCHES_TO_TRY+=(develop master)
else
    BRANCHES_TO_TRY+=(next-develop develop next-master master)
fi

if [[ -n "$REVNG_ORCHESTRA_BRANCH" ]]; then
    REVNG_ORCHESTRA_BRANCHES_TO_TRY=("$REVNG_ORCHESTRA_BRANCH")
else
    REVNG_ORCHESTRA_BRANCHES_TO_TRY=("${BRANCHES_TO_TRY[@]}")
fi

if [[ -z "$REVNG_COMPONENTS_DEFAULT_BUILD" ]]; then
    REVNG_COMPONENTS_DEFAULT_BUILD=optimized
fi

PUSH_BINARY_ARCHIVE_EMAIL="${PUSH_BINARY_ARCHIVE_EMAIL:-sysadmin@rev.ng}"
PUSH_BINARY_ARCHIVE_NAME="${PUSH_BINARY_ARCHIVE_NAME:-rev.ng CI}"

function orchestra () {
    command orchestra -C "$ORCHESTRA_ROOT" "$@"
}

function orc () {
    command orchestra -C "$ORCHESTRA_ROOT" "$@"
}
