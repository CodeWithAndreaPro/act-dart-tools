# Report Contract

ACT Dart Migrate emits deterministic text or JSON reports for the selected Migration Subcommand. JSON output is the machine-readable contract used by ACT orchestration.

With `--json`, stdout contains JSON only. Human diagnostics and unexpected internal-error details go to stderr.

## Success Envelope

Successful JSON output has `ok: true`, a top-level `migration` field naming the selected Migration Subcommand, and schema version `2`:

```json
{
  "ok": true,
  "migration": "primary-constructors",
  "schemaVersion": 2,
  "toolVersion": "0.2.0",
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

`changedFiles` contains relative Dart file paths that would be changed in a dry run or were written in a real run.

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

Each `skippedDeclarations` entry has the same declaration fields plus a stable reason code and message:

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

`skippedFiles` and `skippedDirectories` contain `{ "path", "reason" }` objects. File-level skip reasons currently include `generatedFile`; directory-level reasons include `nestedPackage`, `nestedRepository`, and `excludedDirectory`.

`transformCounts` counts migrated declarations by transform kind. `skipReasonCounts` combines declaration, skipped-file, and skipped-directory reason counts. Report arrays and count maps are deterministic.

The opt-in `--skip-super-constructor-initializers` workaround reports skipped class declarations with reason code `superConstructorInitializer` when a class primary-constructor migration would otherwise retain an explicit `super(...)` or `super.named(...)` initializer.

## Failure Envelope

Failure JSON output has `ok: false` and an `error` object:

```json
{
  "ok": false,
  "migration": "primary-constructors",
  "schemaVersion": 2,
  "toolVersion": "0.2.0",
  "error": {
    "code": "invalidRoot",
    "message": "Target package root does not exist or has no pubspec.yaml: example"
  }
}
```

Errors from a recognized Migration Subcommand include that subcommand in the top-level `migration` field. This keeps failures attributable even when the run does not reach a successful migration report.

Root-level errors omit `migration` because no migration was selected:

```json
{
  "ok": false,
  "schemaVersion": 2,
  "toolVersion": "0.2.0",
  "error": {
    "code": "argumentError",
    "message": "Unknown Migration Subcommand."
  }
}
```

Stable error codes are `argumentError`, `invalidRoot`, `parseFailure`, `validationFailure`, and `internalError`.

Active exit codes are:

- `0`: success, including no-op and skip-only runs
- `1`: transformed source validation failure
- `64`: argument error
- `65`: input parse failure
- `66`: invalid root
- `70`: internal error

Formatter failure is not a CLI exit category because formatting is not performed by the CLI.
