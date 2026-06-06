# act-dart-tools

A collection of command line tools for Dart development.

## Tools

### act_dart_primary_constructors

Bundled ACT tooling for Dart primary-constructor migrations.

This package provides a small Dart CLI that migrates eligible Dart classes from
ordinary constructor boilerplate to Dart experimental primary-constructor syntax.
It is intentionally conservative: when a declaration cannot be migrated safely,
the tool leaves the source unchanged and reports a precise skip reason.

