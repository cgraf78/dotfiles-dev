# git-tools Landing and Cleanup

<!-- agent-rule-id: dev-git-tools-cleanup -->
<!-- agent-rule-trigger: Landing a GitHub pull request or removing its merged branch and completed worktree -->

git-tools (`git pr-land`, `git cleanup-repo`) proves squash, rebase, and
stacked landings exactly before it deletes a branch or removes a worktree. It
is this host's tooling for the base playbook's "remove the completed worktree
with its merged branch" step.

- Land only when the requested work includes landing, and only after
  `git pr-watch` (git-tools/pr-watch.md) reported the pull request's current
  head done. `git pr-land` checks readiness again and refuses a pull request
  that is not ready; do not merge around it with `gh pr merge`. Run it alone,
  not piped to `tail` or followed by other commands, so its exit status is
  the result you act on.
- After it merges, `git pr-land` publishes the merged result the watch hook
  reads (through a one-shot `git pr-watch`), so no further watcher is needed.
  If it prints `next: git pr-watch <pr>`, the record could not be published;
  run that command once.
- From the main checkout, or any checkout other than the pull request's own
  worktree, `git pr-land` lands the pull request, then deletes the local head
  when every local commit is in what landed, removing its clean linked
  worktree first. It refuses a main checkout Git reaches only through
  `core.worktree`, such as the base dotfiles checkout of `$HOME`; land from a
  linked worktree of that repository instead.
- If you landed from the pull request's own worktree (`git pr-land` never
  removes the current worktree), or it merged another way, run
  `git cleanup-repo --no-update-base --worktree <worktree> --min-age 1`
  from the main checkout (for base dotfiles, from `$HOME`). It also deletes
  the repository's other proven-merged branches that have no checkout.
- `--worktree` alone scopes removal to the worktrees it names.
  Never pass `--remove-worktrees`, alone or with `--worktree`: an explicit
  `--remove-worktrees` removes every eligible worktree, including clean ones
  concurrent agents just created.
- A branch landed by a merge commit or fast-forward is proven only by
  ancestry, and `--min-age 1` keeps it until a day after it was created or
  last moved; while the branch is kept, its selected worktree is kept too, so
  rerun the cleanup later.
- Run the cleanup with the shell's working directory outside the completed
  worktree: a process whose working directory is inside it, including the
  shell running the cleanup, keeps the worktree in use. If your own agent
  session runs inside it (a runtime-native worktree), cleanup reports it
  `in-use` for the life of the session; leave it for a later run.
- When either command keeps a branch or worktree, report the reason it
  prints (`git cleanup-repo --porcelain` gives the code) instead of forcing
  removal with `git worktree remove --force` or `git branch -D`.
  `unique-commits` names a commit only the worktree's reflog or own refs
  hold, `unpublished` a branch with commits never pushed, and
  `uninspectable` state cleanup could not read (reftable reflogs included);
  show the user what it names and let them decide.
- Run `dot-worktree-gc` (its cross-clone sweep of old worktrees and merged
  branches) only when the user asks for a cross-clone cleanup, and review its
  default dry run before `--apply`.
