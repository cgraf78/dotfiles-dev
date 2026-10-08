# Development interactive shell

Ordered Bash and Zsh fragments enable Sley, git-tools, and Direnv through the
base profile's `_tool_init` interface. Agent command wrappers and advanced Git
aliases live in the same capability as their dependencies. The `grok`/`agent`
wrappers call the base loader helper after each launch to strip the block
Grok's installer appends to `~/.zshrc` and `~/.bashrc`; base keeps Grok's PATH
entry and completions.
