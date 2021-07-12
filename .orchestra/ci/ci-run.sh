#!/bin/bash

# rev.ng main CI script
# This script runs orchestra to build the required components.
# If the build is successful the pushes the newly produced binary archives.
# It also records the components HEAD commits so that the post-build script can promote next-* branches.
#
# Parameters are supplied as environment variables.
#
# REVNG_ORCHESTRA_URL: orchestra git repo URL (must be git+ssh:// or git+https://)
#
# Optional parameters:
#
# BASE_USER_OPTIONS_YML:
#   user_options.yml is initialized to this value.
#   %GITLAB_ROOT% is replaced with the base URL of the Gitlab instance.
# PUSH_BINARY_ARCHIVES: if == 1, push binary archives
# PROMOTE_BRANCHES: if == 1, promote next-* branches
# PUSH_CHANGES: if == 1, push binary archives and promote next-* branches
# IGNORE_ALL_NEXT_BRANCHES:
#   If == 1 the list of branches to try to checkout for the configuration and
#   the components will not include next-* branches, unless PUSHED_REF specifies
#   a next-* branch
# ONLY_COMPONENTS_MATCHING_DEFAULT_BUILD:
#   If == 1, only components with a build name matching REVNG_COMPONENTS_DEFAULT_BUILD are built
# COMPONENTS_BLACKLIST:
#   space separated list of regexes matching components that will not be built explicitly (can still be built as
#   dependencies)
# REVNG_COMPONENTS_DEFAULT_BUILD: the preferred build for revng core components. Defaults to optimized.
# SSH_PRIVATE_KEY: private key used to push binary archives
# REVNG_ORCHESTRA_BRANCH: branch to use when installing orchestra from git
# BUILD_ALL_FROM_SOURCE: if == 1 do not use binary archives and build everything
# NOTES: echoed at the start of the run, useful for tagging manually executed CI jobs

set -e

CI_SCRIPTS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$CI_SCRIPTS_ROOT/include/common.sh"

if [[ -n "$NOTES" ]]; then
    log "NOTES: $NOTES"
fi

cd "$CI_SCRIPTS_ROOT"

# Install dependencies
"$CI_SCRIPTS_ROOT/install-dependencies.sh"

# Register deploy key, if any
source "$CI_SCRIPTS_ROOT/include/register-deploy-key.sh"

# Install orchestra
"$CI_SCRIPTS_ROOT/install-orchestra.sh" "$REVNG_ORCHESTRA_URL" "${REVNG_ORCHESTRA_BRANCHES_TO_TRY[@]}"
# Make sure we can run orchestra
export PATH="$HOME/.local/bin:$PATH"
which orc >/dev/null

# Prepare the user_options.yml file
"$CI_SCRIPTS_ROOT/prepare-user-options.sh" "$BASE_USER_OPTIONS_YML" "$REVNG_COMPONENTS_DEFAULT_BUILD" "${BRANCHES_TO_TRY[@]}"
log "User options:"
cat "$USER_OPTIONS"

orc update --no-config

# Select target components
TARGET_COMPONENTS=()
BLACKLISTED_COMPONENTS=()
for COMPONENT in $(orc components --json | jq -r ".[].name"); do
    # Check if the component is blacklisted
    for BLACKLIST_PATTERN in $COMPONENTS_BLACKLIST; do
        if [[ $COMPONENT =~ $BLACKLIST_PATTERN ]]; then
            BLACKLISTED_COMPONENTS+=("$COMPONENT")
            continue 2
        fi
    done
    # If the component should contain the default build
    if [[ "$ONLY_COMPONENTS_MATCHING_DEFAULT_BUILD" == 1 ]]; then
        # Check if it does, if not skip it
        if orc components "$COMPONENT" --json | jq -e ".[].builds | has(\"$REVNG_COMPONENTS_DEFAULT_BUILD\")" > /dev/null; then
            continue
        fi
    fi

    TARGET_COMPONENTS+=("$COMPONENT")
done

if [[ "${#TARGET_COMPONENTS[*]}" -eq 0 ]]; then
    # It's important to fail here because otherwise branch promotion would run
    # even though no components have been built
    log_err "Nothing to do"
    exit 1
fi

ARTIFACTS_DIR="$CI_PROJECT_DIR/artifacts/$REVNG_COMPONENTS_DEFAULT_BUILD"
mkdir -p "$ARTIFACTS_DIR"

LOGS_DIR="$CI_PROJECT_DIR/artifacts/$REVNG_COMPONENTS_DEFAULT_BUILD/logs"
mkdir -p "$LOGS_DIR"

# Print debugging information
log "Blacklisted components: ${BLACKLISTED_COMPONENTS[*]}"
log "Target components: ${TARGET_COMPONENTS[*]}"
orc components --json > "$LOGS_DIR/components.json"
for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do
    BINARY_ARCHIVE_COMMIT="$(git -C "$BINARY_ARCHIVE_PATH" rev-parse HEAD)"
    echo "Commit for $BINARY_ARCHIVE_PATH: $BINARY_ARCHIVE_COMMIT" >> "$LOGS_DIR/binary_archives_head"
done

if [[ "$BUILD_ALL_FROM_SOURCE" == 1 ]]; then
    log "Build mode: building all components from source"
    BUILD_MODE="-B"
else
    log "Build mode: binary archives enabled"
    BUILD_MODE="-b"
fi

#
# Actually run the build
#
FAILED_COMPONENTS=()
RESULT=0
for TARGET_COMPONENT in "${TARGET_COMPONENTS[@]}"; do
    if [[ "$BUILD_ALL_FROM_SOURCE" != 1 ]]; then
        if orc install --pretend "$TARGET_COMPONENT" &> /dev/null; then
            log "Target component $TARGET_COMPONENT does not need rebuild"
            continue
        fi
    fi
    log "Building target component $TARGET_COMPONENT"
    if ! orc --quiet install "$BUILD_MODE" --test --create-binary-archives "$TARGET_COMPONENT"; then
        FAILED_COMPONENTS+=("$TARGET_COMPONENT")
        RESULT=1
    fi
done

#
# Record next-* head commits for promotion
#
if test "$RESULT" -eq 0; then
    log "Recording information for next-* branches promotion"

    # We also promote orchestra config because fix-binary-archive-symlinks
    # uses the current branch name
    CACHE_DIR="$ARTIFACTS_DIR/cache"
    mkdir -p "$CACHE_DIR"
    cp -r "$ORCHESTRA_DOTDIR/cache" "$CACHE_DIR/cache"
    orc components --json > "$ARTIFACTS_DIR/components.json"
    echo "SUCCESS" > "$ARTIFACTS_DIR/build_status"

    #for SOURCE_PATH in $(orc ls --git-sources) "$ORCHESTRA_ROOT"; do
    #    if test -e "$SOURCE_PATH/.git"; then
    #        cd "$SOURCE_PATH"
    #        BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    #        COMMIT="$(git rev-parse --short HEAD)"
    #        if test "${BRANCH:0:5}" == "next-"; then
    #            echo "$SOURCE_PATH;$BRANCH;$COMMIT" >> "$CI_PROJECT_DIR/cache/heads/$REVNG_COMPONENTS_DEFAULT_BUILD.csv"
    #        fi
    #        cd -
    #    fi
    #done
else
    echo "FAIL" > "$ARTIFACTS_DIR/build_status"
fi

if [[ "$PUSH_BINARY_ARCHIVES" = 1 ]] || [[ "$PUSH_CHANGES" = 1 ]]; then
    BINARY_ARCHIVE_BRANCH_NAME="$(git -C "$ORCHESTRA_ROOT" rev-parse --short HEAD || true)-$REVNG_COMPONENTS_DEFAULT_BUILD-$RANDOM"
    log "Pushing binary archives to branch $BINARY_ARCHIVE_BRANCH_NAME"
    echo "$BINARY_ARCHIVE_BRANCH_NAME" > "$ARTIFACTS_DIR/binary_archive_branch_name"

    # Remove old binary archives
    orc binary-archives clean

    # Push binary archives
    for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do

        cd "$BINARY_ARCHIVE_PATH"

        git config user.email "$PUSH_BINARY_ARCHIVE_EMAIL"
        git config user.name "$PUSH_BINARY_ARCHIVE_NAME"

        git checkout -b "$BINARY_ARCHIVE_BRANCH_NAME"

        # Ensure we track the correct files
        git lfs track "*.tar.*"
        git add .gitattributes
        if ! git diff --staged --exit-code -- .gitattributes > /dev/null; then
            git commit -m'Initialize .gitattributes'
        fi

        git add .

        if ! git diff --cached --quiet; then
            COMMIT_MSG="$(
                echo "Automatic binary archives"
                echo
                echo "ORCHESTRA_CONFIG_COMMIT=$(git -C "$ORCHESTRA_ROOT" rev-parse --short HEAD || true)"
                echo "ORCHESTRA_CONFIG_BRANCH=$(git -C "$ORCHESTRA_ROOT" name-rev --name-only HEAD || true)"
                echo "COMPONENT_TARGET_BRANCH=$COMPONENT_TARGET_BRANCH"
                echo "REVNG_COMPONENTS_DEFAULT_BUILD=$REVNG_COMPONENTS_DEFAULT_BUILD"
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
            git push -u origin "$BINARY_ARCHIVE_BRANCH_NAME"
            git lfs push origin "$BINARY_ARCHIVE_BRANCH_NAME"
        else
            log "No changes to push for $BINARY_ARCHIVE_PATH"
        fi

    done
else
    log "Skipping binary archives push (PUSH_BINARY_ARCHIVES='$PUSH_BINARY_ARCHIVES', PUSH_CHANGES='$PUSH_CHANGES')"
fi

if [[ "${#FAILED_COMPONENTS[*]}" -gt 0 ]]; then
    log_err "The following components failed: ${FAILED_COMPONENTS[*]}"
fi

exit "$RESULT"
