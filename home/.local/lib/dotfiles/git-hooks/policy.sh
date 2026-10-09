# shellcheck shell=bash
# policy.sh — shared agent and repository facts for dotfiles' Git hooks.
#
# Sourced by `commit-msg` and `pre-push`; not a hook itself (the dot in its
# name keeps Git, `dot doctor`, and readers from treating it as one). Hooks
# may run under macOS /bin/bash 3.2, so keep this Bash 3.2 compatible.
#
# The global hooksPath reaches every clone on the machine, including
# third-party projects with their own conventions. Owner-specific policy is
# therefore scoped by remote ownership, and agent-specific policy by
# AgentGuard's runtime detection, so neither leaks into unrelated work.

# GitHub account whose repositories follow the dotfiles commit and branch
# conventions. Any other owner is third-party for policy purposes.
_GITHOOK_OWNER=cgraf78

# _githook_lower STRING
#   Print STRING in lowercase. GitHub owner and repository names are
#   case-insensitive; Bash 3.2 has no ${var,,}.
_githook_lower() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'
}

# _githook_remote_repo URL
#   Print the lowercase "owner/repo" a hosted remote URL names, or return 1
#   for local paths and anything that is not exactly two path segments.
#   Accepts scheme URLs (https://, ssh://, git://) and scp-like
#   `host:owner/repo` forms, including SSH host aliases such as
#   `github-dotfiles-work:cgraf78/dotfiles-work.git`.
_githook_remote_repo() {
  local url=$1 rest host

  case $url in
    '' | /* | ./* | ../* | '~'* | file://*) return 1 ;;
    *://*)
      rest=${url#*://}
      # Drop user@host[:port]; GitHub never nests owners below the host.
      case $rest in */*) rest=${rest#*/} ;; *) return 1 ;; esac
      ;;
    *:*)
      # Git treats `a/b:c` as a local path: scp syntax requires no slash
      # before the first colon.
      host=${url%%:*}
      case $host in */*) return 1 ;; esac
      rest=${url#*:}
      ;;
    *) return 1 ;;
  esac

  # Servers ignore leading, doubled, and trailing slashes (`host:/owner/x`,
  # `https://host//owner/x/`); normalize them so those spellings cannot
  # slip past the two-segment check.
  while :; do
    case $rest in
      /*) rest=${rest#/} ;;
      *//*) rest=${rest%%//*}/${rest#*//} ;;
      */) rest=${rest%/} ;;
      *) break ;;
    esac
  done
  # Transports also resolve dot segments (`cgraf78/./x`, `y/../cgraf78/x`).
  rest=$(_githook_dot_segments "$rest")
  rest=${rest%.git}
  case $rest in
    */*/* | '') return 1 ;;
    */*) _githook_lower "$rest" ;;
    *) return 1 ;;
  esac
}

# _githook_dot_segments PATH
#   Resolve `.` and `..` segments in a slash-separated relative PATH. Runs in
#   a subshell so the IFS and noglob changes cannot leak into the hook.
_githook_dot_segments() (
  part='' out=''
  IFS=/
  set -f
  # shellcheck disable=SC2086 # split on IFS=/ deliberately, globbing is off.
  for part in $1; do
    case $part in
      '' | .) ;;
      ..) case $out in */*) out=${out%/*} ;; *) out='' ;; esac ;;
      *) out=${out:+$out/}$part ;;
    esac
  done
  printf '%s\n' "$out"
)

# _githook_owned_url URL
#   Return 0 when URL is a hosted repository owned by $_GITHOOK_OWNER.
_githook_owned_url() {
  local repo
  repo=$(_githook_remote_repo "$1") || return 1
  [ "${repo%%/*}" = "$_GITHOOK_OWNER" ]
}

# _githook_fork
#   Return 0 when the current repository has an `upstream` remote owned by
#   someone else: an owner-hosted fork of a third-party project follows that
#   project's conventions, not the owner's.
_githook_fork() {
  local url repo
  url=$(git remote get-url upstream 2>/dev/null) || return 1
  # A local mirror or unparsable `upstream` says nothing about ownership.
  repo=$(_githook_remote_repo "$url") || return 1
  [ "${repo%%/*}" != "$_GITHOOK_OWNER" ]
}

# _githook_owned_origin
#   Return 0 when the current repository's origin is owned by
#   $_GITHOOK_OWNER and the repository is not a fork. Repositories without an
#   origin are treated as third-party: there is no ownership signal to act on.
#   `git remote get-url` applies insteadOf rewrites, so an alias cannot hide
#   the owner.
_githook_owned_origin() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  _githook_owned_url "$url" && ! _githook_fork
}

# _githook_agent_session
#   Return 0 when AgentGuard detects an AI agent session. AgentGuard owns the
#   runtime-identity contract (Claude, Codex, Muse, ...); duplicating its env
#   and process-tree heuristics here would drift. When AgentGuard cannot be
#   resolved, warn and report a human session so a broken install degrades to
#   the advisory policy instead of locking anyone out.
_githook_agent_session() {
  local assets=${HOME:-}/.local/lib/dotfiles/shdeps-assets.sh

  if ! command -v agentguard_is_session >/dev/null 2>&1; then
    # shellcheck source=/dev/null # base-owned helper, absent from this overlay.
    if ! { [ -r "$assets" ] && . "$assets" &&
      dot_shdeps_dep_source cgraf78/agentguard lib/agentguard/agentguard.sh; } \
      >/dev/null 2>&1 ||
      ! command -v agentguard_is_session >/dev/null 2>&1; then
      echo "git hook: AgentGuard is unavailable (run dot update); applying human policy" >&2
      return 1
    fi
  fi
  agentguard_is_session
}
