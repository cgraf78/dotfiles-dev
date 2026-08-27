# shellcheck shell=bash
# Development aliases and agent wrappers.

alias gl='git log --oneline --graph --decorate'
alias gll='git log --oneline --all --graph --decorate'

lg() {
  local git_dir
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  if [[ "$git_dir" == "$HOME/.dotfiles" ]]; then
    lazygit --git-dir="$git_dir" --work-tree="$HOME" "$@"
  else
    lazygit "$@"
  fi
}

claude() { command claude --dangerously-skip-permissions "$@"; }
codex() { command codex --dangerously-bypass-approvals-and-sandbox "$@"; }

muse() {
  case "${1-}" in
    exec | resume)
      local muse_cmd=$1
      shift
      command muse "$muse_cmd" --yolo "$@"
      ;;
    export | trace | skills | sandbox | session-message | auth | login | logout | init)
      command muse "$@"
      ;;
    *) command muse --yolo "$@" ;;
  esac
}

opencode() {
  if [[ "${1-}" == run ]]; then
    shift
    command opencode run --auto "$@"
  elif [[ $# -eq 0 || "${1-}" == -* || -d "${1-}" ]]; then
    command opencode --auto "$@"
  else
    command opencode "$@"
  fi
}
