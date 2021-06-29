#!/bin/bash

# rev.ng CI post-build script
# This script runs orchestra to build the required components.
# If the build is successful the script can push the newly produced binary
# archives and promote next-<name> branches to <name>.
#
# Parameters are supplied as environment variables.
#
# Target component is mandatory and done with these parameters:
#
# TARGET_COMPONENTS: list of components to build
# TARGET_COMPONENTS_URL:
#   list of glob patterns used to select additional target components
#   by matching their remote URL
#
# Optional parameters:
#
# BASE_USER_OPTIONS_YML:
#   user_options.yml is initialized to this value.
#   %GITLAB_ROOT% is replaced with the base URL of the Gitlab instance.
# COMPONENT_TARGET_BRANCH:
#   branch name to try first when checking out component sources
# PUSH_BINARY_ARCHIVES: if == 1, push binary archives
# PROMOTE_BRANCHES: if == 1, promote next-* branches
# IGNORE_ALL_NEXT_BRANCHES:
#   If == 1 the list of branches to try to checkout for the configuration and
#   the components will not include next-* branches, unless PUSHED_REF specifies
#   a next-* branch
# COMPONENTS_BLACKLIST: space separated list of regexes matching components that will not be built explicitly
# PUSH_CHANGES: if == 1, push binary archives and promote next-* branches
# REVNG_COMPONENTS_DEFAULT_BUILD: the default build for revng core components
# PUSH_BINARY_ARCHIVE_EMAIL: used as author's email in binary archive commit
# PUSH_BINARY_ARCHIVE_NAME: used as author's name in binary archive commit
# SSH_PRIVATE_KEY: private key used to push binary archives
# REVNG_ORCHESTRA_URL: orchestra git repo URL (must be git+ssh:// or git+https://)
# REVNG_ORCHESTRA_BRANCH: branch to use when installing orchestra from git
# BUILD_ALL_FROM_SOURCE: if == 1 do not use binary archives and build everything
# NOTES: echoed at the start of the run, useful for tagging manually executed CI jobs

set -e

CI_SCRIPTS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$CI_SCRIPTS_ROOT/include/common.sh"

cd "$CI_SCRIPTS_ROOT"

# Install dependencies
"$CI_SCRIPTS_ROOT/install-dependencies.sh"

# Register deploy key, if any
source "$CI_SCRIPTS_ROOT/include/register-deploy-key.sh"

# Install orchestra
"$CI_SCRIPTS_ROOT/helpers/install-orchestra.sh" "$REVNG_ORCHESTRA_URL" "${BRANCHES_TO_TRY[@]}"
# Make sure we can run orchestra
export PATH="$HOME/.local/bin:$PATH"
which orc >/dev/null

# Prepare the user_options.yml file
"$CI_SCRIPTS_ROOT/helpers/prepare-user-options.sh" "$BASE_USER_OPTIONS_YML" "$REVNG_COMPONENTS_DEFAULT_BUILD" "${BRANCHES_TO_TRY[@]}"
log "User options:"
cat "$USER_OPTIONS"

# Restore the remote cache
# WARN: Do NOT run `orc update`
# TODO: ensure that remote_refs_cache.json matches for all the flavors
CACHE_DIR="$CI_PROJECT_DIR/cache/optimized"
cp -r "$CACHE_DIR/cache" "$ORCHESTRA_DOTDIR/cache"
cp "$CACHE_DIR/remote_refs_cache.json" "$ORCHESTRA_DOTDIR/remote_refs_cache.json"

#
# Promote `next-*` branches to `*`
#
if [[ "$PROMOTE_BRANCHES" = 1 ]] || [[ "$PUSH_CHANGES" = 1 ]]; then
    # Clone all the components having branch next-*
    for COMPONENT in $(orc components --json --branch 'next-*' | jq -r ".[].name"); do
        HEAD_BRANCH="$(orc components --json "$COMPONENT" | jq -r ".[].head_branch_name")"
        HEAD_COMMIT="$(orc components --json "$COMPONENT" | jq -r ".[].head_commit")"

        # TODO: pick the least bad option
        # Need one layer of indirection to expand environment variables
        SOURCE_DIR="$(orc shell -c "$COMPONENT" 'eval' 'printf $SOURCE_DIR')"
        # SOURCE_DIR="$(orc environment "$COMPONENT" | grep -Po '(?<=SOURCE_DIR=")[^"]*')"

        log "Cloning $COMPONENT"
        orc clone --no-force "$COMPONENT"

        git -C "$SOURCE_DIR" branch -f "$HEAD_BRANCH" "$HEAD_COMMIT"
        git -C "$SOURCE_DIR" switch "$HEAD_BRANCH"
    done

    # Promote next-* to *.
    # We also promote orchestra config because fix-binary-archive-symlinks
    # uses the current branch name
    for SOURCE_PATH in $(orc ls --git-sources) "$ORCHESTRA_ROOT"; do
        if test -e "$SOURCE_PATH/.git"; then
            cd "$SOURCE_PATH"
            BRANCH="$(git rev-parse --abbrev-ref HEAD)"
            if test "${BRANCH:0:5}" == "next-"; then
                PUSH_TO="${BRANCH:5}"
                git branch -d "$PUSH_TO" || true
                git checkout -b "$PUSH_TO" "$BRANCH"
                git push origin "$PUSH_TO"
            fi
            cd -
        fi
    done

    orc fix-binary-archives-symlinks
else
    log "Skipping branch promotion (PROMOTE_BRANCHES='$PROMOTE_BRANCHES', PUSH_CHANGES='$PUSH_CHANGES')"
fi

if [[ "$PUSH_BINARY_ARCHIVES" = 1 ]] || [[ "$PUSH_CHANGES" = 1 ]]; then
    # Ensure we have git lfs
    git lfs >& /dev/null

    # Remove old binary archives
    orc binary-archives clean

    #
    # Push to binary archives
    #
    for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do

        cd "$BINARY_ARCHIVE_PATH"

        git config user.email "$PUSH_BINARY_ARCHIVE_EMAIL"
        git config user.name "$PUSH_BINARY_ARCHIVE_NAME"

        # Ensure we track the correct files
        git lfs track "*.tar.*"
        git add .gitattributes
        if ! git diff --staged --exit-code -- .gitattributes > /dev/null; then
            git commit -m'Initialize .gitattributes'
        fi

        ls -lh
        git add .

        if ! git diff --cached --quiet; then
            COMMIT_MSG="$(
                echo "Automatic binary archives"
                echo
                echo "ORCHESTRA_CONFIG_COMMIT=$(git -C "$ORCHESTRA_ROOT" rev-parse --short HEAD || true)"
                echo "ORCHESTRA_CONFIG_BRANCH=$(git -C "$ORCHESTRA_ROOT" name-rev --name-only HEAD || true)"
                echo "COMPONENT_TARGET_BRANCH=$COMPONENT_TARGET_BRANCH"
            )"

            git commit -m "$COMMIT_MSG"
            git status
            git stash
            GIT_LFS_SKIP_SMUDGE=1 git fetch
            GIT_LFS_SKIP_SMUDGE=1 git rebase -Xtheirs origin/master

            git config --add lfs.dialtimeout 300
            git config --add lfs.tlstimeout 300
            git config --add lfs.activitytimeout 300
            git config --add lfs.keepalive 300
            git push
            git lfs push origin master
        else
            log "No changes to push for $BINARY_ARCHIVE_PATH"
        fi

    done
else
    log "Skipping binary archives push (PUSH_BINARY_ARCHIVES='$PUSH_BINARY_ARCHIVES', PUSH_CHANGES='$PUSH_CHANGES')"
fi

if [[ "${#FAILED_COMPONENTS[*]}" -gt 0 ]]; then
    log_err "The following components failed: ${FAILED_COMPONENTS[*]}}"
fi

exit "$RESULT"
