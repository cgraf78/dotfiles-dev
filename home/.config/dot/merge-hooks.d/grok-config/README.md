# Grok Config Merge Hook

This directory declares the `grok-config` merge-hook instance. The executable
hook at `~/.local/lib/dotfiles/merge-hooks.d/grok-config.sh` merges TOML layers
from `config.d/` into `~/.grok/config.toml`.

The fragment is local policy, not a Grok runtime adapter. It turns off the
Claude-compat cells that would otherwise duplicate first-class Grok hooks and
home rules after those native targets exist:

- `compat.claude.hooks` — `~/.claude/settings.json` AgentGuard and Claude
  plugin hooks
- `compat.claude.rules` — `~/.claude/rules/` and project `.claude/rules/`
- `compat.claude.agents` — `~/.claude/CLAUDE.md` and project `.claude/CLAUDE*.md`

Grok defaults every Claude-compat cell to `true` when the section is absent.
The layer sets only those three keys so `skills`, `mcps`, and `sessions` keep
Grok's defaults, and any user-owned values for those cells stay in place.

The merge is recursive and source-wins for keys the layer names. Other tables
in `~/.grok/config.toml` (`[ui]`, marketplace sources, auth-adjacent CLI state)
are preserved. Sibling files such as `~/.grok/hooks/*.json` are out of scope;
AgentGuard's Grok hooks fragment is a separate merge hook.

The hook applies each cell only when its native replacement is a regular
file: `hooks` waits on `~/.grok/hooks/agentguard.json`, and `rules`/`agents`
wait on `~/.grok/rules/agent-rules.md`. That lets this PR land before those
targets exist without stripping Claude-compat coverage. `dot update` then
disables the matching cells once the native files appear.

A corrupt or symlinked `~/.grok/config.toml` is preserved and reported as a
failed refresh. The hook does not rebuild user UI or marketplace state from
the policy layer.
