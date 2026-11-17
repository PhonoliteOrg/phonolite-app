# Agent instructions

This file follows [5.6](FLUTTER-STANDARDS.md#56-agent-instructions) of the Flutter standards. It defines how to work; the rules themselves are in the linked sections.

## Sources

- Read [FLUTTER-STANDARDS.md](FLUTTER-STANDARDS.md) and [PROJECT-PROFILE.md](PROJECT-PROFILE.md) before changing code. The profile holds this repository's paths, tools, limits, release checklists and commit vocabulary.
- Feature and protocol documents elsewhere in `docs/` describe behavior, not structure or style.

## Before starting

- Name the responsibility and its source area before writing code ([5.1](FLUTTER-STANDARDS.md#51-applying-the-standard)).
- For a defect, explain the cause from the code, or reproduce or instrument it to separate the candidate causes, before changing behavior. If an attempt does not confirm the cause, revert it before trying the next.

## Triggers

| When you… | Apply | Leave as evidence |
| --- | --- | --- |
| rely on how a framework, library or platform API behaves | [1.4](FLUTTER-STANDARDS.md#14-verify-dont-assume) | A comment stating the confirmed fact, where the decision depends on it |
| are about to write an encoder, parser, retry, queue, limiter, buffer or generation counter | [3.6](FLUTTER-STANDARDS.md#36-readable-operations) | The existing owner used, or the reason none fits, in the commit body |
| derive one state from another | [3.6](FLUTTER-STANDARDS.md#36-readable-operations) | Separate named values where the two can disagree |
| start a worker, isolate, request, stream, timer, subscription or native handle | [2.9](FLUTTER-STANDARDS.md#29-runtime-and-resource-ownership), [3.9](FLUTTER-STANDARDS.md#39-async-work-errors-and-resource-lifetime) | Code showing who stops it, its time bound, how waiters fail when it dies, and isolated cleanup |
| add a timeout or wait on I/O | [3.9](FLUTTER-STANDARDS.md#39-async-work-errors-and-resource-lifetime) | The underlying work is aborted on timeout, not just the wait |
| catch an error, or return an empty or default value after an operation | [3.9](FLUTTER-STANDARDS.md#39-async-work-errors-and-resource-lifetime) | A rethrow, a log through the logging owner, or a comment on why the failure does not matter |
| delete, reset or prune stored data, files or credentials | [3.12](FLUTTER-STANDARDS.md#312-durable-data) | Code distinguishing confirmed absence from unavailable or transient failure |
| write a file or database that must survive a crash, or change a stored format | [3.12](FLUTTER-STANDARDS.md#312-durable-data) | Atomic write or transaction, and a migration test |
| count, truncate, compare or format text, dates or numbers | [3.11](FLUTTER-STANDARDS.md#311-text-locale-and-identity) | Grapheme-aware, Unicode-aware and locale-aware handling |
| cross a native, channel or process boundary | [2.10](FLUTTER-STANDARDS.md#210-cross-language-boundaries) | Failures converted at the boundary, return sentinels checked, owner re-checked in handlers |
| build or change an interactive control, modal or route | [3.8](FLUTTER-STANDARDS.md#38-ui-pieces-and-final-assembly) | Shared control layer used; focus, semantics, label, reduced motion and text scaling covered |
| add or change a platform host capability | [2.12](FLUTTER-STANDARDS.md#212-host-release-readiness) | The host's checklist in the profile updated |
| use a Dart or Flutter API listed as a trap | [4.1](FLUTTER-STANDARDS.md#41-dart-and-flutter) | The listed alternative, or a comment on why it does not apply |
| fix a defect | [5.1](FLUTTER-STANDARDS.md#51-applying-the-standard), [5.3](FLUTTER-STANDARDS.md#53-verification) | In the commit body: the mistake, the search for other occurrences and the regression test that fails without the fix |
| change behavior for performance | [5.1](FLUTTER-STANDARDS.md#51-applying-the-standard) | Measurements before and after, and the hardware, in the commit body |
| write a test | [5.3](FLUTTER-STANDARDS.md#53-verification) | A test of behavior, never of source text |
| add a dependency, component or toolchain change | [5.4](FLUTTER-STANDARDS.md#54-commits) | Lockfiles regenerated, build outputs ignored, toolchain minimums raised together |

## Evidence

- Confirmed API facts go in a short comment beside the code that depends on them.
- Causes, searches for other occurrences, regression tests and measurements go in the commit body.
- Manual checks and anything not verified go in the final report.

## Self-review

Before reporting the work as finished:

1. Check the diff against every trigger above that applies, and confirm its evidence is present.
2. Apply the [review checklist](FLUTTER-STANDARDS.md#52-review-checklist).
3. If you find a rule broken in more than one place, say so and propose a mechanical check ([5.3](FLUTTER-STANDARDS.md#53-verification)).
4. If files changed on `main`, end the report with the commit offer described under [Commits and approval](#commits-and-approval).

## Verification limits

- Format and analyze affected files and run focused headless tests and the structural checks listed in the profile.
- Do not start the application, simulators, emulators, servers or background services.
- List the specific manual checks the developer should run for anything only the running app can show.

## Commits and approval

- Work and commit on the current branch, normally `main`. Do not create, switch, merge or delete branches, or use worktrees, unless the developer asks ([5.4](FLUTTER-STANDARDS.md#54-commits)).
- After any change to files on `main`, offer to commit: propose the message and list the files, then wait for explicit approval. Never commit, amend, rebase, force-push or push without it.
- Follow [5.4](FLUTTER-STANDARDS.md#54-commits) for the message, with `Changelog:` and `Platforms:` values from the [profile](PROJECT-PROFILE.md#commit-vocabulary).
- Commit only with the configured git identity. Do not pass `--author`, set `GIT_AUTHOR_*` or `GIT_COMMITTER_*`, or change `user.name` or `user.email`. If none is configured, ask the developer to set one.
- Never mention an agent, LLM or tool in commits: no `Co-Authored-By` trailers, tool or model names, or "Generated with" lines in messages, trailers or branch names.
- Do not skip hooks or bypass commit signing.
