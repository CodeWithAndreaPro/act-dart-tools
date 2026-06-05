# dart_primary_constructors

Bundled ACT tooling for Dart primary-constructor migrations.

```bash
dart run dart_primary_constructors --version
dart run dart_primary_constructors migrate --root <target-package> --json
```

The initial implementation provides the command surface and stable no-op report
contract. Source migration behavior is added in later slices.
