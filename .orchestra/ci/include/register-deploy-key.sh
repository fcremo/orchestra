#!/bin/false

# Sets up SSH keys

(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0
if [[ $SOURCED == 0 ]]; then
    log_err "This script must be sourced, not invoked directly"
    exit 1
fi

if test -n "$SSH_PRIVATE_KEY"; then
    log "Installing SSH private key"
    eval "$(ssh-agent -s)"
    echo "$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
    unset SSH_PRIVATE_KEY
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Disable checking the host key
    if ! test -e ~/.ssh/config; then
        cat > ~/.ssh/config <(
            echo "Host *"
            echo "    StrictHostKeyChecking no"
            echo "    UserKnownHostsFile /dev/null"
        )
    fi

    # Change orchestra remote to ssh if we were given the URL
    if [[ -n "$ORCHESTRA_CONFIG_REPO_SSH_URL" ]]; then
        git -C "$ORCHESTRA_ROOT" remote set-url origin "$ORCHESTRA_CONFIG_REPO_SSH_URL"
    fi
fi
