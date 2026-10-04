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

  check_absent() {
    local description=$1 path=$2
    if [[ ! -e $root/$path ]]; then
      printf 'PASS: %s\n' "$description"
      pass=$((pass + 1))
    else
      printf 'FAIL: %s (%s still exists)\n' "$description" "$path" >&2
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
  check_contains 'development Nvim extras use the ordered capability extension' \
    .config/nvim/lua/dotfiles/lazyvim_extras/dev.lua lazyvim.plugins.extras.dap.core
  check_contains 'development Nvim overrides use the ordered capability extension' \
    .config/nvim/lua/dotfiles/plugin_overrides/dev-tools.lua neovim/nvim-lspconfig
  check_contains 'workspace policy uses the ordered capability extension' \
    .config/nvim/lua/dotfiles/plugin_overrides/workspace-dev.lua opts_for_path
  check_contains 'Mason policy uses the final policy extension' \
    .config/nvim/lua/dotfiles/final_policy/mason.lua apply_lsp_policy
  check_absent 'filename-ordered dev overrides are retired' \
    .config/nvim/lua/plugins/zz-dev-extras.lua
  check_absent 'filename-ordered Mason policy is retired' \
    .config/nvim/lua/plugins/zz-mason-policy.lua
  check_absent 'filename-ordered workspace policy is retired' \
    .config/nvim/lua/plugins/workspace-dev.lua
  check_contains 'Lazygit docs use the native Termnav editor command' \
    .config/lazygit/README.md 'termnav nvim open'
  check_not_contains 'Lazygit docs retire the compatibility launcher name' \
    .config/lazygit/README.md 'nvim-tmux-open'
  check_contains 'VS Code shell alias remains dev-owned' .config/shell/interactive.d/70-dev-aliases.sh "alias vs='code'"
  check_contains 'Claude wrapper keeps explicit unsafe-mode policy' .config/shell/interactive.d/70-dev-aliases.sh dangerously-skip-permissions
  check_contains 'Codex wrapper keeps explicit unsafe-mode policy' .config/shell/interactive.d/70-dev-aliases.sh dangerously-bypass-approvals-and-sandbox
  check_contains 'OpenCode interactive wrapper keeps automatic mode' .config/shell/interactive.d/70-dev-aliases.sh 'opencode --auto'
  # shellcheck disable=SC2016 # The assertion intentionally matches literal shell source.
  check_contains 'Muse exec policy keeps automatic mode' .config/shell/interactive.d/70-dev-aliases.sh 'command muse "$muse_cmd" --yolo'
  check_not_contains 'Checkrun schema payloads remain schema-validatable' .config/checkrun/ignore '*/.local/share/checkrun/schemas/*.schema.json'
  check_contains 'Checkrun schema payloads skip formatting only' .config/checkrun/format-ignore '*/.local/share/checkrun/schemas/*.schema.json'
  check_contains 'Checkrun schema payloads skip spelling only' .config/checkrun/spell-ignore '*/.local/share/checkrun/schemas/*.schema.json'
  check_file 'Grok Hive Memory skill is overlay-owned' \
    .grok/skills/hive-memory-attach/SKILL.md
  check_contains 'Grok Hive Memory skill declares its name' \
    .grok/skills/hive-memory-attach/SKILL.md 'name: hive-memory-attach'
  check_contains 'gstack roster includes Grok' \
    .config/dot/merge-hooks.d/gstack/README.md Grok
  check_contains 'gstack roster includes Muse' \
    .config/dot/merge-hooks.d/gstack/README.md Muse

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

  # Converted exports go through base's _shell_env_set. Without it (a base
  # checkout that predates the helper) they stay plain exports; with a stub
  # of its fill-only contract (keep any set value) a caller's values survive.
  mkdir -p "$shell_fixture/.bun/bin"
  # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
  owned_probe='. "$1"; . "$2"; printf "%s|%s|%s|%s\n" "$BUN_INSTALL" "$LG_CONFIG_FILE" "$GITHOOK_PRECOMMIT_STRICT_LINT" "$DS_DEV_CHATBOT"'
  # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
  fill_stub='_shell_env_set() { eval "[ -n \"\${$1+x}\" ]" || export "$1=$2"; }; '
  for owned_sh in bash zsh; do
    command -v "$owned_sh" >/dev/null 2>&1 || continue
    owned_output=$(env -i HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
      GITHOOK_PRECOMMIT_STRICT_LINT=0 \
      "$owned_sh" -c "$owned_probe" \
      _ "$root/.config/shell/env.d/70-dev.sh" "$root/.config/shell/env.d/80-dev-environment.sh")
    check_equal "Dev defaults are plain exports without the base helper ($owned_sh)" \
      "$shell_fixture/.bun|$shell_fixture/.config/lazygit/config.yml|1|claude" "$owned_output"
    owned_output=$(env -i HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
      GITHOOK_PRECOMMIT_STRICT_LINT=0 LG_CONFIG_FILE=/caller/lg.yml DS_DEV_CHATBOT=caller \
      BUN_INSTALL=/caller/bun \
      "$owned_sh" -c "$fill_stub$owned_probe" \
      _ "$root/.config/shell/env.d/70-dev.sh" "$root/.config/shell/env.d/80-dev-environment.sh")
    check_equal "Fill-only load keeps caller dev values ($owned_sh)" \
      "/caller/bun|/caller/lg.yml|0|caller" "$owned_output"
    owned_output=$(env -i HOME="$shell_fixture" PATH="$shell_bin:/usr/bin:/bin" \
      "$owned_sh" -c "$fill_stub$owned_probe" \
      _ "$root/.config/shell/env.d/70-dev.sh" "$root/.config/shell/env.d/80-dev-environment.sh")
    check_equal "Fill-only load fills missing dev values ($owned_sh)" \
      "$shell_fixture/.bun|$shell_fixture/.config/lazygit/config.yml|1|claude" "$owned_output"
  done

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

  # The fragments live under the merge-hook family directory. An empty glob
  # must fail: a moved directory would otherwise make this check vacuous.
  if python3 - "$root/.config/dot/merge-hooks.d/claude/settings.d" <<'PY'
import json
import pathlib
import sys

invalid = []
fragments = sorted(pathlib.Path(sys.argv[1]).glob("*.json"))
if not fragments:
    raise SystemExit(f"{sys.argv[1]}: no Claude settings fragments")
for path in fragments:
    data = json.loads(path.read_text(encoding="utf-8"))
    for rule in data.get("permissions", {}).get("allow", []):
        if isinstance(rule, str) and rule.endswith("(*)"):
            invalid.append(f"{path.name}:{rule}")
if invalid:
    raise SystemExit("\n".join(invalid))
PY
  then
    printf 'PASS: Claude permission allow rules use the supported schema spelling\n'
    pass=$((pass + 1))
  else
    printf 'FAIL: Claude permission allow rules use the supported schema spelling\n' >&2
    fail=$((fail + 1))
  fi

  # AgentGuard owns native lifecycle vocabulary and adapter behavior; this
  # overlay keeps only user policy plus the generic machinery that installs
  # those assets. The negative contract keeps a future hook tweak from quietly
  # recreating a second, drifting integration copy here. It moved with the
  # agent payloads from the base repository, where it had stopped finding its
  # inputs. Any interpreter failure, including a missing input, fails the row.
  if python3 - "$root" <<'PY'
import json
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
errors = []

config_root = root / ".config/dot/merge-hooks.d"
# The base repository's profile-ownership-policy.tsv owns which merge-hook
# namespaces belong to this overlay; keep this list in step with its rows.
owned_dirs = [config_root / name for name in ("claude", "codex", "gemini", "muse", "opencode")]
for directory in owned_dirs:
    for path in directory.rglob("*"):
        if not path.is_file() or path.name == "README.md":
            continue
        text = path.read_text(encoding="utf-8")
        if "agent-hook-" in text or "AGENTGUARD_NAME=" in text:
            errors.append(f"{path.relative_to(root)}: contains provider-owned integration code")

for agent in ("claude", "muse"):
    policy = config_root / agent / "settings.d/20-permissions.json"
    if not policy.is_file():
        errors.append(f"{policy.relative_to(root)}: missing local permission policy")
        continue
    with policy.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if "permissions" not in data or "hooks" in data:
        errors.append(f"{policy.relative_to(root)}: must contain permissions without hooks")

codex_config = config_root / "codex/config.d/10-settings.toml"
codex_data = {}
if codex_config.is_file():
    with codex_config.open("rb") as f:
        codex_data = tomllib.load(f)
else:
    errors.append(f"{codex_config.relative_to(root)}: missing shared Codex settings")
if codex_data.get("features", {}).get("hooks") is not None or "hooks" in codex_data:
    errors.append(f"{codex_config.relative_to(root)}: contains provider-owned hook config")

# Bare Codex follows each machine's local model state. Deliberate model policy
# belongs only in explicitly selected Codex profiles, not the shared layer.
base_model_policy = {
    "model",
    "model_provider",
    "model_reasoning_effort",
    "model_reasoning_summary",
    "model_verbosity",
    "service_tier",
}
managed_model_policy = sorted(base_model_policy.intersection(codex_data))
if managed_model_policy:
    errors.append(
        f"{codex_config.relative_to(root)}: contains shared model policy: "
        + ", ".join(managed_model_policy)
    )

if list((config_root / "gemini/settings.d").glob("*.json")):
    errors.append("gemini/settings.d: local JSON integration fragment remains")

opencode_adapter = config_root / "opencode/agentguard.js"
if opencode_adapter.exists():
    errors.append(f"{opencode_adapter.relative_to(root)}: provider adapter remains in dotfiles")

if errors:
    raise SystemExit("\n".join(errors))
PY
  then
    printf 'PASS: agent integrations keep policy, not provider adapters\n'
    pass=$((pass + 1))
  else
    printf 'FAIL: agent integrations keep policy, not provider adapters\n' >&2
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
