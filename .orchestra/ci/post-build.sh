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

# `orc update` to clone the binary archives
orc update

BUILD_FLAVORS=(optimized release debug)
ARTIFACTS_DIR="$CI_PROJECT_DIR/artifacts"

# Restore the remote cache that was used during the build
# TODO: ensure that remote_refs_cache.json matches for all the builds
# WARNING: Do NOT run `orc update` after this point!
rm -rf "$ORCHESTRA_DOTDIR/cache"
CACHE_DIR="$ARTIFACTS_DIR/optimized/cache"
cp -r "$CACHE_DIR/cache" "$ORCHESTRA_DOTDIR/cache"
cp "$CACHE_DIR/remote_refs_cache.json" "$ORCHESTRA_DOTDIR/remote_refs_cache.json"

function all_builds_successful () {
    for BUILD in "${BUILD_FLAVORS[@]}"; do
        local BUILD_STATUS_FILE="$CI_PROJECT_DIR/artifacts/$BUILD/build_status"
        if ! [[ -e "$BUILD_STATUS_FILE" ]] || ! [[ "$(cat "$BUILD_STATUS_FILE")" == "SUCCESS" ]]; then
            return 1
        fi
    done
    return 0
}

# Promote `next-*` branches to `*`
if [[ "$PROMOTE_BRANCHES" = 1 ]] || [[ "$PUSH_CHANGES" = 1 ]]; then
    if all_builds_successful; then
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

            # Restore component the head commit it had during the build
            git -C "$SOURCE_DIR" checkout -B "$HEAD_BRANCH" "$HEAD_COMMIT"
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
        log_err "Not all builds succeeded, skipping branch promotion"
    fi
else
    log "Skipping branch promotion (PROMOTE_BRANCHES='$PROMOTE_BRANCHES', PUSH_CHANGES='$PUSH_CHANGES')"
fi

# Push binary archives changes
if [[ "$PUSH_BINARY_ARCHIVES" = 1 ]] || [[ "$PUSH_CHANGES" = 1 ]]; then
    if all_builds_successful; then
        # Push to binary archives
        for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do
            cd "$BINARY_ARCHIVE_PATH"

            git config user.email "$PUSH_BINARY_ARCHIVE_EMAIL"
            git config user.name "$PUSH_BINARY_ARCHIVE_NAME"
            git config --add lfs.dialtimeout 300
            git config --add lfs.tlstimeout 300
            git config --add lfs.activitytimeout 300
            git config --add lfs.keepalive 300

            # Ensure we track the correct files
            git lfs track "*.tar.*"
            git add .gitattributes
            if ! git diff --staged --exit-code -- .gitattributes > /dev/null; then
                git commit -m'Initialize .gitattributes'
            fi

            # Consolidate all branches into master
            BINARY_ARCHIVE_BRANCHES=()
            for BUILD in "${BUILD_FLAVORS[@]}"; do
                BUILD_ARTIFACTS_DIR="$ARTIFACTS_DIR/$BUILD"
                BUILD_BINARY_ARCHIVE_BRANCH_FILE="$BUILD_ARTIFACTS_DIR/binary_archive_branch_name"
                BINARY_ARCHIVE_BRANCHES+=("$(cat "$BUILD_BINARY_ARCHIVE_BRANCH_FILE")")
            done
            git fetch
            GIT_LFS_SKIP_SMUDGE=1 git merge --no-ff "${BINARY_ARCHIVE_BRANCHES[@]}"
            # TODO: Remove build-specific branches?
            # git branch -D "${BINARY_ARCHIVE_BRANCHES[@]}"
            # also remember to add --prune or --mirror to git push

            # Push changes
            git push
            git lfs push origin master
        done
    else
        log_err "Not all builds succeeded, skipping binary archives push"
    fi
else
    log "Skipping binary archives push (PUSH_BINARY_ARCHIVES='$PUSH_BINARY_ARCHIVES', PUSH_CHANGES='$PUSH_CHANGES')"
fi

if all_builds_successful; then
    exit 0
else
    exit 1
fi
