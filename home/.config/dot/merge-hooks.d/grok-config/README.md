# Grok Config Merge Hook

This directory declares the `grok-config` merge-hook instance. The executable
hook at `~/.local/lib/dotfiles/merge-hooks.d/grok-config.sh` merges TOML layers
from `config.d/` into `~/.grok/config.toml`.

The fragment is local policy, not a Grok runtime adapter. It turns off the
Claude-compat cells that would otherwise duplicate first-class Grok hooks,
home rules, and MCP config after those native targets exist:

- `compat.claude.hooks` — `~/.claude/settings.json` AgentGuard and Claude
  plugin hooks
- `compat.claude.rules` — `~/.claude/rules/` and project `.claude/rules/`
- `compat.claude.agents` — `~/.claude/CLAUDE.md` and project `.claude/CLAUDE*.md`
- `compat.claude.mcps` — Claude MCP config

Grok defaults every Claude-compat cell to `true` when the section is absent.
The layer sets hooks/rules/agents/mcps. `skills` and `sessions` stay unset so
those cells keep Grok's defaults (Claude skills stay on), and any user-owned
value stays in place.

`[plugins] disabled` lists only hook-bearing or Claude-only plugins (plain
names, not `name@marketplace` keys): hookify, ralph-loop, security-guidance,
memory-sync, claude-md-management, plugin-dev, status-line, claude-code-setup,
and skill-creator. Superpowers, commit-commands, code-review, feature-dev,
pr-review-toolkit, frontend-design, github, and code-simplifier stay enabled.

The merge is recursive and source-wins for keys the layer names. Other tables
in `~/.grok/config.toml` (`[ui]`, marketplace sources, auth-adjacent CLI state)
are preserved. Sibling files such as `~/.grok/hooks/*.json` are out of scope;
AgentGuard's Grok hooks fragment is a separate merge hook.

The hook applies `hooks` only when `~/.grok/hooks/agentguard.json` is a
regular file, and `rules`/`agents` only when `~/.grok/rules/agent-rules.md` is
a regular file. `skills` and `mcps` apply whenever the layer names them:
Grok's own skills directory and empty MCP list are the replacements. If
gating leaves `compat.claude` empty, that object (and an empty parent
`compat`) is deleted so other top-level tables in the same layer still merge.
A filtered layer of `{}` is skipped.

A corrupt or symlinked `~/.grok/config.toml` is preserved and reported as a
failed refresh. The hook does not rebuild user UI or marketplace state from
the policy layer.
