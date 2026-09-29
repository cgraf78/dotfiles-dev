# shellcheck shell=bash
# Development merge-hook behavior split from the frozen monolith.

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"

dot_dev_merges_test() {
  _dev_merges_setup || return

  echo "=== Agent CLI merge hook gates ==="

  agent_gate_home="$TEST_HOME/agent-cli-gate-home"
  agent_gate_empty_path="$TEST_HOME/agent-cli-gate-empty-path"
  agent_gate_marker="$agent_gate_home/downstream-reached"
  mkdir -p "$agent_gate_home" "$agent_gate_empty_path"

  _run_agent_cli_gate_for_test() (
    local agent="$1" cli_present="$2"

    unset -f merge codex claude gemini grok opencode muse 2>/dev/null
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/$agent.sh"
    case "$agent" in
      codex)
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced hook.
        dot_codex_config_merge() { : >"$agent_gate_marker"; }
        ;;
      claude | gemini | grok | muse)
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

  for agent in codex claude gemini grok opencode muse; do
    case "$agent" in
      codex) agent_gate_target="$agent_gate_home/.codex/config.toml" ;;
      claude) agent_gate_target="$agent_gate_home/.claude/settings.json" ;;
      gemini) agent_gate_target="$agent_gate_home/.gemini/settings.json" ;;
      grok) agent_gate_target="$agent_gate_home/.grok/hooks/agentguard.json" ;;
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
    "$agentguard_fixture/grok" \
    "$agentguard_fixture/muse"

  # These fixtures intentionally use made-up events and commands. This suite
  # owns the consumer contract: dotfiles passes the live and incoming documents
  # to provider-owned reconciliation, commits its result atomically, and then
  # applies local policy. AgentGuard's own suite owns the real command-ownership
  # predicate and per-agent vocabulary.
  for json_agent in claude gemini grok muse; do
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

  for json_agent in claude gemini grok muse; do
    case "$json_agent" in
      claude) json_target="$json_agent_home/.claude/settings.json" ;;
      gemini) json_target="$json_agent_home/.gemini/settings.json" ;;
      grok) json_target="$json_agent_home/.grok/hooks/agentguard.json" ;;
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
    "$agentguard_fixture/grok/hooks.json" \
    "$agentguard_fixture/muse/hooks.json"
  for json_agent in claude gemini grok muse; do
    case "$json_agent" in
      claude) json_target="$json_agent_home/.claude/settings.json" ;;
      gemini) json_target="$json_agent_home/.gemini/settings.json" ;;
      grok) json_target="$json_agent_home/.grok/hooks/agentguard.json" ;;
      muse) json_target="$json_agent_home/.config/muse/settings.json" ;;
    esac
    if [[ "$json_agent" != "gemini" && "$json_agent" != "grok" ]]; then
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
    "provider-claude-v2|provider-gemini-v2|provider-grok-v2|provider-muse-v2" \
    "$(
      jq -r '.hooks.ProviderEvent[0].hooks[0].command' \
        "$json_agent_home/.claude/settings.json" \
        "$json_agent_home/.gemini/settings.json" \
        "$json_agent_home/.grok/hooks/agentguard.json" \
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
browser:
http_unix_socket:
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
    _assert_not_contains "gh merge: removes null browser defaults" \
      '"browser"' "$gh_output"
    _assert_not_contains "gh merge: removes null Unix-socket defaults" \
      '"http_unix_socket"' "$gh_output"
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
  rm -rf "$TEST_HOME/.local/state/dot/overlays/dev"
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
  claude_self_heal_output=$(_run_claude_merge 2>&1)
  claude_self_heal_status=$?
  _assert_exit "claude hook: duplicate self-heal merge succeeds" \
    0 "$claude_self_heal_status"
  [[ $claude_self_heal_status -eq 0 ]] || printf '%s\n' "$claude_self_heal_output"
  claude_ups_count=$(jq '.hooks.UserPromptSubmit | length' "$CLAUDE_SETTINGS")
  _assert_eq "claude hook: an already-duplicated settings.json self-heals to one copy" \
    "1" "$claude_ups_count"

  # Genuinely distinct groups for the same event (different matcher) must both
  # survive — dedup is by identity, not a blunt "collapse everything" pass.
  rm -rf "$TEST_HOME/.local/state/dot/overlays/dev"
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
  rm -rf "$TEST_HOME/.local/state/dot/overlays/dev"
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

  echo "=== Grok config merge hook ==="

  grok_config_home="$TEST_HOME/grok-config-merge-home"
  grok_config_dst="$grok_config_home/.grok/config.toml"
  grok_config_user_hooks="$grok_config_home/.grok/hooks/user.json"
  grok_config_native_hooks="$grok_config_home/.grok/hooks/agentguard.json"
  grok_config_native_rules="$grok_config_home/.grok/rules/agent-rules.md"
  grok_config_family="$grok_config_home/.config/dot/merge-hooks.d/grok-config/config.d"
  mkdir -p \
    "$grok_config_family" \
    "$grok_config_home/.grok/hooks" \
    "$grok_config_home/.grok/rules"
  cp "$REAL_HOME/.config/dot/merge-hooks.d/grok-config/config.d/"*.toml \
    "$grok_config_family/"
  grok_hive_skill="$REAL_HOME/.grok/skills/hive-memory-attach/SKILL.md"
  grok_hive_name=""
  [[ -f $grok_hive_skill ]] &&
    grok_hive_name=$(sed -n 's/^name: //p' "$grok_hive_skill" | head -n 1)
  _assert_eq "Grok Hive Memory skill is tracked in the overlay home" \
    "hive-memory-attach" "$grok_hive_name"

  _grok_config_seed_toml() {
    cat >"$grok_config_dst" <<'TOML'
[cli]
installer = "internal"

[marketplace]
default_skills_installs_purged = true

[[marketplace.sources]]
name = "xAI Official"
git = "https://example.test/marketplace.git"

[ui]
permission_mode = "always-approve"

[compat.claude]
hooks = true
skills = true
TOML
  }

  _grok_config_probe() {
    python3 - "$grok_config_dst" <<'PY'
import sys, tomllib
from pathlib import Path
data = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
claude = data.get("compat", {}).get("claude", {})
sources = data["marketplace"]["sources"]
disabled = data.get("plugins", {}).get("disabled", [])
deny = data.get("permission", {}).get("deny", [])
status_line = data.get("ui", {}).get("status_line", {})
skill_disabled = data.get("skills", {}).get("disabled", [])
print(
    "|".join(
        [
            str(claude.get("hooks", "<unset>")).lower(),
            str(claude.get("rules", "<unset>")).lower(),
            str(claude.get("agents", "<unset>")).lower(),
            str(claude.get("skills", "<unset>")).lower(),
            str(claude.get("mcps", "<unset>")).lower(),
            data["ui"]["permission_mode"],
            sources[0]["name"],
            "security-guidance"
            if "security-guidance" in disabled
            else "<no-plugin-disable>",
            data.get("sandbox", {}).get("profile", "<unset>"),
            "Bash(rm -rf *)" if "Bash(rm -rf *)" in deny else "<no-rm-deny>",
            status_line.get("type", "<unset>"),
            ",".join(status_line.get("items", [])),
            "gstack-autoplan"
            if "gstack-autoplan" in skill_disabled
            else "<no-autoplan>",
            "keep-investigate"
            if "gstack-investigate" not in skill_disabled
            else "<investigate-disabled>",
        ]
    )
)
PY
  }

  _run_grok_config_merge() (
    unset -f merge 2>/dev/null
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/grok-config.sh"
    HOME="$grok_config_home" merge
  )

  grok_config_gate_output=$(
    # shellcheck disable=SC2329 # Invoked by the sourced merge hook.
    _dot_tool_present() { return 1; }
    export -f _dot_tool_present
    printf '{"keep":true}\n' >"$grok_config_user_hooks"
    printf 'theme="dark"\n' >"$grok_config_dst"
    _run_grok_config_merge 2>&1
  )
  grok_config_gate_status=$?
  _assert_exit "Grok config merge: absent grok is a successful no-op" \
    0 "$grok_config_gate_status"
  _assert_eq "Grok config merge: absent grok emits no output" \
    "" "$grok_config_gate_output"
  _assert_eq "Grok config merge: absent grok preserves config.toml" \
    'theme="dark"' "$(cat "$grok_config_dst")"

  grok_yq_bin=$(_merge_hook_mikefarah_yq 2>/dev/null || true)
  if [[ -n $grok_yq_bin ]]; then
    _grok_config_seed_toml
    printf '{"keep":true}\n' >"$grok_config_user_hooks"
    grok_config_output=$(_run_grok_config_merge 2>&1)
    grok_config_status=$?
    _assert_exit "Grok config merge: no native targets is a successful skip" \
      0 "$grok_config_status"
    _assert_eq "Grok config merge: no native targets leaves mcps unset" \
      "true|<unset>|<unset>|true|<unset>|always-approve|xAI Official|<no-plugin-disable>|workspace|Bash(rm -rf *)|builtin|cwd,model,context,session-name|<no-autoplan>|keep-investigate" \
      "$(_grok_config_probe)"
    grok_config_deny=$(
      python3 - "$grok_config_dst" <<'PY'
import sys, tomllib
from pathlib import Path
data = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print("\n".join(data.get("permission", {}).get("deny", [])))
PY
    )
    _assert_contains "Grok config merge: denies ~/.ssh credential reads" \
      "Read(~/.ssh/**)" "$grok_config_deny"
    _assert_not_contains "Grok config merge: deny rules do not embed a home path" \
      "/home/" "$grok_config_deny"

    printf '{"hooks":{}}\n' >"$grok_config_native_hooks"
    grok_config_output=$(_run_grok_config_merge 2>&1)
    grok_config_status=$?
    _assert_exit "Grok config merge: native hooks only refreshes config.toml" \
      0 "$grok_config_status"
    _assert_contains "Grok config merge: logs the Grok config layer" \
      "Grok config" "$grok_config_output"
    _assert_eq "Grok config merge: native hooks only disables hooks; mcps stay unset" \
      "false|<unset>|<unset>|true|<unset>|always-approve|xAI Official|<no-plugin-disable>|workspace|Bash(rm -rf *)|builtin|cwd,model,context,session-name|<no-autoplan>|keep-investigate" \
      "$(_grok_config_probe)"

    _grok_config_seed_toml
    rm -f "$grok_config_native_hooks"
    printf '# grok rules\n' >"$grok_config_native_rules"
    _run_grok_config_merge >/dev/null
    _assert_eq "Grok config merge: native rules only disables rules/agents" \
      "true|false|false|true|<unset>|always-approve|xAI Official|<no-plugin-disable>|workspace|Bash(rm -rf *)|builtin|cwd,model,context,session-name|<no-autoplan>|keep-investigate" \
      "$(_grok_config_probe)"

    _grok_config_seed_toml
    printf '{"hooks":{}}\n' >"$grok_config_native_hooks"
    printf '{"keep":true}\n' >"$grok_config_user_hooks"
    grok_config_hooks_hash=$(sha256sum "$grok_config_user_hooks" | awk '{print $1}')
    _run_grok_config_merge >/dev/null
    _assert_eq "Grok config merge: both native targets disable Claude-compat cells" \
      "false|false|false|true|<unset>|always-approve|xAI Official|<no-plugin-disable>|workspace|Bash(rm -rf *)|builtin|cwd,model,context,session-name|<no-autoplan>|keep-investigate" \
      "$(_grok_config_probe)"
    grok_config_hooks_after=$(sha256sum "$grok_config_user_hooks" | awk '{print $1}')
    _assert_eq "Grok config merge: leaves sibling ~/.grok/hooks/user.json unchanged" \
      "$grok_config_hooks_hash" "$grok_config_hooks_after"

    grok_config_again_status=0
    _run_grok_config_merge >/dev/null || grok_config_again_status=$?
    _assert_exit "Grok config merge: second run is idempotent" \
      0 "$grok_config_again_status"
    _assert_eq "Grok config merge: second run keeps the same Claude-compat cells" \
      "false|false|false|true|<unset>|always-approve|xAI Official|<no-plugin-disable>|workspace|Bash(rm -rf *)|builtin|cwd,model,context,session-name|<no-autoplan>|keep-investigate" \
      "$(_grok_config_probe)"

    _grok_config_seed_toml
    rm -f "$grok_config_native_hooks" "$grok_config_native_rules"
    cat >"$grok_config_family/99-gated.toml" <<'TOML'
[compat.claude]
hooks = false

[relay]
enabled = true
TOML
    _run_grok_config_merge >/dev/null
    grok_config_relay=$(
      python3 - "$grok_config_dst" <<'PY'
import sys, tomllib
from pathlib import Path
data = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(str(data.get("relay", {}).get("enabled", "<unset>")).lower())
PY
    )
    _assert_eq "Grok config merge: ungated tables survive empty compat.claude" \
      "true" "$grok_config_relay"
    _assert_eq "Grok config merge: gated-empty compat.claude leaves user hooks" \
      "true|<unset>|<unset>|true|<unset>|always-approve|xAI Official|<no-plugin-disable>|workspace|Bash(rm -rf *)|builtin|cwd,model,context,session-name|<no-autoplan>|keep-investigate" \
      "$(_grok_config_probe)"
    rm -f "$grok_config_family/99-gated.toml"

    # Native hooks make the gated layer non-empty so dest is parsed. With
    # no ungated tables, an empty gated layer would skip without seeing
    # the corrupt file.
    printf '{"hooks":{}}\n' >"$grok_config_native_hooks"
    printf 'not toml {' >"$grok_config_dst"
    grok_config_corrupt_output=$(_run_grok_config_merge 2>&1)
    grok_config_corrupt_status=$?
    _assert_exit "Grok config merge: preserves a corrupt destination" \
      1 "$grok_config_corrupt_status"
    _assert_contains "Grok config merge: reports a corrupt destination" \
      "corrupt" "$grok_config_corrupt_output"
    _assert_eq "Grok config merge: corrupt destination bytes are unchanged" \
      "not toml {" "$(cat "$grok_config_dst")"
  else
    echo "SKIP: Grok config merge tests require mikefarah yq"
  fi
  unset -f _run_grok_config_merge _grok_config_seed_toml _grok_config_probe merge 2>/dev/null

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
  "stores show")
    [[ "${HIVE_MEMORY_STORES_SHOW_RC:-0}" == 0 ]] || exit "$HIVE_MEMORY_STORES_SHOW_RC"
    if [[ -n ${HIVE_MEMORY_STORES_SHOW_JSON:-} ]]; then
      printf '%s\n' "$HIVE_MEMORY_STORES_SHOW_JSON"
    else
      printf '{}\n'
    fi
    ;;
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
    unset -f merge _hive_memory_config _hive_memory_effective_store_spec \
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
    export HIVE_MEMORY_STORES_SHOW_RC="${HIVE_MEMORY_STORES_SHOW_RC:-}"
    export HIVE_MEMORY_STORES_SHOW_JSON="${HIVE_MEMORY_STORES_SHOW_JSON:-}"
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

  _hive_show_json() {
    local name="$1" root="$2" description="$3" sensitivity="$4" available="$5"
    printf '{"name":"%s","config":{"root":"%s","expected_id":null,"description":"%s","sensitivity":"%s"},"manifest":null,"available":%s,"effective_agent_policy":null}' \
      "$name" "$root" "$description" "$sensitivity" "$available"
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
  export HIVE_MEMORY_STORES_SHOW_JSON
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json personal \
    "$TEST_HOME/gdrive/hive-memory/personal" "Personal memory" private false)
  : >"$_HIVE_LOG"
  _run_hive_merge 2>/dev/null
  _assert_file_exists "hive hook: initializes configured default store" \
    "$TEST_HOME/gdrive/hive-memory/personal/manifest.toml"
  _assert_contains "hive hook: checks managed config cheaply" \
    "--config $TEST_HOME/.config/hive-memory/config.toml stores list --json" \
    "$(cat "$_HIVE_LOG")"
  _assert_not_contains "hive hook: skips update-time doctor" \
    "doctor --quick" "$(cat "$_HIVE_LOG")"

  rm -rf "$TEST_HOME/gdrive/hive-memory/personal"
  cat >"$TEST_HOME/.config/hive-memory/config.local.toml" <<'TOML'
[stores.personal]
root = "${HOME}/gdrive/hive-memory/personal"
TOML
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json personal \
    "$TEST_HOME/gdrive/hive-memory/personal" "Personal memory" private false)
  : >"$_HIVE_LOG"
  _run_hive_merge 2>/dev/null
  _assert_file_exists "hive hook: initializes effective layered store root" \
    "$TEST_HOME/gdrive/hive-memory/personal/manifest.toml"
  _assert_contains "hive hook: asks Hive for effective layered store config" \
    "--config $TEST_HOME/.config/hive-memory/config.toml stores show --json" \
    "$(cat "$_HIVE_LOG")"

  _HIVE_LITERAL_ROOT="$TEST_HOME/provider-\$HOME"
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json personal \
    "$_HIVE_LITERAL_ROOT" "Personal memory" private false)
  : >"$_HIVE_LOG"
  _run_hive_merge 2>/dev/null
  _assert_contains "hive hook: preserves provider-resolved root bytes" \
    "stores init personal --root $_HIVE_LITERAL_ROOT" "$(cat "$_HIVE_LOG")"

  rm -rf "$TEST_HOME/gdrive/hive-memory/personal"
  export HIVE_MEMORY_STORES_SHOW_RC=7
  : >"$_HIVE_LOG"
  _hive_invalid_layer_output=$(_run_hive_merge 2>&1)
  unset HIVE_MEMORY_STORES_SHOW_RC
  _assert_contains "hive hook: invalid layered config warns without initializing" \
    "effective config unavailable" "$_hive_invalid_layer_output"
  _assert_not_contains "hive hook: invalid layered config skips store init" \
    "stores init" "$(cat "$_HIVE_LOG")"
  unset HIVE_MEMORY_STORES_SHOW_JSON

  _HIVE_XDG_CONFIG=$(_tmpdir)/config
  _HIVE_XDG_STORE=$(_tmpdir)/store
  mkdir -p "$_HIVE_XDG_CONFIG/hive-memory"
  cat >"$_HIVE_XDG_CONFIG/hive-memory/config.toml" <<TOML
default_store = "xdg"

[stores.xdg]
  root = "$_HIVE_XDG_STORE"
TOML
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json xdg \
    "$_HIVE_XDG_STORE" "" private false)
  export HIVE_MEMORY_STORES_SHOW_JSON
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
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json newline \
    "$_HIVE_NEWLINE_STORE" "" private false)
  export HIVE_MEMORY_STORES_SHOW_JSON
  : >"$_HIVE_LOG"
  HIVE_MEMORY_CONFIG="$_HIVE_NEWLINE_CONFIG" _run_hive_merge 2>/dev/null
  _assert_file_exists "hive hook: explicit config preserves trailing newline bytes" \
    "$_HIVE_NEWLINE_STORE/manifest.toml"
  _assert_file_exists "hive hook: explicit newline config remains at the exact path" \
    "$_HIVE_NEWLINE_CONFIG"

  : >"$_HIVE_LOG"
  _run_hive_merge 2>/dev/null
  _init_count=$(grep -c 'stores init personal' "$_HIVE_LOG" || true)
  _assert_eq "hive hook: existing manifest skips init" "0" "$_init_count"
  _assert_contains "hive hook: existing manifest still checks config" \
    "--config $TEST_HOME/.config/hive-memory/config.toml stores list --json" \
    "$(cat "$_HIVE_LOG")"

  rm -rf "$TEST_HOME/.config/hive-memory" "$TEST_HOME/gdrive"

  mkdir -p "$TEST_HOME/.config/hive-memory"
  _write_hive_personal_config
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json personal \
    "$TEST_HOME/gdrive/hive-memory/personal" "Personal memory" private false)
  export HIVE_MEMORY_STORES_SHOW_JSON
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
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json local \
    "$TEST_HOME/.local/share/hive-memory/local" "Local memory" private false)
  export HIVE_MEMORY_STORES_SHOW_JSON
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
  HIVE_MEMORY_STORES_SHOW_JSON=$(_hive_show_json local \
    "$TEST_HOME/.local/share/hive-memory/sensitivity-only" "" private false)
  export HIVE_MEMORY_STORES_SHOW_JSON
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
