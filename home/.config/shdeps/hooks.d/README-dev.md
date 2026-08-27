# Development dependency hooks

These hooks install development-only tools that cannot be expressed as a
portable package or ordinary repository dependency. Each hook is selected by
the dev-owned Shdeps declarations and must remain safe to run repeatedly.
