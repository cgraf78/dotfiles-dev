# Development-only Zsh integrations; `_tool_init` is inherited from base.

_tool_init sley _tool_shdeps_source_emit cgraf78/sley share/sley/shell.sh
_tool_init git-tools _tool_shdeps_source_emit cgraf78/git-tools share/git-tools/shell.sh
_dot_direnv_before=${functions[_direnv_hook]:-}
_tool_init direnv direnv hook zsh
# The direnv hook forks `direnv export` (~7ms) on every prompt even with no
# `.envrc` in scope. Gate it on an upward scan (~0.05ms): skip only when no
# `.envrc` exists upward AND no environment is loaded (a loaded diff means an
# unload may be pending). The hook body snapshot reinstalls only when
# `_tool_init` redefined the hook, so re-sourcing over our own gate can never
# recurse; any unexpected shape keeps the raw hook (today's behavior).
# Plain (not `local`/`typeset`) assignment: this file is sourced inside a
# function in production but at top level when probed. Unset below.
if (($+functions[_direnv_hook])) &&
  [[ ${functions[_direnv_hook]} != "$_dot_direnv_before" ]] &&
  functions -c _direnv_hook _dot_direnv_hook_orig 2>/dev/null; then
  _direnv_hook() {
    if [[ -n "${DIRENV_DIFF:-}" ]] || _dot_upward_envrc; then
      _dot_direnv_hook_orig "$@"
    fi
  }
fi
unset _dot_direnv_before
