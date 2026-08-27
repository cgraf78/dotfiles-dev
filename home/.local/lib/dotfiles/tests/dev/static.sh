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
