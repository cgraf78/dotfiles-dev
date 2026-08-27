# Development merge hooks

This overlay contributes merge hooks for development applications including
Git, GitHub CLI, agent tools, Mise, Sley, and VS Code. The standalone Dot
client discovers these hooks only when the selected overlay is eligible for
automatic extensions; isolated repository tests invoke their public interfaces
explicitly.
