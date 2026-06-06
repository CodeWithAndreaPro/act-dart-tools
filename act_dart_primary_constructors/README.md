# dart_primary_constructors

Bundled ACT tooling for Dart primary-constructor migrations.

This package provides a small Dart CLI that migrates eligible Dart classes from
ordinary constructor boilerplate to Dart experimental primary-constructor syntax.
It is intentionally conservative: when a declaration cannot be migrated safely,
the tool leaves the source unchanged and reports a precise skip reason.

## Usage

```bash
dart run dart_primary_constructors --version
dart run dart_primary_constructors migrate --root <target-package> --json
dart run dart_primary_constructors migrate --root <target-package> --dry-run
```

## How it works

The high-level flow is:

```text
bin/dart_primary_constructors.dart
  -> runDartPrimaryConstructors()
  -> discoverTargetPackageFiles()
  -> migrateTargetPackageFiles()
  -> MigrationReport / CliErrorReport
```

The CLI validates the target package root, discovers candidate Dart files, plans
AST-backed source edits, validates transformed source, writes files unless
`--dry-run` is enabled, then emits either text output or JSON.

## Core implementation blocks

`bin/dart_primary_constructors.dart` is the executable entry point. It delegates
to `runDartPrimaryConstructors()` and sets the process exit code.

`lib/dart_primary_constructors.dart` defines the public package export surface
for the CLI, report model, version, and exit codes.

`lib/src/cli.dart` owns argument parsing and orchestration. It handles
`--version`, the `migrate` command, root validation, migration execution, error
mapping, and text or JSON report output.

`lib/src/discovery.dart` finds target Dart files under the selected package root.
It skips generated files, hidden or transient tooling directories, nested
packages, and nested git repositories. Skipped paths are recorded for reporting.

`lib/src/migration.dart` collects the migration implementation through internal
part files under `lib/src/migration/`.

`lib/src/migration/engine.dart` runs migration planning over discovered files. It
parses each file with analyzer using the `primary-constructors` feature flag,
collects edits and skip reports, validates transformed source by parsing it
again, and writes changed files when not running in dry-run mode.

`lib/src/migration/class_primary_constructor.dart` contains the main
class-level transformation logic. It classifies each class as a no-op, migrated,
or skipped, then builds the required source edits for safe migrations.

`lib/src/migration/initializer_handling.dart` classifies constructor initializer
lists. It can retain safe `assert(...)` and unnamed `super(...)` initializers,
move safe field initializer assignments, and reject unsafe initializer shapes.

`lib/src/migration/constructor_body_safety.dart` checks constructor bodies. It
allows movable block bodies that do not write instance fields and skips bodies
that could change initialization semantics.

`lib/src/migration/field_comments.dart` decides whether field comments can move
to declaring parameters. Directly attached comments can move; ambiguous comments
cause the declaration to be skipped.

`lib/src/source_edit.dart` applies validated non-overlapping source edits from
the end of the file backward so earlier offsets remain stable.

`lib/src/report.dart` defines the stable report contract for successful runs and
CLI errors.

## Migration behavior

The primary transform converts eligible constructor and field boilerplate into
declaring parameters. For example:

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

The tool supports safe cases including const constructors, named and optional
parameters, simple `super` parameters, retained `assert` and unnamed `super`
initializers, safe initializer-list field assignments, simple constructor
bodies, and directly attached field comments.

Unsupported or ambiguous cases are skipped with a precise declaration skip
reason instead of being rewritten speculatively.

## Reporting

Successful reports include changed files, migrated declarations, skipped
declarations, skipped files, skipped directories, transform counts, and skip
reason counts. JSON output is designed to be deterministic and machine-readable.

Error reports use the same schema/version metadata and include an error code and
message.
