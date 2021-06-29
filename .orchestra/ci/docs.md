# rev.ng CI scripts documentation

## Architecture

Currently, rev.ng CI runs in Gitlab CI, triggered by pushes to the public or private repositories.
The CI scripts take parameters from environment variables (see below for their documentation).
 
CI stages always run the entrypoint `ci.sh`. The first argument to `ci.sh` is the CI stage (`build` or `post-build`).

The entrypoint is responsible for checking out the correct configuration branch and exports some variables required by
the other scripts.

## Environment variables

- PUSHED_REF: Name of the branch which will be tried to be checked out first. Affects the configuration and all 
  components. Normally set by Gitlab or whoever triggers the CI.
  Format: refs/heads/<branchname>
  
- BASE_USER_OPTIONS_YML: user_options.yml is initialized to this value. %GITLAB_ROOT% is replaced with the base URL of 
  the Gitlab instance
  
- REVNG_ORCHESTRA_URL: orchestra git repo URL (must be git+ssh:// or git+https://)
  
### Optional
  
- IGNORE_ALL_NEXT_BRANCHES: If == 1 the list of branches to try to checkout for the configuration and the components
  will not include next-* branches, unless PUSHED_REF specifies a next-* branch
  
- IGNORE_CONFIG_NEXT_BRANCHES: If == 1 the list of branches to try to checkout for the configuration will not include 
  next-* branches, unless PUSHED_REF specifies a next-* branch
  
- PUSH_BINARY_ARCHIVES: if == 1, push binary archives
  
- PROMOTE_BRANCHES: if == 1, promote next-* branches
  
- IGNORE_ALL_NEXT_BRANCHES: if == 1 the list of branches to try to checkout for the configuration and the 
  components will not include next-* branches, unless PUSHED_REF specifies a next-* branch
  
- COMPONENTS_BLACKLIST: space separated list of regexes matching components that will not be built explicitly
- PUSH_CHANGES: if == 1, push binary archives and promote next-* branches
- REVNG_COMPONENTS_DEFAULT_BUILD: the preferred build for revng core components. Defaults to optimized.
- SSH_PRIVATE_KEY: private key used to push binary archives
- REVNG_ORCHESTRA_BRANCH: branch to use when installing orchestra from git
- BUILD_ALL_FROM_SOURCE: if == 1 do not use binary archives and build everything
- NOTES: echoed at the start of the run, useful for tagging manually executed CI jobs
