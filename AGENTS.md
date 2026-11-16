# Agentic Development

- Before making changes, read and follow the engineering standards in [docs/engineering-standards.md](docs/engineering-standards.md). Feature and protocol documents elsewhere in `docs/` describe behavior, not structure or style.
- After every major change or completed set of changes, offer to commit it and wait for explicit approval. Never commit, amend, rebase, force-push or push without approval.
- Write detailed commit messages following [the commit rules](docs/engineering-standards.md#54-commits), so that the history can be turned into release changelogs:
  - One logical change per commit.
  - An imperative summary line of at most 72 characters that names the effect.
  - A body wrapped at 72 columns explaining what changed, why, and any platform, migration or compatibility impact.
  - `Changelog:` (`Added`, `Changed`, `Fixed`, `Compatibility`, `Maintenance` or `None`) and `Platforms:` trailers.
- Commits are authored and committed only by the user's own git identity, as configured in the repository or global git config. Do not pass `--author`, set `GIT_AUTHOR_*` or `GIT_COMMITTER_*`, or change `user.name` or `user.email`. If no identity is configured, ask the user to set one instead of committing.
- Never mention an LLM, agent or tool in commits. No `Co-Authored-By` trailers, tool or model names, or "Generated with" lines in messages, trailers or branch names.
- Do not skip hooks or bypass commit signing.
