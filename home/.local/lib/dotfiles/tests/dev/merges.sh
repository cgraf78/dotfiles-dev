# shellcheck shell=bash
# Development merge-hook behavior split from the frozen monolith.

# shellcheck source=helpers.sh
. "${BASH_SOURCE[0]%/*}/helpers.sh"

dot_dev_merges_test() {
  set +e +u
  local owner_root
  owner_root=$(_dev_repo_root)
  REAL_HOME=$owner_root/home
  TEST_HOME=$(_tmpdir)
  DOT_TEST_SOURCE_HOME=$REAL_HOME
  export REAL_HOME TEST_HOME DOT_TEST_SOURCE_HOME
  mkdir -p "$TEST_HOME"
  HOME=$TEST_HOME
  DOT_QUIET=0
  export HOME DOT_QUIET
  unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME
  mkdir -p "$TEST_HOME/.config"
  cp -R "$REAL_HOME/.config/dot" "$TEST_HOME/.config/dot"
  DOT_TEST_SLEY_ROOT=$TEST_HOME/provider-sley
  mkdir -p "$DOT_TEST_SLEY_ROOT/share/sley/vscode/sley-tools-0.0.1"
  cat >"$DOT_TEST_SLEY_ROOT/share/sley/vscode/sley-tools-0.0.1/package.json" <<'JSON'
{"name":"sley-tools","displayName":"Sley Tools","publisher":"cgraf","version":"0.0.1","engines":{"vscode":"^1.80.0"},"main":"./extension.js"}
JSON
  printf '%s\n' 'module.exports = { activate() {}, deactivate() {} };' \
    >"$DOT_TEST_SLEY_ROOT/share/sley/vscode/sley-tools-0.0.1/extension.js"
  export DOT_TEST_SLEY_ROOT
  merge_support_bin=$(_mock_bin)
  cat >"$merge_support_bin/cmp" <<'CMP'
#!/usr/bin/env bash
[[ ${1:-} != -s ]] || shift
git diff --no-index --quiet -- "$1" "$2"
CMP
  chmod +x "$merge_support_bin/cmp"
  PATH="$merge_support_bin:$PATH"
  export PATH
  # shellcheck source=load-merge-api.sh
  . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh" || {
    _fail 'Development merge tests load the public Dot hook API'
    return
  }

  echo "=== Agent CLI merge hook gates ==="

  agent_gate_home="$TEST_HOME/agent-cli-gate-home"
  agent_gate_empty_path="$TEST_HOME/agent-cli-gate-empty-path"
  agent_gate_marker="$agent_gate_home/downstream-reached"
  mkdir -p "$agent_gate_home" "$agent_gate_empty_path"

  _run_agent_cli_gate_for_test() (
    local agent="$1" cli_present="$2"

    unset -f merge codex claude gemini opencode muse 2>/dev/null
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/$agent.sh"
    case "$agent" in
      codex)
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced hook.
        dot_codex_config_merge() { : >"$agent_gate_marker"; }
        ;;
      claude | gemini | muse)
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced hook.
        _merge_hook_jq_available() {
          : >"$agent_gate_marker"
          return 1
        }
        ;;
      opencode)
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced hook.
        dot_agentguard_integration_file() {
          : >"$agent_gate_marker"
          return 1
        }
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced hook.
        _warn() { :; }
        ;;
    esac
    if [[ "$cli_present" == yes ]]; then
      eval "$agent() { :; }"
    fi
    HOME="$agent_gate_home" PATH="$agent_gate_empty_path" merge
  )

  for agent in codex claude gemini opencode muse; do
    case "$agent" in
      codex) agent_gate_target="$agent_gate_home/.codex/config.toml" ;;
      claude) agent_gate_target="$agent_gate_home/.claude/settings.json" ;;
      gemini) agent_gate_target="$agent_gate_home/.gemini/settings.json" ;;
      opencode)
        agent_gate_target="$agent_gate_home/.config/opencode/plugins/dotfiles-agentguard.js"
        ;;
      muse) agent_gate_target="$agent_gate_home/.config/muse/settings.json" ;;
    esac
    mkdir -p "${agent_gate_target%/*}"
    printf 'preserved-%s\n' "$agent" >"$agent_gate_target"

    rm -f "$agent_gate_marker"
    agent_gate_output=$(_run_agent_cli_gate_for_test "$agent" no 2>&1)
    agent_gate_status=$?
    _assert_exit "$agent merge: absent CLI is a successful no-op" \
      0 "$agent_gate_status"
    _assert_eq "$agent merge: absent CLI emits no output" \
      "" "$agent_gate_output"
    _assert_eq "$agent merge: absent CLI does not reach downstream work" \
      "missing" "$(test -e "$agent_gate_marker" && printf present || printf missing)"
    _assert_eq "$agent merge: absent CLI preserves existing state" \
      "preserved-$agent" "$(cat "$agent_gate_target")"

    rm -f "$agent_gate_marker"
    _run_agent_cli_gate_for_test "$agent" yes >/dev/null 2>&1
    agent_gate_installed_status=$?
    case "$agent" in
      opencode) agent_gate_expected_status=1 ;;
      *) agent_gate_expected_status=0 ;;
    esac
    _assert_exit "$agent merge: installed CLI retains downstream status" \
      "$agent_gate_expected_status" "$agent_gate_installed_status"
    _assert_eq "$agent merge: installed CLI reaches existing merge behavior" \
      "present" "$(test -e "$agent_gate_marker" && printf present || printf missing)"
  done
  unset -f _run_agent_cli_gate_for_test merge 2>/dev/null

  # The remaining cases exercise each hook's merge behavior, not platform
  # discovery. Keep those fixtures deterministic even when they run in clean
  # child shells or on CI hosts without the corresponding desktop application.
  # shellcheck disable=SC2329 # Invoked indirectly by sourced hooks.
  _dot_tool_present() { return 0; }
  export -f _dot_tool_present

  echo "=== OpenCode AgentGuard merge hook ==="

  opencode_hook="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/opencode.sh"
  if [[ ! -r "$opencode_hook" ]]; then
    _fail "OpenCode merge: hook exists"
  else
    opencode_home="$TEST_HOME/opencode-merge-home"
    opencode_source="$opencode_home/source"
    opencode_plugins="$opencode_home/.config/opencode/plugins"
    opencode_target="$opencode_plugins/dotfiles-agentguard.js"
    opencode_other="$opencode_plugins/unrelated.js"
    opencode_link_target="$opencode_home/unmanaged-target.js"
    mkdir -p "$opencode_source" "$opencode_plugins"
    cat >"$opencode_source/agentguard.js" <<'OPENCODE_PLUGIN'
// agentguard-managed:opencode-plugin
export const AgentGuardPlugin = async () => ({})
OPENCODE_PLUGIN
    printf '%s\n' 'export const unrelated = true' >"$opencode_other"

    _run_opencode_merge_for_test() (
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$opencode_hook"
      # shellcheck disable=SC2329 # Detected indirectly by command -v.
      opencode() { :; }
      # shellcheck disable=SC2329 # Invoked by the sourced merge hook.
      dot_agentguard_integration_file() {
        [[ "$1" == "opencode" && "$2" == "agentguard.js" ]] || return 1
        printf '%s\n' "$opencode_source/agentguard.js"
      }
      merge
    )

    HOME="$opencode_home" _run_opencode_merge_for_test
    _assert_eq "OpenCode merge: installs the managed plugin" "yes" \
      "$(test -f "$opencode_target" && test ! -L "$opencode_target" && printf yes || printf no)"
    _assert_exit "OpenCode merge: installed bytes match the source" 0 \
      "$(
        cmp -s "$opencode_source/agentguard.js" "$opencode_target"
        printf '%s' "$?"
      )"
    _assert_eq "OpenCode merge: preserves unrelated plugins" \
      "export const unrelated = true" "$(cat "$opencode_other")"

    opencode_identity_before=$(
      stat -c '%i:%Y' "$opencode_target" 2>/dev/null ||
        stat -f '%i:%m' "$opencode_target"
    )
    opencode_listing_before=$(
      printf '%s\n' "$opencode_plugins"/* | sed 's#.*/##' | LC_ALL=C sort
    )
    HOME="$opencode_home" _run_opencode_merge_for_test
    opencode_identity_after=$(
      stat -c '%i:%Y' "$opencode_target" 2>/dev/null ||
        stat -f '%i:%m' "$opencode_target"
    )
    _assert_eq "OpenCode merge: unchanged rerun preserves inode and mtime" \
      "$opencode_identity_before" "$opencode_identity_after"
    _assert_eq "OpenCode merge: unchanged rerun creates no sibling or duplicate" \
      "$opencode_listing_before" \
      "$(printf '%s\n' "$opencode_plugins"/* | sed 's#.*/##' | LC_ALL=C sort)"

    cat >"$opencode_source/agentguard.js" <<'OPENCODE_PLUGIN'
// agentguard-managed:opencode-plugin
export const AgentGuardPlugin = async () => ({ event: async () => {} })
OPENCODE_PLUGIN
    HOME="$opencode_home" _run_opencode_merge_for_test
    _assert_exit "OpenCode merge: changed managed source updates the target" 0 \
      "$(
        cmp -s "$opencode_source/agentguard.js" "$opencode_target"
        printf '%s' "$?"
      )"

    opencode_managed_before=$(cat "$opencode_target")
    printf '%s\n' 'export const malformedSource = true' \
      >"$opencode_source/agentguard.js"
    HOME="$opencode_home" _run_opencode_merge_for_test >/dev/null 2>&1
    _assert_eq "OpenCode merge: invalid source marker preserves the managed target" \
      "$opencode_managed_before" "$(cat "$opencode_target")"
    cat >"$opencode_source/agentguard.js" <<'OPENCODE_PLUGIN'
// agentguard-managed:opencode-plugin
export const AgentGuardPlugin = async () => ({ event: async () => {} })
OPENCODE_PLUGIN

    printf '%s\n' 'export const userOwned = true' >"$opencode_target"
    HOME="$opencode_home" _run_opencode_merge_for_test >/dev/null 2>&1
    _assert_eq "OpenCode merge: preserves an unmanaged regular target" \
      "export const userOwned = true" "$(cat "$opencode_target")"

    rm -f "$opencode_target"
    printf '%s\n' 'export const linkTarget = true' >"$opencode_link_target"
    ln -s "$opencode_link_target" "$opencode_target"
    HOME="$opencode_home" _run_opencode_merge_for_test >/dev/null 2>&1
    _assert_eq "OpenCode merge: preserves an unmanaged target symlink" "yes" \
      "$(test -L "$opencode_target" && printf yes || printf no)"
    _assert_eq "OpenCode merge: does not modify a symlink target" \
      "export const linkTarget = true" "$(cat "$opencode_link_target")"

    rm -f "$opencode_target" "$opencode_source/agentguard.js"
    cat >"$opencode_target" <<'OPENCODE_PLUGIN'
// agentguard-managed:opencode-plugin
export const AgentGuardPlugin = async () => ({})
OPENCODE_PLUGIN
    opencode_missing_output=$(HOME="$opencode_home" \
      _run_opencode_merge_for_test 2>&1)
    opencode_missing_status=$?
    _assert_exit "OpenCode merge: absent dependency is a failed refresh" \
      1 "$opencode_missing_status"
    _assert_contains "OpenCode merge: absent dependency reports the failed refresh" \
      "AgentGuard opencode integration unavailable" "$opencode_missing_output"
    _assert_eq "OpenCode merge: absent dependency preserves last known-good plugin" \
      "yes" "$(test -e "$opencode_target" && printf yes || printf no)"

    rm -f "$opencode_target"
    opencode_missing_output=$(HOME="$opencode_home" \
      _run_opencode_merge_for_test 2>&1)
    opencode_missing_status=$?
    _assert_exit "OpenCode merge: cold bootstrap without provider fails visibly" \
      1 "$opencode_missing_status"
    _assert_eq "OpenCode merge: cold bootstrap does not install a partial plugin" \
      "missing" "$(test -e "$opencode_target" && printf present || printf missing)"

    rm -f "$opencode_source/agentguard.js"
    printf '%s\n' 'export const userOwned = true' >"$opencode_target"
    opencode_missing_output=$(HOME="$opencode_home" \
      _run_opencode_merge_for_test 2>&1)
    opencode_missing_status=$?
    _assert_exit "OpenCode merge: absent source with unmanaged target still fails refresh" \
      1 "$opencode_missing_status"
    _assert_eq "OpenCode merge: absent source preserves an unmanaged target" \
      "export const userOwned = true" "$(cat "$opencode_target")"
    unset -f _run_opencode_merge_for_test merge 2>/dev/null
  fi

  echo "=== Native AgentGuard JSON layers ==="

  agentguard_fixture="$TEST_HOME/agentguard-integration-assets"
  mkdir -p \
    "$agentguard_fixture/_shared" \
    "$agentguard_fixture/claude" \
    "$agentguard_fixture/gemini" \
    "$agentguard_fixture/muse"

  # These fixtures intentionally use made-up events and commands. This suite
  # owns the consumer contract: dotfiles passes the live and incoming documents
  # to provider-owned reconciliation, commits its result atomically, and then
  # applies local policy. AgentGuard's own suite owns the real command-ownership
  # predicate and per-agent vocabulary.
  for json_agent in claude gemini muse; do
    printf '{"hooks":{"ProviderEvent":[{"hooks":[{"type":"command","command":"provider-%s-v2"}]}]}}\n' \
      "$json_agent" >"$agentguard_fixture/$json_agent/hooks.json"
  done
  cat >"$agentguard_fixture/_shared/reconcile-hooks.jq" <<'JQ'
# Neutral provider fixture: replace the provider-owned event generation, retire
# a provider event, and preserve every other live setting. The production
# ownership rules belong to AgentGuard and are tested there.
($d[0] // {}) as $live |
$s[0] as $provider |
($live * ($provider | del(.hooks))) |
.hooks = (($live.hooks // {}) + ($provider.hooks // {})) |
del(.hooks.ProviderRetired)
JQ

  json_agent_home="$TEST_HOME/json-agent-merge-home"
  mkdir -p \
    "$json_agent_home/.config/dot/merge-hooks.d/claude/settings.d" \
    "$json_agent_home/.config/dot/merge-hooks.d/gemini/settings.d" \
    "$json_agent_home/.config/dot/merge-hooks.d/muse/settings.d"
  printf '{"permissions":{"allow":["LocalClaudePolicy"]}}\n' \
    >"$json_agent_home/.config/dot/merge-hooks.d/claude/settings.d/20-policy.json"
  printf '{"permissions":{"allow":["LocalMusePolicy"]}}\n' \
    >"$json_agent_home/.config/dot/merge-hooks.d/muse/settings.d/20-policy.json"

  _run_agentguard_json_merge_for_test() (
    local agent="$1" home="$2"
    unset -f merge 2>/dev/null
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/$agent.sh"
    eval "$agent() { :; }"
    # shellcheck disable=SC2329 # Invoked by the sourced merge hook.
    dot_agentguard_integration_file() {
      if [[ "$1" == "$agent" && "$2" == "hooks.json" ]]; then
        printf '%s/%s/hooks.json\n' "$agentguard_fixture" "$agent"
      elif [[ "$1" == "_shared" && "$2" == "reconcile-hooks.jq" ]]; then
        printf '%s/_shared/reconcile-hooks.jq\n' "$agentguard_fixture"
      else
        return 1
      fi
    }
    HOME="$home" merge
  )

  for json_agent in claude gemini muse; do
    case "$json_agent" in
      claude) json_target="$json_agent_home/.claude/settings.json" ;;
      gemini) json_target="$json_agent_home/.gemini/settings.json" ;;
      muse) json_target="$json_agent_home/.config/muse/settings.json" ;;
    esac
    mkdir -p "${json_target%/*}"
    json_legacy="$json_agent_home/$json_agent-legacy-settings.json"
    cat >"$json_legacy" <<JSON
{
  "hooks": {
    "ProviderEvent": [{"hooks": [{"type": "command", "command": "provider-$json_agent-v1"}]}],
    "ProviderRetired": [{"hooks": [{"type": "command", "command": "provider-$json_agent-retired"}]}],
    "UserEvent": [{"hooks": [{"type": "command", "command": "user-$json_agent"}]}]
  },
  "userState": "$json_agent-state"
}
JSON
    cp "$json_legacy" "$json_target"

    json_merge_output=$(HOME="$json_agent_home" \
      _run_agentguard_json_merge_for_test "$json_agent" "$json_agent_home" 2>&1)
    json_merge_status=$?
    _assert_exit "$json_agent consumer: provider reconciliation succeeds" \
      0 "$json_merge_status"
    _assert_eq "$json_agent consumer: installs the current provider generation" \
      "provider-$json_agent-v2" \
      "$(jq -r '.hooks.ProviderEvent[0].hooks[0].command' "$json_target")"
    _assert_eq "$json_agent consumer: retires the previous provider event" \
      "false" "$(jq -r '.hooks | has("ProviderRetired")' "$json_target")"
    _assert_eq "$json_agent consumer: preserves user-owned hooks and state" \
      "user-$json_agent|$json_agent-state" \
      "$(jq -r '[.hooks.UserEvent[0].hooks[0].command, .userState] | join("|")' "$json_target")"
    _assert_eq "$json_agent consumer: does not mutate the source fixture" \
      "provider-$json_agent-v1" \
      "$(jq -r '.hooks.ProviderEvent[0].hooks[0].command' "$json_legacy")"
  done
  _assert_eq "claude consumer: layers local policy after provider config" \
    "LocalClaudePolicy" \
    "$(jq -r '.permissions.allow[0]' "$json_agent_home/.claude/settings.json")"
  _assert_eq "muse consumer: layers local policy after provider config" \
    "LocalMusePolicy" \
    "$(jq -r '.permissions.allow[0]' "$json_agent_home/.config/muse/settings.json")"

  rm -f \
    "$agentguard_fixture/claude/hooks.json" \
    "$agentguard_fixture/gemini/hooks.json" \
    "$agentguard_fixture/muse/hooks.json"
  for json_agent in claude gemini muse; do
    case "$json_agent" in
      claude) json_target="$json_agent_home/.claude/settings.json" ;;
      gemini) json_target="$json_agent_home/.gemini/settings.json" ;;
      muse) json_target="$json_agent_home/.config/muse/settings.json" ;;
    esac
    if [[ "$json_agent" != "gemini" ]]; then
      json_last_good="$json_agent_home/$json_agent-last-good.json"
      cp "$json_target" "$json_last_good"
      rm -f "$json_target"
      ln -s "$json_last_good" "$json_target"
    fi
    json_merge_output=$(HOME="$json_agent_home" \
      _run_agentguard_json_merge_for_test "$json_agent" "$json_agent_home" 2>&1)
    json_merge_status=$?
    _assert_exit "$json_agent consumer: missing required provider is a failed refresh" \
      1 "$json_merge_status"
    _assert_contains "$json_agent consumer: missing provider reports the failed refresh" \
      "AgentGuard $json_agent integration unavailable" "$json_merge_output"
  done
  _assert_eq "agent consumers: missing provider assets preserve live native hooks" \
    "provider-claude-v2|provider-gemini-v2|provider-muse-v2" \
    "$(
      jq -r '.hooks.ProviderEvent[0].hooks[0].command' \
        "$json_agent_home/.claude/settings.json" \
        "$json_agent_home/.gemini/settings.json" \
        "$json_agent_home/.config/muse/settings.json" |
        paste -sd '|' -
    )"
  _assert_eq "agent consumers: missing provider preserves legacy target symlinks" \
    "link|link" \
    "$(
      test -L "$json_agent_home/.claude/settings.json" && printf link || printf regular
      printf '|'
      test -L "$json_agent_home/.config/muse/settings.json" && printf link || printf regular
    )"
  unset -f _run_agentguard_json_merge_for_test merge 2>/dev/null

  echo "=== Git config merge hook ==="

  git_home="$TEST_HOME/git-merge-home"
  mkdir -p "$git_home/.config/git"
  cat >"$git_home/.config/git/config" <<'GIT_CONFIG'
[push]
	default = simple
GIT_CONFIG
  cat >"$git_home/.gitconfig" <<'GIT_CONFIG'
[user]
	name = Local User
GIT_CONFIG

  HOME="$git_home" GIT_CONFIG_GLOBAL="$git_home/.gitconfig" \
    bash -c '
      . "$2"
      _log() { printf "%s\n" "$*"; }
      _warn() { printf "%s\n" "$*" >&2; }
      . "$1"
      merge
      merge
    ' _ "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/git.sh" \
    "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"

  _assert_eq "Git config merge: managed push policy becomes globally effective" \
    "simple" \
    "$(HOME="$git_home" GIT_CONFIG_GLOBAL="$git_home/.gitconfig" \
      git config --global --includes --get push.default)"
  _assert_eq "Git config merge: preserves host-specific global settings" \
    "Local User" \
    "$(HOME="$git_home" GIT_CONFIG_GLOBAL="$git_home/.gitconfig" \
      git config --global --get user.name)"
  # shellcheck disable=SC2088 # Assert the literal portable Git config path.
  _assert_eq "Git config merge: records one portable managed include" \
    '~/.config/git/config' \
    "$(HOME="$git_home" GIT_CONFIG_GLOBAL="$git_home/.gitconfig" \
      git config --global --get-all include.path)"

  echo "=== GitHub CLI merge hook ==="

  gh_yq_bin=$(_merge_hook_mikefarah_yq 2>/dev/null || true)
  if [[ -n "$gh_yq_bin" ]]; then
    gh_home=$(_tmpdir)
    mkdir -p \
      "$gh_home/.config/dot/merge-hooks.d/gh/config.d" \
      "$gh_home/.config/gh"
    cat >"$gh_home/.config/gh/config.yml" <<'YAML'
git_protocol: https
local_only: keep
aliases:
  old: old command
YAML
    cat >"$gh_home/.config/gh/hosts.yml" <<'YAML'
github.com:
  user: fixture-user
  oauth_token: seeded-token
YAML
    cat >"$gh_home/.config/dot/merge-hooks.d/gh/config.d/10-config.yml" <<'YAML'
git_protocol: ssh
editor: nvim
aliases:
  co: pr checkout
YAML
    cat >"$gh_home/.config/dot/merge-hooks.d/gh/config.d/20-extra.yaml" <<'YAML'
pager: delta
aliases:
  view: pr view
YAML
    _run_gh_merge_for_test() {
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/gh.sh"
      merge
    }
    gh_mock_bin=$(_mock_bin)
    cat >"$gh_mock_bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/.gh-calls.log"
if [[ "${GH_MOCK_FAIL:-0}" == "1" ]]; then
  exit 1
fi
if [[ "$1" == "auth" && "$2" == "token" ]]; then
  printf '%s\n' "fallback-token"
  exit 0
fi
exit 1
GH
    chmod +x "$gh_mock_bin/gh"
    HOME="$gh_home" PATH="$gh_mock_bin:$PATH" _run_gh_merge_for_test
    unset -f _run_gh_merge_for_test merge 2>/dev/null
    gh_output=$("$gh_yq_bin" eval -o=json '.' "$gh_home/.config/gh/config.yml")
    _assert_contains "gh merge: source overrides existing scalar" \
      '"git_protocol": "ssh"' "$gh_output"
    _assert_contains "gh merge: preserves local-only key" \
      '"local_only": "keep"' "$gh_output"
    _assert_contains "gh merge: first config layer applied" \
      '"co": "pr checkout"' "$gh_output"
    _assert_contains "gh merge: later config layer applied" \
      '"view": "pr view"' "$gh_output"
    _assert_file_content "gh merge: seeds github-pat from hosts.yml" \
      "seeded-token" "$gh_home/.config/gh/github-pat"
    _gh_pat_mode=$(stat -c '%a' "$gh_home/.config/gh/github-pat" 2>/dev/null || stat -f '%Lp' "$gh_home/.config/gh/github-pat" 2>/dev/null || true)
    _assert_eq "gh merge: github-pat is owner-only" "600" "$_gh_pat_mode"
    if [[ ! -e "$gh_home/.gh-calls.log" ]]; then
      _pass "gh merge: hosts.yml token seed skips gh"
    else
      _fail "gh merge: hosts.yml token seed skips gh"
    fi

    rm -f "$gh_home/.config/gh/github-pat" "$gh_home/.gh-calls.log"
    cat >"$gh_home/.config/gh/hosts.yml" <<'YAML'
github.com:
  user: fixture-user
  users:
    fixture-user:
      oauth_token: nested-token
YAML
    _run_gh_merge_nested_hosts_for_test() {
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/gh.sh"
      merge
    }
    HOME="$gh_home" PATH="$gh_mock_bin:$PATH" _run_gh_merge_nested_hosts_for_test
    unset -f _run_gh_merge_nested_hosts_for_test merge 2>/dev/null
    _assert_file_content "gh merge: seeds github-pat from nested hosts.yml users" \
      "nested-token" "$gh_home/.config/gh/github-pat"
    if [[ ! -e "$gh_home/.gh-calls.log" ]]; then
      _pass "gh merge: nested hosts.yml token seed skips gh"
    else
      _fail "gh merge: nested hosts.yml token seed skips gh"
    fi

    printf '%s\n' "existing-token" >"$gh_home/.config/gh/github-pat"
    rm -f "$gh_home/.gh-calls.log"
    _run_gh_merge_existing_for_test() {
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/gh.sh"
      merge
    }
    HOME="$gh_home" PATH="$gh_mock_bin:$PATH" _run_gh_merge_existing_for_test
    unset -f _run_gh_merge_existing_for_test merge 2>/dev/null
    _assert_file_content "gh merge: preserves existing github-pat" \
      "existing-token" "$gh_home/.config/gh/github-pat"
    if [[ ! -e "$gh_home/.gh-calls.log" ]]; then
      _pass "gh merge: existing github-pat skips gh"
    else
      _fail "gh merge: existing github-pat skips gh"
    fi

    rm -f "$gh_home/.config/gh/github-pat" "$gh_home/.gh-calls.log"
    rm -f "$gh_home/.config/gh/hosts.yml"
    _run_gh_merge_fallback_for_test() {
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/gh.sh"
      merge
    }

    gh_missing_double_output=$(HOME="$gh_home" PATH="$gh_mock_bin:$PATH" \
      _run_gh_merge_fallback_for_test 2>&1)
    if [[ ! -e "$gh_home/.gh-calls.log" && ! -e "$gh_home/.config/gh/github-pat" ]]; then
      _pass "gh merge: test mode requires an explicit credential double"
    else
      _fail "gh merge: test mode requires an explicit credential double"
    fi
    _assert_contains "gh merge: missing credential double is reported" \
      "test gh" "$gh_missing_double_output"

    rm -f "$gh_home/.config/gh/github-pat" "$gh_home/.gh-calls.log"
    gh_non_account_output=$(DOT_TEST=0 HOME="$gh_home" \
      PATH="$gh_mock_bin:$PATH" _run_gh_merge_fallback_for_test 2>&1)
    if [[ ! -e "$gh_home/.gh-calls.log" && ! -e "$gh_home/.config/gh/github-pat" ]]; then
      _pass "gh merge: non-account HOME leaves credentials unread"
    else
      _fail "gh merge: non-account HOME leaves credentials unread"
    fi
    _assert_contains "gh merge: non-account HOME is reported" \
      "account home" "$gh_non_account_output"

    rm -f "$gh_home/.config/gh/github-pat" "$gh_home/.gh-calls.log"
    HOME="$gh_home" PATH="$gh_mock_bin:$PATH" DOT_TEST_GH="$gh_mock_bin/gh" \
      _run_gh_merge_fallback_for_test
    unset -f _run_gh_merge_fallback_for_test merge 2>/dev/null
    _assert_file_content "gh merge: falls back to gh auth token when hosts.yml has no token" \
      "fallback-token" "$gh_home/.config/gh/github-pat"
    _assert_contains "gh merge: fallback calls gh auth token" \
      "auth token" "$(cat "$gh_home/.gh-calls.log")"

    rm -f "$gh_home/.config/gh/github-pat" "$gh_home/.gh-calls.log"
    _run_gh_merge_failed_fallback_for_test() {
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/gh.sh"
      merge
    }
    DOT_QUIET=1 GH_MOCK_FAIL=1 HOME="$gh_home" PATH="$gh_mock_bin:$PATH" \
      DOT_TEST_GH="$gh_mock_bin/gh" _run_gh_merge_failed_fallback_for_test
    DOT_QUIET=1 GH_MOCK_FAIL=1 HOME="$gh_home" PATH="$gh_mock_bin:$PATH" \
      DOT_TEST_GH="$gh_mock_bin/gh" _run_gh_merge_failed_fallback_for_test
    unset -f _run_gh_merge_failed_fallback_for_test merge 2>/dev/null
    _gh_fallback_call_count=$(wc -l <"$gh_home/.gh-calls.log" | tr -d ' ')
    _assert_eq "gh merge: failed keyring fallback is throttled" "1" "$_gh_fallback_call_count"
    if [[ ! -e "$gh_home/.config/gh/github-pat" ]]; then
      _pass "gh merge: failed keyring fallback does not create github-pat"
    else
      _fail "gh merge: failed keyring fallback does not create github-pat"
    fi

    rm -f "$gh_home/.config/gh/github-pat" "$gh_home/.gh-calls.log"
    cat >"$gh_home/.config/gh/hosts.yml" <<'YAML'
github.com:
  git_protocol: https
  users:
    fixture-user:
      git_protocol: https
  user: fixture-user
YAML
    _run_gh_merge_manual_retry_for_test() {
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/gh.sh"
      merge
    }
    HOME="$gh_home" PATH="$gh_mock_bin:$PATH" DOT_TEST_GH="$gh_mock_bin/gh" \
      _run_gh_merge_manual_retry_for_test
    unset -f _run_gh_merge_manual_retry_for_test merge 2>/dev/null
    _assert_file_content "gh merge: manual update retries keyring fallback after prior quiet failure" \
      "fallback-token" "$gh_home/.config/gh/github-pat"
    _assert_contains "gh merge: manual retry calls gh auth token" \
      "auth token" "$(cat "$gh_home/.gh-calls.log")"
  else
    echo "  SKIP: GitHub CLI merge hook assertions (mikefarah/yq unavailable)"
  fi

  echo "=== VS Code Sley merge hook ==="

  if command -v jq >/dev/null 2>&1; then
    _assert_vscode_macos_ctrl_arrow_keybindings() {
      local keybindings_file="$1"
      local keybindings

      keybindings=$(
        jq -c '
          map(select(.when == "editorTextFocus"))
          | map(select(.key as $key | [
              "ctrl+left",
              "ctrl+right",
              "ctrl+shift+left",
              "ctrl+shift+right",
              "ctrl+shift+up",
              "ctrl+shift+down"
            ] | index($key)))
        ' "$keybindings_file"
      )

      _assert_contains "vscode mac editor: Ctrl+Left moves word-left" \
        '{"command":"cursorWordStartLeft","key":"ctrl+left","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Right moves word-right" \
        '{"command":"cursorWordEndRight","key":"ctrl+right","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Shift+Left selects word-left" \
        '{"command":"cursorWordStartLeftSelect","key":"ctrl+shift+left","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Shift+Right selects word-right" \
        '{"command":"cursorWordEndRightSelect","key":"ctrl+shift+right","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Shift+Up extends selection up" \
        '{"command":"cursorUpSelect","key":"ctrl+shift+up","when":"editorTextFocus"}' \
        "$keybindings"
      ctrl_shift_down_expected=$(
        jq -nc --arg key "ctrl+shift+down" \
          '{"command":"cursorDownSelect","key":$key,"when":"editorTextFocus"}'
      )
      _assert_contains "vscode mac editor: Ctrl+Shift+Down extends selection down" \
        "$ctrl_shift_down_expected" \
        "$keybindings"
    }

    _assert_vscode_macos_karabiner_terminal_keybindings() {
      local keybindings_file="$1"

      _assert_eq "vscode mac terminal: Karabiner Ctrl controls stay terminal-native" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "cmd+a", text: "\u0001"},
              {key: "cmd+b", text: "\u0002"},
              {key: "cmd+l", text: "\u000c"},
              {key: "cmd+n", text: "\u000e"},
              {key: "cmd+r", text: "\u0012"},
              {key: "cmd+u", text: "\u0015"},
              {key: "cmd+w", text: "\u0017"},
              {key: "cmd+z", text: "\u001a"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
      _assert_eq "vscode mac editor: Cmd+B keeps the native sidebar binding" \
        "0" \
        "$(jq '[.[] | select(
          .key == "cmd+b"
          and (
            .command == "-workbench.action.toggleSidebarVisibility"
            or .command == "workbench.action.toggleSidebarVisibility"
          )
        )] | length' "$keybindings_file")"

      _assert_eq "vscode mac terminal: Cmd+V pastes outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+v" and .command == "workbench.action.terminal.paste" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+V reaches nvim after Karabiner translates Ctrl+V" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+v" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0016")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Ctrl+Shift+V transport pastes without focused nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "f20" and .command == "workbench.action.terminal.paste" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode mac editor: Ctrl+Shift+V transport preserves Windows-style paste" \
        "1" \
        "$(jq '[.[] | select(.key == "f20" and .command == "editor.action.clipboardPasteAction" and .when == "textInputFocus && !editorReadonly && !terminalFocus")] | length' "$keybindings_file")"
      _assert_eq "vscode mac: native Shift+Cmd+V stays unmanaged" \
        "0" \
        "$(jq '[.[] | select(.key == "shift+cmd+v")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+C copies a Karabiner-translated selection" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+c" and .command == "workbench.action.terminal.copySelection" and .when == "terminalFocus && terminalTextSelected")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+C reaches nvim when no text is selected" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+c" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && !terminalTextSelected" and .args.text == "\u0003")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+P opens VS Code quick open outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+p" and .command == "workbench.action.quickOpen" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+P reaches nvim after Karabiner translates Ctrl+P" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+p" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0010")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: every Karabiner-translated Ctrl letter reaches focused nvim" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "cmd+f", text: "\u0006"},
              {key: "cmd+g", text: "\u0007"},
              {key: "cmd+i", text: "\u0009"},
              {key: "cmd+o", text: "\u000f"},
              {key: "cmd+p", text: "\u0010"},
              {key: "cmd+s", text: "\u0013"},
              {key: "cmd+t", text: "\u0014"},
              {key: "cmd+v", text: "\u0016"},
              {key: "cmd+x", text: "\u0018"},
              {key: "cmd+y", text: "\u0019"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus && termnav.nvimFocused"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Karabiner-translated shifted chords reach focused nvim" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "shift+cmd+f", text: "\u001b[102;6u"},
              {key: "shift+cmd+g", text: "\u001b[103;6u"},
              {key: "shift+cmd+p", text: "\u001b[112;6u"},
              {key: "f20", text: "\u001b[118;6u"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus && termnav.nvimFocused"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
    }

    _assert_vscode_focus_fallback_keybindings() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: tmux prefix is extension-independent" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+b"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u0002"
          and .when == "terminalFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: tmux prefix has no focus-only duplicate" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+b"
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: explicit tmux pane controls are extension-independent" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "ctrl+h", text: "\u0008"},
                {key: "ctrl+k", text: "\u000b"},
                {key: "ctrl+l", text: "\u000c"},
                {key: "ctrl+\\", text: "\u001c"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+J avoids sendSequence newline normalization" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+j"
          and .command == "workbench.action.terminal.sendSequence"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: tmux pane navigation has no focus-only duplicates" \
        "0" \
        "$(jq '[.[] | select(
          (.key == "ctrl+h" or .key == "ctrl+j" or .key == "ctrl+k" or .key == "ctrl+l" or .key == "ctrl+\\")
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+/ transport is extension-independent" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "ctrl+/", text: "\u001f"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+/ transport has no focus-only duplicate" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+/"
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: synced macOS Ctrl+/ generation is retired" \
        "0" \
        "$(jq '[.[] | select(
          .key == "cmd+/"
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"

      if [[ "$platform" == "macOS" ]]; then
        _assert_eq "vscode macOS terminal: Cmd+J keeps native workbench ownership" \
          "0" \
          "$(jq '[.[] | select(
            .key == "cmd+j"
            and ((.when // "") | contains("terminalFocus"))
          )] | length' "$keybindings_file")"
        _assert_eq "vscode macOS terminal: Ctrl-backslash needs no invented Cmd translation" \
          "0" \
          "$(jq '[.[] | select(
            .key == "cmd+\\"
            and .command == "workbench.action.terminal.sendSequence"
          )] | length' "$keybindings_file")"
        _assert_eq "vscode macOS terminal: Karabiner-translated Ctrl+/ is extension-independent" \
          "1" \
          "$(jq '[.[] | select(
            .key == "cmd+/"
            and .command == "workbench.action.terminal.sendSequence"
            and .args.text == "\u001f"
            and .when == "terminalFocus"
          )] | length' "$keybindings_file")"
      fi

      _assert_eq "vscode terminal toggle: editor route excludes terminal focus" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.terminal.focus"
          and .when == "terminalIsOpen && !terminalFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode terminal toggle: host route excludes focused nvim" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.focusActiveEditorGroup"
          and .when == "terminalFocus && terminalIsOpen && !termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode terminal toggle: focused nvim receives Ctrl+backtick" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u001b[96;5u"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode terminal toggle: focused nvim has no legacy NUL route" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u0000"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform fallback: negated Termnav routes stay allowlisted" \
        '[]' \
        "$(jq -c --arg platform "$platform" '
          def route: {key, command, when};
          (
            [
              {
                key: "ctrl+`",
                command: "workbench.action.focusActiveEditorGroup",
                when: "terminalFocus && terminalIsOpen && !termnav.nvimFocused"
              },
              {
                key: "ctrl+p",
                command: "workbench.action.quickOpen",
                when: "terminalFocus && !termnav.nvimFocused"
              },
              {
                key: "ctrl+v",
                command: "workbench.action.terminal.paste",
                when: "terminalFocus && !termnav.nvimFocused"
              }
            ]
            + if $platform == "macOS" then
                [
                  {
                    key: "cmd+p",
                    command: "workbench.action.quickOpen",
                    when: "terminalFocus && !termnav.nvimFocused"
                  },
                  {
                    key: "cmd+v",
                    command: "workbench.action.terminal.paste",
                    when: "terminalFocus && !termnav.nvimFocused"
                  },
                  {
                    key: "f20",
                    command: "workbench.action.terminal.paste",
                    when: "terminalFocus && !termnav.nvimFocused"
                  }
                ]
              else [] end
          ) as $allowed
          | ([
              .[]
              | select((.when // "") | contains("!termnav.nvimFocused"))
              | route
            ] | unique) as $actual
          | (($actual - $allowed) + ($allowed - $actual) | unique)
        ' "$keybindings_file")"
      _assert_eq "vscode focused nvim: application-aware chords stay positive-only" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "ctrl+.", text: "\u001b[46;5u"},
              {key: "ctrl+shift+e", text: "\u001b[101;6u"},
              {key: "ctrl+shift+f", text: "\u001b[102;6u"},
              {key: "ctrl+shift+m", text: "\u001b[109;6u"},
              {key: "ctrl+shift+p", text: "\u001b[112;6u"},
              {key: "shift+pageup", text: "\u001b[5;2~"},
              {key: "shift+pagedown", text: "\u001b[6;2~"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus && termnav.nvimFocused"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
    }

    _assert_vscode_terminal_clipboard_keybindings() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: Ctrl+C copies only selected text" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+c" and .command == "workbench.action.terminal.copySelection" and .when == "terminalFocus && terminalTextSelected")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+C keeps interrupt behavior without a selection" \
        "2" \
        "$(jq '[.[] | select(.key == "ctrl+c")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+V pastes outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+v" and .command == "workbench.action.terminal.paste" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+V reaches nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+v" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0016")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+P opens VS Code quick open outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+p" and .command == "workbench.action.quickOpen" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+P reaches nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+p" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0010")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+F reaches nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+f" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0006")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: synthesized Ctrl letters exclude native Ctrl+J" \
        "25" \
        "$(jq '[
          .[]
          | select(.key | test("^ctrl\\+[a-z]$"))
          | select(
              .command == "workbench.action.terminal.sendSequence"
              and (
                .when == "terminalFocus"
                or (.when | contains("termnav.nvimFocused"))
              )
            )
        ] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+Shift+G reaches nvim distinctly" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+shift+g" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u001b[103;6u")] | length' "$keybindings_file")"
    }

    _assert_vscode_terminal_native_settings() {
      local settings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: Ctrl+J bypasses the workbench panel shortcut once" \
        "1" \
        "$(jq '[.["terminal.integrated.commandsToSkipShell"][]? | select(
          . == "-workbench.action.togglePanel"
        )] | length' "$settings_file")"
      _assert_eq "vscode $platform terminal: positive panel skip cannot override Ctrl+J passthrough" \
        "0" \
        "$(jq '[.["terminal.integrated.commandsToSkipShell"][]? | select(
          . == "workbench.action.togglePanel"
        )] | length' "$settings_file")"
    }

    _assert_vscode_terminal_local_settings_preserved() {
      local settings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: local skip-shell policy survives Ctrl+J passthrough" \
        '["workbench.action.quickOpen","-local.terminalCommand","-workbench.action.togglePanel"]' \
        "$(jq -c '.["terminal.integrated.commandsToSkipShell"]' "$settings_file")"
    }

    _add_vscode_stale_terminal_native_keybindings() {
      local keybindings_file="$1"
      local migrated

      migrated=$(_tmpfile)
      jq '. + [
        {
          "key": "ctrl+b",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u0002"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+h",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u0008"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+j",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000a"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+j",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000a"},
          "when": "terminalFocus"
        },
        {
          "key": "ctrl+k",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000b"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+l",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000c"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+tab",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001b[9;5u"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+shift+tab",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001b[9;6u"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+/",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001f"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "cmd+/",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001f"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+`",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u0000"},
          "when": "terminalFocus && termnav.nvimFocused"
        }
      ]' "$keybindings_file" >"$migrated"
      mv "$migrated" "$keybindings_file"
    }

    _write_vscode_keybinding_conflicts() {
      local keybindings_file="$1"

      mkdir -p "$(dirname "$keybindings_file")"
      cat >"$keybindings_file" <<'JSON'
[
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;5u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;6u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+v",
    "command": "local.terminalPasteOverride",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u001b[local-action"},
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u0010"},
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "cmd+p",
    "command": "workbench.action.quickOpen",
    "when": "terminalFocus && localTerminalMode"
  }
]
JSON
      # Exercise upgrades from the #80/#90 focus-gated terminal controls, the
      # #98 tab generation, and the normalized #100 Ctrl+J route, including
      # machines that skipped releases.
      _add_vscode_stale_terminal_native_keybindings "$keybindings_file"
    }

    _add_vscode_pre_focus_keybindings() {
      local keybindings_file="$1"
      local platform="$2"
      local migrated

      migrated=$(_tmpfile)
      jq --arg platform "$platform" '
        . + [
          {
            "key": "ctrl+p",
            "command": "workbench.action.quickOpen",
            "when": "terminalFocus"
          },
          {
            "key": "ctrl+v",
            "command": "workbench.action.terminal.paste",
            "when": "terminalFocus"
          }
        ] + (
          if $platform == "macOS" then
            [
              {
                "key": "cmd+a",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0001"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+b",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0002"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+l",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u000c"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+n",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u000e"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+p",
                "command": "workbench.action.quickOpen",
                "when": "terminalFocus"
              },
              {
                "key": "cmd+r",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0012"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+u",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0015"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+v",
                "command": "workbench.action.terminal.paste",
                "when": "terminalFocus"
              },
              {
                "key": "cmd+w",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0017"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+z",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u001a"},
                "when": "terminalFocus"
              }
            ]
          else
            []
          end
        )
      ' "$keybindings_file" >"$migrated"
      mv "$migrated" "$keybindings_file"
    }

    _assert_vscode_focus_keybinding_migration() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform migration: stale Ctrl host actions are removed" \
        "0" \
        "$(jq '[.[] | select(.when == "terminalFocus") | select(
          (.key == "ctrl+p" and .command == "workbench.action.quickOpen")
          or (.key == "ctrl+v" and .command == "workbench.action.terminal.paste")
        )] | length' "$keybindings_file")"

      if [[ "$platform" == "macOS" ]]; then
        _assert_eq "vscode macOS migration: stale Cmd host actions are removed" \
          "0" \
          "$(jq '[.[] | select(.when == "terminalFocus") | select(
            (.key == "cmd+p" and .command == "workbench.action.quickOpen")
            or (.key == "cmd+v" and .command == "workbench.action.terminal.paste")
          )] | length' "$keybindings_file")"
        _assert_eq "vscode macOS migration: terminal-native Cmd routes are restored" \
          "8" \
          "$(jq '[.[] | select(.when == "terminalFocus")
            | select(.command == "workbench.action.terminal.sendSequence")
            | select(.key as $key | [
              "cmd+a", "cmd+b", "cmd+l", "cmd+n",
              "cmd+r", "cmd+u", "cmd+w", "cmd+z"
            ] | index($key))
          ] | length' "$keybindings_file")"
      else
        # Settings Sync can carry an exact macOS generation into another
        # platform's file. Central retirement intentionally removes those known
        # objects everywhere; a near-match remains local and is tested below.
        _assert_eq "vscode $platform migration: synced stale Cmd host actions are removed" \
          "0" \
          "$(jq '[.[] | select(.when == "terminalFocus") | select(
            (.key == "cmd+p" and .command == "workbench.action.quickOpen")
            or (.key == "cmd+v" and .command == "workbench.action.terminal.paste")
          )] | length' "$keybindings_file")"
        _assert_eq "vscode $platform migration: synced stale Cmd terminal routes are removed" \
          "0" \
          "$(jq '[.[] | select(.when == "terminalFocus")
            | select(.command == "workbench.action.terminal.sendSequence")
            | select(.key as $key | [
              "cmd+a", "cmd+b", "cmd+l", "cmd+n",
              "cmd+r", "cmd+u", "cmd+w", "cmd+z"
            ] | index($key))
          ] | length' "$keybindings_file")"
      fi

      _assert_eq "vscode $platform migration: near-match Cmd local binding is preserved" \
        "1" \
        "$(jq '[.[] | select(
          .key == "cmd+p"
          and .command == "workbench.action.quickOpen"
          and .when == "terminalFocus && localTerminalMode"
        )] | length' "$keybindings_file")"
    }

    _assert_vscode_keybinding_precedence() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: exact legacy Ctrl-Tab handler is retired" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+tab"
          and .command == "workbench.action.terminal.focusNext"
          and .when == "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: managed Ctrl-Tab wins over a local near-match" \
        '["workbench.action.terminal.focusNext","workbench.action.terminal.sendSequence"]' \
        "$(jq -c '[.[] | select(.key == "ctrl+tab" and (.command == "workbench.action.terminal.focusNext" or .command == "workbench.action.terminal.sendSequence")) | .command]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: exact legacy Ctrl-Shift-Tab handler is retired" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+shift+tab"
          and .command == "workbench.action.terminal.focusPrevious"
          and .when == "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: managed Ctrl-Shift-Tab wins over a local near-match" \
        '["workbench.action.terminal.focusPrevious","workbench.action.terminal.sendSequence"]' \
        "$(jq -c '[.[] | select(.key == "ctrl+shift+tab" and (.command == "workbench.action.terminal.focusPrevious" or .command == "workbench.action.terminal.sendSequence")) | .command]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: tab routes are terminal-native" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "ctrl+tab", text: "\u001b[9;5u"},
                {key: "ctrl+shift+tab", text: "\u001b[9;6u"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: every tab sequence is adapter-independent" \
        "0" \
        "$(jq '[.[] | select(
          (.key == "ctrl+tab" or .key == "ctrl+shift+tab")
          and .command == "workbench.action.terminal.sendSequence"
          and .when != "terminalFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform editor: native tab defaults have no managed shadow" \
        "0" \
        "$(jq '[.[] | select(
          [.key, .command, (.when // "")] as $route
          | [
              ["ctrl+shift+tab", "workbench.action.quickOpenLeastRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty && !terminalFocus"],
              ["ctrl+shift+tab", "-workbench.action.quickOpenLeastRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty"],
              ["ctrl+tab", "workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty && !terminalFocus"],
              ["ctrl+tab", "-workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty"],
              ["ctrl+tab", "workbench.action.quickOpenNavigateNextInEditorPicker", "inEditorsPicker && inQuickOpen && !terminalFocus"],
              ["ctrl+tab", "-workbench.action.quickOpenNavigateNextInEditorPicker", "inEditorsPicker && inQuickOpen"],
              ["ctrl+shift+tab", "workbench.action.quickOpenNavigatePreviousInEditorPicker", "inEditorsPicker && inQuickOpen && !terminalFocus"],
              ["ctrl+shift+tab", "-workbench.action.quickOpenNavigatePreviousInEditorPicker", "inEditorsPicker && inQuickOpen"]
            ]
            | any(.[]; . == $route)
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: unrelated local overlap retains precedence" \
        '["workbench.action.terminal.paste","local.terminalPasteOverride"]' \
        "$(jq -c '[.[] | select(.key == "ctrl+v" and (.command == "workbench.action.terminal.paste" or .command == "local.terminalPasteOverride")) | .command]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: same command with different args stays local" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+p"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u001b[local-action"
          and .when == "terminalFocus && localTerminalMode"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: same managed action under a local condition survives" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+p"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u0010"
          and .when == "terminalFocus && localTerminalMode"
        )] | length' "$keybindings_file")"
    }

    _assert_vscode_native_tab_handling() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform: no-termnav keeps terminal-native and local tab routes only" \
        '[]' \
        "$(jq -c '
          [
            .[]
            | select(.key == "ctrl+tab" or .key == "ctrl+shift+tab")
            | {key, command, when: (.when // "")}
          ] as $actual
          | [
              {
                key: "ctrl+tab",
                command: "workbench.action.terminal.focusNext",
                when: "terminalFocus && localTerminalMode"
              },
              {
                key: "ctrl+shift+tab",
                command: "workbench.action.terminal.focusPrevious",
                when: "terminalFocus && localTerminalMode"
              },
              {
                key: "ctrl+tab",
                command: "workbench.action.terminal.sendSequence",
                when: "terminalFocus"
              },
              {
                key: "ctrl+shift+tab",
                command: "workbench.action.terminal.sendSequence",
                when: "terminalFocus"
              }
            ] as $expected
          | (($actual - $expected) + ($expected - $actual) | unique)
        ' "$keybindings_file")"
    }

    _vscode_test_append_jsonc_array() {
      local aggregate="$1" source="$2" family="$3"
      local layer next

      layer=$(_tmpfile)
      next=$(_tmpfile)
      # Match production's comment/BOM/CRLF handling. The history guard must
      # compare semantic objects, not formatting, or harmless editor changes
      # would demand false retirement records.
      if ! LC_ALL=C awk '
        NR == 1 { sub(/^\357\273\277/, "", $0) }
        { sub(/\r$/, "", $0) }
        !/^[[:space:]]*\/\//
      ' "$source" |
        jq -s -e --arg family "$family" '
          if length == 1 and (.[0] | type == "array")
          then .[0] | map({family: $family, binding: .})
          else error("expected one array")
          end
        ' >"$layer"; then
        return 1
      fi
      if ! jq -n --slurpfile a "$aggregate" --slurpfile b "$layer" \
        '$a[0] + $b[0]' >"$next"; then
        return 1
      fi
      mv "$next" "$aggregate"
    }

    _vscode_test_retirement_report() {
      local old="$1" current="$2"

      # Keep the invariant calculation separate from Git/materialization so
      # focused negative fixtures can prove each destructive-policy guard. The
      # Family provenance wraps each binding instead of adding a temporary
      # property to it. Exact comparison includes arbitrary user properties;
      # mutating the object here could let the guard pass a retirement that
      # production would never match.
      jq -nc \
        --arg retire "dotfiles.retire" \
        --arg proof "dotfiles.retire-proof" \
        --arg review_proof "review-build:7030e8e" \
        --arg legacy_proof "legacy-local:280f7f8" \
        --slurpfile old "$old" \
        --slurpfile current "$current" '
        def retired_targets($records):
          $records
          | map(select(.binding[$retire] == true)
            | .binding | del(.[$retire], .[$proof]))
          | unique;
        def retirement_directives($records):
          $records
          | map(select(.binding[$retire] == true)
            | .binding | del(.[$retire]))
          | unique;
        def proof_targets($records; $proof_value):
          $records
          | map(select(
              .binding[$retire] == true
              and .binding[$proof] == $proof_value
            ) | .binding | del(.[$retire], .[$proof]))
          | unique;
        def review_oracle:
          [
            {key: "ctrl+.", command: "editor.action.quickFix", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+/", command: "editor.action.commentLine", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+\\", command: "workbench.action.splitEditor", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+e", command: "workbench.view.explorer", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+f", command: "workbench.view.search", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+m", command: "workbench.actions.view.problems", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+p", command: "workbench.action.showCommands", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "shift+cmd+f", command: "workbench.view.search", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "shift+cmd+p", command: "workbench.action.showCommands", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+v", command: "workbench.action.terminal.paste", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+v", command: "editor.action.clipboardPasteAction", when: "textInputFocus && !editorReadonly && !terminalFocus"},
            {key: "cmd+/", command: "editor.action.commentLine", when: "terminalFocus && !termnav.nvimFocused"}
          ] | unique;
        def legacy_oracle:
          [
            {
              key: "ctrl+tab",
              command: "workbench.action.terminal.focusNext",
              when: "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
            },
            {
              key: "ctrl+shift+tab",
              command: "workbench.action.terminal.focusPrevious",
              when: "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
            }
          ] | unique;
        def effective($records; $platform; $termnav):
          $records
          | map(select(.binding[$retire] != true))
          | map(select(
              .family == "all"
              or .family == $platform
              or (.family == "termnav" and $termnav)
            ))
          | map(.binding)
          | unique;
        def active_union($records):
          $records
          | map(select(.binding[$retire] != true) | .binding)
          | unique;
        (retired_targets($old[0])) as $old_retired |
        (retired_targets($current[0])) as $current_retired |
        (retirement_directives($old[0])) as $old_directives |
        (retirement_directives($current[0])) as $current_directives |
        (proof_targets($current[0]; $review_proof)) as $reviewed |
        (proof_targets($current[0]; $legacy_proof)) as $legacy |
        (review_oracle) as $review_oracle |
        (legacy_oracle) as $legacy_oracle |
        ($reviewed - ($reviewed - $review_oracle)) as $authorized_reviewed |
        ($legacy - ($legacy - $legacy_oracle)) as $authorized_legacy |
        {
          missing: {
            linux: (
              effective($old[0]; "linux"; true)
              - effective($current[0]; "linux"; true)
              - $current_retired
            ),
            macos: (
              effective($old[0]; "macos"; true)
              - effective($current[0]; "macos"; true)
              - $current_retired
            ),
            windows: (
              effective($old[0]; "windows"; true)
              - effective($current[0]; "windows"; true)
              - $current_retired
            ),
            linux_no_termnav: (
              effective($old[0]; "linux"; false)
              - effective($current[0]; "linux"; false)
              - $current_retired
            ),
            macos_no_termnav: (
              effective($old[0]; "macos"; false)
              - effective($current[0]; "macos"; false)
              - $current_retired
            ),
            windows_no_termnav: (
              effective($old[0]; "windows"; false)
              - effective($current[0]; "windows"; false)
              - $current_retired
            )
          },
          removed: ($old_directives - $current_directives),
          misplaced: (
            $current[0]
            | map(select(
                .binding[$retire] == true
                and .family != "all"
              ))
          ),
          unproven: (
            ($current_retired - $old_retired)
            - active_union($old[0])
            - $authorized_reviewed
            - $authorized_legacy
          ),
          review_proof_extra: ($reviewed - $review_oracle),
          review_proof_missing: ($review_oracle - $reviewed),
          legacy_proof_extra: ($legacy - $legacy_oracle),
          legacy_proof_missing: ($legacy_oracle - $legacy),
          invalid_proofs: (
            $current[0]
            | map(select(
                (.binding | has($proof))
                and (
                  .binding[$retire] != true
                  or (
                    .binding[$proof] != $review_proof
                    and .binding[$proof] != $legacy_proof
                  )
                )
              ))
          )
        }
      '
    }

    _assert_vscode_retirement_history() {
      local repo="$1"
      local rel=.config/dot/merge-hooks.d/vscode/keybindings
      local git_root git_prefix git_rel head origin base base_sha path deploy_path old_root
      local source family report report_family
      local old_all current_all
      origin=""
      base=""

      # Runtime merging must not depend on Git: deployed dotfiles may be
      # exported, shallow, or split across overlays. This is deliberately a
      # development-time guard. It compares the proposed source with the event
      # base (or the last landed commit during local/main runs) and turns a
      # forgotten retirement into a failing test before the unsafe edit ships.
      if ! git_root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null); then
        _pass "vscode keybindings: retirement history guard skipped outside Git"
        return
      fi
      git_prefix=$(git -C "$repo" rev-parse --show-prefix 2>/dev/null) || return
      git_rel=$git_prefix$rel

      head=$(git -C "$git_root" rev-parse HEAD 2>/dev/null || true)
      base_sha="${DOT_VSCODE_KEYBINDING_BASE_SHA:-}"
      if [[ -n "$base_sha" && "$base_sha" != "0000000000000000000000000000000000000000" ]]; then
        if [[ "$base_sha" == "$head" ]] &&
          git -C "$git_root" diff --quiet HEAD -- "$git_rel" 2>/dev/null; then
          _fail "vscode keybindings: event base must precede a clean checkout"
          return
        fi
        if git -C "$git_root" cat-file -e "$base_sha^{commit}" 2>/dev/null; then
          base="$base_sha"
        else
          _fail "vscode keybindings: event base commit was not fetched"
          return
        fi
      else
        origin=$(git -C "$git_root" rev-parse origin/main 2>/dev/null || true)
      fi

      if [[ -z "${base:-}" && -n "$origin" && "$origin" != "$head" ]]; then
        # Local feature worktrees compare with the merge base of their fetched
        # base branch. The branch tip can advance during review and may no
        # longer be an ancestor of this checkout; comparing directly with that
        # unrelated future tip would invent removals and hide the immutable
        # predecessor generation. CI takes the event-SHA path above.
        base=$(git -C "$git_root" merge-base "$origin" "$head" 2>/dev/null || true)
      elif [[ -z "${base:-}" ]] &&
        ! git -C "$git_root" diff --quiet HEAD -- "$git_rel" 2>/dev/null; then
        base="$head"
      elif [[ -z "${base:-}" ]]; then
        base=$(git -C "$git_root" rev-parse HEAD^ 2>/dev/null || true)
      fi

      if [[ -z "$base" ]]; then
        if [[ $(git -C "$git_root" rev-parse --is-shallow-repository 2>/dev/null) == true ]]; then
          _pass "vscode keybindings: dynamic retirement history guard deferred to full-history CI"
          return
        fi
        _fail "vscode keybindings: retirement history guard requires a Git base"
        return
      fi
      old_all=$(_tmpfile)
      current_all=$(_tmpfile)
      old_root=$(_tmpdir)
      printf '[]\n' >"$old_all"
      printf '[]\n' >"$current_all"

      # Materialize only the historical source subtree. Reusing the production
      # family selector against this temporary HOME preserves `.replace`
      # semantics; a raw recursive scan could validate a fragment that the
      # runtime would never load and mask a real per-platform disappearance.
      while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ "$path" == *.jsonc ]] || continue
        deploy_path=${path#"$git_prefix"}
        mkdir -p "$old_root/$(dirname "$deploy_path")"
        if ! git -C "$git_root" show "$base:$path" >"$old_root/$deploy_path"; then
          _fail "vscode keybindings: historical JSONC must be readable"
          return
        fi
      done < <(
        git -C "$git_root" ls-tree -r --name-only "$base" -- "$git_rel" |
          LC_ALL=C sort
      )

      # all + the three platform families are the runtime union. termnav is
      # retained here only as the explicitly removed historical family.
      for family in all termnav linux macos windows; do
        report_family="$family"
        while IFS= read -r source; do
          if ! _vscode_test_append_jsonc_array \
            "$old_all" "$source" "$report_family"; then
            _fail "vscode keybindings: historical JSONC must parse completely"
            return
          fi
        done < <(
          HOME="$old_root" _merge_hook_family_files_matching \
            "vscode/keybindings/$family.d" \
            '*.jsonc' '*.replace/*.jsonc'
        )
        if [[ "$family" == "termnav" ]]; then
          # The historical scan above proves this migration's removals. Runtime
          # no longer loads the family, so this current scan only prevents an
          # unreachable fragment from becoming future retirement provenance.
          while IFS= read -r source; do
            [[ -n "$source" ]] || continue
            _fail "vscode keybindings: obsolete termnav family stays removed"
            return
          done < <(
            HOME="$repo" _merge_hook_family_files_matching \
              vscode/keybindings/termnav.d \
              '*.jsonc' '*.replace/*.jsonc'
          )
          continue
        fi
        while IFS= read -r source; do
          if ! _vscode_test_append_jsonc_array \
            "$current_all" "$source" "$report_family"; then
            _fail "vscode keybindings: current JSONC must parse completely"
            return
          fi
        done < <(
          HOME="$repo" _merge_hook_family_files_matching \
            "vscode/keybindings/$family.d" \
            '*.jsonc' '*.replace/*.jsonc'
        )
      done

      # An active object that disappears is a change or deletion. Requiring its
      # exact old form in retirement lets any machine jump directly from the
      # base to this generation, even if Settings Sync delivered an intervening
      # file. Retirement itself is append-only for the same skipped-release
      # reason.
      report=$(_tmpfile)
      _vscode_test_retirement_report "$old_all" "$current_all" >"$report"
      _assert_eq "vscode linux keybindings: changed and deleted bindings enter retirement history" \
        '[]' "$(jq -c '.missing.linux' "$report")"
      _assert_eq "vscode macos keybindings: changed and deleted bindings enter retirement history" \
        '[]' "$(jq -c '.missing.macos' "$report")"
      _assert_eq "vscode windows keybindings: changed and deleted bindings enter retirement history" \
        '[]' "$(jq -c '.missing.windows' "$report")"
      _assert_eq "vscode linux no-termnav keybindings: capability moves enter retirement history" \
        '[]' "$(jq -c '.missing.linux_no_termnav' "$report")"
      _assert_eq "vscode macos no-termnav keybindings: capability moves enter retirement history" \
        '[]' "$(jq -c '.missing.macos_no_termnav' "$report")"
      _assert_eq "vscode windows no-termnav keybindings: capability moves enter retirement history" \
        '[]' "$(jq -c '.missing.windows_no_termnav' "$report")"
      _assert_eq "vscode keybindings: retirement history is append-only" \
        '[]' "$(jq -c '.removed' "$report")"

      # All platforms consume all.d, making it the only safe home for an exact
      # retirement synchronized across machines. A platform-local retirement
      # would pass that platform's history check but strand the same generated
      # object after Settings Sync carries it elsewhere.
      _assert_eq "vscode keybindings: retirement records are globally available from all.d" \
        '[]' "$(jq -c '.misplaced' "$report")"
      # The capability repository starts with the frozen final generation, so
      # its standalone Git history cannot prove pre-extraction ownership. D4's
      # locked source-history gate owns that one cross-repository assertion.
      _pass "vscode keybindings: D4 owns pre-extraction retirement provenance"
      _assert_eq "vscode keybindings: PR 90 review-build proof adds no other targets" \
        '[]' "$(jq -c '.review_proof_extra' "$report")"
      _assert_eq "vscode keybindings: PR 90 review-build proof retains every canonical target" \
        '[]' "$(jq -c '.review_proof_missing' "$report")"
      _assert_eq "vscode keybindings: legacy local proof adds no other targets" \
        '[]' "$(jq -c '.legacy_proof_extra' "$report")"
      _assert_eq "vscode keybindings: legacy local proof retains both canonical targets" \
        '[]' "$(jq -c '.legacy_proof_missing' "$report")"
      _assert_eq "vscode keybindings: retirement proof labels stay allowlisted" \
        '[]' "$(jq -c '.invalid_proofs' "$report")"
      if [[ -n ${DOT_TEST_VSCODE_HISTORY_MARKER:-} ]]; then
        printf 'executed\n' >"$DOT_TEST_VSCODE_HISTORY_MARKER"
      fi
    }

    _assert_vscode_retirement_history "$REAL_HOME"

    # Negative fixtures protect the safety validator itself. These are kept
    # small and semantic so a future refactor cannot silently turn a missing,
    # removed, misplaced, or invented retirement into a passing repository
    # check while the much larger end-to-end fixture remains green.
    vscode_guard_old=$(_tmpfile)
    vscode_guard_current=$(_tmpfile)
    vscode_guard_report=$(_tmpfile)
    cat >"$vscode_guard_old" <<'JSON'
[
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+1",
      "command": "fixture.mustRetire"
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+2",
      "command": "fixture.oldRetirement",
      "dotfiles.retire": true
    }
  }
]
JSON
    cat >"$vscode_guard_current" <<'JSON'
[
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+2",
      "command": "fixture.oldRetirement"
    }
  },
  {
    "family": "macos",
    "binding": {
      "key": "ctrl+alt+3",
      "command": "fixture.misplacedRetirement",
      "dotfiles.retire": true
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+4",
      "command": "fixture.unprovenRetirement",
      "dotfiles.retire": true
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+5",
      "command": "fixture.invalidRetirementProof",
      "dotfiles.retire": true,
      "dotfiles.retire-proof": "review-build:invented"
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+6",
      "command": "fixture.substitutedReviewTarget",
      "dotfiles.retire": true,
      "dotfiles.retire-proof": "review-build:7030e8e"
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+7",
      "command": "fixture.substitutedLegacyTarget",
      "dotfiles.retire": true,
      "dotfiles.retire-proof": "legacy-local:280f7f8"
    }
  }
]
JSON
    _vscode_test_retirement_report \
      "$vscode_guard_old" "$vscode_guard_current" >"$vscode_guard_report"
    _assert_eq "vscode history guard: missing retirement is rejected" \
      "1" "$(jq '.missing.linux | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: removed retirement is rejected" \
      "1" "$(jq '.removed | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: platform-local retirement is rejected" \
      "1" "$(jq '.misplaced | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: unproven retirement is rejected" \
      "5" "$(jq '.unproven | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: unknown retirement proof is rejected" \
      "1" "$(jq '.invalid_proofs | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: substituted review target is rejected" \
      "1" "$(jq '.review_proof_extra | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: substituted legacy target is rejected" \
      "1" "$(jq '.legacy_proof_extra | length' "$vscode_guard_report")"

    vscode_base_guard_repo=$(_tmpdir)
    mkdir -p \
      "$vscode_base_guard_repo/.config/dot/merge-hooks.d/vscode/keybindings/all.d"
    printf '[]\n' \
      >"$vscode_base_guard_repo/.config/dot/merge-hooks.d/vscode/keybindings/all.d/10-keybindings.jsonc"
    git -C "$vscode_base_guard_repo" init -q
    git -C "$vscode_base_guard_repo" add .
    git -C "$vscode_base_guard_repo" \
      -c user.name=dot-fixture -c user.email=dot.fixture.invalid \
      commit -q --no-verify -m base
    vscode_self_base_rc=0
    (
      set -e
      _fail() { return 23; }
      export DOT_VSCODE_KEYBINDING_BASE_SHA
      DOT_VSCODE_KEYBINDING_BASE_SHA=$(
        git -C "$vscode_base_guard_repo" rev-parse HEAD
      )
      _assert_vscode_retirement_history "$vscode_base_guard_repo"
    ) || vscode_self_base_rc=$?
    _assert_eq "vscode history guard: clean checkout cannot compare with itself" \
      "23" "$vscode_self_base_rc"

    vscode_home=$(_tmpdir)
    vscode_bin=$(_tmpdir)/bin
    # Use the actual Sley-owned payload in this consumer integration fixture.
    # A repository-local copy would make local-extension reconciliation pass
    # even if dotfiles and the provider published incompatible contracts.
    vscode_sley_root="${DOT_TEST_SLEY_ROOT:-${DOT_TEST_HOST_HOME:-$REAL_HOME}/.local/share/cgraf78/sley}"
    vscode_sley_source="$vscode_sley_root/share/sley/vscode/sley-tools-0.0.1"
    export DOT_VSCODE_EXTENSIONS_SKIP=1
    mkdir -p \
      "$vscode_bin" \
      "$vscode_home/.config/Code/User" \
      "$vscode_home/.config/dot/merge-hooks.d" \
      "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode" \
      "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.3.0" \
      "$vscode_home/.local/share/dot-vscode-extensions" \
      "$vscode_home/.vscode/extensions"
    cat >"$vscode_home/.config/Code/User/settings.json" <<'JSON'
{
  "[python]": {
    "editor.defaultFormatter": "cgraf.sley-tools",
    "editor.formatOnSave": true,
    "editor.tabSize": 4
  },
  "evenBetterToml.schema.associations": {
    "^/Users/chris/stale\\.toml$": "file:///Users/chris/stale.schema.json",
    "^/root/stale\\.toml$": "file:///root/stale.schema.json"
  },
  "json.schemas": [
    {
      "fileMatch": ["/Users/chris/stale.json"],
      "name": "stale-json",
      "url": "file:///Users/chris/stale.schema.json"
    }
  ],
  "terminal.integrated.commandsToSkipShell": [
    "workbench.action.quickOpen",
    "workbench.action.togglePanel",
    "-local.terminalCommand"
  ],
  "yaml.schemas": {
    "file:///Users/chris/stale.schema.json": ["/Users/chris/stale.yml"]
  }
}
JSON
    _write_vscode_keybinding_conflicts "$vscode_home/.config/Code/User/keybindings.json"
    _add_vscode_pre_focus_keybindings \
      "$vscode_home/.config/Code/User/keybindings.json" \
      "linux"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_home/.config/dot/merge-hooks.d/vscode"
    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/25-order-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+5",
    "command": "fixture.orderCommonEarlier",
    "when": "fixture.orderCommonEarlier"
  }
]
JSON
    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/30-history-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+8",
    "command": "fixture.managedOld",
    "args": {"version": 1},
    "when": "fixture.managedOld"
  },
  {
    "key": "ctrl+alt+9",
    "command": "fixture.managedDeleted",
    "when": "fixture.managedDeleted"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u0010"},
    "when": "terminalFocus && fixtureParallelSource"
  },
  {
    "key": "ctrl+alt+6",
    "command": "fixture.orderCommonLater",
    "when": "fixture.orderCommonLater"
  }
]
JSON
    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/linux.d/20-order-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+7",
    "command": "fixture.orderPlatform",
    "when": "fixture.orderPlatform"
  }
]
JSON
    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/settings.d/50-prefix-probe.json" <<'JSON'
{
  "dotfiles.prefixProbe": true
}
JSON
    cp -R "$vscode_sley_source" \
      "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode/sley-tools-0.0.1"
    # Model an in-place fleet upgrade from the old dotfiles-owned payload.
    # The provider keeps the same extension basename, so basename-only pruning
    # cannot distinguish this stale live link from the desired Sley-owned one.
    cp -R "$vscode_sley_source" \
      "$vscode_home/.local/share/dot-vscode-extensions/sley-tools-0.0.1"
    ln -s "$vscode_home/.local/share/dot-vscode-extensions/sley-tools-0.0.1" \
      "$vscode_home/.vscode/extensions/sley-tools-0.0.1"
    cat >"$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.3.0/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.3.0"
}
JSON
    vscode_mv_log="$vscode_home/mv.log"
    cat >"$vscode_home/.vscode/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {
      "id": "keep.existing"
    },
    "relativeLocation": "keep-existing-extension-1.0.0"
  },
  {
    "identifier": {
      "id": "cgraf.sley-tools"
    },
    "relativeLocation": "stale-sley-tools-0.0.1"
  },
  {
    "identifier": {
      "id": "cgraf.termnav"
    },
    "relativeLocation": "termnav-0.2.0",
    "metadata": {
      "source": "local"
    }
  },
  {
    "identifier": {
      "id": "cgraf.retired-local"
    },
    "relativeLocation": "retired-local-0.0.1",
    "metadata": {
      "source": "local"
    }
  }
]
JSON
    ln -s "$vscode_home/.local/share/dot-vscode-extensions/retired-local-0.0.1" \
      "$vscode_home/.vscode/extensions/retired-local-0.0.1"
    mkdir -p "$vscode_home/.vscode-server/extensions"
    mkdir -p \
      "$vscode_home/.vscode-nosley/extensions" \
      "$vscode_home/.vscode-no-termnav/extensions" \
      "$vscode_home/.config/NoSley/User" \
      "$vscode_home/.config/NoTermnav/User" \
      "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0"
    ln -s "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode/sley-tools-0.0.1" \
      "$vscode_home/.vscode-nosley/extensions/sley-tools-0.0.1"
    cat >"$vscode_home/.vscode-nosley/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {
      "id": "cgraf.sley-tools"
    },
    "relativeLocation": "sley-tools-0.0.1"
  }
]
JSON
    cat >"$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.2.0"
}
JSON
    ln -s \
      "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0" \
      "$vscode_home/.vscode/extensions/termnav-0.2.0"
    ln -s \
      "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0" \
      "$vscode_home/.vscode-no-termnav/extensions/termnav-0.2.0"
    cat >"$vscode_home/.vscode-no-termnav/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {
      "id": "cgraf.termnav"
    },
    "relativeLocation": "termnav-0.2.0",
    "metadata": {
      "source": "local"
    }
  }
]
JSON
    cat >"$vscode_home/.config/NoTermnav/User/keybindings.json" <<'JSON'
[
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;5u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;6u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+/",
    "command": "editor.action.commentLine",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+.",
    "command": "editor.action.quickFix",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+\\",
    "command": "workbench.action.splitEditor",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+e",
    "command": "workbench.view.explorer",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+f",
    "command": "workbench.view.search",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+m",
    "command": "workbench.actions.view.problems",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+p",
    "command": "workbench.action.showCommands",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "shift+cmd+f",
    "command": "workbench.view.search",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "shift+cmd+p",
    "command": "workbench.action.showCommands",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+v",
    "command": "workbench.action.terminal.paste",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+v",
    "command": "editor.action.clipboardPasteAction",
    "when": "textInputFocus && !editorReadonly && !terminalFocus"
  },
  {
    "key": "cmd+/",
    "command": "editor.action.commentLine",
    "when": "terminalFocus && !termnav.nvimFocused"
  }
]
JSON
    _add_vscode_stale_terminal_native_keybindings \
      "$vscode_home/.config/NoTermnav/User/keybindings.json"
    cat >"$vscode_home/.config/NoSley/User/settings.json" <<'JSON'
{
  "[cpp]": {
    "editor.defaultFormatter": "cgraf.sley-tools",
    "editor.formatOnSave": true
  },
  "[python]": {
    "editor.defaultFormatter": "cgraf.sley-tools",
    "editor.formatOnSave": true,
    "editor.tabSize": 4
  }
}
JSON
    mkdir -p "$vscode_home/.config/dot/merge-hooks.d/vscode/variants.d"
    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/variants.d/80-extra.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Linux	$HOME/.vscode-server/extensions	$HOME/.vscode-server/extensions	-
Linux	$HOME/.vscode-nosley/extensions	$HOME/.vscode-nosley/extensions	$HOME/.config/NoSley/User	no-sley
Linux	$HOME/.vscode-no-termnav/extensions	$HOME/.vscode-no-termnav/extensions	$HOME/.config/NoTermnav/User	no-termnav
EOF
    cat >"$vscode_bin/checkrun" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "capabilities --json" ]]; then
  cat <<'JSON'
{
  "editorLanguageIds": {
    "vscode": {
      "bzl": ["starlark", "bzl"],
      "ini": ["ini"],
      "make": ["makefile"],
      "sh": ["shellscript"],
      "sshconfig": ["ssh_config"],
      "starlark": ["starlark", "bzl"],
      "text": ["plaintext"],
      "zsh": ["shellscript"]
    }
  },
  "filetypes": {
    "custom": {
      "extension": {
        "hgrc": "ini",
        "ini": "ini",
        "mak": "make",
        "pathlist": "text",
        "service": "systemd",
        "ssh-config": "sshconfig",
        "ssh_config": "sshconfig",
        "tsv": "text",
        "txt": "text"
      },
      "filename": {
        ".editorconfig": "editorconfig",
        ".gitconfig": "gitconfig",
        "BUILD": "bzl",
        "tmux.conf": "tmux"
      },
      "patterns": [
        {
          "filetype": "bzl",
          "pattern": "WORKSPACE.*"
        },
        {
          "filetype": "text",
          "pattern": "*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.conf"
        },
        {
          "filetype": "text",
          "pattern": "*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.replace/*.conf"
        }
      ]
    },
    "format": ["python", "sh", "starlark", "zsh"],
    "lint": ["python", "sh", "starlark", "zsh", "make", "editorconfig", "gitconfig", "systemd", "tmux"]
  },
  "version": 2
}
JSON
  exit 0
fi
  exit 2
EOF
    cat >"$vscode_home/checkrun-schema-policy.py" <<'EOF'
#!/usr/bin/env python3
import json
import sys

if sys.argv[1:] != ["--lsp-schemas", "--editor-sources"]:
    raise SystemExit(2)

json.dump(
    {
        "json": [
            {
                "name": "Sley verify registry",
                "url": "file:///mock/sley/verify.schema.json",
                "fileMatch": [
                    ".sley/verify.json",
                    "/Users/chris/.sley/verify.json",
                    "/Users/cgraf/.sley/verify.json",
                    "/home/cgraf/.sley/verify.json",
                    "**/.sley/verify.json"
                ],
            }
        ],
        "yaml": {
            "https://example.invalid/docker-compose.schema.json": [
                "docker-compose.yml",
                "/Users/chris/docker-compose.yml",
                "/Users/cgraf/docker-compose.yml",
                "/home/cgraf/docker-compose.yml",
                "**/docker-compose.yml",
            ]
        },
        "toml": {
            ".*/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
            "^/Users/chris/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
            "^/Users/cgraf/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
            "^/home/cgraf/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
        },
    },
    sys.stdout,
    separators=(",", ":"),
)
EOF
    cat >"$vscode_bin/shdeps" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "dep-file cgraf78/checkrun lib/checkrun/schemas/schema_policy.py" ]]; then
  printf '%s\n' "$HOME/checkrun-schema-policy.py"
  exit 0
fi
exit 2
EOF
    real_mv=$(command -v mv)
    cat >"$vscode_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "-f" ]]; then
  printf 'mv would prompt without -f: %s\n' "\$*" >&2
  exit 64
fi
shift
if [[ "\${1:-}" == "--" ]]; then
  shift
fi
printf '%s\n' "\$*" >>"\${DOT_TEST_MV_LOG:?}"
if [[ -n "\${DOT_TEST_MV_FAIL_SUFFIX:-}" && "\${!#}" == *"\$DOT_TEST_MV_FAIL_SUFFIX" ]]; then
  exit 75
fi
if [[ -n "\${DOT_TEST_MV_FAIL_ONCE_MARKER:-}" && ! -e "\$DOT_TEST_MV_FAIL_ONCE_MARKER" ]]; then
  : >"\$DOT_TEST_MV_FAIL_ONCE_MARKER"
  exit 75
fi
exec "$real_mv" -f -- "\$@"
EOF
    chmod +x "$vscode_bin/checkrun" "$vscode_bin/shdeps" "$vscode_bin/mv" "$vscode_home/checkrun-schema-policy.py"

    vscode_variants_home=$(_tmpdir)
    mkdir -p \
      "$vscode_variants_home/.vscode/extensions" \
      "$vscode_variants_home/.config/Code/User" \
      "$vscode_variants_home/.vscode-insiders/extensions" \
      "$vscode_variants_home/.config/Code - Insiders/User" \
      "$vscode_variants_home/.cursor/extensions" \
      "$vscode_variants_home/.config/Cursor/User" \
      "$vscode_variants_home/.config/dot/merge-hooks.d"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_variants_home/.config/dot/merge-hooks.d/vscode"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_default_linux_variants=$(env HOME="$vscode_variants_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants | sort
    ')
    vscode_expected_linux_variants=$(printf '%s\n' \
      "$vscode_variants_home/.vscode/extensions	$vscode_variants_home/.config/Code/User" \
      "$vscode_variants_home/.vscode-insiders/extensions	$vscode_variants_home/.config/Code - Insiders/User" \
      "$vscode_variants_home/.cursor/extensions	$vscode_variants_home/.config/Cursor/User" |
      sort)
    _assert_eq "vscode variants: default Linux variants include Code, Insiders, and Cursor" \
      "$vscode_expected_linux_variants" \
      "$vscode_default_linux_variants"

    partial_mv_bin=$(_tmpdir)/bin
    partial_commit_dir=$(_tmpdir)
    mkdir -p "$partial_mv_bin"
    cat >"$partial_mv_bin/mv" <<'EOF'
#!/usr/bin/env python3
import os
import sys

args = sys.argv[1:]
if args[:1] == ["-f"]:
    args = args[1:]
if args[:1] == ["--"]:
    args = args[1:]
src, dst = args
data = open(src, "rb").read()
with open(dst, "wb") as handle:
    handle.write(data[:32])
os.unlink(src)
EOF
    chmod +x "$partial_mv_bin/mv"
    python3 - <<PY
from pathlib import Path
expected = '{"value": "' + ('x' * 400) + '"}\n'
Path("$partial_commit_dir/settings.json").write_text('{"old": true}\n')
Path("$partial_commit_dir/settings.json.tmp").write_text(expected)
Path("$partial_commit_dir/settings.json.tmp.expected").write_text(expected)
PY
    partial_commit_rc=0
    # shellcheck disable=SC2016 # The inner shell expands temp-path env variables.
    env PATH="$partial_mv_bin:$PATH" \
      REAL_HOME="$REAL_HOME" \
      PARTIAL_TMP="$partial_commit_dir/settings.json.tmp" \
      PARTIAL_DST="$partial_commit_dir/settings.json" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { [[ $1 == wsl ]]; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_commit_tmp "$PARTIAL_TMP" "$PARTIAL_DST"
    ' || partial_commit_rc=$?
    _assert_eq "vscode commit: WSL partial replacement exits cleanly" \
      "0" "$partial_commit_rc"
    partial_expected=$(
      python3 - <<PY
from pathlib import Path
print(Path("$partial_commit_dir/settings.json.tmp.expected").read_text(), end="")
PY
    )
    partial_actual=$(cat "$partial_commit_dir/settings.json")
    _assert_eq "vscode commit: WSL partial replacement writes complete file" \
      "$partial_expected" "$partial_actual"

    # WSL cannot fall back to the native rename path: an open Windows file can
    # turn that apparent success into a truncated config. If the verified
    # writer is unavailable, keep both the destination and retryable temp file
    # rather than gambling with user configuration.
    wsl_missing_python_dir=$(_tmpdir)
    printf '%s\n' '{"old":true}' \
      >"$wsl_missing_python_dir/keybindings.json"
    printf '%s\n' '{"new":true}' \
      >"$wsl_missing_python_dir/keybindings.json.tmp"
    wsl_missing_python_rc=0
    # shellcheck disable=SC2016 # The inner shell owns the command override.
    env REAL_HOME="$REAL_HOME" WSL_FAILURE_DIR="$wsl_missing_python_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { [[ $1 == wsl ]]; }
      command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "python3" ]]; then
          return 1
        fi
        builtin command "$@"
      }
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_commit_tmp \
        "$WSL_FAILURE_DIR/keybindings.json.tmp" \
        "$WSL_FAILURE_DIR/keybindings.json"
    ' || wsl_missing_python_rc=$?
    _assert_eq "vscode commit: WSL missing verified writer fails" \
      "1" "$wsl_missing_python_rc"
    _assert_file_content "vscode commit: WSL failure preserves destination" \
      '{"old":true}' "$wsl_missing_python_dir/keybindings.json"
    _assert_file_content "vscode commit: WSL failure retains retryable temp" \
      '{"new":true}' "$wsl_missing_python_dir/keybindings.json.tmp"

    # A machine can skip the migration release and arrive after a focus-aware
    # replacement was itself deleted. Exact source retirement, rather than
    # today's active actions, must still identify the old generated rule.
    vscode_delayed_upgrade_dir=$(_tmpdir)
    cat >"$vscode_delayed_upgrade_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+p",
    "command": "workbench.action.quickOpen",
    "when": "terminalFocus",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "old"},
    "when": "fixture.retiredExact",
    "dotfiles.retire": true,
    "dotfiles.retire-proof": "review-build:7030e8e"
  }
]
JSON
    cat >"$vscode_delayed_upgrade_dir/keybindings.json" <<'JSON'
[
  {
    "key": "ctrl+p",
    "command": "workbench.action.quickOpen",
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "old"},
    "when": "fixture.retiredExact"
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "local"},
    "when": "fixture.retiredExact"
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "old"},
    "when": "fixture.retiredExact",
    "localOnly": true
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      HOME_DELAYED="$vscode_delayed_upgrade_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$HOME_DELAYED/source.json" \
        "$HOME_DELAYED/keybindings.json" \
        linux
    '
    _assert_eq "vscode keybindings: delayed upgrade retires source-owned baseline" \
      "0" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus"
      )] | length' "$vscode_delayed_upgrade_dir/keybindings.json")"
    _assert_eq "vscode keybindings: proven retirement preserves args and property near-matches" \
      '[{"args":{"text":"local"},"command":"fixture.retiredExact","key":"ctrl+alt+4","when":"fixture.retiredExact"},{"args":{"text":"old"},"command":"fixture.retiredExact","key":"ctrl+alt+4","localOnly":true,"when":"fixture.retiredExact"}]' \
      "$(jq -c '[.[] | select(.command == "fixture.retiredExact")]' \
        "$vscode_delayed_upgrade_dir/keybindings.json")"

    # Target B never runs generation V2 locally; it receives A's plain JSON
    # artifact through a divergent Settings Sync merge. V3's exact retirement
    # record must remove V2 without relying on comments or sibling metadata.
    vscode_sync_a=$(_tmpdir)
    vscode_sync_b=$(_tmpdir)
    cat >"$vscode_sync_a/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+1",
    "command": "fixture.syncV1",
    "when": "fixture.syncV1"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" SYNC_DIR="$vscode_sync_a" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$SYNC_DIR/source.json" "$SYNC_DIR/keybindings.json" macos
    '
    cat >"$vscode_sync_a/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+1",
    "command": "fixture.syncV1",
    "when": "fixture.syncV1",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+2",
    "command": "fixture.syncV2",
    "when": "fixture.syncV2"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" SYNC_DIR="$vscode_sync_a" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$SYNC_DIR/source.json" "$SYNC_DIR/keybindings.json" macos
    '
    # Model a Windows editor transporting the macOS generation with both a BOM
    # and CRLF. The retirement policy lives in source, so transport formatting
    # cannot erase the provenance needed by the target machine.
    {
      printf '\357\273\277'
      awk '{ printf "%s\r\n", $0 }' \
        "$vscode_sync_a/keybindings.json"
    } >"$vscode_sync_b/keybindings.json"
    cat >"$vscode_sync_b/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+2",
    "command": "fixture.syncV2",
    "when": "fixture.syncV2",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+3",
    "command": "fixture.syncV3",
    "when": "fixture.syncV3"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" SYNC_DIR="$vscode_sync_b" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$SYNC_DIR/source.json" "$SYNC_DIR/keybindings.json" linux
    '
    _assert_eq "vscode keybindings: source history retires synced generation unseen by target" \
      '["fixture.syncV3"]' \
      "$(jq -c '[.[] | .command | select(startswith("fixture.sync"))]' \
        "$vscode_sync_b/keybindings.json")"

    # A brand-new profile receives only active bindings. Retirement directives
    # must never leak into VS Code, where they would be invalid shortcuts.
    vscode_first_run_dir=$(_tmpdir)
    cat >"$vscode_first_run_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+1",
    "command": "fixture.firstRun",
    "when": "fixture.firstRun"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      FIRST_RUN_DIR="$vscode_first_run_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$FIRST_RUN_DIR/source.json" \
        "$FIRST_RUN_DIR/keybindings.json" \
        linux
    '
    _assert_eq "vscode keybindings: first run creates managed binding" \
      '["fixture.firstRun"]' \
      "$(jq -c '[.[] | .command | select(startswith("fixture."))]' \
        "$vscode_first_run_dir/keybindings.json")"
    _assert_not_contains "vscode keybindings: first run omits source retirement directives" \
      'dotfiles.retire' \
      "$(cat "$vscode_first_run_dir/keybindings.json")"

    # Losing a source layer could discard either an active binding or the exact
    # retirement that protects a skipped-release migration. Force the
    # intermediate rename to fail before any artifact is written.
    vscode_aggregate_failure_home=$(_tmpdir)
    mkdir -p "$vscode_aggregate_failure_home/.config/dot/merge-hooks.d"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_aggregate_failure_home/.config/dot/merge-hooks.d/vscode"
    vscode_aggregate_failure_marker=$vscode_aggregate_failure_home/mv-failed
    vscode_aggregate_failure_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_aggregate_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_MV_FAIL_ONCE_MARKER="$vscode_aggregate_failure_marker" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_settings_sources() { :; }
      _vscode_checkrun_settings() { printf "{}\n" >"$1"; }
      _remove_vscode_generated_checkrun_settings() { :; }
      _merge_vscode_settings() { :; }
      _merge_vscode_window_title() { :; }
      _merge_vscode_mcp_auth() { :; }
      _merge_vscode_config "$HOME/User"
    ' >/dev/null 2>&1 || vscode_aggregate_failure_rc=$?
    _assert_eq "vscode keybindings: aggregate rename failure propagates" \
      "1" "$vscode_aggregate_failure_rc"
    _assert_file_missing "vscode keybindings: aggregate failure writes no artifact" \
      "$vscode_aggregate_failure_home/User/keybindings.json"

    # A fragment is one reconciliation unit. Silently accepting only the first
    # of two JSON documents could drop active or retirement policy.
    cat >"$vscode_aggregate_failure_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid.jsonc" <<'JSON'
[]
[
  {
    "key": "ctrl+alt+9",
    "command": "fixture.hiddenSecondDocument",
    "when": "fixture.hiddenSecondDocument"
  }
]
JSON
    vscode_multi_fragment_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_aggregate_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_settings_sources() { :; }
      _vscode_checkrun_settings() { printf "{}\n" >"$1"; }
      _remove_vscode_generated_checkrun_settings() { :; }
      _merge_vscode_settings() { :; }
      _merge_vscode_window_title() { :; }
      _merge_vscode_mcp_auth() { :; }
      _merge_vscode_config "$HOME/User"
    ' >/dev/null 2>&1 || vscode_multi_fragment_rc=$?
    _assert_eq "vscode keybindings: multi-document source fragment fails closed" \
      "1" "$vscode_multi_fragment_rc"
    _assert_file_missing "vscode keybindings: invalid source fragment writes no artifact" \
      "$vscode_aggregate_failure_home/User/keybindings.json"

    printf '// comments only\n' \
      >"$vscode_aggregate_failure_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid.jsonc"
    vscode_empty_fragment_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_aggregate_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_settings_sources() { :; }
      _vscode_checkrun_settings() { printf "{}\n" >"$1"; }
      _remove_vscode_generated_checkrun_settings() { :; }
      _merge_vscode_settings() { :; }
      _merge_vscode_window_title() { :; }
      _merge_vscode_mcp_auth() { :; }
      _merge_vscode_config "$HOME/User"
    ' >/dev/null 2>&1 || vscode_empty_fragment_rc=$?
    _assert_eq "vscode keybindings: empty source fragment fails closed" \
      "1" "$vscode_empty_fragment_rc"

    # A failed atomic replacement must leave the entire old generation intact;
    # the retry can then install V2 without reasoning about a partial array.
    vscode_destination_failure_dir=$(_tmpdir)
    cat >"$vscode_destination_failure_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+3",
    "command": "fixture.attemptedV1",
    "when": "fixture.attemptedV1"
  }
]
JSON
    printf '[]\n' \
      >"$vscode_destination_failure_dir/keybindings.json"
    vscode_destination_failure_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_MV_FAIL_SUFFIX="/keybindings.json" \
      DESTINATION_FAILURE_DIR="$vscode_destination_failure_dir" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$DESTINATION_FAILURE_DIR/source.json" \
        "$DESTINATION_FAILURE_DIR/keybindings.json" \
        linux
    ' >/dev/null 2>&1 || vscode_destination_failure_rc=$?
    _assert_eq "vscode keybindings: destination write failure propagates" \
      "1" "$vscode_destination_failure_rc"
    _assert_file_content "vscode keybindings: destination failure leaves old file intact" \
      '[]' \
      "$vscode_destination_failure_dir/keybindings.json"
    cat >"$vscode_destination_failure_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retriedV2",
    "when": "fixture.retriedV2"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      DESTINATION_FAILURE_DIR="$vscode_destination_failure_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$DESTINATION_FAILURE_DIR/source.json" \
        "$DESTINATION_FAILURE_DIR/keybindings.json" \
        linux
    '
    _assert_eq "vscode keybindings: retry installs latest generation only" \
      '["fixture.retriedV2"]' \
      "$(jq -c '[.[] | .command | select(startswith("fixture."))]' \
        "$vscode_destination_failure_dir/keybindings.json")"

    # shellcheck disable=SC2016 # The inner shell expands REAL_HOME from env.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      merge
    '
    _assert_vscode_focus_keybinding_migration \
      "$vscode_home/.config/Code/User/keybindings.json" \
      "linux"
    # Each layer is prepended for compatibility with VS Code's bottom-up user
    # binding resolution. Check both lexical ordering inside all.d and the
    # platform family's precedence over the completed common aggregate.
    _assert_eq "vscode keybindings: later fragments and platform family retain precedence" \
      "true" \
      "$(jq '
        map(.command) as $commands
        | ($commands | index("fixture.orderPlatform")) as $platform
        | ($commands | index("fixture.orderCommonLater")) as $common_later
        | ($commands | index("fixture.orderCommonEarlier")) as $common_earlier
        | $platform < $common_later and $common_later < $common_earlier
      ' "$vscode_home/.config/Code/User/keybindings.json")"

    vscode_settings=$(jq -c . "$vscode_home/.config/Code/User/settings.json")
    _assert_contains "vscode sley: python uses local formatter" \
      '"editor.defaultFormatter":"cgraf.sley-tools"' "$vscode_settings"
    _assert_contains "vscode sley: generated format-on-save enabled" \
      '"editor.formatOnSave":true' "$vscode_settings"
    _assert_contains "vscode sley: shellscript mapping generated" \
      '"[shellscript]"' "$vscode_settings"
    _assert_contains "vscode sley: starlark mapping generated" \
      '"[bzl]"' "$vscode_settings"
    _assert_contains "vscode sley: generated settings preserve static python options" \
      '"editor.tabSize":4' "$vscode_settings"
    _assert_not_contains "vscode sley: lint-only filetypes are not format providers" \
      '"[makefile]"' "$vscode_settings"
    _assert_not_contains "vscode settings: stale isort setting is absent" \
      '"isort.args"' "$vscode_settings"
    _assert_contains "vscode terminal: native bell sound stays enabled" \
      '"accessibility.signals.terminalBell":{"sound":"on"}' "$vscode_settings"
    _assert_contains "vscode sley: exact filename association generated" \
      '".editorconfig":"editorconfig"' "$vscode_settings"
    _assert_contains "vscode sley: gitconfig association generated" \
      '".gitconfig":"gitconfig"' "$vscode_settings"
    _assert_contains "vscode sley: hgrc association generated" \
      '"*.hgrc":"ini"' "$vscode_settings"
    _assert_contains "vscode sley: ini association generated" \
      '"*.ini":"ini"' "$vscode_settings"
    _assert_contains "vscode sley: pathlist association generated" \
      '"*.pathlist":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: ssh-config association generated" \
      '"*.ssh-config":"ssh_config"' "$vscode_settings"
    _assert_contains "vscode sley: ssh_config association generated" \
      '"*.ssh_config":"ssh_config"' "$vscode_settings"
    _assert_contains "vscode sley: txt association generated" \
      '"*.txt":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: tsv association generated" \
      '"*.tsv":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: tmux association generated" \
      '"tmux.conf":"tmux"' "$vscode_settings"
    _assert_contains "vscode sley: build association generated" \
      '"BUILD":"starlark"' "$vscode_settings"
    _assert_contains "vscode sley: systemd extension association generated" \
      '"*.service":"systemd"' "$vscode_settings"
    _assert_contains "vscode sley: makefile extension association generated" \
      '"*.mak":"makefile"' "$vscode_settings"
    _assert_contains "vscode sley: pattern association generated" \
      '"WORKSPACE.*":"starlark"' "$vscode_settings"
    _assert_contains "vscode sley: agent target association generated" \
      '"*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.conf":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: agent replace target association generated" \
      '"*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.replace/*.conf":"plaintext"' "$vscode_settings"
    _assert_contains "vscode schemas: Checkrun JSON schemas generated" \
      '"json.schemas":[{"fileMatch":[".sley/verify.json","**/.sley/verify.json"],"name":"Sley verify registry","url":"file:///mock/sley/verify.schema.json"}]' "$vscode_settings"
    _assert_contains "vscode schemas: Checkrun YAML schemas generated" \
      '"yaml.schemas":{"https://example.invalid/docker-compose.schema.json":["docker-compose.yml","**/docker-compose.yml"]}' "$vscode_settings"
    _assert_contains "vscode schemas: Checkrun TOML schemas generated" \
      '"evenBetterToml.schema.associations":{".*/pyproject\\.toml$":"https://example.invalid/pyproject.schema.json"}' "$vscode_settings"
    _assert_not_contains "vscode schemas: stale synced JSON schemas are pruned" \
      'stale-json' "$vscode_settings"
    _assert_not_contains "vscode schemas: stale synced YAML schemas are pruned" \
      'stale.yml' "$vscode_settings"
    _assert_not_contains "vscode schemas: stale synced TOML schemas are pruned" \
      'stale.toml' "$vscode_settings"
    _assert_not_contains "vscode schemas: generated settings omit absolute home paths" \
      '/Users/chris' "$vscode_settings"
    _assert_contains "vscode settings: C/C++ comment continuation is durable" \
      '"C_Cpp.commentContinuationPatterns":["// ","/**"]' "$vscode_settings"
    _assert_contains "vscode settings: C/C++ snippets stay disabled" \
      '"C_Cpp.suggestSnippets":false' "$vscode_settings"
    _assert_contains "vscode settings: prefixed settings layer is discovered" \
      '"dotfiles.prefixProbe":true' "$vscode_settings"
    vscode_title_expected="fixture-host\${separator}\${activeRepositoryBranchName}\${separator}\${rootNameShort}\${separator}\${activeEditorShort}"
    _assert_eq "vscode settings: generated window title uses local host label" \
      "$vscode_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.config/Code/User/settings.json")"
    vscode_mcp_token_path="$vscode_home/.local/state/dot/vscode-mcp-auth-token"
    vscode_mcp_token_state=$(cat "$vscode_mcp_token_path" 2>/dev/null || true)
    vscode_mcp_token_setting=$(jq -r '.["vscode-mcp-server.authToken"] // empty' "$vscode_home/.config/Code/User/settings.json")
    _assert_eq "vscode mcp auth: generated token matches per-machine state file" \
      "$vscode_mcp_token_state" "$vscode_mcp_token_setting"
    if [[ -n "$vscode_mcp_token_setting" && ${#vscode_mcp_token_setting} -ge 32 ]]; then
      _pass "vscode mcp auth: token is non-trivial length"
    else
      _fail "vscode mcp auth: token is non-trivial length"
    fi
    vscode_mcp_token_perms=$(stat -c '%a' "$vscode_mcp_token_path" 2>/dev/null || stat -f '%Lp' "$vscode_mcp_token_path" 2>/dev/null)
    _assert_eq "vscode mcp auth: token state file is not group/world readable" \
      "600" "$vscode_mcp_token_perms"

    vscode_keybindings_before_repeat=$(cat "$vscode_home/.config/Code/User/keybindings.json")
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      merge
    '
    _assert_eq "vscode mcp auth: token is stable across repeat merges" \
      "$vscode_mcp_token_setting" \
      "$(jq -r '.["vscode-mcp-server.authToken"] // empty' "$vscode_home/.config/Code/User/settings.json")"
    _assert_file_content "vscode keybindings: repeat merge is byte-identical" \
      "$vscode_keybindings_before_repeat" \
      "$vscode_home/.config/Code/User/keybindings.json"

    vscode_valid_keybindings=$(_tmpfile)
    cp "$vscode_home/.config/Code/User/keybindings.json" \
      "$vscode_valid_keybindings"
    printf '[invalid\n' \
      >"$vscode_home/.config/Code/User/keybindings.json"
    vscode_invalid_keybindings_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      merge
    ' >/dev/null 2>&1 || vscode_invalid_keybindings_rc=$?
    _assert_eq "vscode keybindings: reconciliation failure propagates" \
      "1" "$vscode_invalid_keybindings_rc"
    cp "$vscode_valid_keybindings" \
      "$vscode_home/.config/Code/User/keybindings.json"

    # The real merge runner does not make errexit a dependable contract. Model
    # two variants without it so a later success cannot erase an earlier
    # reconciliation failure from the hook's explicit aggregate status.
    vscode_variant_failure_home=$(_tmpdir)
    mkdir -p \
      "$vscode_variant_failure_home/.config/dot/merge-hooks.d" \
      "$vscode_variant_failure_home/failing/User" \
      "$vscode_variant_failure_home/succeeding/User"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_variant_failure_home/.config/dot/merge-hooks.d/vscode"
    printf '[invalid\n' \
      >"$vscode_variant_failure_home/failing/User/keybindings.json"
    printf '[]\n' \
      >"$vscode_variant_failure_home/succeeding/User/keybindings.json"
    vscode_variant_failure_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_variant_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      # The hook compatibility layer installs the real host capability
      # predicate. This fixture deliberately has no editor marker because it
      # exercises variant failure aggregation, so select the hook explicitly
      # rather than depending on an ambient VS Code binary from the CI host.
      _dot_tool_present() { [[ $1 == vscode ]]; }
      _vscode_local_extensions() { :; }
      _vscode_variants() {
        printf "%s\t%s\n" \
          "$HOME/failing/extensions" "$HOME/failing/User" \
          "$HOME/succeeding/extensions" "$HOME/succeeding/User"
      }
      merge
    ' >/dev/null 2>&1 || vscode_variant_failure_rc=$?
    _assert_eq "vscode keybindings: an earlier variant failure survives a later success" \
      "1" "$vscode_variant_failure_rc"
    _assert_eq "vscode keybindings: later variant still reconciles after an earlier failure" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus && !termnav.nvimFocused"
      )] | length' \
        "$vscode_variant_failure_home/succeeding/User/keybindings.json")"

    # Extension hosts are independent, but their user config directory need
    # not be. Stable and insiders builds can share one settings/keybindings
    # target, so exercise the complete merge dispatcher: every extension host
    # must still be visited, while only the last declaration for a shared
    # config target may perform the expensive reconciliation.
    vscode_shared_config_log=$(_tmpfile)
    # shellcheck disable=SC2016 # The inner shell expands its fixture variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" \
      VSCODE_SHARED_CONFIG_LOG="$vscode_shared_config_log" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_install_declared_extensions() { :; }
      _merge_vscode_remote_window_titles() { :; }
      _merge_vscode_remote_mcp_auth() { :; }
      _vscode_local_extensions() { :; }
      _vscode_variants() {
        printf "%s\t%s\t%s\n" \
          "$HOME/stable/extensions" "$HOME/shared/User" "old-policy" \
          "$HOME/insiders/extensions" "$HOME/shared/User" "final-policy" \
          "$HOME/other/extensions" "$HOME/other/User" "other-policy" \
          "$HOME/remote/extensions" "" "extension-only"
      }
      _prune_vscode_local_extensions() {
        printf "extension\t%s\n" "$1" >>"$VSCODE_SHARED_CONFIG_LOG"
      }
      _merge_vscode_config() {
        printf "config\t%s\t%s\n" "$1" "$2" >>"$VSCODE_SHARED_CONFIG_LOG"
      }
      merge
    '
    _assert_file_content "vscode variants: shared config reconciles once with final policy" \
      "$(printf '%s\n' \
        "extension	$vscode_home/stable/extensions/extensions.json" \
        "extension	$vscode_home/insiders/extensions/extensions.json" \
        "extension	$vscode_home/other/extensions/extensions.json" \
        "extension	$vscode_home/remote/extensions/extensions.json" \
        "config	$vscode_home/shared/User	final-policy" \
        "config	$vscode_home/other/User	other-policy")" \
      "$vscode_shared_config_log"

    # The dispatcher test above proves call selection. This integration check
    # proves the stronger premise behind it: replaying an earlier policy before
    # the final no-sley policy produces byte-identical managed config to running
    # that final policy alone. A future additive-only merge would fail here.
    vscode_shared_sequence_dir="$vscode_home/shared-sequence/User"
    vscode_shared_final_dir="$vscode_home/shared-final/User"
    mkdir -p "$vscode_shared_sequence_dir" "$vscode_shared_final_dir"
    # shellcheck disable=SC2016 # The inner shell expands its fixture variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" \
      VSCODE_SHARED_SEQUENCE_DIR="$vscode_shared_sequence_dir" \
      VSCODE_SHARED_FINAL_DIR="$vscode_shared_final_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_config "$VSCODE_SHARED_SEQUENCE_DIR" ""
      _merge_vscode_config "$VSCODE_SHARED_SEQUENCE_DIR" "no-sley"
      _merge_vscode_config "$VSCODE_SHARED_FINAL_DIR" "no-sley"
    '
    _assert_file_content "vscode variants: final-only settings equal replayed shared policy" \
      "$(cat "$vscode_shared_sequence_dir/settings.json")" \
      "$vscode_shared_final_dir/settings.json"
    _assert_file_content "vscode variants: final-only keybindings equal replayed shared policy" \
      "$(cat "$vscode_shared_sequence_dir/keybindings.json")" \
      "$vscode_shared_final_dir/keybindings.json"
    # This variant deliberately installs no local extensions. The static
    # clauses must encode VS Code's documented undefined-context behavior:
    # negation selects the host route while the positive nvim route is dormant.
    # Actual context evaluation is covered by live acceptance with Termnav
    # absent; these assertions intentionally check the generated contract.
    _assert_file_missing "vscode keybindings: extensionless variant has no local extension registry" \
      "$vscode_variant_failure_home/succeeding/extensions/extensions.json"
    _assert_file_missing "vscode keybindings: extensionless variant has no Termnav symlink" \
      "$vscode_variant_failure_home/succeeding/extensions/termnav-0.3.0"
    _assert_eq "vscode keybindings: extensionless config includes negated host fallback" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus && !termnav.nvimFocused"
      )] | length' \
        "$vscode_variant_failure_home/succeeding/User/keybindings.json")"
    _assert_eq "vscode keybindings: extensionless config gates nvim route positively" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.terminal.sendSequence"
        and .when == "terminalFocus && termnav.nvimFocused"
      )] | length' \
        "$vscode_variant_failure_home/succeeding/User/keybindings.json")"

    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/30-history-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+8",
    "command": "fixture.managedOld",
    "args": {"version": 1},
    "when": "fixture.managedOld",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+9",
    "command": "fixture.managedDeleted",
    "when": "fixture.managedDeleted",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+0",
    "command": "fixture.managedNew",
    "args": {"version": 2},
    "when": "fixture.managedNew"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u0010"},
    "when": "terminalFocus && fixtureParallelSource"
  }
]
JSON
    vscode_visible_edit=$(_tmpfile)
    jq '. + [{
        "key": "ctrl+p",
        "command": "workbench.action.quickOpen",
        "when": "terminalFocus"
      }]' "$vscode_home/.config/Code/User/keybindings.json" \
      >"$vscode_visible_edit"
    mv "$vscode_visible_edit" \
      "$vscode_home/.config/Code/User/keybindings.json"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      merge
    '
    _assert_eq "vscode keybindings: prior managed action is retired after arbitrary change" \
      "0" \
      "$(jq '[.[] | select(.command == "fixture.managedOld")] | length' \
        "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: deleted managed action is retired" \
      "0" \
      "$(jq '[.[] | select(.command == "fixture.managedDeleted")] | length' \
        "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: replacement managed action is installed" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+alt+0"
        and .command == "fixture.managedNew"
        and .args.version == 2
        and .when == "fixture.managedNew"
      )] | length' "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: current fragments retain parallel conditions for one action" \
      "2" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.terminal.sendSequence"
        and .args.text == "\u0010"
        and (
          .when == "terminalFocus && termnav.nvimFocused"
          or .when == "terminalFocus && fixtureParallelSource"
        )
      )] | length' "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: retired pre-provenance binding cannot be reintroduced" \
      "0" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus"
      )] | length' "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_vscode_keybinding_precedence \
      "$vscode_home/.config/Code/User/keybindings.json" \
      "linux post-history"

    # Retirement is destructive authority, so a nearly-correct directive must
    # fail closed. Treating a string as truthy here would permit an accidental
    # source typo to delete a user's exact local binding.
    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid-retirement.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+9",
    "command": "fixture.invalidRetirement",
    "when": "fixture.invalidRetirement",
    "dotfiles.retire": "yes"
  }
]
JSON
    vscode_before_invalid_retirement=$(cat \
      "$vscode_home/.config/Code/User/keybindings.json")
    vscode_invalid_retirement_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      merge
    ' >/dev/null 2>&1 || vscode_invalid_retirement_rc=$?
    _assert_eq "vscode keybindings: malformed retirement directive fails closed" \
      "1" "$vscode_invalid_retirement_rc"
    _assert_file_content "vscode keybindings: malformed retirement leaves artifact unchanged" \
      "$vscode_before_invalid_retirement" \
      "$vscode_home/.config/Code/User/keybindings.json"
    rm "$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid-retirement.jsonc"

    # --- MCP auth edge cases: scoping, corruption recovery, race safety ---
    vscode_mcp_edge_home=$(_tmpdir)

    # Cursor never installs nabheet.vscode-ide-mcp (the declarative marketplace
    # profiles target editor = "vscode"), so it must never receive the secret
    # setting.
    vscode_mcp_applicable_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_applicable "$HOME/Library/Application Support/Cursor/User/settings.json" && exit 1
      _vscode_mcp_auth_applicable "$HOME/.cursor-server/data/Machine/settings.json" && exit 1
      _vscode_mcp_auth_applicable "$HOME/.config/Code/User/settings.json" || exit 1
      exit 0
    ' || vscode_mcp_applicable_rc=$?
    _assert_eq "vscode mcp auth: Cursor variants are excluded from token injection" \
      "0" "$vscode_mcp_applicable_rc"

    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_mcp_relative_path=$(env HOME="$vscode_mcp_edge_home" \
      XDG_STATE_HOME=relative/state REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token_path
      printf "%s" "$REPLY"
    ')
    _assert_eq "vscode mcp auth: relative XDG state uses HOME fallback" \
      "$vscode_mcp_edge_home/.local/state/dot/vscode-mcp-auth-token" \
      "$vscode_mcp_relative_path"

    vscode_mcp_missing_path_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env -u HOME -u XDG_STATE_HOME REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token_path
    ' >/dev/null 2>&1 || vscode_mcp_missing_path_rc=$?
    _assert_eq "vscode mcp auth: missing state roots fail closed" \
      "1" "$vscode_mcp_missing_path_rc"

    vscode_mcp_newline_state=$(_tmpdir)/state$'\n'
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env -u HOME XDG_STATE_HOME="$vscode_mcp_newline_state" \
      REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token
    '
    _assert_file_exists "vscode mcp auth: absolute XDG state works without HOME" \
      "$vscode_mcp_newline_state/dot/vscode-mcp-auth-token"
    _assert_file_missing "vscode mcp auth: XDG trailing newline is not truncated" \
      "${vscode_mcp_newline_state%$'\n'}/dot/vscode-mcp-auth-token"

    # A partial write (disk-full, crash mid-printf) leaves a short, non-empty,
    # garbage token. A bare non-empty check would trust it forever; shape
    # validation must regenerate a proper 64-char hex token instead.
    mkdir -p "$vscode_mcp_edge_home/.local/state/dot"
    printf 'a3f' >"$vscode_mcp_edge_home/.local/state/dot/vscode-mcp-auth-token"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_mcp_malformed_token=$(env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token
      printf "%s" "$REPLY"
    ')
    if [[ "$vscode_mcp_malformed_token" =~ ^[0-9a-f]{64}$ ]]; then
      _pass "vscode mcp auth: malformed existing token is regenerated as valid hex64"
    else
      _fail "vscode mcp auth: malformed existing token is regenerated as valid hex64"
    fi

    # Race safety: launch two real concurrent processes racing on first-run
    # creation against the same fresh path (the cron + interactive dot
    # update scenario). The mkdir-based mutex should serialize them so both
    # observe the same final token rather than each installing a different
    # value into whatever settings.json happens to read it.
    rm -rf "$vscode_mcp_edge_home/.local/state/dot"
    vscode_mcp_race_out="$vscode_mcp_edge_home/race-out.txt"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" \
      TMPDIR="$_DOT_TEST_TMP_ROOT" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      out1=$(mktemp); out2=$(mktemp)
      ( _vscode_mcp_auth_token && printf "%s" "$REPLY" >"$out1" ) &
      pid1=$!
      ( _vscode_mcp_auth_token && printf "%s" "$REPLY" >"$out2" ) &
      pid2=$!
      wait "$pid1" "$pid2"
      cat "$out1"; printf "\n"; cat "$out2"
      rm -f "$out1" "$out2"
    ' >"$vscode_mcp_race_out" 2>/dev/null
    vscode_mcp_race_line1=$(sed -n 1p "$vscode_mcp_race_out")
    vscode_mcp_race_line2=$(sed -n 2p "$vscode_mcp_race_out")
    _assert_eq "vscode mcp auth: concurrent first-run creation converges on one shared token" \
      "$vscode_mcp_race_line1" "$vscode_mcp_race_line2"
    if [[ "$vscode_mcp_race_line1" =~ ^[0-9a-f]{64}$ ]]; then
      _pass "vscode mcp auth: concurrent creation still produces a valid hex64 token"
    else
      _fail "vscode mcp auth: concurrent creation still produces a valid hex64 token"
    fi

    # Lock ownership: a process that times out waiting for a lock it never
    # acquired must NOT rmdir it out from under whoever actually holds it —
    # that would let a third racer sneak in and break their mutual exclusion
    # too. Pre-hold the lock with a fresh mtime (not stale) so the callee is
    # forced through the ~2s give-up-and-proceed-unlocked path, then assert
    # the lock this process never owned is still standing afterward.
    rm -rf "$vscode_mcp_edge_home/.local/state/dot"
    mkdir -p "$vscode_mcp_edge_home/.local/state/dot"
    vscode_mcp_foreign_lock="$vscode_mcp_edge_home/.local/state/dot/vscode-mcp-auth-token.lock"
    mkdir "$vscode_mcp_foreign_lock"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token || true
    '
    if [[ -d "$vscode_mcp_foreign_lock" ]]; then
      _pass "vscode mcp auth: giving up on a foreign lock does not release it"
    else
      _fail "vscode mcp auth: giving up on a foreign lock does not release it"
    fi
    rmdir "$vscode_mcp_foreign_lock" 2>/dev/null

    # A silent {} on generation failure would leave the extension installed
    # and unauthenticated with no trace. The security gap must be _warn'd.
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_mcp_warn_output=$(env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" \
      TMPDIR="$_DOT_TEST_TMP_ROOT" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*"; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token() { return 1; }
      out=$(mktemp)
      _vscode_mcp_auth_settings "$out"
      cat "$out"
      rm -f "$out"
    ' 2>&1)
    _assert_contains "vscode mcp auth: generation failure is warned, not silent" \
      "warning: could not generate vscode-mcp-server auth token" "$vscode_mcp_warn_output"
    _assert_contains "vscode mcp auth: generation failure still emits a valid empty settings layer" \
      '{}' "$vscode_mcp_warn_output"

    _assert_contains "vscode settings: bash LSP indexes shell-like files" \
      '"bashIde.globPattern":"**/*@(.sh|.inc|.bash|.zsh|.command)"' "$vscode_settings"
    _assert_contains "vscode settings: bash LSP uses PATH shfmt" \
      '"bashIde.shfmt.path":""' "$vscode_settings"
    _assert_contains "vscode settings: unchanged diff regions stay collapsed" \
      '"diffEditor.hideUnchangedRegions.enabled":true' "$vscode_settings"
    _assert_contains "vscode settings: copied text stays plain" \
      '"editor.copyWithSyntaxHighlighting":false' "$vscode_settings"
    _assert_contains "vscode settings: editor font size is durable" \
      '"editor.fontSize":11' "$vscode_settings"
    _assert_contains "vscode settings: linked editing is durable" \
      '"editor.linkedEditing":true' "$vscode_settings"
    _assert_contains "vscode settings: minimap stays disabled" \
      '"editor.minimap.enabled":false' "$vscode_settings"
    _assert_contains "vscode settings: line length ruler is durable" \
      '"editor.rulers":[100]' "$vscode_settings"
    _assert_contains "vscode settings: editor does not scroll past EOF" \
      '"editor.scrollBeyondLastLine":false' "$vscode_settings"
    _assert_contains "vscode settings: git autofetch is durable" \
      '"git.autofetch":true' "$vscode_settings"
    _assert_contains "vscode settings: git sync prompt stays disabled" \
      '"git.confirmSync":false' "$vscode_settings"
    _assert_contains "vscode settings: smart commit is enabled" \
      '"git.enableSmartCommit":true' "$vscode_settings"
    _assert_not_contains "vscode settings: personal remote SSH platform is absent" \
      '"remote.SSH.remotePlatform":{"example-host":"linux"}' "$vscode_settings"
    _assert_contains "vscode settings: search smart case is enabled" \
      '"search.smartCase":true' "$vscode_settings"
    _assert_contains "vscode settings: search respects global ignores" \
      '"search.useGlobalIgnoreFiles":true' "$vscode_settings"
    _assert_contains "vscode settings: Settings Sync ignores generated schema paths" \
      '"settingsSync.ignoredSettings":["evenBetterToml.schema.associations","json.schemas","vscode-mcp-server.authToken","window.title","yaml.schemas"]' "$vscode_settings"
    _assert_contains "vscode settings: Sley diagnostics skip noisy HOME dependencies" \
      '"sleyTools.diagnosticExclude":[".vscode/extensions/**",".vscode-server/**","Downloads/**","**/node_modules/**"]' "$vscode_settings"
    _assert_contains "vscode settings: shell integration history is durable" \
      '"terminal.integrated.shellIntegration.history":10000' "$vscode_settings"
    _assert_not_contains "vscode settings: personal cmder profile is absent" \
      '"cmder":{"args":["/K","%CMDER_ROOT%\\vendor\\bin\\vscode_init.cmd"],"path":"C:\\WINDOWS\\System32\\cmd.exe"}' "$vscode_settings"
    _assert_not_contains "vscode settings: stale notebook association is absent" \
      '"workbench.editorAssociations"' "$vscode_settings"
    _assert_contains "vscode settings: editor labels omit path context" \
      '"workbench.editor.labelFormat":"default"' "$vscode_settings"
    _assert_contains "vscode settings: modified tabs stay visible" \
      '"workbench.editor.highlightModifiedTabs":true' "$vscode_settings"
    vscode_mv_ops=$(cat "$vscode_mv_log")
    _assert_contains "vscode sley: settings replacement uses forced mv" \
      "$vscode_home/.config/Code/User/settings.json" "$vscode_mv_ops"
    _assert_contains "vscode sley: keybindings replacement uses forced mv" \
      "$vscode_home/.config/Code/User/keybindings.json" "$vscode_mv_ops"
    sorted_settings=$(_tmpfile)
    jq --indent 4 --sort-keys '.' "$vscode_home/.config/Code/User/settings.json" >"$sorted_settings"
    if cmp -s "$sorted_settings" "$vscode_home/.config/Code/User/settings.json"; then
      _pass "vscode sley: saved settings are sorted"
    else
      _fail "vscode sley: saved settings are sorted"
    fi
    sorted_keybindings=$(_tmpfile)
    jq --indent 4 --sort-keys '.' \
      "$vscode_home/.config/Code/User/keybindings.json" \
      >"$sorted_keybindings"
    if cmp -s "$sorted_keybindings" "$vscode_home/.config/Code/User/keybindings.json"; then
      _pass "vscode sley: saved keybindings are sorted"
    else
      _fail "vscode sley: saved keybindings are sorted"
    fi
    vscode_keybindings_file="$vscode_home/.config/Code/User/keybindings.json"
    _assert_vscode_keybinding_precedence "$vscode_keybindings_file" "linux"
    _assert_eq "vscode terminal: Alt-Shift-[ sends tmux/nvim tab-move escape" \
      "1" \
      "$(jq '[.[] | select(.key == "alt+shift+[" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus" and .args.text == "\u001b{")] | length' "$vscode_keybindings_file")"
    _assert_eq "vscode terminal: Alt-Shift-] sends tmux/nvim tab-move escape" \
      "1" \
      "$(jq '[.[] | select(.key == "alt+shift+]" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus" and .args.text == "\u001b}")] | length' "$vscode_keybindings_file")"
    _assert_vscode_terminal_clipboard_keybindings "$vscode_keybindings_file" "linux"
    _assert_vscode_focus_fallback_keybindings "$vscode_keybindings_file" "Linux"
    _assert_vscode_terminal_native_settings \
      "$vscode_home/.config/Code/User/settings.json" "Linux"
    _assert_vscode_terminal_local_settings_preserved \
      "$vscode_home/.config/Code/User/settings.json" "Linux"
    vscode_extensions=$(jq -c . "$vscode_home/.vscode/extensions/extensions.json")
    _assert_contains "vscode sley: extension registered" \
      '"id":"cgraf.sley-tools"' "$vscode_extensions"
    _assert_contains "vscode termnav: extension registered" \
      '"id":"cgraf.termnav"' "$vscode_extensions"
    _assert_eq "vscode local extensions: registration uses the manifest version" \
      "0.3.0" \
      "$(jq -r '.[] | select(.identifier.id == "cgraf.termnav") | .version' "$vscode_home/.vscode/extensions/extensions.json")"
    _assert_eq "vscode termnav: enabled upgrade keeps one current registration" \
      '["termnav-0.3.0"]' \
      "$(jq -c '[.[] | select(.identifier.id == "cgraf.termnav") | .relativeLocation]' "$vscode_home/.vscode/extensions/extensions.json")"
    _assert_eq "vscode local extensions: only declared extensions are registered" \
      '["cgraf.sley-tools","cgraf.termnav"]' \
      "$(jq -c '[.[] | select(.metadata.source == "local") | .identifier.id]' "$vscode_home/.vscode/extensions/extensions.json")"
    _assert_contains "vscode sley: preserves existing extension registrations" \
      '"id":"keep.existing"' "$vscode_extensions"
    _assert_contains "vscode sley: refreshes stale local extension registration" \
      '"relativeLocation":"sley-tools-0.0.1"' "$vscode_extensions"
    _assert_not_contains "vscode sley: removes stale local extension location" \
      'stale-sley-tools-0.0.1' "$vscode_extensions"
    _assert_not_contains "vscode local extensions: retired registration is pruned" \
      '"id":"cgraf.retired-local"' "$vscode_extensions"
    if [[ ! -L "$vscode_home/.vscode/extensions/retired-local-0.0.1" ]]; then
      _pass "vscode local extensions: retired broken symlink is pruned"
    else
      _fail "vscode local extensions: retired broken symlink is pruned"
    fi
    if [[ -L "$vscode_home/.vscode/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode sley: extension symlink deployed"
    else
      _fail "vscode sley: extension symlink deployed"
    fi
    _assert_eq "vscode sley: existing same-version link migrates to provider" \
      "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode/sley-tools-0.0.1" \
      "$(readlink "$vscode_home/.vscode/extensions/sley-tools-0.0.1")"
    if [[ -L "$vscode_home/.vscode/extensions/termnav-0.3.0" ]]; then
      _pass "vscode termnav: extension symlink deployed"
    else
      _fail "vscode termnav: extension symlink deployed"
    fi
    _assert_file_missing "vscode termnav: enabled upgrade prunes older generation" \
      "$vscode_home/.vscode/extensions/termnav-0.2.0"
    _assert_eq "vscode remote settings: generated window title uses remote host label" \
      "$vscode_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.vscode-server/data/Machine/settings.json")"
    _assert_eq "vscode remote settings: mcp auth token matches local variant's per-machine state" \
      "$vscode_mcp_token_state" \
      "$(jq -r '.["vscode-mcp-server.authToken"] // empty' "$vscode_home/.vscode-server/data/Machine/settings.json")"

    # The Ctrl+Arrow editor bindings are macOS-specific: Karabiner exempts
    # VS Code so integrated terminals receive raw Ctrl+Arrow sequences, and
    # this keybinding layer restores editor word movement only for that platform.
    vscode_mac_keybindings="$vscode_home/Library/Application Support/Code/User/keybindings.json"
    rm -rf "$vscode_home/Library/Application Support/Code/User"
    _write_vscode_keybinding_conflicts "$vscode_mac_keybindings"
    _add_vscode_pre_focus_keybindings "$vscode_mac_keybindings" "macOS"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Darwin\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/Library/Application Support/Code/User"
      }
      merge
    '
    _assert_vscode_keybinding_precedence "$vscode_mac_keybindings" "macOS"
    _assert_vscode_focus_keybinding_migration "$vscode_mac_keybindings" "macOS"
    _assert_vscode_macos_ctrl_arrow_keybindings "$vscode_mac_keybindings"
    _assert_vscode_macos_karabiner_terminal_keybindings "$vscode_mac_keybindings"
    _assert_vscode_terminal_clipboard_keybindings "$vscode_mac_keybindings" "macOS"
    _assert_vscode_focus_fallback_keybindings "$vscode_mac_keybindings" "macOS"
    _assert_vscode_terminal_native_settings \
      "$vscode_home/Library/Application Support/Code/User/settings.json" "macOS"

    rm -rf "$vscode_home/.config/Code/User"

    # Remote VS Code server profiles have an extensions dir but no local
    # settings/keybindings dir. Work overlays describe those as extension-only
    # variants so local dot extensions are visible to remote extension hosts
    # without inventing unrelated config files.
    remote_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="remote-only-host" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      merge
    ' || remote_rc=$?
    _assert_eq "vscode sley: extension-only merge exits cleanly" "0" "$remote_rc"
    vscode_remote_only_title_expected="remote-only-host\${separator}\${activeRepositoryBranchName}\${separator}\${rootNameShort}\${separator}\${activeEditorShort}"
    _assert_eq "vscode remote settings: server-only host gets generated window title" \
      "$vscode_remote_only_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.vscode-server/data/Machine/settings.json")"
    vscode_remote_extensions=$(jq -c . "$vscode_home/.vscode-server/extensions/extensions.json")
    _assert_contains "vscode sley: extension-only variant registered" \
      '"id":"cgraf.sley-tools"' "$vscode_remote_extensions"
    _assert_contains "vscode termnav: extension-only variant registered" \
      '"id":"cgraf.termnav"' "$vscode_remote_extensions"
    if [[ -L "$vscode_home/.vscode-server/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode sley: extension-only symlink deployed"
    else
      _fail "vscode sley: extension-only symlink deployed"
    fi
    if [[ -L "$vscode_home/.vscode-server/extensions/termnav-0.3.0" ]]; then
      _pass "vscode termnav: extension-only symlink deployed"
    else
      _fail "vscode termnav: extension-only symlink deployed"
    fi

    vscode_server_only_home=$(_tmpdir)
    mkdir -p "$vscode_server_only_home/.vscode-server"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_server_only_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_VSCODE_HOSTNAME="server-only-host" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      merge
    '
    vscode_server_only_title_expected="server-only-host\${separator}\${activeRepositoryBranchName}\${separator}\${rootNameShort}\${separator}\${activeEditorShort}"
    _assert_eq "vscode remote settings: server root works without detected variants" \
      "$vscode_server_only_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_server_only_home/.vscode-server/data/Machine/settings.json")"

    vscode_inaccessible_remote_home=$(_tmpdir)
    mkdir -p "$vscode_inaccessible_remote_home/.cursor-server"
    if ((EUID == 0)); then
      echo "  SKIP: vscode inaccessible server-root permission fixture (running as root)"
    else
      chmod 000 "$vscode_inaccessible_remote_home/.cursor-server"
      vscode_inaccessible_remote_dirs=""
      # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
      vscode_inaccessible_remote_dirs=$(env \
        HOME="$vscode_inaccessible_remote_home" REAL_HOME="$REAL_HOME" \
        PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" \
        DOT_TEST_VSCODE_HOSTNAME="inaccessible-remote-host" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { return 1; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_remote_settings_dirs
      ')
      chmod 700 "$vscode_inaccessible_remote_home/.cursor-server"
      _assert_eq "vscode remote settings: inaccessible server root is not discovered" \
        "" "$vscode_inaccessible_remote_dirs"
    fi

    vscode_nosley_extensions=$(jq -c . "$vscode_home/.vscode-nosley/extensions/extensions.json")
    _assert_not_contains "vscode sley: no-sley variant unregisters formatter extension" \
      '"id":"cgraf.sley-tools"' "$vscode_nosley_extensions"
    _assert_eq "vscode sley: no-sley variant keeps independent local extensions" \
      '["cgraf.termnav"]' \
      "$(jq -c '[.[] | select(.metadata.source == "local") | .identifier.id]' "$vscode_home/.vscode-nosley/extensions/extensions.json")"
    if [[ ! -e "$vscode_home/.vscode-nosley/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode sley: no-sley variant removes formatter symlink"
    else
      _fail "vscode sley: no-sley variant removes formatter symlink"
    fi
    if [[ -L "$vscode_home/.vscode-nosley/extensions/termnav-0.3.0" ]]; then
      _pass "vscode termnav: no-sley variant keeps tab router"
    else
      _fail "vscode termnav: no-sley variant keeps tab router"
    fi
    vscode_no_termnav_extensions=$(jq -c . \
      "$vscode_home/.vscode-no-termnav/extensions/extensions.json")
    _assert_not_contains "vscode termnav: no-termnav variant unregisters adapter" \
      '"id":"cgraf.termnav"' "$vscode_no_termnav_extensions"
    _assert_contains "vscode termnav: no-termnav keeps independent local extensions" \
      '"id":"cgraf.sley-tools"' "$vscode_no_termnav_extensions"
    _assert_file_missing "vscode termnav: no-termnav removes current adapter symlink" \
      "$vscode_home/.vscode-no-termnav/extensions/termnav-0.3.0"
    _assert_file_missing "vscode termnav: no-termnav removes older adapter symlinks" \
      "$vscode_home/.vscode-no-termnav/extensions/termnav-0.2.0"
    _assert_eq "vscode keybindings: every PR 90 review-build fallback is retired exactly" \
      "0" \
      "$(jq '[.[] | select(
        [.key, .command, (.when // "")] as $route
        | [
            ["ctrl+.", "editor.action.quickFix", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+/", "editor.action.commentLine", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+\\", "workbench.action.splitEditor", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+e", "workbench.view.explorer", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+f", "workbench.view.search", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+m", "workbench.actions.view.problems", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+p", "workbench.action.showCommands", "terminalFocus && !termnav.nvimFocused"],
            ["shift+cmd+f", "workbench.view.search", "terminalFocus && !termnav.nvimFocused"],
            ["shift+cmd+p", "workbench.action.showCommands", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+v", "workbench.action.terminal.paste", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+v", "editor.action.clipboardPasteAction", "textInputFocus && !editorReadonly && !terminalFocus"],
            ["cmd+/", "editor.action.commentLine", "terminalFocus && !termnav.nvimFocused"]
          ]
          | any(.[]; . == $route)
      )] | length' "$vscode_home/.config/NoTermnav/User/keybindings.json")"
    _assert_vscode_focus_fallback_keybindings \
      "$vscode_home/.config/NoTermnav/User/keybindings.json" "Linux"
    _assert_vscode_terminal_native_settings \
      "$vscode_home/.config/NoTermnav/User/settings.json" "Linux no-Termnav"
    _assert_vscode_native_tab_handling \
      "$vscode_home/.config/NoTermnav/User/keybindings.json" "Linux"

    for vscode_no_termnav_platform in macos windows; do
      vscode_no_termnav_config="$vscode_home/.config/NoTermnav-$vscode_no_termnav_platform/User"
      _write_vscode_keybinding_conflicts \
        "$vscode_no_termnav_config/keybindings.json"
      # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
      env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
        DOT_TEST_MV_LOG="$vscode_mv_log" \
        DOT_TEST_VSCODE_CONFIG="$vscode_no_termnav_config" \
        DOT_TEST_VSCODE_PLATFORM="$vscode_no_termnav_platform" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { return 1; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_keybinding_platform() {
          printf "%s\n" "$DOT_TEST_VSCODE_PLATFORM"
        }
        _merge_vscode_config "$DOT_TEST_VSCODE_CONFIG" no-termnav
      '
      case "$vscode_no_termnav_platform" in
        macos) vscode_no_termnav_label="macOS" ;;
        windows) vscode_no_termnav_label="Windows" ;;
      esac
      _assert_vscode_focus_fallback_keybindings \
        "$vscode_no_termnav_config/keybindings.json" \
        "$vscode_no_termnav_label"
      _assert_vscode_terminal_native_settings \
        "$vscode_no_termnav_config/settings.json" \
        "$vscode_no_termnav_label no-Termnav"
      _assert_vscode_native_tab_handling \
        "$vscode_no_termnav_config/keybindings.json" \
        "$vscode_no_termnav_label"
    done

    vscode_missing_termnav_home=$(_tmpdir)
    mkdir -p \
      "$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/local-extensions.d" \
      "$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/variants.d" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions" \
      "$vscode_missing_termnav_home/dev/termnav-9.9.9" \
      "$vscode_missing_termnav_home/managed/termnav-0.2.0" \
      "$vscode_missing_termnav_home/managed/termnav-tools-0.1.0" \
      "$vscode_missing_termnav_home/managed/termnav-2-tools-0.1.0"
    cat >"$vscode_missing_termnav_home/managed/termnav-0.2.0/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.2.0"
}
JSON
    cat >"$vscode_missing_termnav_home/managed/termnav-2-tools-0.1.0/package.json" <<'JSON'
{
  "name": "termnav-2-tools",
  "publisher": "cgraf",
  "version": "0.1.0"
}
JSON
    cat >"$vscode_missing_termnav_home/managed/termnav-tools-0.1.0/package.json" <<'JSON'
{
  "name": "termnav-tools",
  "publisher": "cgraf",
  "version": "0.1.0"
}
JSON
    cat >"$vscode_missing_termnav_home/dev/termnav-9.9.9/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "9.9.9"
}
JSON
    ln -s "$vscode_missing_termnav_home/managed/termnav-0.2.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.2.0"
    ln -s "$vscode_missing_termnav_home/managed/termnav-0.1.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.1.0"
    ln -s "$vscode_missing_termnav_home/dev/termnav-9.9.9" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-9.9.9"
    ln -s "$vscode_missing_termnav_home/managed/termnav-tools-0.1.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-tools-0.1.0"
    ln -s "$vscode_missing_termnav_home/managed/termnav-2-tools-0.1.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-2-tools-0.1.0"
    cat >"$vscode_missing_termnav_home/.vscode-no-termnav/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {"id": "cgraf.termnav"},
    "relativeLocation": "termnav-0.2.0",
    "metadata": {"source": "local"}
  }
]
JSON
    cat >"$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/local-extensions.d/10-extensions.tsv" <<'EOF'
# extension_id	source_dir	disabled_by_variant_options
cgraf.termnav	$HOME/managed/termnav-0.3.0	no-termnav
EOF
    cat >"$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/variants.d/10-variants.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Linux	$HOME/.vscode-no-termnav/extensions	$HOME/.vscode-no-termnav/extensions	-	no-termnav
EOF
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_missing_termnav_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      # This synthetic profile uses a nonstandard extension directory so the
      # generic host detector cannot infer VS Code. Keep the cleanup test about
      # Termnav ownership instead of whichever editor happens to be installed.
      _dot_tool_present() { [[ $1 == vscode ]]; }
      merge
    '
    _assert_eq \
      "vscode termnav: opt-out unregisters adapter when source is unavailable" \
      '[]' \
      "$(jq -c '[.[].identifier.id]' \
        "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/extensions.json")"
    _assert_file_missing \
      "vscode termnav: opt-out removes older adapter when source is unavailable" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.2.0"
    if [[ ! -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.1.0" ]]; then
      _pass "vscode termnav: opt-out removes broken managed adapter generations"
    else
      _fail "vscode termnav: opt-out removes broken managed adapter generations"
    fi
    if [[ -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-9.9.9" ]]; then
      _pass "vscode termnav: opt-out preserves same-ID development symlink"
    else
      _fail "vscode termnav: opt-out preserves same-ID development symlink"
    fi
    if [[ -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-tools-0.1.0" ]]; then
      _pass "vscode termnav: opt-out preserves same-parent prefix sibling"
    else
      _fail "vscode termnav: opt-out preserves same-parent prefix sibling"
    fi
    if [[ -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-2-tools-0.1.0" ]]; then
      _pass "vscode termnav: opt-out preserves numeric-prefix sibling"
    else
      _fail "vscode termnav: opt-out preserves numeric-prefix sibling"
    fi

    vscode_nosley_settings=$(jq -c . "$vscode_home/.config/NoSley/User/settings.json")
    _assert_not_contains "vscode sley: no-sley variant removes formatter settings" \
      'cgraf.sley-tools' "$vscode_nosley_settings"
    _assert_not_contains "vscode sley: no-sley variant removes generated format-on-save" \
      '"[cpp]"' "$vscode_nosley_settings"
    _assert_contains "vscode sley: no-sley variant preserves unrelated language settings" \
      '"editor.tabSize":4' "$vscode_nosley_settings"
    _assert_contains "vscode schemas: no-sley keeps Checkrun schema policy" \
      '"json.schemas":[{"fileMatch":[".sley/verify.json","**/.sley/verify.json"],"name":"Sley verify registry","url":"file:///mock/sley/verify.schema.json"}]' "$vscode_nosley_settings"

    win_profile="$vscode_home/win/Users/Chris"
    win_appdata="$win_profile/AppData/Roaming"
    win_code_user="$win_appdata/Code/User"
    win_ext_dir="$win_profile/.vscode/extensions"
    mkdir -p "$win_code_user" "$win_ext_dir/keep-existing-extension-1.0.0"
    cat >"$win_code_user/settings.json" <<'JSON'
{
  "editor.tabSize": 4,
  "terminal.integrated.commandsToSkipShell": [
    "workbench.action.quickOpen",
    "workbench.action.togglePanel",
    "-local.terminalCommand"
  ]
}
JSON
    # Windows shares the Ctrl baseline but must never claim macOS Cmd-shaped
    # locals. Seed the complete macOS historical shape here so WSL exercises
    # the persisted "windows" platform key, not just Linux/macOS branches.
    _write_vscode_keybinding_conflicts "$win_code_user/keybindings.json"
    _add_vscode_pre_focus_keybindings \
      "$win_code_user/keybindings.json" \
      "windows"
    win_extensions_before='[{"identifier":{"id":"keep.existing"},"relativeLocation":"keep-existing-extension-1.0.0","metadata":{"ownedBy":"windows"}}]'
    printf '%s\n' "$win_extensions_before" >"$win_ext_dir/extensions.json"
    rm -f \
      "$vscode_home/.vscode-server/extensions/extensions.json" \
      "$vscode_home/.vscode-server/extensions/sley-tools-0.0.1"

    wsl_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_WINDOWS_APPDATA="$win_appdata" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_WSL_PAIRED_ACCOUNT=1 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        merge
      ' || wsl_rc=$?
    _assert_eq "vscode wsl: merge exits cleanly" "0" "$wsl_rc"

    win_extensions=$(jq -c . "$win_ext_dir/extensions.json")
    _assert_contains "vscode wsl: Windows native extension registration is preserved" \
      '"id":"keep.existing"' "$win_extensions"
    _assert_file_content "vscode wsl: Windows native extension registry is untouched" \
      "$win_extensions_before" "$win_ext_dir/extensions.json"
    _assert_not_contains "vscode wsl: Windows native does not register sley extension" \
      '"id":"cgraf.sley-tools"' "$win_extensions"
    _assert_not_contains "vscode wsl: Windows native does not register termnav extension" \
      '"id":"cgraf.termnav"' "$win_extensions"
    _assert_file_missing "vscode wsl: Windows native sley extension not copied" \
      "$win_ext_dir/sley-tools-0.0.1"

    wsl_extensions=$(jq -c . "$vscode_home/.vscode-server/extensions/extensions.json")
    _assert_contains "vscode wsl: server registers sley extension" \
      '"id":"cgraf.sley-tools"' "$wsl_extensions"
    _assert_contains "vscode wsl: server registers termnav extension" \
      '"id":"cgraf.termnav"' "$wsl_extensions"
    _assert_eq "vscode wsl: server only registers declared local extensions" \
      '["cgraf.sley-tools","cgraf.termnav"]' \
      "$(jq -c '[.[] | select(.metadata.source == "local") | .identifier.id]' "$vscode_home/.vscode-server/extensions/extensions.json")"
    if [[ -L "$vscode_home/.vscode-server/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode wsl: server sley symlink deployed"
    else
      _fail "vscode wsl: server sley symlink deployed"
    fi
    if [[ -L "$vscode_home/.vscode-server/extensions/termnav-0.3.0" ]]; then
      _pass "vscode wsl: server termnav symlink deployed"
    else
      _fail "vscode wsl: server termnav symlink deployed"
    fi

    win_settings=$(jq -c . "$win_code_user/settings.json")
    _assert_contains "vscode wsl: Windows settings use local formatter" \
      '"editor.defaultFormatter":"cgraf.sley-tools"' "$win_settings"
    vscode_mv_ops=$(cat "$vscode_mv_log")
    _assert_not_contains "vscode wsl: Windows settings replacement avoids forced mv" \
      "$win_code_user/settings.json" "$vscode_mv_ops"
    _assert_not_contains "vscode wsl: Windows keybindings replacement avoids forced mv" \
      "$win_code_user/keybindings.json" "$vscode_mv_ops"
    _assert_vscode_terminal_clipboard_keybindings \
      "$win_code_user/keybindings.json" "Windows"
    _assert_vscode_focus_fallback_keybindings \
      "$win_code_user/keybindings.json" "Windows"
    _assert_vscode_terminal_native_settings \
      "$win_code_user/settings.json" "Windows"
    _assert_vscode_terminal_local_settings_preserved \
      "$win_code_user/settings.json" "Windows"
    _assert_vscode_focus_keybinding_migration \
      "$win_code_user/keybindings.json" "Windows"
    _assert_vscode_keybinding_precedence \
      "$win_code_user/keybindings.json" "Windows"

    # Regression: on a machine where a second Linux account (e.g. root) also
    # runs `dot update`, both accounts previously resolved the same native
    # Windows profile and raced unlocked writes on the same settings.json,
    # which is how it got corrupted. An unpaired account must leave the
    # native Windows config untouched entirely.
    win_settings_before_unpaired=$(cat "$win_code_user/settings.json")
    win_keybindings_before_unpaired=$(cat "$win_code_user/keybindings.json")
    win_extensions_before_unpaired=$(cat "$win_ext_dir/extensions.json")

    wsl_unpaired_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_WINDOWS_APPDATA="$win_appdata" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_WSL_PAIRED_ACCOUNT=0 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        merge
      ' || wsl_unpaired_rc=$?
    _assert_eq "vscode wsl unpaired: merge exits cleanly" "0" "$wsl_unpaired_rc"

    _assert_file_content "vscode wsl unpaired: native settings.json untouched" \
      "$win_settings_before_unpaired" "$win_code_user/settings.json"
    _assert_file_content "vscode wsl unpaired: native keybindings.json untouched" \
      "$win_keybindings_before_unpaired" "$win_code_user/keybindings.json"
    _assert_file_content "vscode wsl unpaired: native extensions.json untouched" \
      "$win_extensions_before_unpaired" "$win_ext_dir/extensions.json"

    # Regression: VS Code variant overlays can declare a WSL-platform
    # variant with an arbitrary config_dir (that's the whole point of the
    # mechanism — see merge-hooks.d/README.md). A future overlay pointing one
    # at the native Windows profile must not bypass account pairing just
    # because it comes through this overlay path instead of the built-in
    # appdata resolver.
    vscode_native_variant_home=$(_tmpdir)
    mkdir -p "$vscode_native_variant_home/.config/dot/merge-hooks.d/vscode/variants.d"
    native_marker="$vscode_native_variant_home/native-marker"
    native_ext_dir="$vscode_native_variant_home/native-ext"
    native_cfg_dir="$vscode_native_variant_home/native-cfg"
    touch "$native_marker"
    mkdir -p "$native_cfg_dir"
    cat >"$vscode_native_variant_home/.config/dot/merge-hooks.d/vscode/variants.d/80-native-test.tsv" <<EOF
# platform	marker	extensions_dir	config_dir	options
WSL	$native_marker	$native_ext_dir	$native_cfg_dir	-
EOF

    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    native_variant_paired=$(HOME="$vscode_native_variant_home" REAL_HOME="$REAL_HOME" \
      DOT_TEST=1 DOT_TEST_WSL_PAIRED_ACCOUNT=1 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_variants
      ')
    _assert_contains "vscode wsl variant overlay: paired account sees native-platform TSV variant" \
      "$native_cfg_dir" "$native_variant_paired"

    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    native_variant_unpaired=$(HOME="$vscode_native_variant_home" REAL_HOME="$REAL_HOME" \
      DOT_TEST=1 DOT_TEST_WSL_PAIRED_ACCOUNT=0 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_variants
      ')
    _assert_not_contains "vscode wsl variant overlay: unpaired account skips native-platform TSV variant" \
      "$native_cfg_dir" "$native_variant_unpaired"

    # Regression: _vscode_expand_path's ~ and ~/* case patterns were
    # unescaped, so bash tilde-expanded them to the live $HOME before pattern
    # matching. That made them also match an already-absolute path that
    # simply happens to live under $HOME (exactly what a TSV overlay author
    # would write instead of the $HOME/~ placeholder syntax), silently
    # double-prefixing it with $HOME again.
    expand_path_home=$(_tmpdir)
    expand_path_absolute="$expand_path_home/.vscode/extensions"
    expand_path_result=$(HOME="$expand_path_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_expand_path "$1"
    ' _ "$expand_path_absolute")
    _assert_eq "vscode expand path: absolute path under HOME is left unchanged" \
      "$expand_path_absolute" "$expand_path_result"

    expand_path_tilde_result=$(HOME="$expand_path_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_expand_path "~/.vscode/extensions"
    ')
    _assert_eq "vscode expand path: ~/ placeholder still expands to HOME" \
      "$expand_path_home/.vscode/extensions" "$expand_path_tilde_result"
  else
    echo "  SKIP: VS Code Sley merge hook assertions (jq unavailable)"
  fi

  echo ""
  echo "=== Sapling hook merge ==="

  # Sley owns the executable and its behavior. This suite only needs an
  # executable at the public installation path to exercise dot's activation
  # and merge policy; Sley's own suite covers the gate itself.
  _install_sapling_gate_fixture() {
    local fixture_home="$1"
    local gate="$fixture_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate"
    mkdir -p "${gate%/*}"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$gate"
    chmod +x "$gate"
  }

  sl_gate_bin=$(_tmpdir)/bin
  mkdir -p "$sl_gate_bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$sl_gate_bin/sl"
  chmod +x "$sl_gate_bin/sl"

  sl_missing_hook_home=$(_tmpdir)
  mkdir -p "$sl_missing_hook_home/.config/dot/merge-hooks.d/sapling/hgrc.d"
  cat >"$sl_missing_hook_home/.config/dot/merge-hooks.d/sapling/hgrc.d/10-sley.hgrc" <<'EOF'
[hooks]
precommit.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
EOF
  cat >"$sl_missing_hook_home/.hgrc" <<'EOF'
# dot-managed:hgrc:sley-legacy begin
# DO NOT EDIT: changes will be overwritten by dot update
# source: .config/dot/merge-hooks.d/legacy-sapling-hooks.sh
[hooks]
precommit.sley = /old/legacy/hook
# dot-managed:hgrc:sley-legacy end
EOF
  # shellcheck disable=SC2016 # The inner shell expands REAL_HOME from env.
  env HOME="$sl_missing_hook_home" REAL_HOME="$REAL_HOME" PATH="$sl_gate_bin:$PATH" bash -c '
    set -euo pipefail
    . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
    _log() { :; }
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/sapling.sh"
    merge
  '
  _assert_contains "sapling hook merge: missing gate preserves legacy block" \
    "/old/legacy/hook" "$(cat "$sl_missing_hook_home/.hgrc")"
  _assert_not_contains "sapling hook merge: missing gate does not install broken hook" \
    "$sl_missing_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" \
    "$(cat "$sl_missing_hook_home/.hgrc")"

  sl_non_hook_home=$(_tmpdir)
  mkdir -p "$sl_non_hook_home/.config/dot/merge-hooks.d/sapling/hgrc.d"
  _install_sapling_gate_fixture "$sl_non_hook_home"
  cat >"$sl_non_hook_home/.config/dot/merge-hooks.d/sapling/hgrc.d/10-mixed.hgrc" <<'EOF'
[hooks]
precommit.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
[ui]
username = Test User <test@example.com>
EOF
  # shellcheck disable=SC2016 # The inner shell expands REAL_HOME from env.
  env HOME="$sl_non_hook_home" REAL_HOME="$REAL_HOME" PATH="$sl_gate_bin:$PATH" bash -c '
    set -euo pipefail
    . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
    _log() { :; }
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/sapling.sh"
    merge
  '
  sl_non_hook_hgrc=$(cat "$sl_non_hook_home/.hgrc")
  _assert_contains "sapling hook merge: non-hook assignment preserved" \
    "username = Test User <test@example.com>" "$sl_non_hook_hgrc"
  _assert_contains "sapling hook merge: non-hook assignment does not block hooks" \
    "precommit.sley = $sl_non_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" \
    "$sl_non_hook_hgrc"

  sl_hook_home=$(_tmpdir)
  mkdir -p "$sl_hook_home/.config/dot/merge-hooks.d/sapling/hgrc.d"
  _install_sapling_gate_fixture "$sl_hook_home"
  cat >"$sl_hook_home/.config/dot/merge-hooks.d/sapling/hgrc.d/10-sley.ini" <<'EOF'
[hooks]
precommit.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-amend.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-absorb.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-record.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-continue.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-backout.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-graft.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-import.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-fold.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-split.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-rebase.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
pre-histedit.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate
EOF
  cat >"$sl_hook_home/.hgrc" <<'EOF'
# dot-managed:hgrc:sley-legacy begin
# DO NOT EDIT: changes will be overwritten by dot update
# source: .config/dot/merge-hooks.d/legacy-sapling-hooks.sh
[hooks]
precommit.sley = /old/legacy/hook
# dot-managed:hgrc:sley-legacy end
EOF
  # shellcheck disable=SC2016 # The inner shell expands REAL_HOME from env.
  env HOME="$sl_hook_home" REAL_HOME="$REAL_HOME" PATH="$sl_gate_bin:$PATH" bash -c '
    set -euo pipefail
    . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
    _log() { :; }
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/sapling.sh"
    merge
  '
  sl_hook_hgrc=$(cat "$sl_hook_home/.hgrc")
  _assert_contains "sapling hook merge: installs precommit gate" \
    "precommit.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-amend gate" \
    "pre-amend.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-absorb gate" \
    "pre-absorb.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-record gate" \
    "pre-record.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-continue gate" \
    "pre-continue.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-backout gate" \
    "pre-backout.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-graft gate" \
    "pre-graft.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-import gate" \
    "pre-import.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-fold gate" \
    "pre-fold.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-split gate" \
    "pre-split.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-rebase gate" \
    "pre-rebase.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: installs pre-histedit gate" \
    "pre-histedit.sley = $sl_hook_home/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" "$sl_hook_hgrc"
  _assert_contains "sapling hook merge: uses renamed source label" \
    "# source: .config/dot/merge-hooks.d/sapling/hgrc.d" "$sl_hook_hgrc"
  _assert_not_contains "sapling hook merge: legacy hook absent" \
    "/old/legacy/hook" "$sl_hook_hgrc"

  echo ""
  unset -f jq
  echo "=== Claude config merge hook ==="

  CLAUDE_DIR="$TEST_HOME/.claude"
  CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
  CLAUDE_AGENTGUARD_ASSETS="$TEST_HOME/agentguard-claude-assets"
  rm -rf "$CLAUDE_DIR"
  mkdir -p \
    "$CLAUDE_DIR" \
    "$CLAUDE_AGENTGUARD_ASSETS/_shared" \
    "$CLAUDE_AGENTGUARD_ASSETS/claude" \
    "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"
  printf '{"hooks": {}}\n' >"$CLAUDE_AGENTGUARD_ASSETS/claude/hooks.json"
  cat >"$CLAUDE_AGENTGUARD_ASSETS/_shared/reconcile-hooks.jq" <<'JQ'
# This section tests dotfiles' later Claude policy merge, not AgentGuard's
# provider semantics. Preserve the live fixture so the local layer remains the
# only variable under test.
($d[0] // {})
JQ

  _CLAUDE_HOOK="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/claude.sh"

  _run_claude_merge() (
    unset -f merge _merge_claude_settings 2>/dev/null
    # shellcheck source=/dev/null
    . "$_CLAUDE_HOOK"
    # shellcheck disable=SC2329 # Detected indirectly by command -v.
    claude() { :; }
    # shellcheck disable=SC2329 # Invoked by the sourced merge hook.
    dot_agentguard_integration_file() {
      if [[ "$1" == "claude" && "$2" == "hooks.json" ]]; then
        printf '%s/claude/hooks.json\n' "$CLAUDE_AGENTGUARD_ASSETS"
      elif [[ "$1" == "_shared" && "$2" == "reconcile-hooks.jq" ]]; then
        printf '%s/_shared/reconcile-hooks.jq\n' "$CLAUDE_AGENTGUARD_ASSETS"
      else
        return 1
      fi
    }
    merge
  )

  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"
  cat >"$CLAUDE_SETTINGS" <<'JSON'
{
  "permissions": {
    "allow": [
      "Glob(*)",
      "Read(*)",
      "Bash(npm test:*)"
    ]
  }
}
JSON
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d/10-settings.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Glob",
      "Read"
    ]
  }
}
JSON

  _run_claude_merge 2>/dev/null
  claude_allow=$(jq -r '.permissions.allow[]' "$CLAUDE_SETTINGS")
  _assert_contains "claude hook: bare glob permission kept" "Glob" "$claude_allow"
  _assert_contains "claude hook: bare read permission kept" "Read" "$claude_allow"
  _assert_contains "claude hook: scoped bash permission kept" "Bash(npm test:*)" "$claude_allow"
  _assert_not_contains "claude hook: stale glob wildcard normalized" "Glob(*)" "$claude_allow"
  _assert_not_contains "claude hook: stale read wildcard normalized" "Read(*)" "$claude_allow"

  rm -rf "$CLAUDE_DIR"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"

  # Hook-array dedup: a prior version of this merge concatenated every event's
  # hook groups without deduplicating, so each `dot update` run appended
  # another full copy forever (a real incident: 107 duplicate UserPromptSubmit
  # groups accumulated in a live settings.json, each one a separate hook
  # process Claude had to run per prompt). These cases lock in idempotency,
  # self-healing of already-corrupted files, and correct replace-not-duplicate
  # behavior when a hook's own config (e.g. timeout) changes.
  mkdir -p "$CLAUDE_DIR" "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d/10-settings.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [{"command": "agent-hook-prompt-submit", "timeout": 10, "type": "command"}],
        "matcher": ""
      }
    ]
  }
}
JSON

  # Repeat merges against a clean start must not grow the array.
  printf '{}\n' >"$CLAUDE_SETTINGS"
  _run_claude_merge 2>/dev/null
  _run_claude_merge 2>/dev/null
  _run_claude_merge 2>/dev/null
  claude_ups_count=$(jq '.hooks.UserPromptSubmit | length' "$CLAUDE_SETTINGS")
  _assert_eq "claude hook: repeat merges do not accumulate duplicate hook groups" \
    "1" "$claude_ups_count"

  # Self-healing: a file already corrupted by the old accretive-merge bug
  # (multiple byte-identical groups) must collapse to one canonical copy.
  jq -n '{hooks: {UserPromptSubmit: [
    {hooks: [{command: "agent-hook-prompt-submit", timeout: 10, type: "command"}], matcher: ""},
    {hooks: [{command: "agent-hook-prompt-submit", timeout: 10, type: "command"}], matcher: ""},
    {hooks: [{command: "agent-hook-prompt-submit", timeout: 10, type: "command"}], matcher: ""}
  ]}}' >"$CLAUDE_SETTINGS"
  _run_claude_merge 2>/dev/null
  claude_ups_count=$(jq '.hooks.UserPromptSubmit | length' "$CLAUDE_SETTINGS")
  _assert_eq "claude hook: an already-duplicated settings.json self-heals to one copy" \
    "1" "$claude_ups_count"

  # Genuinely distinct groups for the same event (different matcher) must both
  # survive — dedup is by identity, not a blunt "collapse everything" pass.
  printf '{}\n' >"$CLAUDE_SETTINGS"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d/10-settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"hooks": [{"command": "agent-hook-pre-bash", "timeout": 600, "type": "command"}], "matcher": "Bash"},
      {"hooks": [{"command": "agent-hook-pre-edit", "timeout": 10, "type": "command"}], "matcher": "Edit|Write"}
    ]
  }
}
JSON
  _run_claude_merge 2>/dev/null
  claude_pre_count=$(jq '.hooks.PreToolUse | length' "$CLAUDE_SETTINGS")
  _assert_eq "claude hook: distinct matcher groups for the same event both survive" \
    "2" "$claude_pre_count"

  # A config-only change (new timeout, same matcher+command) must replace the
  # stale group in place, not sit duplicated alongside it.
  jq -n '{hooks: {UserPromptSubmit: [
    {hooks: [{command: "agent-hook-prompt-submit", timeout: 10, type: "command"}], matcher: ""}
  ]}}' >"$CLAUDE_SETTINGS"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d/10-settings.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [{"command": "agent-hook-prompt-submit", "timeout": 20, "type": "command"}],
        "matcher": ""
      }
    ]
  }
}
JSON
  _run_claude_merge 2>/dev/null
  claude_ups_count=$(jq '.hooks.UserPromptSubmit | length' "$CLAUDE_SETTINGS")
  _assert_eq "claude hook: a timeout-only config change replaces the stale group" \
    "1" "$claude_ups_count"
  claude_ups_timeout=$(jq '.hooks.UserPromptSubmit[0].hooks[0].timeout' "$CLAUDE_SETTINGS")
  _assert_eq "claude hook: the replaced group carries the new timeout value" \
    "20" "$claude_ups_timeout"

  rm -rf "$CLAUDE_DIR"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/claude/settings.d"

  # ---------------------------------------------------------------------------
  # Tests: codex merge hook
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Codex config merge hook ==="

  if command -v yq >/dev/null 2>&1; then
    if [[ -n ${DOT_TEST_YQ_MERGE_BLOCK_MARKER:-} ]]; then
      printf 'executed\n' >"$DOT_TEST_YQ_MERGE_BLOCK_MARKER"
    fi

    CODEX_DIR="$TEST_HOME/.codex"
    CODEX_CONFIG="$CODEX_DIR/config.toml"
    CODEX_AGENTGUARD_ASSETS="$TEST_HOME/agentguard-codex-assets"
    rm -rf "$CODEX_DIR"
    mkdir -p "$CODEX_DIR" \
      "$CODEX_AGENTGUARD_ASSETS/_shared" \
      "$CODEX_AGENTGUARD_ASSETS/codex" \
      "$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/50-environment.replace" \
      "$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/layered.d/50-environment.replace" \
      "$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/experimental.d"

    _CODEX_HOOK="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/codex.sh"
    _CODEX_BIN=$(_mock_bin)
    _CODEX_VERSION_PROBE="$TEST_HOME/.codex-version-probe"
    export DOT_TEST_CODEX_VERSION_PROBE="$_CODEX_VERSION_PROBE"
    cat >"$_CODEX_BIN/codex" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  if [[ -n "${DOT_TEST_CODEX_VERSION_PROBE:-}" ]]; then
    printf 'version-probed\n' >>"$DOT_TEST_CODEX_VERSION_PROBE"
  fi
  printf 'codex version should not be queried\n' >&2
  exit 0
fi
exit 2
MOCK
    chmod +x "$_CODEX_BIN/codex"

    _run_codex_merge() (
      unset -f merge _merge_codex_config _trust_codex_dotfile_hooks 2>/dev/null
      # shellcheck source=/dev/null
      . "$_CODEX_HOOK"
      # shellcheck disable=SC2329 # Invoked by Codex source discovery.
      dot_agentguard_integration_file() {
        if [[ "$1" == "codex" && "$2" == "hooks.toml" ]]; then
          printf '%s/codex/hooks.toml\n' "$CODEX_AGENTGUARD_ASSETS"
        elif [[ "$1" == "_shared" && "$2" == "reconcile-hooks.jq" ]]; then
          printf '%s/_shared/reconcile-hooks.jq\n' "$CODEX_AGENTGUARD_ASSETS"
        else
          return 1
        fi
      }
      PATH="$_CODEX_BIN:$PATH" merge
    )

    # A neutral provider fixture proves the dependency layer participates in
    # merge, cache, and trust handling without copying AgentGuard's real Codex
    # compatibility map into this consumer suite.
    cat >"$CODEX_AGENTGUARD_ASSETS/_shared/reconcile-hooks.jq" <<'JQ'
# Neutral provider contract fixture. Replace incoming provider event arrays,
# retire one provider event, and preserve consumer-owned hook metadata/state.
($d[0] // {}) as $live |
$s[0] as $provider |
($live * ($provider | del(.hooks))) |
.hooks = (($live.hooks // {}) + ($provider.hooks // {})) |
del(.hooks.ProviderRetired)
JQ
    cat >"$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml" <<'TOML'
[features]
hooks = true

[[hooks.PreToolUse]]
matcher = "ProviderShell"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "provider-pre-shell"
timeout = 120

[[hooks.PreToolUse]]
matcher = "ProviderEdit"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "provider-pre-edit"
timeout = 10

[[hooks.PostToolUse]]
matcher = "ProviderEdit"
[[hooks.PostToolUse.hooks]]
type = "command"
command = "provider-post-edit"
timeout = 60
TOML

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/10-settings.toml" <<'TOML'
model = "common-model"
project_doc_fallback_filenames = ["AGENTS.md", "CLAUDE.md"]

[projects."/home/testuser"]
trust_level = "trusted"

[tui]
status_line = ["model-with-reasoning"]
TOML

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/50-environment.replace/80-work.toml" <<'TOML'
[projects."/work/project"]
trust_level = "trusted"

[mcp_servers.example]
command = "true"

[mcp_servers.example.tools.lookup]
approval_mode = "approve"
TOML

    # Pre-existing config.toml carries a legacy [profiles.default] table (CLI state
    # from before the overlay migration); the merge must strip it from config.toml.
    cat >"$CODEX_CONFIG" <<'TOML'
[profiles.default]
model = "local-default"

[notice.model_migrations]
"gpt-5.3-codex" = "gpt-5.4"

[tui.model_availability_nux]
"gpt-5.5" = 2

[[hooks.PreToolUse]]
matcher = "RetiredProviderShell"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "provider-pre-shell-v1"

[[hooks.ProviderRetired]]
[[hooks.ProviderRetired.hooks]]
type = "command"
command = "provider-retired"
TOML

    _CODEX_ALIAS_PARENT=$(_tmpdir)
    ln -s "$TEST_HOME" "$_CODEX_ALIAS_PARENT/home-link"
    cat >>"$CODEX_CONFIG" <<TOML

[hooks.state."$_CODEX_ALIAS_PARENT/home-link/.codex/config.toml:pre_tool_use:0:0"]
enabled = false
trusted_hash = "sha256:old"
TOML

    # Named profiles render as standalone ~/.codex/<name>.config.toml overlays.
    # Layer a common + work profile fragment and seed the overlay with local CLI
    # state to verify merge order and state preservation below.
    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/layered.d/10-settings.toml" <<'TOML'
approval_policy = "never"
model_reasoning_effort = "high"

[features]
web_search_request = true
TOML

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/layered.d/50-environment.replace/80-work.toml" <<'TOML'
model_reasoning_effort = "low"
sandbox_mode = "danger-full-access"
TOML

    cat >"$CODEX_DIR/layered.config.toml" <<'TOML'
model = "local-allow"
approval_policy = "on-request"
TOML

    # These profiles were previously dot-managed. Removing their source families
    # must also retire generated outputs instead of leaving stale policy behind.
    printf 'sandbox_mode = "danger-full-access"\n' >"$CODEX_DIR/allow_all.config.toml"
    printf 'sandbox_mode = "workspace-write"\n' >"$CODEX_DIR/no_prompt.config.toml"

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/experimental.d/10-settings.toml" <<'TOML'
model = "experimental-model"
model_reasoning_effort = "high"
TOML

    _run_codex_merge 2>/dev/null
    _assert_file_exists "codex hook: config created" "$CODEX_CONFIG"
    _assert_file_missing "codex hook: merge does not probe installed Codex version" "$_CODEX_VERSION_PROBE"
    codex_content=$(cat "$CODEX_CONFIG")
    _assert_contains "codex hook: emits hook array tables" "[[hooks.PreToolUse]]" "$codex_content"

    if python3 - "$CODEX_CONFIG" <<'PY'; then
import hashlib
import json
import pathlib
import sys
import tomllib

EVENT_LABELS = {
    "PreToolUse": "pre_tool_use",
    "PermissionRequest": "permission_request",
    "PostToolUse": "post_tool_use",
    "PreCompact": "pre_compact",
    "PostCompact": "post_compact",
    "SessionStart": "session_start",
    "UserPromptSubmit": "user_prompt_submit",
    "Stop": "stop",
}
MATCHER_EVENTS = {
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "SessionStart",
}


def current_hash(event_name, group, hook):
    normalized_hook = {
        "type": "command",
        "command": hook["command"],
        "timeout": max(int(hook.get("timeout", 600)), 1),
        "async": bool(hook.get("async", False)),
    }
    if hook.get("statusMessage") is not None:
        normalized_hook["statusMessage"] = hook["statusMessage"]
    identity = {
        "event_name": EVENT_LABELS[event_name],
        "hooks": [normalized_hook],
    }
    if event_name in MATCHER_EVENTS and group.get("matcher") is not None:
        identity["matcher"] = group["matcher"]
    payload = json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()
    return "sha256:" + hashlib.sha256(payload).hexdigest()


with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["model"] == "common-model"
assert data["features"]["hooks"] is True
assert "profiles" not in data, "legacy [profiles.*] tables must be stripped from config.toml"
assert "profile" not in data, "legacy top-level profile selector must be stripped"
assert data["projects"]["/home/testuser"]["trust_level"] == "trusted"
assert data["projects"]["/work/project"]["trust_level"] == "trusted"
assert data["mcp_servers"]["example"]["tools"]["lookup"]["approval_mode"] == "approve"
assert data["notice"]["model_migrations"]["gpt-5.3-codex"] == "gpt-5.4"
assert data["tui"]["model_availability_nux"]["gpt-5.5"] == 2
assert data["hooks"]["PreToolUse"][0]["matcher"] == "ProviderShell"
assert data["hooks"]["PreToolUse"][0]["hooks"][0]["command"] == "provider-pre-shell"
assert data["hooks"]["PreToolUse"][1]["matcher"] == "ProviderEdit"
assert data["hooks"]["PreToolUse"][1]["hooks"][0]["command"] == "provider-pre-edit"
assert data["hooks"]["PostToolUse"][0]["matcher"] == "ProviderEdit"
assert data["hooks"]["PostToolUse"][0]["hooks"][0]["command"] == "provider-post-edit"
assert "ProviderRetired" not in data["hooks"]
assert "provider-pre-shell-v1" not in str(data["hooks"])
state = data["hooks"]["state"]
config_path = pathlib.Path(sys.argv[1]).resolve()
shell_key = f"{config_path}:pre_tool_use:0:0"
edit_key = f"{config_path}:pre_tool_use:1:0"
post_edit_key = f"{config_path}:post_tool_use:0:0"
assert state[shell_key]["enabled"] is False
assert state[shell_key]["trusted_hash"] == current_hash(
    "PreToolUse",
    data["hooks"]["PreToolUse"][0],
    data["hooks"]["PreToolUse"][0]["hooks"][0],
)
assert state[edit_key]["trusted_hash"] == current_hash(
    "PreToolUse",
    data["hooks"]["PreToolUse"][1],
    data["hooks"]["PreToolUse"][1]["hooks"][0],
)
assert state[post_edit_key]["trusted_hash"] == current_hash(
    "PostToolUse",
    data["hooks"]["PostToolUse"][0],
    data["hooks"]["PostToolUse"][0]["hooks"][0],
)
PY
      _pass "codex hook: merges common/work, preserves local state, and trusts managed hooks"
    else
      _fail "codex hook: merges common/work, preserves local state, and trusts managed hooks"
    fi

    mv \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml" \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml.unavailable"
    # Recreate the former generated outputs after a successful merge. Even a
    # provider failure must still perform the independent retirement cleanup.
    printf 'sandbox_mode = "danger-full-access"\n' >"$CODEX_DIR/allow_all.config.toml"
    printf 'sandbox_mode = "workspace-write"\n' >"$CODEX_DIR/no_prompt.config.toml"
    codex_before_missing=$(cat "$CODEX_CONFIG")
    codex_missing_output=$(_run_codex_merge 2>&1)
    codex_missing_status=$?
    _assert_exit "codex consumer: missing provider asset is a failed refresh" \
      1 "$codex_missing_status"
    _assert_contains "codex consumer: missing provider asset reports the failed refresh" \
      "AgentGuard codex integration unavailable" "$codex_missing_output"
    _assert_eq "codex consumer: missing provider asset preserves the whole live config" \
      "$codex_before_missing" "$(cat "$CODEX_CONFIG")"
    _assert_eq "codex consumer: missing provider asset preserves live hook tables" \
      "provider-pre-shell" \
      "$(
        python3 - "$CODEX_CONFIG" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    print(tomllib.load(f)["hooks"]["PreToolUse"][0]["hooks"][0]["command"])
PY
      )"
    mv \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml.unavailable" \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml"

    _assert_file_missing "codex hook: retires generated allow_all profile" \
      "$CODEX_DIR/allow_all.config.toml"
    _assert_file_missing "codex hook: retires generated no_prompt profile" \
      "$CODEX_DIR/no_prompt.config.toml"

    # Profile overlays: common + work fragments merge into the per-profile file,
    # later layers win, source layers override pre-existing local keys, and local
    # CLI-owned keys without a source counterpart survive.
    if python3 - "$CODEX_DIR/layered.config.toml" <<'PY'; then
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["model_reasoning_effort"] == "low", data       # work overrides common
assert data["sandbox_mode"] == "danger-full-access", data  # work-only key lands
assert data["approval_policy"] == "never", data            # source beats local state
assert data["model"] == "local-allow", data                # local-only key preserved
assert data["features"]["web_search_request"] is True, data  # nested profile tables survive
PY
      _pass "codex hook: renders profile overlays, layering work over common and preserving local state"
    else
      _fail "codex hook: renders profile overlays, layering work over common and preserving local state"
    fi

    if python3 - "$CODEX_DIR/experimental.config.toml" <<'PY'; then
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["model"] == "experimental-model", data
assert data["model_reasoning_effort"] == "high", data
PY
      _pass "codex hook: renders dynamically discovered profile families"
    else
      _fail "codex hook: renders dynamically discovered profile families"
    fi

    _run_codex_merge 2>/dev/null
    if python3 - "$CODEX_CONFIG" <<'PY'; then
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert "profiles" not in data, "new Codex config should not keep legacy inline profiles"
PY
      _pass "codex hook: keeps config.toml free of legacy inline profiles"
    else
      _fail "codex hook: keeps config.toml free of legacy inline profiles"
    fi
    _assert_file_missing "codex hook: repeat merge does not probe installed Codex version" "$_CODEX_VERSION_PROBE"

    codex_content_before_cache_probe=$(cat "$CODEX_CONFIG")
    saved_path=$PATH
    codex_cache_output=""
    codex_cache_status=0
    codex_cache_output=$(_run_codex_merge 2>&1) || codex_cache_status=$?
    PATH=$saved_path
    _assert_exit "codex hook: warm cache succeeds without merge dependencies" \
      0 "$codex_cache_status"
    _assert_not_contains "codex hook: warm cache emits no missing-dependency warning" \
      "mikefarah/yq not found" "$codex_cache_output"
    _assert_eq "codex hook: warm cache skips yq when inputs are unchanged" \
      "$codex_content_before_cache_probe" "$(cat "$CODEX_CONFIG")"

    cat >>"$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/50-environment.replace/80-work.toml" <<'TOML'

[projects."/cache-source-change"]
trust_level = "trusted"
TOML
    saved_path=$PATH
    _codex_no_yq_bin=$(_mock_bin)
    ln -s "$(command -v python3)" "$_codex_no_yq_bin/python3"
    PATH="$_codex_no_yq_bin:/usr/bin:/bin" _run_codex_merge 2>/dev/null
    PATH=$saved_path
    _run_codex_merge 2>/dev/null
    if python3 - "$CODEX_CONFIG" <<'PY'; then
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["projects"]["/cache-source-change"]["trust_level"] == "trusted"
PY
      _pass "codex hook: skipped merge does not cache stale config"
    else
      _fail "codex hook: skipped merge does not cache stale config"
    fi

    if [[ -n "${CI:-}" ]]; then
      _pass "codex hook: installed Codex trust check skipped in CI"
    elif [[ "${DOT_TEST_INSTALLED_CODEX:-0}" != "1" ]]; then
      # The config merge behavior above is deterministic; this probe exercises the
      # user's installed Codex binary, which may depend on host-specific wrappers,
      # downloads, or cache permissions. Keep base dotfiles tests hermetic unless
      # someone explicitly opts into that integration check.
      _pass "codex hook: installed Codex trust check skipped (set DOT_TEST_INSTALLED_CODEX=1)"
    elif command -v codex >/dev/null 2>&1; then
      _CODEX_TEST_DOTSLASH_CACHE="${DOTSLASH_CACHE:-}"
      if [[ -z "$_CODEX_TEST_DOTSLASH_CACHE" && "$(uname -s)" == "Darwin" && "$HOME" != "$REAL_HOME" ]]; then
        _CODEX_TEST_DOTSLASH_CACHE="$REAL_HOME/Library/Caches/dotslash"
      fi

      _codex_check_status=0
      CODEX_HOME="$CODEX_DIR" CODEX_TEST_DOTSLASH_CACHE="$_CODEX_TEST_DOTSLASH_CACHE" python3 - "$CODEX_CONFIG" <<'PY' || _codex_check_status=$?
import json
import os
import pathlib
import select
import subprocess
import sys
import time
import tomllib

config_path = pathlib.Path(sys.argv[1])
with config_path.open("rb") as f:
    config = tomllib.load(f)
state = config["hooks"]["state"]

env = os.environ.copy()
env["CODEX_HOME"] = str(config_path.parent)
if env.get("CODEX_TEST_DOTSLASH_CACHE"):
    env.setdefault("DOTSLASH_CACHE", env["CODEX_TEST_DOTSLASH_CACHE"])
proc = subprocess.Popen(
    ["codex", "app-server", "--listen", "stdio://"],
    cwd=str(config_path.parent),
    env=env,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
for message in [
    {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {"clientInfo": {"name": "dot-core-test", "title": None, "version": "0"}},
    },
    {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "hooks/list",
        "params": {"cwds": [str(config_path.parent.parent)]},
    },
]:
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()

result = None
stderr = []
deadline = time.time() + 8
while time.time() < deadline:
    ready, _, _ = select.select([proc.stdout, proc.stderr], [], [], 0.2)
    for stream in ready:
        line = stream.readline()
        if not line:
            continue
        if stream is proc.stderr:
            stderr.append(line.rstrip())
            continue
        payload = json.loads(line)
        if payload.get("id") == 2:
            result = payload
            deadline = time.time()
            break

proc.terminate()
try:
    proc.wait(timeout=2)
except subprocess.TimeoutExpired:
    proc.kill()

if result is None:
    if any(
        "sandbox-exec: sandbox_apply: Operation not permitted" in line
        or "failed to create CAS artifact directory" in line
        for line in stderr
    ):
        print(
            "codex app-server trust check skipped: host Codex wrapper is unavailable",
            file=sys.stderr,
        )
        sys.exit(77)
    raise AssertionError("codex hooks/list did not return; stderr=" + "\n".join(stderr))

entry = result["result"]["data"][0]
assert entry["warnings"] == [], entry["warnings"]
assert entry["errors"] == [], entry["errors"]
generated_hooks = [
    hook for hook in entry["hooks"]
    if pathlib.Path(hook.get("sourcePath", "")).resolve() == config_path.resolve()
]
assert generated_hooks, entry["hooks"]
for hook in generated_hooks:
    assert hook["key"] in state, hook
    if "trustStatus" in hook:
        assert hook["trustStatus"] == "trusted", hook
    if "currentHash" in hook:
        assert state[hook["key"]]["trusted_hash"] == hook["currentHash"], hook
PY
      if [[ "$_codex_check_status" -eq 0 ]]; then
        _pass "codex hook: installed Codex reports generated hooks trusted"
      elif [[ "$_codex_check_status" -eq 77 ]]; then
        _pass "codex hook: installed Codex trust check skipped (macOS sandbox unavailable)"
      else
        _fail "codex hook: installed Codex reports generated hooks trusted"
      fi
    else
      _pass "codex hook: installed Codex trust check skipped (codex unavailable)"
    fi

    # Bootstrap: no existing config.toml
    rm -f "$CODEX_CONFIG"
    _run_codex_merge 2>/dev/null
    if [[ -s "$CODEX_CONFIG" ]] && python3 -c "
import pathlib, sys, tomllib
with open(sys.argv[1], 'rb') as f: data = tomllib.load(f)
assert data['model'] == 'common-model'
assert data['features']['hooks'] is True
assert data['projects']['/work/project']['trust_level'] == 'trusted'
key = str(pathlib.Path(sys.argv[1]).resolve()) + ':pre_tool_use:0:0'
assert data['hooks']['state'][key]['trusted_hash'].startswith('sha256:')
" "$CODEX_CONFIG" 2>/dev/null; then
      _pass "codex hook: bootstrap from scratch (no existing config) with trusted hooks"
    else
      _fail "codex hook: bootstrap from scratch (no existing config) with trusted hooks"
    fi

    # Corrupt config recovery
    printf 'this is [[[not valid toml' >"$CODEX_CONFIG"
    _run_codex_merge 2>/dev/null
    if [[ -s "$CODEX_CONFIG" ]] && python3 -c "
import sys, tomllib
with open(sys.argv[1], 'rb') as f: tomllib.load(f)
" "$CODEX_CONFIG" 2>/dev/null; then
      _pass "codex hook: recovers from corrupt config"
    else
      _fail "codex hook: recovers from corrupt config"
    fi

    rm -rf "$CODEX_DIR"
    rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/codex"
  else
    echo "  SKIP: Codex merge hook assertions (mikefarah/yq unavailable)"
  fi

  # ---------------------------------------------------------------------------
  # Tests: hive-memory merge hook
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Hive Memory merge hook ==="

  _HIVE_HOOK="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/hive-memory.sh"
  _HIVE_BIN=$(_mock_bin)
  _HIVE_LOG=$(_tmpdir)/hm.log

  cat >"$_HIVE_BIN/hm" <<'HM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HIVE_MEMORY_HM_LOG"
if [[ "${1:-}" == "--config" ]]; then
  shift 2
fi
case "$1 $2" in
  "stores init")
    root=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --root)
          shift
          root=$1
          ;;
      esac
      shift || break
    done
    mkdir -p "$root"
    printf '%s\n' 'schema_version = 1' >"$root/manifest.toml"
    ;;
  "stores list")
    exit "${HIVE_MEMORY_STORES_LIST_RC:-0}"
    ;;
esac
HM
  chmod +x "$_HIVE_BIN/hm"

  _run_hive_merge() {
    local old_path="$PATH" rc
    unset -f merge _hive_memory_config _hive_memory_default_store_spec \
      _hive_memory_cloud_root_for \
      _hive_memory_warn _hive_memory_init_default_store \
      _hive_memory_check_config _hive_memory_remove_legacy_core hm 2>/dev/null
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    # shellcheck disable=SC2329 # merge resolves this fixture through command lookup.
    hm() {
      "$_HIVE_BIN/hm" "$@"
    }
    export HIVE_MEMORY_HM_LOG="$_HIVE_LOG"
    export HIVE_MEMORY_STORES_LIST_RC="${HIVE_MEMORY_STORES_LIST_RC:-}"
    export PATH="$_HIVE_BIN:$PATH"
    hash -r
    merge >/dev/null
    rc=$?
    export PATH="$old_path"
    hash -r
    unset -f hm
    return "$rc"
  }

  _write_hive_personal_config() {
    local config="${1:-$TEST_HOME/.config/hive-memory/config.toml}"
    mkdir -p "$(dirname "$config")"
    cat >"$config" <<'TOML'
default_store = "personal"

[stores.personal]
root = "${HOME}/gdrive/hive-memory/personal"
description = "Personal memory"
sensitivity = "private"
TOML
  }

  _HIVE_LEGACY_HOME=$(_tmpdir)
  mkdir -p "$_HIVE_LEGACY_HOME/.local/share/hive-memory/bin" \
    "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory" \
    "$_HIVE_LEGACY_HOME/.local/bin"
  printf 'old copied binary\n' >"$_HIVE_LEGACY_HOME/.local/share/hive-memory/bin/hm-core"
  printf 'unrelated state\n' >"$_HIVE_LEGACY_HOME/.local/share/hive-memory/keep"
  cat >"$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm" <<'HM'
#!/usr/bin/env bash
printf 'hm 1.0.0\n'
HM
  cat >"$_HIVE_LEGACY_HOME/.local/bin/hm" <<'HM'
#!/usr/bin/env bash
# Dotfiles-owned front door for the generic `hm` binary.
exec "$HOME/.local/share/cgraf78/hive-memory/hm" "$@"
HM
  chmod +x "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm" \
    "$_HIVE_LEGACY_HOME/.local/bin/hm"
  (
    HOME="$_HIVE_LEGACY_HOME"
    export HOME
    _run_hive_merge
  ) >/dev/null 2>&1
  _assert_file_exists "hive hook migration: unproven shdeps keeps legacy fallback" \
    "$_HIVE_LEGACY_HOME/.local/share/hive-memory/bin/hm-core"
  mv "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm" \
    "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm.real"
  ln -s "$_HIVE_LEGACY_HOME/.local/share/hive-memory/bin/hm-core" \
    "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm"
  (
    HOME="$_HIVE_LEGACY_HOME"
    DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION=1
    export HOME DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION
    _run_hive_merge
  ) >/dev/null 2>&1
  _assert_file_exists "hive hook migration: stable core symlink cannot authorize deletion" \
    "$_HIVE_LEGACY_HOME/.local/share/hive-memory/bin/hm-core"
  rm "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm"
  mv "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm.real" \
    "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm"
  (
    HOME="$_HIVE_LEGACY_HOME"
    DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION=1
    export HOME DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION
    _run_hive_merge
  ) >/dev/null 2>&1
  _assert_file_missing "hive hook migration: removes obsolete copied core binary" \
    "$_HIVE_LEGACY_HOME/.local/share/hive-memory/bin/hm-core"
  _assert_file_exists "hive hook migration: preserves unrelated Hive state" \
    "$_HIVE_LEGACY_HOME/.local/share/hive-memory/keep"

  _HIVE_SYMLINK_HOME=$(_tmpdir)
  mkdir -p "$_HIVE_SYMLINK_HOME/.local/share/hive-memory/bin" \
    "$_HIVE_SYMLINK_HOME/.local/share/cgraf78/hive-memory" \
    "$_HIVE_SYMLINK_HOME/.local/lib/dot/hive-memory" \
    "$_HIVE_SYMLINK_HOME/.local/bin"
  printf 'old copied binary\n' >"$_HIVE_SYMLINK_HOME/.local/share/hive-memory/bin/hm-core"
  cp "$_HIVE_LEGACY_HOME/.local/share/cgraf78/hive-memory/hm" \
    "$_HIVE_SYMLINK_HOME/.local/share/cgraf78/hive-memory/hm"
  cp "$_HIVE_LEGACY_HOME/.local/bin/hm" \
    "$_HIVE_SYMLINK_HOME/.local/lib/dot/hive-memory/hm-launcher"
  ln -s ../lib/dot/hive-memory/hm-launcher "$_HIVE_SYMLINK_HOME/.local/bin/hm"
  (
    HOME="$_HIVE_SYMLINK_HOME"
    DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION=1
    export HOME DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION
    _run_hive_merge
  ) >/dev/null 2>&1
  _assert_file_exists "hive hook migration: old symlink launcher cannot authorize deletion" \
    "$_HIVE_SYMLINK_HOME/.local/share/hive-memory/bin/hm-core"

  _HIVE_FAILED_HOME=$(_tmpdir)
  mkdir -p "$_HIVE_FAILED_HOME/.local/share/hive-memory/bin"
  printf 'last working core\n' >"$_HIVE_FAILED_HOME/.local/share/hive-memory/bin/hm-core"
  (
    HOME="$_HIVE_FAILED_HOME"
    DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION=1
    export HOME DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION
    _run_hive_merge
  ) >/dev/null 2>&1
  _assert_file_exists "hive hook migration: failed dependency refresh keeps legacy core" \
    "$_HIVE_FAILED_HOME/.local/share/hive-memory/bin/hm-core"

  _HIVE_EMPTY_LEGACY_HOME=$(_tmpdir)
  mkdir -p "$_HIVE_EMPTY_LEGACY_HOME/.local/share/hive-memory/bin"
  (
    HOME="$_HIVE_EMPTY_LEGACY_HOME"
    export HOME
    _run_hive_merge
  ) >/dev/null 2>&1
  if [[ -d "$_HIVE_EMPTY_LEGACY_HOME/.local/share/hive-memory/bin" ]]; then
    _pass "hive hook migration: absent owned core leaves empty namespace alone"
  else
    _fail "hive hook migration: absent owned core leaves empty namespace alone"
  fi

  _hive_default_config=$(
    unset HIVE_MEMORY_CONFIG XDG_CONFIG_HOME
    HOME="$TEST_HOME"
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    _hive_memory_config || exit $?
    printf '%s' "$REPLY"
  )
  _assert_eq "hive hook config: unset XDG uses HOME fallback" \
    "$TEST_HOME/.config/hive-memory/config.toml" "$_hive_default_config"

  _hive_empty_xdg_config=$(
    unset HIVE_MEMORY_CONFIG
    HOME="$TEST_HOME"
    XDG_CONFIG_HOME=""
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    _hive_memory_config
    printf '%s' "$REPLY"
  )
  _assert_eq "hive hook config: empty XDG uses HOME fallback" \
    "$TEST_HOME/.config/hive-memory/config.toml" "$_hive_empty_xdg_config"

  _hive_relative_xdg_config=$(
    unset HIVE_MEMORY_CONFIG
    HOME="$TEST_HOME"
    XDG_CONFIG_HOME="relative/config"
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    _hive_memory_config
    printf '%s' "$REPLY"
  )
  _assert_eq "hive hook config: relative XDG uses HOME fallback" \
    "$TEST_HOME/.config/hive-memory/config.toml" "$_hive_relative_xdg_config"

  _hive_absolute_xdg_config=$(
    unset HIVE_MEMORY_CONFIG HOME
    XDG_CONFIG_HOME="/var/lib/example-config"
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    _hive_memory_config
    printf '%s' "$REPLY"
  )
  _assert_eq "hive hook config: absolute XDG works without HOME" \
    "/var/lib/example-config/hive-memory/config.toml" "$_hive_absolute_xdg_config"

  _hive_missing_root_rc=0
  _hive_missing_root_config=$(
    unset HIVE_MEMORY_CONFIG XDG_CONFIG_HOME HOME
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    _hive_memory_config || exit $?
    printf '%s' "$REPLY"
  ) || _hive_missing_root_rc=$?
  _assert_eq "hive hook config: missing XDG and HOME fails closed" \
    "1" "$_hive_missing_root_rc"
  _assert_eq "hive hook config: missing roots do not invent a path" \
    "" "$_hive_missing_root_config"

  _hive_explicit_config=$(
    HOME="$TEST_HOME"
    HIVE_MEMORY_CONFIG="relative/explicit.toml"
    XDG_CONFIG_HOME="/var/lib/example-config"
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    _hive_memory_config
    printf '%s' "$REPLY"
  )
  _assert_eq "hive hook config: explicit override wins unchanged" \
    "relative/explicit.toml" "$_hive_explicit_config"

  _hive_empty_explicit_config=$(
    # shellcheck disable=SC2030 # This fixture is intentionally subshell-local.
    HOME="$TEST_HOME"
    HIVE_MEMORY_CONFIG=""
    # shellcheck disable=SC2030 # This fixture is intentionally subshell-local.
    XDG_CONFIG_HOME="/var/lib/example-config"
    export HOME HIVE_MEMORY_CONFIG XDG_CONFIG_HOME
    # shellcheck source=/dev/null
    . "$_HIVE_HOOK"
    _hive_memory_config
    printf '%s' "$REPLY"
  )
  _assert_eq "hive hook config: empty explicit override still wins" \
    "" "$_hive_empty_explicit_config"

  unset HIVE_MEMORY_CONFIG XDG_CONFIG_HOME
  mkdir -p "$TEST_HOME/.config/hive-memory" "$TEST_HOME/gdrive"
  _write_hive_personal_config
  : >"$_HIVE_LOG"
  _run_hive_merge 2>/dev/null
  _assert_file_exists "hive hook: initializes configured default store" \
    "$TEST_HOME/gdrive/hive-memory/personal/manifest.toml"
  _assert_contains "hive hook: checks managed config cheaply" \
    "--config $TEST_HOME/.config/hive-memory/config.toml stores list --json" \
    "$(cat "$_HIVE_LOG")"
  _assert_not_contains "hive hook: skips update-time doctor" \
    "doctor --quick" "$(cat "$_HIVE_LOG")"

  _HIVE_XDG_CONFIG=$(_tmpdir)/config
  _HIVE_XDG_STORE=$(_tmpdir)/store
  mkdir -p "$_HIVE_XDG_CONFIG/hive-memory"
  cat >"$_HIVE_XDG_CONFIG/hive-memory/config.toml" <<TOML
default_store = "xdg"

[stores.xdg]
  root = "$_HIVE_XDG_STORE"
TOML
  : >"$_HIVE_LOG"
  _hive_xdg_no_home_rc=0
  _hive_xdg_no_home_output=$(
    set -u
    unset HIVE_MEMORY_CONFIG HOME
    # shellcheck disable=SC2031 # The earlier fixture assignment cannot escape its subshell.
    export XDG_CONFIG_HOME="$_HIVE_XDG_CONFIG"
    _run_hive_merge
  ) 2>&1 || _hive_xdg_no_home_rc=$?
  _assert_eq "hive hook: absolute XDG merge works without HOME under nounset" \
    "0" "$_hive_xdg_no_home_rc"
  _assert_eq "hive hook: HOME-less XDG merge emits no path diagnostic" \
    "" "$_hive_xdg_no_home_output"
  _assert_file_exists "hive hook: absolute XDG config initializes its store" \
    "$_HIVE_XDG_STORE/manifest.toml"
  _assert_contains "hive hook: absolute XDG config drives initialization" \
    "stores init xdg --root $_HIVE_XDG_STORE" "$(cat "$_HIVE_LOG")"
  _assert_contains "hive hook: validates the selected XDG config" \
    "--config $_HIVE_XDG_CONFIG/hive-memory/config.toml stores list --json" \
    "$(cat "$_HIVE_LOG")"

  _HIVE_NEWLINE_CONFIG=$(_tmpdir)/config$'\n'
  _HIVE_NEWLINE_STORE=$(_tmpdir)/newline-store
  mkdir -p "$(dirname "$_HIVE_NEWLINE_CONFIG")"
  cat >"$_HIVE_NEWLINE_CONFIG" <<TOML
default_store = "newline"

[stores.newline]
root = "$_HIVE_NEWLINE_STORE"
TOML
  : >"$_HIVE_LOG"
  HIVE_MEMORY_CONFIG="$_HIVE_NEWLINE_CONFIG" _run_hive_merge 2>/dev/null
  _assert_file_exists "hive hook: explicit config preserves trailing newline bytes" \
    "$_HIVE_NEWLINE_STORE/manifest.toml"
  _assert_file_exists "hive hook: explicit newline config remains at the exact path" \
    "$_HIVE_NEWLINE_CONFIG"

  : >"$_HIVE_LOG"
  _run_hive_merge 2>/dev/null
  _init_count=$(grep -c '^stores init personal' "$_HIVE_LOG" || true)
  _assert_eq "hive hook: existing manifest skips init" "0" "$_init_count"
  _assert_contains "hive hook: existing manifest still checks config" \
    "--config $TEST_HOME/.config/hive-memory/config.toml stores list --json" \
    "$(cat "$_HIVE_LOG")"

  rm -rf "$TEST_HOME/.config/hive-memory" "$TEST_HOME/gdrive"

  mkdir -p "$TEST_HOME/.config/hive-memory"
  _write_hive_personal_config
  : >"$_HIVE_LOG"
  _hive_missing_cloud_output=$(_run_hive_merge 2>&1)
  _assert_contains "hive hook: missing cloud root warns during update" \
    "cloud root not available" "$_hive_missing_cloud_output"
  _assert_contains "hive hook: missing cloud root still checks config" \
    "--config $TEST_HOME/.config/hive-memory/config.toml stores list --json" \
    "$(cat "$_HIVE_LOG")"

  mkdir -p "$TEST_HOME/gdrive"
  : >"$_HIVE_LOG"
  export HIVE_MEMORY_STORES_LIST_RC=7
  _hive_config_fail_output=$(_run_hive_merge 2>&1)
  unset HIVE_MEMORY_STORES_LIST_RC
  _assert_contains "hive hook: config check failure warns" \
    "config check reported issues" "$_hive_config_fail_output"
  _assert_not_contains "hive hook: config failure does not run doctor" \
    "doctor --quick" "$(cat "$_HIVE_LOG")"

  rm -rf "$TEST_HOME/.config/hive-memory" "$TEST_HOME/gdrive"

  mkdir -p "$TEST_HOME/.config/hive-memory"
  cat >"$TEST_HOME/.config/hive-memory/config.toml" <<'TOML'
default_store = "local"

[stores.local]
root = "${HOME}/.local/share/hive-memory/local"
description = "Local memory"
sensitivity = "private"
TOML
  : >"$_HIVE_LOG"
  _hive_local_output=$(_run_hive_merge 2>&1)
  _assert_not_contains "hive hook: local root does not require gdrive" \
    "cloud root not available" "$_hive_local_output"
  _assert_file_exists "hive hook: local root initializes without cloud root" \
    "$TEST_HOME/.local/share/hive-memory/local/manifest.toml"

  rm -rf "$TEST_HOME/.config/hive-memory" "$TEST_HOME/gdrive"

  mkdir -p "$TEST_HOME/.config/hive-memory"
  cat >"$TEST_HOME/.config/hive-memory/config.toml" <<'TOML'
default_store = "local"

[stores.local]
root = "${HOME}/.local/share/hive-memory/sensitivity-only"
sensitivity = "private"
TOML
  : >"$_HIVE_LOG"
  _run_hive_merge 2>/dev/null
  _hive_sensitivity_args=$(cat "$_HIVE_LOG")
  _assert_contains "hive hook: omitted description preserves sensitivity flag" \
    "--sensitivity private" "$_hive_sensitivity_args"
  _assert_not_contains "hive hook: sensitivity is not shifted into description" \
    "--description private" "$_hive_sensitivity_args"

  rm -rf "$TEST_HOME/.config/hive-memory" "$TEST_HOME/.local/share/hive-memory"

  echo "=== Mise merge hook ==="
  _MISE_HOOK="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/mise.sh"
  mise_home=$(_tmpdir)
  mise_bin=$(_mock_bin)
  mise_log=$mise_home/mise.log
  mkdir -p "$mise_home/.config/mise"
  cat >"$mise_bin/mise" <<'MISE'
#!/usr/bin/env bash
printf 'token=%s args=%s\n' "${MISE_GITHUB_TOKEN:-}" "$*" >>"$MISE_TEST_LOG"
[[ "${MISE_FAIL_INSTALL:-0}" != 1 || "$1" != install ]]
MISE
  cat >"$mise_bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MISE_GH_LOG"
printf '%s\n' gh-token
GH
  chmod +x "$mise_bin/mise" "$mise_bin/gh"
  mise_gh_log=$mise_home/gh.log
  _run_mise_merge() (
    local interactive=${1:-0}
    unset -f merge 2>/dev/null
    . "$_MISE_HOOK"
    # shellcheck disable=SC2329 # The sourced hook invokes this override.
    _mise_interactive() { [[ $interactive -eq 1 ]]; }
    merge
  )
  unset MISE_GITHUB_TOKEN GITHUB_TOKEN DOT_TEST_GH
  : >"$mise_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  PREFIX=/data/data/com.termux/files/usr HOME="$mise_home" PATH="$mise_bin:$PATH" \
    MISE_TEST_LOG="$mise_log" _run_mise_merge
  _assert_file_content 'Mise merge: Android skips unsupported release tooling' '' "$mise_log"

  : >"$mise_log"
  rm -f "$mise_home/.config/mise/config.toml"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  HOME="$mise_home" PATH="$mise_bin:$PATH" MISE_TEST_LOG="$mise_log" _run_mise_merge
  _assert_file_content 'Mise merge: absent config is a no-op' '' "$mise_log"

  printf '[tools]\n' >"$mise_home/.config/mise/config.toml"
  : >"$mise_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  HOME="$mise_home" PATH="$mise_bin:$PATH" MISE_TEST_LOG="$mise_log" \
    GITHUB_TOKEN=actions-token _run_mise_merge
  _assert_contains 'Mise merge: trusts the tracked config' \
    'args=trust ' "$(<"$mise_log")"
  _assert_contains 'Mise merge: installs only the lockfile graph' \
    'token=actions-token args=install --locked' "$(<"$mise_log")"
  _assert_contains 'Mise merge: prunes the retired SuperHTML provider after success' \
    'args=prune --tools --yes ubi:kristoff-it/superhtml' "$(<"$mise_log")"

  : >"$mise_log"
  rm -f "$mise_gh_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  HOME="$mise_home" PATH="$mise_bin:$PATH" MISE_TEST_LOG="$mise_log" \
    MISE_GH_LOG="$mise_gh_log" MISE_GITHUB_TOKEN=existing-token \
    GITHUB_TOKEN=actions-token _run_mise_merge
  _assert_contains 'Mise merge: preserves an existing dedicated token' \
    'token=existing-token args=install --locked' "$(<"$mise_log")"
  _assert_file_missing 'Mise merge: an existing token skips gh' "$mise_gh_log"

  : >"$mise_log"
  rm -f "$mise_gh_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  HOME="$mise_home" PATH="$mise_bin:$PATH" MISE_TEST_LOG="$mise_log" \
    MISE_GH_LOG="$mise_gh_log" GITHUB_TOKEN=actions-token _run_mise_merge
  _assert_contains 'Mise merge: GitHub Actions token feeds Mise' \
    'token=actions-token args=install --locked' "$(<"$mise_log")"
  _assert_file_missing 'Mise merge: GitHub Actions token skips gh' "$mise_gh_log"

  : >"$mise_log"
  rm -f "$mise_gh_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  interactive_output=$(HOME="$mise_home" PATH="$mise_bin:$PATH" \
    MISE_TEST_LOG="$mise_log" MISE_GH_LOG="$mise_gh_log" \
    _run_mise_merge 1 2>&1 || true)
  _assert_contains 'Mise merge: interactive tests require an explicit gh double' \
    'test gh' "$interactive_output"
  _assert_file_missing 'Mise merge: missing interactive double cannot reach gh' \
    "$mise_gh_log"

  : >"$mise_log"
  rm -f "$mise_gh_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  interactive_output=$(DOT_TEST=0 HOME="$mise_home" PATH="$mise_bin:$PATH" \
    MISE_TEST_LOG="$mise_log" MISE_GH_LOG="$mise_gh_log" \
    _run_mise_merge 1 2>&1 || true)
  _assert_contains 'Mise merge: interactive non-account HOME is rejected' \
    "HOME is not the account home: $mise_home" "$interactive_output"
  _assert_file_missing 'Mise merge: non-account HOME cannot reach gh' "$mise_gh_log"

  : >"$mise_log"
  rm -f "$mise_gh_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  HOME="$mise_home" PATH="$mise_bin:$PATH" MISE_TEST_LOG="$mise_log" \
    MISE_GH_LOG="$mise_gh_log" DOT_TEST_GH="$mise_bin/gh" \
    _run_mise_merge 1
  _assert_file_content 'Mise merge: explicit interactive gh double is invoked' \
    'auth token' "$mise_gh_log"
  _assert_contains 'Mise merge: interactive gh token feeds Mise' \
    'token=gh-token args=install --locked' "$(<"$mise_log")"

  : >"$mise_log"
  # shellcheck disable=SC2031 # PATH assignments below are command-scoped fixtures.
  HOME="$mise_home" PATH="$mise_bin:$PATH" MISE_TEST_LOG="$mise_log" \
    MISE_FAIL_INSTALL=1 _run_mise_merge || true
  _assert_not_contains 'Mise merge: failed install does not prune tool state' \
    'args=prune' "$(<"$mise_log")"

  unset -f _run_mise_merge _mise_interactive merge 2>/dev/null
  _test_summary
}
