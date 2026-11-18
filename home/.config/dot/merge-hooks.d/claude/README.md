# Claude Merge Hook

This directory declares the `claude` merge-hook instance. The executable hook
at `~/.local/lib/dotfiles/merge-hooks.d/claude.sh` builds the source stream in this
order:

1. AgentGuard's native `claude/hooks.json` generation and shared
   `_shared/reconcile-hooks.jq`, resolved through shdeps.
2. Dotfiles and overlay layers from `settings.d/`, in normal family order.

That split is intentional. AgentGuard owns Claude event names, matchers,
commands, environment wiring, and timeouts because those details are reusable
by every AgentGuard user. This directory owns only machine/user policy, such as
the permission allowlist in `settings.d/20-permissions.json`.

The provider generation comes first so local policy and overlays can still
extend or override ordinary Claude settings. AgentGuard's filter replaces old
provider commands and retires old events while preserving user hooks. If either
asset cannot be resolved or validated, the hook reports a failed refresh and
leaves the complete live `~/.claude/settings.json` untouched; it does not apply
permission policy alone against a missing guard base.

`settings.d/30-bypass-permission-requests.json` makes bypass-permissions
sessions prompt-free. Claude Code still asks about some Bash and Monitor
commands in that mode, such as an `rm` whose target it cannot rule out as a
critical path. Its `CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS` switch
does nothing while any `PermissionRequest` hook is registered, and AgentGuard
and some plugins register one, so this layer answers those requests
with `allow` instead. It answers only when the request's `permission_mode` is
`bypassPermissions`; every other mode keeps its prompts. AgentGuard's own
hooks still see every request and keep guarding commands.

Change native hook behavior and its tests in AgentGuard under
`share/agentguard/integrations/claude/`. Keep additions here limited to local
policy that does not belong in a reusable integration.
