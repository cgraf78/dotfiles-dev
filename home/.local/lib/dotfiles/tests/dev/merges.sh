# shellcheck shell=bash

dot_dev_merges_test() {
  local root=${DOT_TEST_SOURCE_HOME:-$HOME} pass=0 fail=0 path
  local -a required=(
    .local/lib/dotfiles/merge-hooks.d/claude.sh
    .local/lib/dotfiles/merge-hooks.d/codex.sh
    .local/lib/dotfiles/merge-hooks.d/gh.sh
    .local/lib/dotfiles/merge-hooks.d/git.sh
    .local/lib/dotfiles/merge-hooks.d/gstack.sh
    .local/lib/dotfiles/merge-hooks.d/hive-memory.sh
    .local/lib/dotfiles/merge-hooks.d/mise.sh
    .local/lib/dotfiles/merge-hooks.d/vscode.sh
  )

  for path in "${required[@]}"; do
    if [[ -f $root/$path ]] && bash -n "$root/$path"; then
      pass=$((pass + 1))
    else
      printf 'FAIL: missing or invalid merge hook: %s\n' "$path" >&2
      fail=$((fail + 1))
    fi
  done

  "${DOT_TEST_REPORTER:?}" complete "$pass" "$fail"
  ((fail == 0))
}
