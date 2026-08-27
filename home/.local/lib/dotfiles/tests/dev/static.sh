# shellcheck shell=bash

# shellcheck source=helpers.sh
. "${BASH_SOURCE[0]%/*}/helpers.sh"

dot_dev_static_test() {
  local owner_root root pass=0 fail=0

  owner_root=$(_dev_repo_root)
  root=$owner_root/home

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

  check_not_contains() {
    local description=$1 path=$2 pattern=$3
    if [[ -f $root/$path ]] && ! grep -F "$pattern" "$root/$path" >/dev/null; then
      printf 'PASS: %s\n' "$description"
      pass=$((pass + 1))
    else
      printf 'FAIL: %s (%s unexpectedly contains %s)\n' \
        "$description" "$path" "$pattern" >&2
      fail=$((fail + 1))
    fi
  }

  check_equal() {
    local description=$1 expected=$2 actual=$3
    if [[ $actual == "$expected" ]]; then
      printf 'PASS: %s\n' "$description"
      pass=$((pass + 1))
    else
      printf 'FAIL: %s (expected %q, got %q)\n' \
        "$description" "$expected" "$actual" >&2
      fail=$((fail + 1))
    fi
  }

  check_file 'global Git configuration is dev-owned' .config/git/config
  check_contains 'advanced Git tooling is selected' .config/shdeps/30-dev.conf cgraf78/git-tools
  check_contains 'development checks are selected' .config/shdeps/30-dev.conf cgraf78/checkrun
  check_contains 'development Nvim plugins are additive' .config/nvim/lua/plugins/git-dev.lua diffview.nvim
  check_contains 'development Nvim extras load after editor policy' .config/nvim/lua/plugins/zz-dev-extras.lua lazyvim.plugins.extras.dap.core
  check_contains 'VS Code shell alias remains dev-owned' .config/shell/interactive.d/70-dev-aliases.sh "alias vs='code'"
  check_contains 'Claude wrapper keeps explicit unsafe-mode policy' .config/shell/interactive.d/70-dev-aliases.sh dangerously-skip-permissions
  check_contains 'Codex wrapper keeps explicit unsafe-mode policy' .config/shell/interactive.d/70-dev-aliases.sh dangerously-bypass-approvals-and-sandbox
  check_contains 'OpenCode interactive wrapper keeps automatic mode' .config/shell/interactive.d/70-dev-aliases.sh 'opencode --auto'
  # shellcheck disable=SC2016 # The assertion intentionally matches literal shell source.
  check_contains 'Muse exec policy keeps automatic mode' .config/shell/interactive.d/70-dev-aliases.sh 'command muse "$muse_cmd" --yolo'
  check_not_contains 'Checkrun schema payloads remain schema-validatable' .config/checkrun/ignore '*/.local/share/checkrun/schemas/*.schema.json'
  check_contains 'Checkrun schema payloads skip formatting only' .config/checkrun/format-ignore '*/.local/share/checkrun/schemas/*.schema.json'
  check_contains 'Checkrun schema payloads skip spelling only' .config/checkrun/spell-ignore '*/.local/share/checkrun/schemas/*.schema.json'

  shell_fixture=$(_tmpdir)
  shell_bin=$shell_fixture/.local/bin
  mkdir -p "$shell_bin" "$shell_fixture/.config/gh" "$shell_fixture/.dotfiles"
  cat >"$shell_bin/git" <<'SH'
#!/bin/sh
if [ "${1:-}" = rev-parse ] && [ "${2:-}" = --absolute-git-dir ]; then
  printf '%s\n' "$GIT_MOCK_ABSOLUTE_DIR"
  exit 0
fi
exit 1
SH
  cat >"$shell_bin/lazygit" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"$LAZYGIT_LOG"
SH
  cat >"$shell_bin/sley" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "$shell_bin/git" "$shell_bin/lazygit" "$shell_bin/sley"
  printf '%s\n' shell-gh-token >"$shell_fixture/.config/gh/github-pat"
  chmod 600 "$shell_fixture/.config/gh/github-pat"

  lazygit_log=$(_tmpdir)/lazygit.log
  HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
    GIT_MOCK_ABSOLUTE_DIR="$shell_fixture/.dotfiles" LAZYGIT_LOG="$lazygit_log" \
    bash -c '. "$1"; lg log' _ "$root/.config/shell/interactive.d/70-dev-aliases.sh"
  check_equal 'Lazygit wrapper passes explicit base-dotfiles context' \
    "--git-dir=$shell_fixture/.dotfiles --work-tree=$shell_fixture log" \
    "$(<"$lazygit_log")"
  HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
    GIT_MOCK_ABSOLUTE_DIR="$shell_fixture/git/project/.git" LAZYGIT_LOG="$lazygit_log" \
    bash -c '. "$1"; lg log' _ "$root/.config/shell/interactive.d/70-dev-aliases.sh"
  check_equal 'Lazygit wrapper leaves normal repositories unmodified' log \
    "$(<"$lazygit_log")"

  alias_probe=$(bash -c '. "$1"; alias gl >/dev/null 2>&1; printf "gl=%s\n" "$?"; alias dl >/dev/null 2>&1; printf "dl=%s\n" "$?"; alias dll >/dev/null 2>&1; printf "dll=%s\n" "$?"' \
    _ "$root/.config/shell/interactive.d/70-dev-aliases.sh")
  check_contains_value() {
    local description=$1 pattern=$2 value=$3
    if [[ $value == *"$pattern"* ]]; then
      printf 'PASS: %s\n' "$description"
      pass=$((pass + 1))
    else
      printf 'FAIL: %s (missing %s)\n' "$description" "$pattern" >&2
      fail=$((fail + 1))
    fi
  }
  check_contains_value 'Git log alias remains available' 'gl=0' "$alias_probe"
  check_contains_value 'Retired dl alias stays absent' 'dl=1' "$alias_probe"
  check_contains_value 'Retired dll alias stays absent' 'dll=1' "$alias_probe"

  # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
  env_output=$(env -i HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
    bash -c '. "$1"; . "$2"; printf "gh=%s\ngithub=%s\ncodex=%s\nsley=%s\noverride=%s\n" "$GH_TOKEN" "$GITHUB_PERSONAL_ACCESS_TOKEN" "$CODEX_GITHUB_PERSONAL_ACCESS_TOKEN" "$(command -v sley)" "$OPENCODE_DISABLE_CLAUDE_CODE_SKILLS"' \
    _ "$root/.config/shell/env.d/70-dev.sh" "$root/.config/shell/env.d/80-dev-environment.sh")
  check_contains_value 'Noninteractive Bash exports the GitHub token' \
    'gh=shell-gh-token' "$env_output"
  check_contains_value 'Noninteractive Bash propagates the GitHub token' \
    'github=shell-gh-token' "$env_output"
  check_contains_value 'Noninteractive Bash propagates the Codex token' \
    'codex=shell-gh-token' "$env_output"
  check_contains_value 'Noninteractive Bash resolves Sley from local bin' \
    "sley=$shell_bin/sley" "$env_output"

  # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
  override_output=$(env -i HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
    GH_TOKEN=explicit-gh GITHUB_PERSONAL_ACCESS_TOKEN=explicit-github \
    CODEX_GITHUB_PERSONAL_ACCESS_TOKEN=explicit-codex \
    OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=0 \
    bash -c '. "$1"; . "$2"; printf "%s|%s|%s|%s\n" "$GH_TOKEN" "$GITHUB_PERSONAL_ACCESS_TOKEN" "$CODEX_GITHUB_PERSONAL_ACCESS_TOKEN" "$OPENCODE_DISABLE_CLAUDE_CODE_SKILLS"' \
    _ "$root/.config/shell/env.d/70-dev.sh" "$root/.config/shell/env.d/80-dev-environment.sh")
  check_equal 'Explicit dev environment overrides survive Bash loading' \
    'explicit-gh|explicit-github|explicit-codex|0' "$override_output"

  if command -v zsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
    zsh_output=$(env -i HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
      zsh -c '. "$1"; . "$2"; printf "gh=%s\nsley=%s\n" "$GH_TOKEN" "$(command -v sley)"' \
      _ "$root/.config/shell/env.d/70-dev.sh" "$root/.config/shell/env.d/80-dev-environment.sh")
    check_contains_value 'Noninteractive Zsh exports the GitHub token' \
      'gh=shell-gh-token' "$zsh_output"
    check_contains_value 'Noninteractive Zsh resolves Sley from local bin' \
      "sley=$shell_bin/sley" "$zsh_output"
  fi
  check_contains 'Deployed Selene policy preserves unused-variable warnings' .config/checkrun/selene.toml 'unused_variable = "warn"'
  check_not_contains 'Deployed Selene policy is not weakened for repository fixtures' .config/checkrun/selene.toml 'unused_variable = "allow"'
  if [[ $(<"$owner_root/.selene.toml") == *'unused_variable = "allow"'* &&
  $(<"$owner_root/.selene.toml") == *'global_usage = "allow"'* ]]; then
    printf 'PASS: repository-only Selene exceptions stay outside deployed policy\n'
    pass=$((pass + 1))
  else
    printf 'FAIL: repository-only Selene exceptions stay outside deployed policy\n' >&2
    fail=$((fail + 1))
  fi

  if python3 - "$root/.config/claude/settings.d" <<'PY'; then
import json
import pathlib
import sys

invalid = []
for path in pathlib.Path(sys.argv[1]).glob("*.json"):
    data = json.loads(path.read_text(encoding="utf-8"))
    for rule in data.get("permissions", {}).get("allow", []):
        if isinstance(rule, str) and rule.endswith("(*)"):
            invalid.append(f"{path.name}:{rule}")
if invalid:
    raise SystemExit("\n".join(invalid))
PY
    printf 'PASS: Claude permission allow rules use the supported schema spelling\n'
    pass=$((pass + 1))
  else
    printf 'FAIL: Claude permission allow rules use the supported schema spelling\n' >&2
    fail=$((fail + 1))
  fi

  if grep -F 'tmux' "$root/.config/mise/config.toml" "$root/.config/mise/mise.lock" \
    "$root/.local/lib/dotfiles/merge-hooks.d/mise.sh" >/dev/null; then
    printf 'FAIL: base-owned tmux remains in the dev Mise boundary\n' >&2
    fail=$((fail + 1))
  else
    printf 'PASS: base-owned tmux is absent from the dev Mise boundary\n'
    pass=$((pass + 1))
  fi

  if [[ -e $root/.config/agent-rules ||
    -e $root/.local/lib/dotfiles/agent-rules-sync.sh ]] ||
    grep -F 'cgraf78/agent-rules-sync' "$root/.config/shdeps/30-dev.conf" >/dev/null 2>&1; then
    printf 'FAIL: base agent rules or agent-rules-sync leaked into dev\n' >&2
    fail=$((fail + 1))
  else
    printf 'PASS: base agent rules and agent-rules-sync remain absent\n'
    pass=$((pass + 1))
  fi

  "${DOT_TEST_REPORTER:?}" complete "$pass" "$fail"
  ((fail == 0))
}
