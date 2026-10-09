# Sley Policy Providers

This directory contains dotfiles-owned policy reached through Sley's reusable
SCM hook APIs. These files are internal providers, not PATH-visible commands or
alternative hook frameworks.

`validate-commit-msg` enforces the existing Git and Sapling commit-message
grammar. Sley supplies the generic executable-provider contract and passes one
message-file path; dotfiles selects the applicable profile through
`COMMIT_MSG_FORMAT`. Keeping the prose policy here avoids teaching Sley one
user's required sections while allowing every supported SCM integration to use
the same Sley orchestration.

Strict mode (`--strict` or `COMMIT_MSG_STRICT=1`) turns every structural
finding into an error: missing or placeholder sections, sections out of
order, and, for Git, Markdown (`##`) section headers, a missing blank line
before a section, or body text past 80 columns. Lines of 73-80 columns, or
whose code span straddles column 72, only warn, since the rule is "~72".
URLs, code, trailers, and single words too long to wrap are exempt from the
width check, and the
`commit -v` diff below Git's scissors line is never checked. Sapling messages
back Phabricator Markdown fields, so their paragraphs stay unwrapped, their
headings stay legal, and adjacent `Summary:`/`Test Plan:` fields remain
valid. Without strict mode the same findings are warnings.

The validator retains stdin, `--file`, `--format`, and `--strict` inputs for
focused policy tests and compatible internal callers. Hook integrations should
route through `sley hook validate-message --validator ...` instead of invoking
the provider directly.

The Git adapter in `../git-hooks/commit-msg` selects this provider. Private
overlay policy may select it through the same Sley API with a different format;
no private policy or vocabulary belongs in this public directory.
