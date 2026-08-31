# act-dart-tools

A collection of command line tools for Dart development.

## act_dart_migrate

A CLI for deterministic Dart migrations.

This package provides one Dart executable with migration subcommands.

### primary-constructors

`primary-constructors` can be used to migrate eligible Dart classes and enhanced enums from ordinary constructor boilerplate to the new [primary constructor syntax](https://dart.dev/language/primary-constructors).

Example usage:

```sh
dart run act_dart_migrate primary-constructors <target-package>
```

See [`act_dart_migrate/README.md`](act_dart_migrate/README.md) for detailed CLI usage and package-local documentation.
