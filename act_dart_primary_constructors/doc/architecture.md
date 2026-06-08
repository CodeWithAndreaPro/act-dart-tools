# Architecture Overview

This document explains how the `act_dart_primary_constructors` CLI moves from a
Target Package path to a migration report. It describes package responsibilities
and seams, not stable private APIs.

The CLI is bundled ACT tooling. Its runtime job is intentionally narrow: inspect
a Target Package, plan conservative source rewrites, validate those rewrites,
write changed files when not in dry-run mode, and emit a stable report.

## Pipeline

1. CLI argument handling turns command-line input into a target package run.
2. Target Package run orchestration validates the package root and coordinates
   discovery, migration, error mapping, and report construction.
3. Discovery finds non-generated Dart files and records skipped files or
   directories before migration planning starts.
4. Migration planning parses each discovered Dart file, plans declaration-level
   transforms, validates source edit ranges, and builds transformed source in
   memory.
5. Transformed-source validation parses every changed file in memory before any
   write occurs.
6. A real run writes only already-validated changed files; a dry run writes
   nothing.
7. Report serialization combines discovery facts, migration facts, stable
   transform names, skip reason codes, counts, and exit-facing errors.

## CLI Boundary

The CLI owns:

- Target Package root validation.
- Dart file and skipped-path discovery.
- Conservative migration planning for supported transforms.
- Source edit range validation before edits are applied.
- Parse-before-write behavior for inspected input files.
- Validation-before-write behavior for changed output files.
- File writes for non-dry-run migrations.
- Stable JSON and text report generation.

The CLI does not own formatting, target package analysis, target package tests,
package setup commands, git operations, or rich human presentation workflows.
Those steps sit outside the executable so migration planning remains local,
deterministic, and easy to validate from the report.

ACT-owned orchestration surrounds the CLI. It can prepare the environment,
invoke the bundled executable, read the JSON report, format changed Dart files,
and run target-package verification after the CLI exits. Keeping those concerns
outside this package prevents the migration report from hiding unrelated setup,
formatting, or verification failures.

## Discovery

`lib/src/discovery.dart` owns Target Package file discovery. It walks the target
root in deterministic order, includes non-generated Dart files, and records
skipped paths before migration planning receives any files.

Generated Dart files are skipped because rewriting generated source would fight
the generator that owns those files. Nested packages are skipped because a child
`pubspec.yaml` marks a separate Target Package boundary. Nested repositories and
worktrees are skipped because they are separate source-control boundaries.
Transient, hidden, and build-output directories are skipped as whole subtrees so
their contents are not parsed or reported one file at a time.

Discovery output separates files to inspect from skipped files and skipped
directories. Later stages use those facts to build `skippedFiles`,
`skippedDirectories`, and combined skip counts in the final report.

## Target Package Run Orchestration

`lib/src/target_package_run.dart` owns the package-level run. It normalizes and
validates the target root, calls discovery, runs the migration engine, maps
migration failures to public error codes, and creates the success report.

This layer is the seam between CLI argument handling and the migration engine.
Tests can replace file-system access or parsing at this boundary without making
runtime behavior depend on a different production implementation.

## Migration Planning

`lib/src/migration.dart` and its parts own declaration planning. The planner
parses each discovered Dart file with the primary-constructor experiment enabled,
then considers top-level class and enhanced-enum declarations.

Planning is conservative. It creates source edits only for supported shapes
and records skipped declarations with stable reason codes for unsupported or
unsafe shapes. Class primary-constructor migration, enhanced-enum
primary-constructor migration, constructor shorthand, and empty class-body
collapse are planned through the same file-level path so their edits and report
facts are combined deterministically.

If an inspected input file cannot be parsed, the run fails before any changed
file is written. That parse-before-write behavior prevents a partially migrated
package when input source is invalid.

## Source Edits

`lib/src/source_edit.dart` owns source ranges and edit application. It validates
range bounds and rejects overlapping edits before building transformed source.

Migration planners produce edit intents; source editing applies them in a stable
order. This keeps syntax decisions in the migration planners and raw text-edit
safety in one reusable module.

## Transformed-Source Validation And Writes

The migration engine builds all changed file contents in memory before writing
anything. Every changed source is parsed again with the primary-constructor
experiment enabled.

If transformed-source validation fails, the run returns a validation failure and
writes no files. This validation-before-write behavior is separate from source
edit range validation: edit validation proves the text edits are structurally
safe to apply, while transformed-source validation proves the resulting Dart file
is parser-valid.

When validation succeeds, non-dry-run mode writes the changed files. Dry-run mode
returns the same planning and report facts without writing files.

## Reports

`lib/src/report.dart` owns stable report serialization. It keeps public
transform names, declaration skip reason codes, file and directory skip reason
codes, deterministic sorting, combined counts, success JSON, failure JSON, and
concise text output in one place.

The report is the integration contract between the CLI and surrounding ACT
orchestration. It is also the right place for users and agents to look when they
need to understand what changed, what was skipped, and why a run failed.

## Analyzer-Valid Regression Support

Analyzer-valid regression coverage is a test-only responsibility area. It should
exercise representative fixture packages through the normal migration path and
then prove the migrated output remains valid with analyzer APIs.

That support must stay out of the production CLI boundary. Runtime migration
uses parser validation and report facts; analyzer-valid regression tests provide
release confidence without expanding what the executable does to a Target
Package.

## Stability Of This Overview

The stable surface is the CLI behavior and report vocabulary, not private helper
classes or private methods inside these modules. Future refactors may reorganize
implementation details as long as the public command behavior, conservative
write boundary, and report contract remain intact.
