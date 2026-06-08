# act_dart_primary_constructors

Bundled ACT tooling for Dart primary-constructor migrations.

This package provides a Dart CLI that migrates eligible Dart classes and enhanced
enums from ordinary constructor boilerplate to Dart experimental
primary-constructor syntax. It is intentionally conservative: when a declaration
cannot be migrated safely, the tool leaves the source unchanged and reports a
precise skip reason.

This package is the active development source. Maintainers periodically sync it
into the ACT primary-constructor skill bundle for distribution, but sync
mechanics are tracked separately from CLI feature work.

## Usage

Run the CLI from this package or from the synced bundled copy inside the ACT
skill package:

```bash
dart run act_dart_primary_constructors --help
dart run act_dart_primary_constructors --version
dart run act_dart_primary_constructors migrate --help
dart run act_dart_primary_constructors migrate [target-package] --json
dart run act_dart_primary_constructors migrate [target-package] --dry-run
dart run act_dart_primary_constructors migrate [target-package] --include-skipped
```

The root command supports `--help`, `--version`, and `migrate` in V1.
Root help prints usage, root options, and available commands. `migrate --help`
prints migrate-specific usage, target package behavior, and migrate options.
Help output is always plain text on stdout and exits successfully.

The optional `target-package` positional argument selects the Target package
root. If omitted, it defaults to the current working directory (`.`). The root
must be a directory that contains a `pubspec.yaml`. Discovery scans
non-generated Dart files under that root and reports generated files, nested
packages, nested repositories or worktrees, and excluded transient directories
separately.

`--mode safe` is the only V1 migration mode and is the default. Future modes may
relax guards, but V1 does not expose aggressive migration behavior.

`--dry-run` runs the same discovery, migration planning, parse validation, and
reporting path as a real run, but writes no files.

`--json` writes a machine-readable report to stdout. With `--json`, stdout is
JSON only; human diagnostics and unexpected internal-error details go to stderr.

Without `--json`, text output is concise by default and summarizes counts.
`--include-skipped` expands text output with skipped declarations, skipped files,
and skipped directories. `--include-skipped` does not change JSON output because
JSON always includes skipped records.

The CLI does not provide source diff output or include/exclude path flags in V1.

## V1 Migration Scope

The public V1 transform names are:

- `primaryConstructor`
- `constructorShorthand`
- `emptyClassBody`

`primaryConstructor` migrates eligible class and enhanced-enum constructors to
primary constructors. It preserves modifiers, type parameters, bounds, clauses,
parameter shape, nullability, defaults, required markers, private names, public
call-site names for private named declaring parameters, and simple `super`
parameters. `const` constructors remain explicit `const` primary constructors.

Primary-constructor migration also supports conservative initializer handling.
Safe parameter-only field initializer assignments may move to field declarations.
Constructor assertions and unnamed `super(...)` initializers may be retained in a
primary constructor body while preserving relative order. Constructor bodies may
move only when they are not responsible for instance-field initialization.

Enhanced-enum migration preserves enum value argument shape and retained enum
members such as methods, getters, factories, and static members.

`constructorShorthand` is the separate report transform for eligible generative
constructors that remain in class bodies and can be rewritten to constructor
declaration shorthand. Primary-constructor migration remains preferred where it
is safe. Factory constructors are not rewritten to shorthand.

`emptyClassBody` collapses truly empty ordinary class bodies to semicolon form,
including classes made empty by primary-constructor migration. It does not apply
to enums, mixins, extension types, or class bodies that contain comments.

Already-primary declarations are treated as unchanged and are omitted from the
migrated and skipped declaration arrays.

## Conservative Skips

The CLI skips rather than guesses when a migration could change semantics or
move syntax to a different target.

Major declaration skip categories include:

- Constructor shape: multiple unnamed generative constructors, named generative
  constructors for primary migration, external constructors, redirecting
  constructors, unsupported constructor bodies, and non-empty bodies that
  initialize instance fields.
- Metadata and comments: constructor metadata, parameter metadata, field
  metadata, constructor comments, ambiguous field comments, and body comments
  that would be lost by empty-body collapse.
- Field mapping: missing fields, static fields, `late` fields, external fields,
  initialized fields, implicit field types, multi-variable field declarations,
  and unsupported field modifiers.
- Initializers: initializer entries that depend on instance state or unsupported
  expressions, unsupported initializer shapes, and named `super` initializers.

Generated Dart files are skipped with `generatedFile`. Whole subtrees are skipped
and reported once for `nestedPackage`, `nestedRepository`, or
`excludedDirectory`.

Parse failure in any in-scope non-generated Dart file aborts the run before any
writes. Transformed changed files are parsed in memory before any file is
written. No-op and skip-only runs exit successfully.

## JSON Report Contract

Successful JSON output has `ok: true` and schema version `1`:

```json
{
  "ok": true,
  "schemaVersion": 1,
  "toolVersion": "0.1.0",
  "root": "/absolute/target/package",
  "mode": "safe",
  "dryRun": false,
  "formatted": false,
  "changedFiles": ["lib/user.dart"],
  "migratedDeclarations": [],
  "skippedDeclarations": [],
  "skippedFiles": [],
  "skippedDirectories": [],
  "transformCounts": {},
  "skipReasonCounts": {}
}
```

`formatted` is always `false` in V1 because formatting is external to the CLI.

`changedFiles` contains relative Dart file paths that would be changed in a dry
run or were written in a real run.

Each `migratedDeclarations` entry has:

```json
{
  "path": "lib/user.dart",
  "declarationKind": "class",
  "declarationName": "User",
  "transform": "primaryConstructor",
  "offset": 0
}
```

Each `skippedDeclarations` entry has the same declaration fields plus a stable
reason code and message:

```json
{
  "path": "lib/user.dart",
  "declarationKind": "class",
  "declarationName": "User",
  "transform": "primaryConstructor",
  "offset": 0,
  "reason": "fieldMetadata",
  "message": "Field metadata is not moved to declaring parameters."
}
```

`skippedFiles` and `skippedDirectories` contain `{ "path", "reason" }` objects.
File-level skip reasons currently include `generatedFile`; directory-level
reasons include `nestedPackage`, `nestedRepository`, and `excludedDirectory`.

`transformCounts` counts migrated declarations by transform kind.
`skipReasonCounts` combines declaration, skipped-file, and skipped-directory
reason counts. Report arrays and count maps are deterministic.

Failure JSON output has `ok: false`:

```json
{
  "ok": false,
  "schemaVersion": 1,
  "toolVersion": "0.1.0",
  "error": {
    "code": "invalidRoot",
    "message": "Target package root does not exist or has no pubspec.yaml: example"
  }
}
```

Stable V1 error codes are `argumentError`, `invalidRoot`, `parseFailure`,
`validationFailure`, and `internalError`.

Active V1 exit codes are:

- `0`: success, including no-op and skip-only runs
- `1`: transformed source validation failure
- `64`: argument error
- `65`: input parse failure
- `66`: invalid root
- `70`: internal error

Formatter failure is not a CLI exit category in V1 because formatting is not
performed by the CLI.

## Formatting And Verification

The CLI owns discovery, conservative migration planning, source-edit validation,
parse validation, file writes, and report generation. It does not run `dart
format`, `dart analyze`, `dart test`, `flutter analyze`, `flutter test`, `pub
get`, or git commands.

Formatting is external in V1 so the migration executable does not bundle a
formatter dependency, mutate Target package setup, or hide formatter failures
inside the migration report. The ACT skill reads `changedFiles` from the JSON
report and formats only those Dart files with the resolved Dart runner and the
primary-constructor formatter flag:

```bash
dart format --enable-experiment=primary-constructors <changed-dart-files>
```

The ACT skill owns user workflow verification around the CLI. It verifies target
SDK/toolchain and analyzer experiment prerequisites, runs pre-migration analysis,
bootstraps only the bundled CLI package, invokes the CLI with `--json`, formats
changed files externally, then runs post-migration analysis and tests. For
Flutter Target packages, tests use the primary-constructor experiment flag and
avoid automatic target-package pub get. For pure Dart Target packages, tests use
the resolved Dart runner with the primary-constructor experiment flag.

Maintainer-only Corpus verification lives outside this package. It treats the CLI
as a black-box executable, runs it against disposable Target package copies,
compares formatted Dart source and normalized JSON reports, and runs analyzer and
test verification in those disposable worktrees. Corpus verification complements
focused fixtures; it is not part of normal ACT user migration runs.

## Maintainer Notes

This package is bundled ACT tooling, not a Target package dependency, global
activation, or pub.dev dependency in V1. Active development lives in
`act-dart-tools/act_dart_primary_constructors/`; ACT users run the synced bundled
copy inside the `act-dart-migrate-primary-constructors` skill package. This keeps
the user workflow self-contained and independent of pub.dev or Target project
dependencies while preserving standalone CLI development history here.

Commit `pubspec.lock` for this package. The lockfile keeps analyzer and CLI
dependency behavior reproducible for the bundled executable and ACT validation.

Sync mechanics for the ACT skill bundle are maintainer work outside normal CLI
feature issues unless an issue explicitly requests sync work.

The implementation separates CLI argument handling and report output from Target
package discovery, migration planning, stable report serialization, and source
edits. Keep user-facing docs focused on CLI behavior and report contracts; avoid
depending on internal module names in skill orchestration.

## Example

The primary-constructor transform converts eligible constructor and field
boilerplate into declaring parameters. For example:

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
