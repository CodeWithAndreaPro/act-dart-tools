## 0.1.0

- Implemented V1 conservative Dart primary-constructor migration for eligible
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
