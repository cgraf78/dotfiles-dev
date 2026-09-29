# Development commands

Executable files below `home/.local/bin/` are development-facing launchers.
Reusable implementation remains in each provider repository; this overlay owns
only activation and user-environment policy.

## `gh-ci-status`

Summarizes CI for every repository an owner has on GitHub: each default
branch's latest check rollup plus every open pull request's rollup, draft, and
auto-merge state. Repositories are discovered live on every run, so new
repositories appear without configuration.

```sh
gh-ci-status                 # authenticated gh user, all repositories
gh-ci-status --failing       # only failing or pending items
gh-ci-status --watch         # poll until nothing is pending (30 min cap)
gh-ci-status --owner my-org  # another user or organization
gh-ci-status --porcelain     # key=value summary plus tab-separated records
```

Only repositories the owner owns are listed; archived repositories and forks
are skipped unless `--include-archived` or `--include-forks` is given.
Repositories without CI report `none` and never fail the run. Each repository's
oldest 30 open pull requests are checked, and a longer queue prints a warning.
Exit status is 0 when everything with checks passed, 1 on any failure or query
error, 2 on a usage or local environment error, and 8 when nothing failed but
checks are still pending.

This command is self-contained rather than a launcher: it is one script with
no provider of its own. Extract it to a provider repository if it grows an
independent lifecycle.
