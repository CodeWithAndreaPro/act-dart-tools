# Maintainer Notes

This package is bundled ACT tooling. Keep package docs focused on command behavior and report contracts.

Commit `pubspec.lock` for this package. The lockfile keeps analyzer and CLI dependency behavior reproducible for the bundled executable and ACT validation.

The implementation separates CLI argument handling and report output from Target package discovery, migration planning, stable report serialization, and source edits. Keep user-facing docs focused on CLI behavior and report contracts; avoid depending on internal module names in skill orchestration.
