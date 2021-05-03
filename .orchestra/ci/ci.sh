#!/bin/bash

# rev.ng CI entrypoint script
# This script checks out the correct configuration branch and initializes
# variables for the actual CI script (ci-run.sh)
#
# Parameters are supplied as environment variables.
#
# Optional parameters:
#
# PUSHED_REF:
#   Name of the branch which will be tried to be checked out first. Affects the
#   configuration and all components. Normally set by Gitlab or whoever triggers
#   the CI.
#   Format: refs/heads/<branchname>
# IGNORE_ALL_NEXT_BRANCHES:
#   If == 1 the list of branches to try to checkout for the configuration and
#   the components will not include next-* branches, unless PUSHED_REF specifies
#   a next-* branch
# IGNORE_CONFIG_NEXT_BRANCHES:
#   If == 1 the list of branches to try to checkout for the configuration will
#   not include next-* branches, unless PUSHED_REF specifies a next-* branch

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ORCHESTRA_DIR="$DIR/../.."

BOLD="\e[1m"
RED="\e[31m"
RESET="\e[0m"

# Runs git in the orchestra directory
function ogit () {
    git -C "$ORCHESTRA_DIR" "$@"
}

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

set -e

# Determine target branch
#
# PUSHED_REF contains the git ref that was pushed and triggered the CI.
#
# If this ref is a branch, it will be used as the first default branch to try
# for all components and for orchestra configuration

COMPONENT_TARGET_BRANCH=""

if [[ -n "$PUSHED_REF" ]]; then
    log "PUSHED_REF=$PUSHED_REF"
    if [[ "$PUSHED_REF" = refs/heads/* ]]; then
        COMPONENT_TARGET_BRANCH="${PUSHED_REF#refs/heads/}"
    else
        log_err "PUSHED_REF ($PUSHED_REF) is not a branch, bailing out"
        exit 0
    fi
fi

# If the target branch is not part of the default list and it does not already
# exist, create it
if [[ ! "$COMPONENT_TARGET_BRANCH" =~ ^(next-)?(develop|master)$ ]] && \
    ! git rev-parse --quiet --verify "$COMPONENT_TARGET_BRANCH" >/dev/null ; then
    log "Creating branch $COMPONENT_TARGET_BRANCH for orchestra configuration from master"
    ogit checkout "$COMPONENT_TARGET_BRANCH" || ogit checkout -b "$COMPONENT_TARGET_BRANCH" master
fi

# Switch orchestra to the target branch or try the default list
if [[ "$IGNORE_ALL_NEXT_BRANCHES" == 1 ]] ||
    [[ "$IGNORE_CONFIG_NEXT_BRANCHES" == 1 ]]; then
    BRANCHES_TO_TRY=("$COMPONENT_TARGET_BRANCH" develop master)
else
    BRANCHES_TO_TRY=("$COMPONENT_TARGET_BRANCH" next-develop develop next-master master)
fi

ogit fetch
for B in "${BRANCHES_TO_TRY[@]}"; do
    if ogit checkout "$B"; then
        ORCHESTRA_TARGET_BRANCH="$B"
        break
    fi
done

if [[ -z "$ORCHESTRA_TARGET_BRANCH" ]]; then
    log_err "All checkout attempts failed, aborting"
    exit 1
fi

ORCHESTRA_CONFIG_COMMIT="$(ogit rev-parse --short "$ORCHESTRA_TARGET_BRANCH")"
log "Using configuration branch $ORCHESTRA_TARGET_BRANCH (commit $ORCHESTRA_CONFIG_COMMIT)"

export COMPONENT_TARGET_BRANCH

# Run "true" CI script
log "Starting ci-run with COMPONENT_TARGET_BRANCH=$COMPONENT_TARGET_BRANCH"
"$DIR/ci-run.sh"
