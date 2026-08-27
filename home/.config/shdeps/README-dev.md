# Development dependencies

`30-dev.conf` contains packages and public providers needed only by the `dev`
profile. Language toolchains live in `00-toolchains.conf`; installation hooks
for custom development tools live in `hooks.d/`.

The base repository continues to own Git itself, Dot, shell fundamentals, and
`agent-rules-sync`. The editor overlay owns Neovim and editor-only dependencies.
