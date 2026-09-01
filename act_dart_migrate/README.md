# act_dart_migrate

Bundled ACT tooling for deterministic Dart migrations.

This package provides one Dart executable, `act_dart_migrate`, with Migration Subcommands. The first Migration Subcommand is `primary-constructors`, which migrates eligible Dart classes and enhanced enums from ordinary constructor boilerplate to Dart [primary-constructor](https://dart.dev/language/primary-constructors) syntax.

The migration is intentionally conservative: when a declaration cannot be migrated safely, the CLI leaves the source unchanged and reports a precise skip reason.

## Requirements

The bundled `act_dart_migrate` tool runs with the Dart SDK constraint in `pubspec.yaml`, currently `^3.8.0`.

Migrated primary-constructor output requires Target Packages on Dart SDK 3.13.0 or higher. Formatting, analysis, running, and testing are performed outside this CLI.

## Before Using The Tool

These prerequisites are specific to the `primary-constructors` Migration Subcommand.

Run the migration on a Target Package that already compiles without errors.

Set the Target Package Dart SDK constraint to 3.13 or higher in `pubspec.yaml`:

```yaml
environment:
  sdk: ^3.13.0
```

Before running the migration, fix analyzer errors and warnings in the Target Package. Some lint-based warnings can be fixed with `dart fix --apply`; others need manual changes.

## Usage

Run the CLI like this:

```bash
dart run act_dart_migrate
dart run act_dart_migrate --version
dart run act_dart_migrate list --json
dart run act_dart_migrate primary-constructors <target-package> --json
dart run act_dart_migrate primary-constructors <target-package> --dry-run
dart run act_dart_migrate primary-constructors <target-package> --include-skipped
```

Running the executable without arguments prints concise usage and exits successfully. Root `--version` prints the package version without selecting a Migration Subcommand.

`list --json` writes a machine-readable discovery response for supported Migration Subcommands without requiring a Target Package or running migration planning. Its `targetPackageMinimumDartSdk` and `targetPackageRequiredExperiments` fields describe Target Package prerequisites for migrated output, not the SDK used to run the bundled tool.

The required `target-package` positional argument selects the Target package root. Use `.` to migrate the current working directory. The root must be a directory that contains a `pubspec.yaml`. Discovery scans non-generated Dart files under that root and reports generated files, nested packages, nested repositories or worktrees, and excluded transient directories separately.

`--dry-run` runs the same discovery, migration planning, parse validation, and reporting path as a real run, but writes no files.

`--json` writes a machine-readable report to stdout. With `--json`, stdout is JSON only; human diagnostics and unexpected internal-error details go to stderr.

Without `--json`, text output is concise by default and summarizes counts. `--include-skipped` expands text output with skipped declarations, skipped files, and skipped directories. `--include-skipped` does not change JSON output because JSON always includes skipped records.

Eligible class migrations retain explicit `super(...)` and `super.named(...)` initializers in the primary-constructor body. This syntax is supported by the Dart 3.13 Target Package minimum.

## Package Docs

See [Migration Rules](doc/migration_rules.md) for the supported transforms, stable transform names, declaration skip reason codes, file and directory skip reason codes, and no-op behavior for `primary-constructors`.

See [Report Contract](doc/report_contract.md) for schema version, selected migration attribution, success and failure envelopes, stable error codes, exit codes, and deterministic report ordering.

See [Architecture Overview](doc/architecture.md) for the CLI pipeline, responsibility boundaries, shared internal core responsibilities, and migration-specific module responsibilities.

At a high level, the CLI supports conservative primary-constructor migration for eligible classes and enhanced enums, extension type representation-parameter validation, constructor declaration shorthand for eligible constructors that remain in supported declaration bodies, and empty class-body collapse. The CLI skips rather than guesses when a migration could change semantics.

## Formatting And Verification

The CLI owns discovery, conservative migration planning, source-edit validation, parse validation, file writes, and report generation. It does not run formatting, analysis, tests, dependency resolution, or git commands.

Formatting is external, so the migration executable does not bundle a formatter dependency, mutate Target Package setup, or hide formatter failures inside the migration report.

As such, this is the recommended usage:

```bash
dart run act_dart_migrate primary-constructors <target-package>
dart format <target-package>
```

Analysis and tests are also external responsibilities.

## Example

The primary-constructor transform converts eligible constructor and field boilerplate into declaring parameters. For example:

```dart
class User {
  final String id;

  User(this.id);
}
```

becomes:

```dart
class User(final String id);
```
