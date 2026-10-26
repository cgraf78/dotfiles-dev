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
gh-ci-status --no-scheduled  # skip scheduled runs and missing-rollup recovery
```

Only repositories the owner owns are listed; archived repositories and forks
are skipped unless `--include-archived` or `--include-forks` is given.
When GitHub reports no check rollup for a default-branch commit, the normal
view reads classic branch protection's required check runs and commit statuses
on that commit. It reports a pass only when each required context has a passing
result from the configured GitHub App; unrelated checks cannot make the branch
green. A protected branch with unavailable required-check metadata stays
unknown. The same row distinguishes no active workflows from missing required
checks. `--no-scheduled` retains the faster rollup-only view. Repositories
without a current CI result report `none` and never fail the run. Each
repository's oldest 30 open pull requests are checked, and a longer queue
prints a warning.

Scheduled runs catch nightly failures that a later push would otherwise hide,
since a push moves the default branch past the commit the nightly ran on.
Failing, running, or stale scheduled runs are listed under their repository;
runs from inactive workflows, older than 45 days, or cancelled/skipped are
ignored. A run waiting on an approval counts as failing because it needs a
person. An active workflow whose newest scheduled run is older than
`--stale-days` (default: 10) fails as stale, so a schedule that suddenly stops
cannot keep reporting its last pass as ok; workflows that run less often need
a higher value, and 45 or higher disables stale detection.

Exit status is 0 when nothing failed (checks still running are not failures),
1 on any failure or query error, 2 on a usage or local environment error, and
8 when `--watch` times out with checks still pending.

This command is self-contained rather than a launcher: it is one script with
no provider of its own. Extract it to a provider repository if it grows an
independent lifecycle.
