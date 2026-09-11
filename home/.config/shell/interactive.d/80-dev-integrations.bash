# shellcheck shell=bash
# Development-only Bash integrations; `_tool_init` is inherited from base.

_tool_init sley _tool_shdeps_source_emit cgraf78/sley share/sley/shell.sh
_tool_init git-tools _tool_shdeps_source_emit cgraf78/git-tools share/git-tools/shell.sh
_dot_direnv_before=$(declare -f _direnv_hook 2>/dev/null) || true
_tool_init direnv direnv hook bash
# The direnv hook forks `direnv export` (~7ms) on every prompt even with no
# `.envrc` in scope. Gate it on an upward scan (~0.05ms): skip only when no
# `.envrc` exists upward AND no environment is loaded (a loaded diff means an
# unload may be pending). The hook body snapshot reinstalls only when
# `_tool_init` redefined the hook, so re-sourcing over our own gate can never
# recurse; any unexpected shape keeps the raw hook (today's behavior).
# Plain (not `local`) assignments: this file is sourced inside a function in
# production but at top level when probed, and `local` fails outside
# functions. Both are unset below.
_dot_direnv_after=$(declare -f _direnv_hook 2>/dev/null) || true
if [[ -n $_dot_direnv_after && $_dot_direnv_after != "$_dot_direnv_before" &&
  $_dot_direnv_after == *$'\n'* ]]; then
  eval "_dot_direnv_hook_orig() ${_dot_direnv_after#*$'\n'}"
  _direnv_hook() {
    local _st=$?
    if [[ -n "${DIRENV_DIFF:-}" ]] || _dot_upward_envrc; then
      _dot_direnv_hook_orig "$@"
      _st=$?
    fi
    return "$_st"
  }
fi
unset _dot_direnv_before _dot_direnv_after
