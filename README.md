# act-dart-tools

This repo hosts a collection of command line tools (currently just one 😅) for Dart development.

## act_dart_migrate

A CLI for deterministic migrations of your Dart & Flutter codebases.

### Why this tool?

When new Dart language features are introduced, you usually have the following migration options:

1. Migrate code by hand (least desirable)
2. Use lint rules and IDE-assists
3. Use `dart fix`

`dart fix` is the most desirable option, but it only works with a supported set of diagnostic codes (e.g. `--code=migrate_design_widgets`). Unfortunately, certain opt-in features (such as the new [primary constructor syntax](https://dart.dev/language/primary-constructors)) are not supported at all.

This CLI was designed to fill the gap and support deterministic migrations that can be automated, using specific migration subcommands such as `primary-constructors`. 👇

### primary-constructors

Migrates eligible Dart classes and enhanced enums from ordinary constructor boilerplate to the new [primary constructor syntax](https://dart.dev/language/primary-constructors).

#### Example usage

```sh
dart run act_dart_migrate primary-constructors <target-package>
```

#### Example migration

This CLI has been used to migrate a [forked](https://github.com/bizz84/flutter-gallery) version of the Flutter Gallery app. Here's the resulting PR with 1285 additions & 2695 deletions:

- [Migrate Flutter Gallery to Dart primary constructors](https://github.com/bizz84/flutter-gallery/pull/3/changes)

### Usage

See [`act_dart_migrate/README.md`](act_dart_migrate/README.md) for detailed CLI usage and package-local documentation.
