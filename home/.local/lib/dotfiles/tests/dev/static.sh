# shellcheck shell=bash

dot_dev_static_test() {
  local root=${DOT_TEST_SOURCE_HOME:-$HOME} pass=0 fail=0

  check_file() {
    local description=$1 path=$2
    if [[ -f $root/$path ]]; then
      printf 'PASS: %s\n' "$description"
      pass=$((pass + 1))
    else
      printf 'FAIL: %s (%s is missing)\n' "$description" "$path" >&2
      fail=$((fail + 1))
    fi
  }

  check_contains() {
    local description=$1 path=$2 pattern=$3
    if [[ -f $root/$path ]] && grep -F "$pattern" "$root/$path" >/dev/null; then
      printf 'PASS: %s\n' "$description"
      pass=$((pass + 1))
    else
      printf 'FAIL: %s (%s lacks %s)\n' "$description" "$path" "$pattern" >&2
      fail=$((fail + 1))
    fi
  }

  check_file 'global Git configuration is dev-owned' .config/git/config
  check_contains 'advanced Git tooling is selected' .config/shdeps/30-dev.conf cgraf78/git-tools
  check_contains 'development checks are selected' .config/shdeps/30-dev.conf cgraf78/checkrun
  check_contains 'development Nvim plugins are additive' .config/nvim/lua/plugins/git-dev.lua diffview.nvim
  check_contains 'development Nvim extras load after editor policy' .config/nvim/lua/plugins/zz-dev-extras.lua lazyvim.plugins.extras.dap.core

  if grep -F 'tmux' "$root/.config/mise/config.toml" "$root/.config/mise/mise.lock" \
    "$root/.local/lib/dotfiles/merge-hooks.d/mise.sh" >/dev/null; then
    printf 'FAIL: base-owned tmux remains in the dev Mise boundary\n' >&2
    fail=$((fail + 1))
  else
    printf 'PASS: base-owned tmux is absent from the dev Mise boundary\n'
    pass=$((pass + 1))
  fi

  if [[ ${DOT_PROFILE_FIXTURE:-0} != 1 ]]; then
    if [[ -e $root/.config/agent-rules ||
      -e $root/.local/lib/dotfiles/agent-rules-sync.sh ]] ||
      grep -F 'cgraf78/agent-rules-sync' "$root/.config/shdeps/30-dev.conf" >/dev/null 2>&1; then
      printf 'FAIL: base agent rules or agent-rules-sync leaked into dev\n' >&2
      fail=$((fail + 1))
    else
      printf 'PASS: base agent rules and agent-rules-sync remain absent\n'
      pass=$((pass + 1))
    fi
  fi

  "${DOT_TEST_REPORTER:?}" complete "$pass" "$fail"
  ((fail == 0))
}
