# shellcheck shell=bash

# shellcheck source=helpers.sh
. "${BASH_SOURCE[0]%/*}/helpers.sh"

dot_dev_launchers_test() {
  local owner_root root path
  local -a required=(
    .local/bin/hm
    .local/lib/dotfiles/git-hooks/pre-commit
    .local/lib/dotfiles/git-hooks/commit-msg
    .local/lib/dotfiles/sley-hooks/validate-commit-msg
  )

  owner_root=$(_dev_repo_root)
  root=$owner_root/home
  BIN_DIR=$root/.local/bin

  for path in "${required[@]}"; do
    _assert_file_exists "dev launcher is installed: $path" "$root/$path"
    if [[ -x $root/$path ]]; then
      _pass "dev launcher is executable: $path"
    else
      _fail "dev launcher is executable: $path"
    fi
  done

  _assert_file_missing 'base agent rules remain outside dev' \
    "$root/.config/agent-rules"
  _assert_file_missing 'base agent-rules-sync implementation remains outside dev' \
    "$root/.local/lib/dotfiles/agent-rules-sync.sh"
  echo "=== hm launcher ==="

  HM_LAUNCHER_HOME=$(_tmpdir)
  HM_LAUNCHER_BIN="$HM_LAUNCHER_HOME/.local/bin"
  mkdir -p "$HM_LAUNCHER_BIN" "$HM_LAUNCHER_HOME/.local/lib/dotfiles"
  cp "$BIN_DIR/hm" "$HM_LAUNCHER_BIN/hm"
  cat >"$HM_LAUNCHER_HOME/.local/lib/dotfiles/shdeps-assets.sh" <<'MOCK'
dot_shdeps_dep_source() {
  local provider
  provider=$(shdeps dep-file "$1" "$2") || return
  # shellcheck source=/dev/null
  . "$provider"
}
MOCK
  HM_LAUNCHER_REAL="$HM_LAUNCHER_HOME/.local/share/cgraf78/hive-memory/hm"
  mkdir -p "${HM_LAUNCHER_REAL%/*}"
  cat >"$HM_LAUNCHER_REAL" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == env-probe ]]; then
  printf 'agent=%s\n' "${HIVE_MEMORY_AGENT_ID:-}"
  printf 'session=%s\n' "${HIVE_MEMORY_SESSION_ID:-}"
  printf 'project=%s\n' "${HIVE_MEMORY_PROJECT:-}"
else
  printf 'real:%s\n' "$*"
fi
MOCK
  chmod +x "$HM_LAUNCHER_REAL"

  # The launcher consumes AgentGuard as a required provider. Keep the fixture
  # opaque so this suite tests only dotfiles' Hive mapping; AgentGuard's own
  # suite owns runtime-specific detection and session precedence.
  HM_AGENTGUARD_API=$(_tmpdir)/agentguard.sh
  cat >"$HM_AGENTGUARD_API" <<'MOCK'
agentguard_agent_name() {
  printf '%s\n' "${HM_TEST_AGENT:-unknown}"
}

agentguard_session_id() {
  if [[ -n "${HM_TEST_SESSION:-}" ]]; then
    printf '%s\n' "$HM_TEST_SESSION"
  elif [[ -n "${1:-}" ]]; then
    printf 'fallback:%s\n' "$1"
  else
    return 1
  fi
}
MOCK
  HM_AGENTGUARD_BIN=$(_mock_bin)
  cat >"$HM_AGENTGUARD_BIN/shdeps" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == dep-file && "$2" == cgraf78/agentguard && \
  "$3" == lib/agentguard/agentguard.sh ]]; then
  printf '%s\n' "$HM_AGENTGUARD_API"
  exit 0
fi
exit 1
MOCK
  chmod +x "$HM_AGENTGUARD_BIN/shdeps"

  # Clear ambient runtime identity for every probe so the assertions describe
  # only the environment each case supplies, regardless of which agent runs
  # dot test. Later env operands intentionally override this baseline.
  HM_LAUNCHER_SCRUB_ENV=(
    GEMINI_PROJECT_DIR=
    HM_AGENTGUARD_API="$HM_AGENTGUARD_API"
    HM_TEST_AGENT=unknown
    HM_TEST_SESSION=
    HIVE_MEMORY_AGENT_ID=
    HIVE_MEMORY_PROJECT_INFER=
    HIVE_MEMORY_SESSION_ID=
    HIVE_MEMORY_PROJECT=
    PATH="$HM_AGENTGUARD_BIN:$PATH"
  )

  result=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" HOME="$HM_LAUNCHER_HOME" \
    "$HM_LAUNCHER_BIN/hm" recall --limit 2)
  _assert_eq "hm launcher: delegates to stable Shdeps archive path" \
    "real:recall --limit 2" "$result"

  _hm_plain_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" "$HM_LAUNCHER_BIN/hm" env-probe)
  _assert_eq "hm launcher: leaves human agent unset" \
    "agent=" "$(printf '%s\n' "$_hm_plain_probe" | grep '^agent=')"
  _assert_eq "hm launcher: leaves human session unset" \
    "session=" "$(printf '%s\n' "$_hm_plain_probe" | grep '^session=')"
  _assert_eq "hm launcher: leaves human project unset" \
    "project=" "$(printf '%s\n' "$_hm_plain_probe" | grep '^project=')"

  _hm_provider_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT="provider-agent" \
    HM_TEST_SESSION="provider-session" "$HM_LAUNCHER_BIN/hm" env-probe)
  _assert_contains "hm launcher: consumes AgentGuard agent identity" \
    "agent=provider-agent" "$_hm_provider_probe"
  _assert_contains "hm launcher: consumes AgentGuard session identity" \
    "session=provider-session" "$_hm_provider_probe"
  _assert_contains "hm launcher: maps agent calls to the current project" \
    "project=$(pwd)" "$_hm_provider_probe"

  _hm_gemini_project="$HM_LAUNCHER_HOME/gemini-project"
  _hm_gemini_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT=gemini \
    HM_TEST_SESSION="gemini-session" \
    GEMINI_PROJECT_DIR="$_hm_gemini_project" "$HM_LAUNCHER_BIN/hm" env-probe)
  _assert_contains "hm launcher: uses Gemini's precise project hint" \
    "project=$_hm_gemini_project" "$_hm_gemini_probe"

  _hm_explicit_only_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HIVE_MEMORY_AGENT_ID="custom-agent" \
    "$HM_LAUNCHER_BIN/hm" env-probe)
  _assert_contains "hm launcher: preserves an explicit Hive agent" \
    "agent=custom-agent" "$_hm_explicit_only_probe"
  _assert_contains "hm launcher: gives AgentGuard the Hive fallback namespace" \
    "session=fallback:custom-agent" "$_hm_explicit_only_probe"

  _hm_explicit_context_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT="provider-agent" \
    HM_TEST_SESSION="provider-session" \
    HIVE_MEMORY_SESSION_ID="hive-session" \
    HIVE_MEMORY_PROJECT="/explicit/project" \
    "$HM_LAUNCHER_BIN/hm" env-probe)
  _assert_contains "hm launcher: preserves explicit Hive session" \
    "session=hive-session" "$_hm_explicit_context_probe"
  _assert_contains "hm launcher: preserves explicit Hive project" \
    "project=/explicit/project" "$_hm_explicit_context_probe"

  _hm_no_project_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT="provider-agent" \
    HM_TEST_SESSION="provider-session" HIVE_MEMORY_PROJECT_INFER=0 \
    "$HM_LAUNCHER_BIN/hm" env-probe)
  _assert_eq "hm launcher: keeps project unset when inference is disabled" \
    "project=" "$(printf '%s\n' "$_hm_no_project_probe" | grep '^project=')"

  _hm_missing_output=""
  _hm_missing_rc=0
  mv "$HM_LAUNCHER_REAL" "$HM_LAUNCHER_REAL.saved"
  _hm_missing_output=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" "$HM_LAUNCHER_BIN/hm" --version 2>&1) || _hm_missing_rc=$?
  mv "$HM_LAUNCHER_REAL.saved" "$HM_LAUNCHER_REAL"
  _assert_eq "hm launcher: missing core exits like a missing command" \
    "127" "$_hm_missing_rc"
  _assert_contains "hm launcher: missing core names the rejected path" \
    "$HM_LAUNCHER_REAL" "$_hm_missing_output"

  HM_MISSING_PROVIDER_BIN=$(_mock_bin)
  cat >"$HM_MISSING_PROVIDER_BIN/shdeps" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
  chmod +x "$HM_MISSING_PROVIDER_BIN/shdeps"
  _hm_provider_missing_rc=0
  _hm_provider_missing_output=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" PATH="$HM_MISSING_PROVIDER_BIN:$PATH" \
    "$HM_LAUNCHER_BIN/hm" --version 2>&1) || _hm_provider_missing_rc=$?
  _assert_eq "hm launcher: missing AgentGuard is a broken installation" \
    "127" "$_hm_provider_missing_rc"
  _assert_contains "hm launcher: missing AgentGuard suggests repair" \
    "run dot update" "$_hm_provider_missing_output"

  # ---------------------------------------------------------------------------
  # Tests: Sley consumer policy
  # ---------------------------------------------------------------------------

}
