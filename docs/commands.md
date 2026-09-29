# Development commands

Executable files below `home/.local/bin/` are development-facing launchers.
Reusable implementation remains in each provider repository; this overlay owns
only activation and user-environment policy.

## `gh-ci-status`

Summarizes CI for every repository an owner has on GitHub: each default
branch's latest check rollup, the latest scheduled run of each active workflow
on that branch, and every open pull request's rollup, draft, and auto-merge
state. Repositories are discovered live on every run, so new
repositories appear without configuration.

```sh
gh-ci-status                 # authenticated gh user, all repositories
gh-ci-status --failing       # only failing or pending items
gh-ci-status --watch         # poll until nothing is pending (30 min cap)
gh-ci-status --owner my-org  # another user or organization
gh-ci-status --porcelain     # key=value summary plus tab-separated records
gh-ci-status --no-scheduled  # skip scheduled runs (one fewer call per repo)
```

Only repositories the owner owns are listed; archived repositories and forks
are skipped unless `--include-archived` or `--include-forks` is given.
Repositories without CI report `none` and never fail the run. Each repository's
oldest 30 open pull requests are checked, and a longer queue prints a warning.

Scheduled runs catch nightly failures that a later push would otherwise hide,
since a push moves the default branch past the commit the nightly ran on.
Failing or running scheduled runs are listed under their repository; runs from
inactive workflows, older than 45 days, or cancelled/skipped are ignored. A
run waiting on an approval counts as failing because it needs a person.

Exit status is 0 when nothing failed (checks still running are not failures),
1 on any failure or query error, 2 on a usage or local environment error, and
8 when `--watch` times out with checks still pending.

This command is self-contained rather than a launcher: it is one script with
no provider of its own. Extract it to a provider repository if it grows an
independent lifecycle.
