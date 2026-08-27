# shellcheck shell=bash

dot_dev_launchers_test() {
  local root=${DOT_TEST_SOURCE_HOME:-$HOME} pass=0 fail=0 path
  local -a required=(
    .local/bin/hm
    .local/lib/dotfiles/git-hooks/pre-commit
    .local/lib/dotfiles/git-hooks/commit-msg
    .local/lib/dotfiles/sley-hooks/validate-commit-msg
  )

  for path in "${required[@]}"; do
    if [[ -x $root/$path ]]; then
      pass=$((pass + 1))
    else
      printf 'FAIL: dev launcher is not executable: %s\n' "$path" >&2
      fail=$((fail + 1))
    fi
  done

  if [[ -e $root/.config/agent-rules ||
    -e $root/.local/lib/dotfiles/agent-rules-sync.sh ]]; then
    printf 'FAIL: base agent-rule payload leaked into dev\n' >&2
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi

  "${DOT_TEST_REPORTER:?}" complete "$pass" "$fail"
  ((fail == 0))
}
