# Grok Config Merge Hook

This directory declares the `grok-config` merge-hook instance. The executable
hook at `~/.local/lib/dotfiles/merge-hooks.d/grok-config.sh` merges TOML layers
from `config.d/` into `~/.grok/config.toml`.

The fragment is local policy, not a Grok runtime adapter. It turns off the
Claude-compat cells that would otherwise duplicate first-class Grok hooks
and home rules after those native targets exist:

- `compat.claude.hooks` — `~/.claude/settings.json` AgentGuard. Plugin
  hooks are a separate source; `compat.claude.hooks = false` does not
  stop them.
- `compat.claude.rules` — `~/.claude/rules/` and project `.claude/rules/`
- `compat.claude.agents` — `~/.claude/CLAUDE.md` and project `.claude/CLAUDE*.md`

Grok defaults every Claude-compat cell to `true` when the section is absent.
The layer sets hooks/rules/agents. `skills`, `mcps`, and `sessions` stay unset
so those cells keep Grok's defaults, and any user-owned value stays in place.

The layer does not set `[plugins] disabled`. Plugin hooks still load when
`compat.claude.hooks` is false, but none of the currently loaded plugin
Stop hooks keep a Grok turn alive on every completion: hookify and
ralph-loop `decision:block` only when a rule or loop is active, and
security-guidance's Stop dispatcher reads Claude snake_case stdin so it
fails open on Grok. Superpowers SessionStart stdout is ignored.

`20-safety.toml` sets `[sandbox] profile = "workspace"` and a conservative
`[permission] deny` list (`Bash(rm -rf *)` plus Read/Edit of SSH, GnuPG, and
common credential files). It does not set `ui.permission_mode`; that key stays
user-owned.

The merge is recursive and source-wins for keys the layer names. Other tables
in `~/.grok/config.toml` (`[ui]`, marketplace sources, auth-adjacent CLI state)
are preserved. Sibling files such as `~/.grok/hooks/*.json` are out of scope;
AgentGuard's Grok hooks fragment is a separate merge hook.

The hook applies `hooks` only when `~/.grok/hooks/agentguard.json` is a
regular file, and `rules`/`agents` only when `~/.grok/rules/agent-rules.md` is
a regular file. `skills` and `mcps` apply whenever the layer names them;
this overlay leaves both unset. If gating leaves `compat.claude` empty,
that object (and an empty parent `compat`) is deleted so other top-level
tables in the same layer still merge.
A filtered layer of `{}` is skipped.

A corrupt or symlinked `~/.grok/config.toml` is preserved and reported as a
failed refresh. The hook does not rebuild user UI or marketplace state from
the policy layer.
