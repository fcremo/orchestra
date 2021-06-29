#!/bin/bash

# Helper script that installs orchestra
# Usage: install-orchestra.sh <REVNG_ORCHESTRA_URL> [BRANCHES_TO_TRY...]
#
# REVNG_ORCHESTRA_URL: orchestra git repo URL (must be git+ssh:// or git+https://)
# BRANCHES_TO_TRY: list of branches to try to install from. Defaults to master

CI_SCRIPTS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$CI_SCRIPTS_ROOT/include/common.sh"

if [[ $# -le 1 ]]; then
    log_err "Wrong number of arguments"
    exit 1
fi

REVNG_ORCHESTRA_URL="$1"; shift
if [[ $# -eq 0  ]]; then
    BRANCHES_TO_TRY=(master)
else
    BRANCHES_TO_TRY=()
    while [[ $# -gt 0 ]]; do
        BRANCHES_TO_TRY+=("$1")
        shift
    done
fi

for BRANCH in "${BRANCHES_TO_TRY[@]}"; do
    if pip3 install --user "$REVNG_ORCHESTRA_URL@$BRANCH" &> /dev/null; then
        log "Installed orchestra from $REVNG_ORCHESTRA_URL@$BRANCH"
        exit 0
    fi
done
log_err "Could not install orchestra from $REVNG_ORCHESTRA_URL. These branches were tried: ${BRANCHES_TO_TRY[*]}"
exit 1
