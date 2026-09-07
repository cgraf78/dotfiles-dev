# Grok Merge Hook

This directory declares the `grok` merge-hook instance. The executable hook
at `~/.local/lib/dotfiles/merge-hooks.d/grok.sh` resolves AgentGuard's native
`grok/hooks.json` generation and AgentGuard's shared reconciler through
shdeps, then writes that fragment to Grok's dedicated global hooks file
`~/.grok/hooks/agentguard.json`.

Grok discovers global hooks by merging every `~/.grok/hooks/*.json` file. A
dedicated AgentGuard fragment keeps provider hooks out of `~/.grok/config.toml`
and out of any user-owned sibling JSON files.

AgentGuard owns Grok event names, tool matchers, commands, session identity,
and timeouts. Those are runtime compatibility facts, not personal dotfiles
policy, so their implementation and exact tests live under
`share/agentguard/integrations/grok/` in AgentGuard.

There are no local Grok settings layers here: the complete native hook
fragment comes from the dependency. The provider filter owns event retirement
and changed-command replacement. If either dependency asset is temporarily
unavailable, the hook reports a failed refresh and preserves the last
destination rather than installing an unguarded partial config.
