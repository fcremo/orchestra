#!/bin/bash

# Sets up user-options.yml
#
# Usage: prepare-user-options.sh <BASE_USER_OPTIONS_YML> <REVNG_COMPONENTS_DEFAULT_BUILD> <BRANCHES_TO_TRY...>
# BASE_USER_OPTIONS_YML:
#   user_options.yml is initialized to this value.
#   %GITLAB_ROOT% is replaced with the base URL of the Gitlab instance.
# REVNG_COMPONENTS_DEFAULT_BUILD: the default build for revng core components
# BRANCHES_TO_TRY: list of branches to try to clone projects from

CI_SCRIPTS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$CI_SCRIPTS_ROOT/include/common.sh"

if [[ $# -le 3 ]]; then
    log_err "Wrong number of arguments"
    exit 1
fi

if [[ -e "$USER_OPTIONS" ]]; then
    log_err "$USER_OPTIONS already exists!"
    exit 1
fi

BASE_USER_OPTIONS_YML="$1"; shift
REVNG_COMPONENTS_DEFAULT_BUILD="$1"; shift
BRANCHES_TO_TRY=()
while [[ $# -gt 0 ]]; do
    BRANCHES_TO_TRY+=("$1")
    shift
done

REMOTE="$(git -C "$ORCHESTRA_ROOT" remote get-url origin | sed 's|^\([^:]*:\)\([^/]\)|\1/\2|')"
GITLAB_ROOT="$(dirname "$(dirname "$REMOTE")")"
echo "${BASE_USER_OPTIONS_YML//\%GITLAB_ROOT\%/$GITLAB_ROOT}" > "$USER_OPTIONS"

# Build branches list
cat >> "$USER_OPTIONS" <<EOF
#@overlay/replace
branches:
EOF
for B in "${BRANCHES_TO_TRY[@]}"; do
    echo "  - $B" >> "$USER_OPTIONS";
done

# Set default builds
echo "#@overlay/replace" >> "$USER_OPTIONS"
echo "revng_components_default_build: $REVNG_COMPONENTS_DEFAULT_BUILD" >> "$USER_OPTIONS"
