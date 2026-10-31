# git-tools Pull Request Watching

<!-- agent-rule-id: dev-git-tools-pr-watch -->
<!-- agent-rule-trigger: Monitoring a GitHub pull request's checks to green -->

`git pr-watch` judges each pull request on its current head: the newest run of
each workflow, only finished runs counted green, failures confirmed against
automatic re-runs, plus merge conflicts and auto-merge. It is this host's
watcher for the base playbook's "Monitor checks to green" step. Where GitHub
is reachable only through a host wrapper, follow the on-demand playbook that
names that wrapper first; it says how to run this watcher, if at all.

- After creating a pull request, after every push, and after enabling
  auto-merge, run `git pr-watch --wait <pr>...` with the runtime's background
  execution, so its exit wakes you. One call takes several pull requests of
  one repository. It follows a new head itself, and when run from the clone
  (or a worktree of the clone) you pushed from, it waits out GitHub catching
  up with that push. After pushing from elsewhere, or to a fork, check that
  each `pr=` line's `head=` is the commit you pushed.
- Run the watcher alone: no pipe (`| tail`), no command after it (`; echo
  $?`, `|| true`). The completion notice carries the watcher's exit status
  only when it is the whole command, and a `tail` can cut the report. Its
  final line, `result: <status> reason=<word> prs=<list>`, restates the
  outcome.
- Act on its exit status:
  - `0`: every pull request is done: checks green, or merged once auto-merge
    is on. Read each `pr=` line's `reason`: `review-required` or
    `changes-requested` means green checks still waiting on review.
  - `1`: one needs action, and the whole watch ends. `check` lines name
    failing checks and each `run:` line is a command that prints a failed
    job's full log, also while the rest of its workflow run is still going.
    Read the log before deciding a failure is a flake; rerun a job only when
    the log shows an infrastructure flake. A conflict, a closed pull
    request, falling behind, or auto-merge turned off is reported the same
    way. Fix, push, and watch again.
  - `8`: still pending at its time cap, or stalled. Each `action:` line names
    what a stalled pull request waits on (a review, a maintainer's approval, a
    check that never reported); report that instead of restarting the watch.
  - `3`: GitHub could not be read; rerun the printed `next:` line, or the
    original command when none is printed.
  - `2`: usage, authentication, or environment; fix the cause, then rerun.
- Restart a watch with the printed `next:` line: it lists only the pull
  requests not yet finished.
