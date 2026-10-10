# Checkrun Schema Associations

<!-- agent-rule-id: dev-checkrun-schema-associations -->
<!-- agent-rule-trigger: Editing structured dotfiles config or adding a Checkrun schema association -->

When adding or modifying tracked JSON, JSONC, YAML, or TOML configuration files
in dotfiles, consider whether the file should be associated with a schema in
`~/.config/checkrun/associations.json`.

- Prefer official, first-party, SchemaStore, or dependency-owned schemas. Do
  not invent local schemas just to make a file look covered.
- Use generic match patterns for reusable conventions, such as `package.json`,
  `.github/workflows/*.yml`, or `.config/dot/merge-hooks.d/foo-*.json`.
- If a merge-hook source layer is valid by itself, associate the source layer
  with the generated target's schema rather than only the generated output.
- When a schema is useful for editor feedback but cannot be enforced offline,
  use the policy's advisory/editor-only shape instead of blocking lint.
- To add or change an association, follow the "Adding a Schema Association"
  checklist in `~/.config/checkrun/README.md` step by step. Besides the policy
  entry, it fetches a new public payload the way the scheduled refresh does,
  confirms the Neovim and VS Code projections that `dot update` regenerates,
  and extends `schema-associations-test`; skipping a step leaves one consumer
  without the schema.
- Decide `enforce` by validating the real tracked files and a deliberately
  invalid sample, not by assuming the published schema fits local usage.
- If no proper schema exists, leave the file unassociated and rely on parser,
  formatter, linter, or native validation tools.
