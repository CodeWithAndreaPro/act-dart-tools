# act-dart-tools

A collection of command line tools for Dart development.

## Tools

### act_dart_migrate

Bundled ACT tooling for deterministic Dart migrations.

This package provides one Dart executable with Migration Subcommands. The first
Migration Subcommand migrates eligible Dart classes and enhanced enums from
ordinary constructor boilerplate to Dart experimental primary-constructor syntax.
It is intentionally conservative: when a declaration cannot be migrated safely,
the tool leaves the source unchanged and reports a precise skip reason.

See [`act_dart_migrate/README.md`](act_dart_migrate/README.md)
for CLI usage and package-local documentation.
