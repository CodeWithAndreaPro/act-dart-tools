# act_dart_primary_constructors

Bundled ACT tooling for Dart primary-constructor migrations.

This package provides a Dart CLI that migrates eligible Dart classes and enhanced enums from ordinary constructor boilerplate to Dart experimental
[primary-constructor](https://dart.dev/language/primary-constructors) syntax. It is intentionally conservative: when a declaration cannot be migrated safely, the tool leaves the source unchanged and reports a precise skip reason.

## Minimum Requirements

Ensure these are installed:

- Flutter SDK 3.44.0 or higher
- Dart SDK 3.12.0 or higher (already installed on Flutter SDK)

## Before Using The Tool

**Important**: Use the tool on a package/app that **already compiles without errors**.

Set the Dart SDK version to 3.12 in your `pubspec.yaml` file.

```yaml
environment:
  sdk: ^3.12.0
```

Enable the `primary-constructors` experiment in your `analysis_options.yaml` file.

```yaml
analyzer:
  enable-experiment:
    - primary-constructors
```

From this point on, always run the following commands with `--enable-experiment=primary-constructors` flag.

```bash
flutter run --enable-experiment=primary-constructors
flutter test --enable-experiment=primary-constructors
```

Before using the tool, it is highly recommended that you fix all the analyzer errors and warnings.

Some of them are based on lint rules that can be automatically fixed by `dart fix --apply`. But others will need to be manually fixed.

## Usage

Run the CLI from this package like this:

```bash
dart run act_dart_primary_constructors # shows help output
dart run act_dart_primary_constructors migrate <target-package> --json
dart run act_dart_primary_constructors migrate <target-package> --dry-run
dart run act_dart_primary_constructors migrate <target-package> --include-skipped
```

For maximum speed, build an AOT-compiled executable from this package root and
run the generated binary instead of `dart run`:

```bash
dart compile exe bin/act_dart_primary_constructors.dart
./bin/act_dart_primary_constructors.exe migrate <target-package> --json
```

This avoids repeated `dart run` startup overhead and is useful for repeated or
large migration runs.

The root command supports no-argument help output, `--version`, and `migrate`.
Running the executable without arguments prints concise usage, target package
behavior, and migrate options. The CLI does not expose a `--help` flag. Help
output is plain text on stdout and exits successfully.

The required `target-package` positional argument selects the Target package
root. Use `.` to migrate the current working directory. The root must be a
directory that contains a `pubspec.yaml`. Discovery scans non-generated Dart
files under that root and reports generated files, nested packages, nested
repositories or worktrees, and excluded transient directories separately.

`--dry-run` runs the same discovery, migration planning, parse validation, and
reporting path as a real run, but writes no files.

`--json` writes a machine-readable report to stdout. With `--json`, stdout is
JSON only; human diagnostics and unexpected internal-error details go to stderr.

Without `--json`, text output is concise by default and summarizes counts.
`--include-skipped` expands text output with skipped declarations, skipped files,
and skipped directories. `--include-skipped` does not change JSON output because
JSON always includes skipped records.

## Performance

`act_dart_primary_constructors` is **very fast**: the AOT-compiled executable can process 100,000 lines of code in under 1 second (tested on Mac Studio M2 Max).

## Package Docs

See [Migration Rules](doc/migration_rules.md) for the supported transforms,
stable transform names, declaration skip reason codes, file and directory skip
reason codes, and no-op behavior.

See [Architecture Overview](doc/architecture.md) for the CLI pipeline,
responsibility boundaries, write-safety checks, and report-generation flow.

At a high level, the CLI supports conservative primary-constructor migration for
eligible classes and enhanced enums, constructor declaration shorthand for
eligible constructors that remain in class bodies, and empty class-body collapse.
The CLI skips rather than guesses when a migration could change semantics.

## JSON Report Contract

Successful JSON output has `ok: true` and schema version `1`:

```json
{
  "ok": true,
  "schemaVersion": 1,
  "toolVersion": "0.1.0",
  "root": "/absolute/target/package",
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

`formatted` is always `false` because formatting is external to the CLI.

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

Stable error codes are `argumentError`, `invalidRoot`, `parseFailure`,
`validationFailure`, and `internalError`.

Active exit codes are:

- `0`: success, including no-op and skip-only runs
- `1`: transformed source validation failure
- `64`: argument error
- `65`: input parse failure
- `66`: invalid root
- `70`: internal error

Formatter failure is not a CLI exit category because formatting is not performed
by the CLI.

## Formatting And Verification

The CLI owns discovery, conservative migration planning, source-edit validation,
parse validation, file writes, and report generation. It does not run `dart
format`, `dart analyze`, `dart test`, `flutter analyze`, `flutter test`, `pub
get`, or git commands.

Formatting is external, so the migration executable does not bundle a formatter
dependency, mutate Target package setup, or hide formatter failures inside the
migration report. The ACT skill reads `changedFiles` from the JSON report and
formats only those Dart files with the resolved Dart runner and the
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
activation, or pub.dev dependency. Active development lives in
`act-dart-tools/act_dart_primary_constructors/`; ACT users run the synced bundled
copy inside the `act-dart-migrate-primary-constructors` skill package. This keeps
the user workflow self-contained and independent of pub.dev or Target project
dependencies while preserving standalone CLI development history here.

Commit `pubspec.lock` for this package. The lockfile keeps analyzer and CLI
dependency behavior reproducible for the bundled executable and ACT validation.

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
