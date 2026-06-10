# act_dart_migrate

Bundled ACT tooling for deterministic Dart migrations.

This package provides one Dart executable, `act_dart_migrate`, with Migration Subcommands. The first Migration Subcommand is `primary-constructors`, which migrates eligible Dart classes and enhanced enums from ordinary constructor boilerplate to Dart experimental [primary-constructor](https://dart.dev/language/primary-constructors) syntax and validates extension type representation parameters before safe body transforms.

The migration is intentionally conservative: when a declaration cannot be migrated safely, the CLI leaves the source unchanged and reports a precise skip reason.

## Requirements

The package requires Dart SDK 3.12.0 or higher.

Migrated primary-constructor output is experimental Dart syntax. Analyzer, formatting, running, and testing support for that syntax is configured and verified outside this CLI.

## Before Using The Tool

These prerequisites are specific to the `primary-constructors` Migration Subcommand.

Run the migration on a Target Package that already compiles without errors.

Set the Target Package Dart SDK constraint to 3.12 or higher in `pubspec.yaml`:

```yaml
environment:
  sdk: ^3.12.0
```

Enable the `primary-constructors` experiment in the Target Package `analysis_options.yaml` file:

```yaml
analyzer:
  enable-experiment:
    - primary-constructors
```

Analyzer, run, test, and format commands that process migrated source need the primary-constructor experiment flag:

```bash
flutter run --enable-experiment=primary-constructors
flutter test --enable-experiment=primary-constructors
dart format --enable-experiment=primary-constructors <changed-dart-files>
```

Each relevant `.vscode/launch.json` configuration should also contain the `--enable-experiment=primary-constructors` flag:

```json
{
  "name": "example_app",
  "request": "launch",
  "type": "dart",
  "args": ["--enable-experiment=primary-constructors"]
}
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
dart run act_dart_migrate primary-constructors <target-package> --skip-super-constructor-initializers
```

Running the executable without arguments prints concise usage and exits successfully. Root `--version` prints the package version without selecting a Migration Subcommand.

`list --json` writes a machine-readable discovery response for supported Migration Subcommands without requiring a Target Package or running migration planning.

The required `target-package` positional argument selects the Target package root. Use `.` to migrate the current working directory. The root must be a directory that contains a `pubspec.yaml`. Discovery scans non-generated Dart files under that root and reports generated files, nested packages, nested repositories or worktrees, and excluded transient directories separately.

`--dry-run` runs the same discovery, migration planning, parse validation, and reporting path as a real run, but writes no files.

`--json` writes a machine-readable report to stdout. With `--json`, stdout is JSON only; human diagnostics and unexpected internal-error details go to stderr.

Without `--json`, text output is concise by default and summarizes counts. `--include-skipped` expands text output with skipped declarations, skipped files, and skipped directories. `--include-skipped` does not change JSON output because JSON always includes skipped records.

`--skip-super-constructor-initializers` is not enabled by default. It is an opt-in Dart SDK primary-constructor workaround for a stable-channel compiler failure seen when a migrated class has both a primary constructor and an abstract superclass whose constructor has required parameters:

```dart
abstract class Parent {
  const Parent({required this.index});
  final int index;
}

class const Child(final int value) extends Parent {
  this : super(index: value);
}
```

When enabled, the flag skips otherwise eligible class migrations whose primary-constructor body would retain an explicit `super(...)` or `super.named(...)` initializer. It does not skip classes merely because a constructor uses super parameters such as `super.key`.

This flag will be deprecated or removed once the Dart SDK fix is merged to stable.

## Package Docs

See [Migration Rules](doc/migration_rules.md) for the supported transforms, stable transform names, declaration skip reason codes, file and directory skip reason codes, and no-op behavior for `primary-constructors`.

See [Report Contract](doc/report_contract.md) for schema version `2`, selected migration attribution, success and failure envelopes, stable error codes, exit codes, and deterministic report ordering.

See [Architecture Overview](doc/architecture.md) for the CLI pipeline, responsibility boundaries, shared internal core responsibilities, and migration-specific module responsibilities.

At a high level, the CLI supports conservative primary-constructor migration for eligible classes and enhanced enums, extension type representation-parameter validation, constructor declaration shorthand for eligible constructors that remain in supported declaration bodies, and empty class-body collapse. The CLI skips rather than guesses when a migration could change semantics.

## Formatting And Verification

The CLI owns discovery, conservative migration planning, source-edit validation, parse validation, file writes, and report generation. It does not run `dart format`, `dart analyze`, `dart test`, `flutter analyze`, `flutter test`, `pub get`, or git commands.

Formatting is external, so the migration executable does not bundle a formatter dependency, mutate Target package setup, or hide formatter failures inside the migration report. The ACT skill reads `changedFiles` from the JSON report and formats only those Dart files with the resolved Dart runner and the primary-constructor formatter flag:

```bash
dart format --enable-experiment=primary-constructors <changed-dart-files>
```

The ACT skill owns user workflow verification around the CLI. It verifies target SDK/toolchain and analyzer experiment prerequisites, runs pre-migration analysis, bootstraps only the bundled CLI package, invokes the CLI with `--json`, formats changed files externally, then runs post-migration analysis and tests. For Flutter Target packages, tests use the primary-constructor experiment flag and avoid automatic target-package pub get. For pure Dart Target packages, tests use the resolved Dart runner with the primary-constructor experiment flag.

## Maintainer Notes

This package is bundled ACT tooling. Keep package docs focused on command behavior and report contracts.

Commit `pubspec.lock` for this package. The lockfile keeps analyzer and CLI dependency behavior reproducible for the bundled executable and ACT validation.

The implementation separates CLI argument handling and report output from Target package discovery, migration planning, stable report serialization, and source edits. Keep user-facing docs focused on CLI behavior and report contracts; avoid depending on internal module names in skill orchestration.

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
