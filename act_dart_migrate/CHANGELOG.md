## 0.3.0

- Expanded primary-constructor migration support for eligible unnamed, named, and
  `.new` constructors, including refined parameter-shape handling.
- Added extension type primary-constructor migration coverage.
- Bumped JSON report schema version to `3` for the expanded stable report
  vocabulary.
- Improved retained body-member conflict detection and class-body rewrite behavior
  when migrations remove all body members.
- Updated migration rules documentation and tests for non-trivial mixin classes,
  constructor shorthand interactions, named constructors, and field formal
  parameters.

## 0.2.0

- Renamed the package and executable to `act_dart_migrate` for consolidated ACT
  Dart migration tooling.
- Replaced the previous root migration command shape with the
  `primary-constructors` Migration Subcommand and root command discovery through
  `list --json`.
- Updated JSON Migration Reports to schema version `2` with top-level
  `migration: "primary-constructors"` attribution for selected-subcommand reports.
- Refreshed package-local README and docs for the active command grammar,
  migration rules, report contract, and modular-monolith architecture.
- Split reusable discovery, package-root, source-edit, report, exit-code, and
  target-package run mechanics into shared internal core modules while preserving
  primary-constructor migration semantics.
- Added deterministic command-discovery JSON for supported Migration
  Subcommands.

## 0.1.0

- Implemented conservative Dart primary-constructor migration for eligible
  classes and enhanced enums.
- Added constructor declaration shorthand migration for eligible constructors
  that remain in class or enum bodies.
- Added empty class-body collapse when migrations remove all body members.
- Added Target Package discovery with stable skip reporting for generated files,
  nested packages, nested repositories or worktrees, and excluded transient
  directories.
- Added stable JSON report behavior with deterministic changed-file,
  migrated-declaration, skipped-declaration, skipped-file, skipped-directory,
  transform-count, and skip-reason-count output.
- Kept formatting and verification outside the CLI boundary: the tool reports
  changed files but does not run formatters, analyzers, tests, package commands,
  or git operations.
