## 0.4.1

- Removed the obsolete `--skip-super-constructor-initializers` Dart SDK workaround and its skip reason (no longer needed in Dart 3.13 targets).

## 0.4.0

- Updated primary-constructor Target Package requirements for Dart 3.13 and removed the obsolete experiment requirement.
- Changed license to MIT.

## 0.3.1

- Bumped JSON report schema version to `4`.
- Renamed command-discovery metadata fields to target-package-specific names (`targetPackageMinimumDartSdk` and `targetPackageRequiredExperiments`) to clarify they describe the Target Package prerequisites, not the SDK used to run the tool.
- Added safe migration of `.new` constructor shorthand for generative and factory constructors that remain in class, enhanced-enum, or extension-type bodies.
- Treated inline field-declaration comments as ambiguous and reported them with the `fieldComment` skip reason to preserve conservative migration behavior.
- Documented the command-discovery envelope, target-package SDK and experiment requirements, and stopped pinning concrete schema and tool versions in the report contract docs.

## 0.3.0

- Expanded primary-constructor migration support for eligible unnamed, named, and `.new` constructors, including refined parameter-shape handling.
- Added extension type primary-constructor migration coverage.
- Bumped JSON report schema version to `3` for the expanded stable report vocabulary.
- Improved retained body-member conflict detection and class-body rewrite behavior when migrations remove all body members.
- Updated migration rules documentation and tests for non-trivial mixin classes, constructor shorthand interactions, named constructors, and field formal parameters.

## 0.2.0

- Renamed the package and executable to `act_dart_migrate` for consolidated ACT Dart migration tooling.
- Replaced the previous root migration command shape with the `primary-constructors` Migration Subcommand and root command discovery through `list --json`.
- Updated JSON Migration Reports to schema version `2` with top-level `migration: "primary-constructors"` attribution for selected-subcommand reports.
- Refreshed package-local README and docs for the active command grammar, migration rules, report contract, and modular-monolith architecture.
- Split reusable discovery, package-root, source-edit, report, exit-code, and target-package run mechanics into shared internal core modules while preserving primary-constructor migration semantics.
- Added deterministic command-discovery JSON for supported Migration Subcommands.

## 0.1.0

- Implemented conservative Dart primary-constructor migration for eligible classes and enhanced enums.
- Added constructor declaration shorthand migration for eligible constructors that remain in class or enum bodies.
- Added empty class-body collapse when migrations remove all body members.
- Added Target Package discovery with stable skip reporting for generated files, nested packages, nested repositories or worktrees, and excluded transient directories.
- Added stable JSON report behavior with deterministic changed-file, migrated-declaration, skipped-declaration, skipped-file, skipped-directory, transform-count, and skip-reason-count output.
- Kept formatting and verification outside the CLI boundary: the tool reports changed files but does not run formatters, analyzers, tests, package commands, or git operations.
