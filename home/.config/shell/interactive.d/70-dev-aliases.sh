# shellcheck shell=bash
# Development aliases and agent wrappers.

alias gl='git log --oneline --graph --decorate'
alias gll='git log --oneline --all --graph --decorate'
alias vs='code'

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
# Decide dispatch from option arity and the first positional argument. Values
# such as `-p review` are profiles, and resume session names are never commands.
# Unknown flags preserve native dispatch until their public arity is known.
__codex_local_tui() {
  local codex_positional=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --) return 0 ;;
      --remote | --remote=* | --remote-auth-token-env | --remote-auth-token-env=* | \
        --no-daemon | -h | --help | -V | --version) return 1 ;;
      -c | --config | --enable | --disable | -i | --image | -m | --model | \
        --local-provider | -p | --profile | -s | --sandbox | -C | --cd | \
        --add-dir | -a | --ask-for-approval)
        [[ $# -ge 2 ]] || return 1
        shift
        ;;
      --config=* | --enable=* | --disable=* | --image=* | --model=* | \
        --local-provider=* | --profile=* | --sandbox=* | --cd=* | --add-dir=* | \
        --ask-for-approval=* | -c?* | -i?* | -m?* | -p?* | -s?* | -C?* | -a?*) ;;
      --strict-config | --oss | --approve-for-me | \
        --dangerously-bypass-approvals-and-sandbox | --dangerously-bypass-hook-trust | \
        --worktree | --search | --no-alt-screen | --last | --all | \
        --include-non-interactive) ;;
      -*) return 1 ;;
      *)
        if [[ $codex_positional == 0 ]]; then
          case "$1" in
            exec | e | review | agents | app-server | remote-control | app | mcp | plugin | \
              login | logout | completion | update | doctor | sandbox | debug | apply | a | \
              queue | archive | delete | migrate-rollouts | migrate-nfs-db | unarchive | \
              cloud | exec-server | features | help) return 1 ;;
          esac
          codex_positional=1
        fi
        ;;
    esac
    shift
  done
}

codex() {
  # Shared Codex backends execute lifecycle hooks without the TUI's terminal.
  # Keep interactive local work in the foreground so AgentGuard can prove
  # pane ownership; never guess a thread's pane from cwd or process recency.
  # The override retains the shared-session mode when it is explicitly wanted.
  if [[ -t 0 && -t 1 && ${CODEX_USE_SHARED_DAEMON:-} != 1 ]] && __codex_local_tui "$@"; then
    command codex --dangerously-bypass-approvals-and-sandbox --no-daemon "$@"
  else
    command codex --dangerously-bypass-approvals-and-sandbox "$@"
  fi
}

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
